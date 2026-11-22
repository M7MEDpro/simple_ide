import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/features/diagnostics/diagnostics.dart';

enum LineKind { stdout, stderr, input, system, success, failure }

enum Severity { error, warning, note }

/**
 * A file location found in compiler or runtime output.
 */
class SourceLink {
  const SourceLink(this.path, this.line, this.column, this.severity);
  final String path;
  final int line; // 1-based
  final int column; // 1-based
  final Severity severity;
}

class ConsoleLine {
  ConsoleLine(this.text, this.kind);
  String text;
  final LineKind kind;
  SourceLink? link;
  bool _scanned = false;
}

final _gccLike = RegExp(
  r'^\s*((?:[A-Za-z]:)?[^:*?"<>|]+?):(\d+):(?:(\d+):)?\s*(fatal error|error|warning|note|Error|Warning|Context)\b',
);
final _python = RegExp(r'File "(.+?)", line (\d+)');
final _javaErr = RegExp(r'^((?:[A-Za-z]:)?[^:*?"<>|]+?\.java):(\d+):\s*(error|warning)');
final _rustArrow = RegExp(r'-->\s+((?:[A-Za-z]:)?[^:*?"<>|]+?):(\d+):(\d+)');
final _jsStack = RegExp(r'\(?((?:[A-Za-z]:)?[^:*?"<>|()]+?\.(?:m?js|cjs|ts)):(\d+):(\d+)\)?');
final _goLike = RegExp(r'^\s*((?:\./)?[^:*?"<>|\s]+?\.go):(\d+):(\d+):');

/**
 * Finds a clickable source location in one line of compiler or runtime
 * output. Locations that don't exist on disk are ignored so the console
 * never offers a dead link.
 *
 * @param text   one line of output
 * @param cwd    directory that relative paths resolve against
 * @param exists file-existence check, replaceable in tests
 * @return the location, or null when the line holds none
 */
SourceLink? parseSourceLink(String text, String cwd, {bool Function(String)? exists}) {
  exists ??= (path) => File(path).existsSync();
  SourceLink? build(String file, String line, String? col, Severity sev) {
    var path = file.trim();
    if (!p.isAbsolute(path)) path = p.normalize(p.join(cwd, path));
    if (!exists!(path)) return null;
    return SourceLink(path, int.parse(line), int.tryParse(col ?? '') ?? 1, sev);
  }

  Severity sevOf(String s) {
    final l = s.toLowerCase();
    if (l.contains('error')) return Severity.error;
    if (l.contains('warning')) return Severity.warning;
    return Severity.note;
  }

  var m = _gccLike.firstMatch(text);
  if (m != null) return build(m[1]!, m[2]!, m[3], sevOf(m[4]!));
  m = _javaErr.firstMatch(text);
  if (m != null) return build(m[1]!, m[2]!, null, sevOf(m[3]!));
  m = _python.firstMatch(text);
  if (m != null) return build(m[1]!, m[2]!, null, Severity.error);
  m = _rustArrow.firstMatch(text);
  if (m != null) return build(m[1]!, m[2]!, m[3], Severity.error);
  m = _goLike.firstMatch(text);
  if (m != null) return build(m[1]!, m[2]!, m[3], Severity.error);
  m = _jsStack.firstMatch(text);
  if (m != null && !text.contains('node:internal')) {
    return build(m[1]!, m[2]!, m[3], Severity.error);
  }
  return null;
}

/**
 * Scrollback for the integrated console. Output arrives in arbitrary chunks;
 * this stitches them back into lines per stream and throttles repaints.
 */
class ConsoleBuffer extends ChangeNotifier {
  static const maxLines = 10000;

  final List<ConsoleLine> lines = [];
  String cwd = Directory.current.path;
  int errors = 0;
  int warnings = 0;

  /** Receives problems recognised in the output as it streams in. */
  void Function(Diagnostic d)? onDiagnostic;
  DiagnosticParser? _parser;

  ConsoleLine? _openOut;
  ConsoleLine? _openErr;
  Timer? _notifyTimer;

  void write(String chunk, LineKind kind) {
    if (chunk.isEmpty) return;
    final parts = chunk.replaceAll('\r\n', '\n').replaceAll('\r', '').split('\n');
    var open = kind == LineKind.stderr ? _openErr : _openOut;
    for (var i = 0; i < parts.length; i++) {
      final last = i == parts.length - 1;
      if (open != null) {
        open.text += parts[i];
        if (!last) {
          _finish(open);
          open = null;
        }
      } else if (!last || parts[i].isNotEmpty) {
        final line = ConsoleLine(parts[i], kind);
        lines.add(line);
        if (!last) {
          _finish(line);
        } else {
          open = line;
        }
      }
    }
    if (kind == LineKind.stderr) {
      _openErr = open;
    } else {
      _openOut = open;
    }
    _trim();
    _schedule();
  }

  void writeln(String text, LineKind kind) {
    _closeOpen();
    for (final part in text.split('\n')) {
      final line = ConsoleLine(part, kind);
      lines.add(line);
      _finish(line);
    }
    _trim();
    _schedule();
  }

  void _closeOpen() {
    if (_openOut != null) _finish(_openOut!);
    if (_openErr != null) _finish(_openErr!);
    _openOut = null;
    _openErr = null;
  }

  /**
   * Flushes any partial line, e.g. when a program exits without a newline.
   */
  void endStreams() {
    _closeOpen();
    _schedule();
  }

  void _finish(ConsoleLine line) {
    if (line._scanned) return;
    line._scanned = true;
    if (line.kind != LineKind.stdout && line.kind != LineKind.stderr) return;
    line.link = parseSourceLink(line.text, cwd);
    final d = (_parser ??= DiagnosticParser(cwd)).feed(line.text);
    if (d == null) return;
    if (d.severity == Severity.error) errors++;
    if (d.severity == Severity.warning) warnings++;
    onDiagnostic?.call(d);
  }

  void _trim() {
    if (lines.length > maxLines + 500) lines.removeRange(0, lines.length - maxLines);
  }

  void _schedule() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 16), notifyListeners);
  }

  /**
   * Starts a fresh problem count, e.g. at the beginning of a run. The
   * parser picks up the current [cwd].
   */
  void resetDiagnostics() {
    errors = 0;
    warnings = 0;
    _parser = DiagnosticParser(cwd);
    _schedule();
  }

  void clear() {
    lines.clear();
    _openOut = null;
    _openErr = null;
    _parser = null;
    errors = 0;
    warnings = 0;
    notifyListeners();
  }

  String get plainText => lines.map((l) => l.text).join('\n');

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _notifyTimer?.cancel();
    super.dispose();
  }
}
