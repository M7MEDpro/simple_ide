import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/features/runner/languages.dart';

/**
 * One problem reported by a compiler, interpreter, or syntax check.
 */
class Diagnostic {
  const Diagnostic({
    required this.path,
    required this.line,
    required this.column,
    required this.severity,
    required this.message,
  });

  final String path;

  /** 1-based line number. */
  final int line;

  /** 1-based column number; 1 when the tool didn't report one. */
  final int column;
  final Severity severity;
  final String message;

  @override
  String toString() => '${p.basename(path)}:$line:$column ${severity.name}: $message';
}

final _gcc = RegExp(
  r'^\s*((?:[A-Za-z]:)?[^:*?"<>|]+?):(\d+):(?:(\d+):)?\s*(fatal error|error|warning|Error|Warning):\s*(.*)$',
);
final _javac = RegExp(r'^((?:[A-Za-z]:)?[^:*?"<>|]+?\.java):(\d+):\s*(error|warning):\s*(.*)$');
final _pyFrame = RegExp(r'^\s*File "(.+?)", line (\d+)');
final _exceptionLine = RegExp(r'^(\w+(?:Error|Exception|Warning)|KeyboardInterrupt)\b(?::\s*(.*))?$');
final _jsFrame = RegExp(r'^\s+at .*?\(?((?:[A-Za-z]:)?[^:*?"<>|()]+?\.(?:m?js|cjs|ts)):(\d+):(\d+)\)?$');
final _nodeCheckHeader = RegExp(r'^((?:[A-Za-z]:)?[^:*?"<>|]+?\.(?:m?js|cjs)):(\d+)$');
final _rustHeader = RegExp(r'^(error|warning)(?:\[\w+\])?:\s*(.*)$');
final _rustArrow = RegExp(r'^\s*-->\s+((?:[A-Za-z]:)?[^:*?"<>|]+?):(\d+):(\d+)');
final _go = RegExp(r'^\s*((?:\./)?[^:*?"<>|\s]+?\.go):(\d+):(\d+):\s*(.*)$');

/**
 * Turns tool output into [Diagnostic]s, one line at a time. Stateful because
 * some tools spread one problem over several lines: Python prints the frame
 * before the exception, Node prints the message before the stack, and rustc
 * prints the message before the location.
 */
class DiagnosticParser {
  /**
   * @param cwd    directory that relative paths resolve against
   * @param exists file-existence check, replaceable in tests
   */
  DiagnosticParser(this.cwd, {bool Function(String)? exists}) : _exists = exists ?? ((f) => File(f).existsSync());

  final String cwd;
  final bool Function(String) _exists;

  (String, int)? _pyPending;
  String? _messagePending;
  (Severity, String)? _rustPending;

  String? _resolve(String file) {
    var path = file.trim();
    if (!p.isAbsolute(path)) path = p.normalize(p.join(cwd, path));
    return _exists(path) ? path : null;
  }

  static Severity _sev(String s) => s.toLowerCase().contains('warning') ? Severity.warning : Severity.error;

  /**
   * Feeds one line of output.
   *
   * @param line a complete line, without its newline
   * @return the diagnostic this line completes, or null
   */
  Diagnostic? feed(String line) {
    Diagnostic? make(String file, String ln, String? col, Severity sev, String msg) {
      final path = _resolve(file);
      if (path == null) return null;
      return Diagnostic(
        path: path,
        line: int.parse(ln),
        column: int.tryParse(col ?? '') ?? 1,
        severity: sev,
        message: msg.trim().isEmpty ? (sev == Severity.error ? 'Error' : 'Warning') : msg.trim(),
      );
    }

    var m = _gcc.firstMatch(line);
    if (m != null) return make(m[1]!, m[2]!, m[3], _sev(m[4]!), m[5]!);

    m = _javac.firstMatch(line);
    if (m != null) return make(m[1]!, m[2]!, null, _sev(m[3]!), m[4]!);

    m = _go.firstMatch(line);
    if (m != null) return make(m[1]!, m[2]!, m[3], Severity.error, m[4]!);

    m = _pyFrame.firstMatch(line);
    if (m != null) {
      final path = _resolve(m[1]!);
      if (path != null) _pyPending = (path, int.parse(m[2]!));
      return null;
    }

    m = _nodeCheckHeader.firstMatch(line);
    if (m != null) {
      final path = _resolve(m[1]!);
      if (path != null) _pyPending = (path, int.parse(m[2]!));
      return null;
    }

    m = _rustHeader.firstMatch(line);
    if (m != null) {
      _rustPending = (_sev(m[1]!), m[2]!);
      return null;
    }

    m = _rustArrow.firstMatch(line);
    if (m != null && _rustPending != null) {
      final (sev, msg) = _rustPending!;
      _rustPending = null;
      return make(m[1]!, m[2]!, m[3], sev, msg);
    }

    m = _exceptionLine.firstMatch(line);
    if (m != null) {
      final msg = m[2] == null || m[2]!.isEmpty ? m[1]! : '${m[1]}: ${m[2]}';
      final frame = _pyPending;
      if (frame != null) {
        _pyPending = null;
        return Diagnostic(path: frame.$1, line: frame.$2, column: 1, severity: Severity.error, message: msg);
      }
      _messagePending = msg; // Node prints the message before the stack.
      return null;
    }

    m = _jsFrame.firstMatch(line);
    if (m != null && _messagePending != null && !line.contains('node:internal')) {
      final d = make(m[1]!, m[2]!, m[3], Severity.error, _messagePending!);
      if (d != null) _messagePending = null;
      return d;
    }
    return null;
  }

  /**
   * Parses a whole block of output at once.
   *
   * @param output text from a tool, possibly many lines
   * @return every diagnostic found, in order
   */
  List<Diagnostic> parseAll(String output) => [
        for (final l in output.replaceAll('\r\n', '\n').split('\n')) ?feed(l),
      ];
}

/**
 * Current problems, grouped by file. Fed by run output and by background
 * syntax checks that run after each save.
 */
class DiagnosticsStore extends ChangeNotifier {
  final Map<String, List<Diagnostic>> _byFile = {};
  final Set<String> _stale = {};
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  static String _key(String path) => p.normalize(path).toLowerCase();

  /** Files with at least one problem, in a stable order. */
  List<String> get files {
    final keys = _byFile.keys.toList()..sort();
    return [for (final k in keys) _byFile[k]!.first.path];
  }

  List<Diagnostic> forFile(String path) => _byFile[_key(path)] ?? const [];

  /**
   * Returns the highest-priority severity for [path] (or for any file inside
   * [path] when [isDir] is true), or null if there are no problems.
   */
  Severity? worstSeverity(String path, {bool isDir = false}) {
    Severity? worst;
    if (!isDir) {
      for (final d in forFile(path)) {
        if (worst == null || d.severity.index < worst.index) worst = d.severity;
      }
      return worst;
    }
    for (final list in _byFile.values) {
      if (list.isEmpty) continue;
      if (p.isWithin(path, list.first.path)) {
        for (final d in list) {
          if (worst == null || d.severity.index < worst.index) worst = d.severity;
        }
      }
    }
    return worst;
  }

  bool isStale(String path) => _stale.contains(_key(path));

  int get errorCount => _byFile.values.fold(0, (n, l) => n + l.where((d) => d.severity == Severity.error).length);
  int get warningCount => _byFile.values.fold(0, (n, l) => n + l.where((d) => d.severity == Severity.warning).length);
  bool get isEmpty => _byFile.isEmpty;

  void add(Diagnostic d) {
    final list = _byFile.putIfAbsent(_key(d.path), () => []);
    final dupe = list.any((x) => x.line == d.line && x.column == d.column && x.message == d.message);
    if (dupe) return;
    list
      ..add(d)
      ..sort((a, b) => a.line != b.line ? a.line.compareTo(b.line) : a.column.compareTo(b.column));
    _stale.remove(_key(d.path));
    notifyListeners();
  }

  /**
   * Replaces everything known about one file, e.g. after a syntax check.
   *
   * @param path  the checked file
   * @param items its problems; empty clears the file
   */
  void replaceFile(String path, List<Diagnostic> items) {
    final k = _key(path);
    _stale.remove(k);
    if (items.isEmpty) {
      if (_byFile.remove(k) == null) return;
    } else {
      _byFile[k] = [...items]
        ..sort((a, b) => a.line != b.line ? a.line.compareTo(b.line) : a.column.compareTo(b.column));
    }
    notifyListeners();
  }

  /**
   * Marks a file's problems as possibly outdated because its text changed
   * after they were reported.
   */
  void markStale(String path) {
    final k = _key(path);
    if (_byFile.containsKey(k) && _stale.add(k)) notifyListeners();
  }

  void clear() {
    if (_byFile.isEmpty) return;
    _byFile.clear();
    _stale.clear();
    notifyListeners();
  }
}

/**
 * Runs a fast syntax-only check for languages whose toolchain offers one.
 */
class SyntaxChecker {
  final Map<String, int> _generation = {};

  /**
   * The check command for a file, or null when its language has none.
   *
   * @param path the source file
   * @return program followed by its arguments
   */
  static List<String>? commandFor(String path) {
    switch (languageFor(path).id) {
      case 'c':
        return ['gcc', '-fsyntax-only', '-Wall', path];
      case 'cpp':
        return ['g++', '-std=c++17', '-fsyntax-only', '-Wall', path];
      case 'python':
        // compile() reports syntax errors without writing __pycache__.
        return ['python', '-c', "import sys;compile(open(sys.argv[1],encoding='utf-8').read(),sys.argv[1],'exec')", path];
      case 'javascript':
        return ['node', '--check', path];
      default:
        return null;
    }
  }

  /**
   * Checks a saved file and reports its problems. Older checks for the same
   * file are discarded if a newer one finishes first.
   *
   * @param path   the saved file
   * @param report receives the file's full list of problems
   */
  Future<void> check(String path, void Function(List<Diagnostic>) report, {Map<String, String> extraEnv = const {}}) async {
    final cmd = commandFor(path);
    if (cmd == null) return;
    final key = path.toLowerCase();
    final gen = (_generation[key] ?? 0) + 1;
    _generation[key] = gen;
    try {
      final r = await Process.run(
        cmd.first,
        cmd.sublist(1),
        workingDirectory: p.dirname(path),
        environment: extraEnv.isEmpty ? null : extraEnv,
      ).timeout(const Duration(seconds: 15));
      if (_generation[key] != gen) return;
      final out = '${r.stdout}\n${r.stderr}';
      final parser = DiagnosticParser(p.dirname(path));
      final found = parser.parseAll(out).where((d) => p.equals(d.path, path)).toList();
      report(found);
    } catch (_) {
      // Toolchain missing or hung: no live checks, Run still reports errors.
    }
  }
}
