import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/features/runner/languages.dart';

enum RunStatus { idle, building, running, succeeded, failed, stopped }

/**
 * Drives the host's ready-made compilers and interpreters as OS processes.
 * SimpleIDE contains no compiler logic of its own: it expands a command
 * template, spawns the tool, and routes stdout/stderr/stdin through the
 * console.
 */
class Runner extends ChangeNotifier {
  Runner(this.console);

  final ConsoleBuffer console;

  RunStatus status = RunStatus.idle;
  String? target; // what is running, for the status bar
  int? exitCode;
  DateTime? _startedAt;
  Duration elapsed = Duration.zero;
  Timer? _ticker;
  Process? _proc;
  bool _stopRequested = false;
  int _generation = 0;

  bool get busy => status == RunStatus.building || status == RunStatus.running;
  bool get acceptsInput => status == RunStatus.running && _proc != null;

  static final _tempRoot = Directory(p.join(Directory.systemTemp.path, 'SimpleIDE'));

  /**
   * A tiny C file linked into C/C++ builds that switches stdout to
   * unbuffered mode, so `printf("Enter n: ")` shows before `scanf` blocks.
   */
  static Future<String> _stdioHelper(Map<String, String> extraEnv) async {
    final cFile = File(p.join(_tempRoot.path, 'simpleide_stdio.c'));
    final oFile = File(p.join(_tempRoot.path, 'simpleide_stdio.o'));
    const src = '#include <stdio.h>\n'
        '__attribute__((constructor)) static void simpleide_unbuffer(void) {\n'
        '  setvbuf(stdout, NULL, _IONBF, 0);\n'
        '  setvbuf(stderr, NULL, _IONBF, 0);\n'
        '}\n';
    final changed = !cFile.existsSync() || cFile.readAsStringSync() != src;
    if (changed) {
      cFile.parent.createSync(recursive: true);
      cFile.writeAsStringSync(src);
    }
    if (!changed && oFile.existsSync()) return oFile.path;
    try {
      final r = await Process.run(
        'gcc',
        ['-c', '-O2', cFile.path, '-o', oFile.path],
        environment: extraEnv.isEmpty ? null : extraEnv,
        runInShell: Platform.isWindows,
      ).timeout(const Duration(seconds: 6));
      if (r.exitCode == 0 && oFile.existsSync()) return oFile.path;
    } catch (_) {}
    return cFile.path;
  }

  /**
   * Returns true when [outPath] already exists and is newer than [sourceFile]
   * and any local headers in the same directory.
   */
  static bool isUpToDate(String sourceFile, String outPath) {
    final out = File(outPath);
    final src = File(sourceFile);
    if (!out.existsSync() || !src.existsSync()) return false;
    final outTime = out.lastModifiedSync();
    if (src.lastModifiedSync().isAfter(outTime)) return false;
    try {
      for (final e in src.parent.listSync(followLinks: false).whereType<File>()) {
        final ext = p.extension(e.path).toLowerCase();
        if (ext == '.h' || ext == '.hpp' || ext == '.hh') {
          if (e.lastModifiedSync().isAfter(outTime)) return false;
        }
      }
    } catch (_) {}
    return true;
  }

  static Map<String, String> templateVars(String file) {
    final name = p.basenameWithoutExtension(file);
    final outDir = p.join(_tempRoot.path, 'build', file.toLowerCase().hashCode.toUnsigned(32).toRadixString(16));
    return {
      'file': file,
      'dir': p.dirname(file),
      'name': name,
      'ext': p.extension(file),
      'out': p.join(outDir, Platform.isWindows ? '$name.exe' : name),
      'outDir': outDir,
    };
  }

  /**
   * Resolves the commands that will run for a file, after user overrides.
   *
   * @param file      absolute path of the source file
   * @param overrides per-extension commands from Settings; a value may hold
   *                  "build && run"
   * @return a (build, run) pair; build is null for interpreted languages and
   *         both are null when the language has no runner
   */
  static (String?, String?) commandsFor(String file, Map<String, String> overrides) {
    final lang = languageFor(file);
    final ext = p.extension(file).toLowerCase();
    final override = overrides[ext];
    if (override != null && override.trim().isNotEmpty) {
      // An override may hold "build && run".
      final parts = override.split('&&').map((s) => s.trim()).toList();
      return parts.length > 1 ? (parts.first, parts.sublist(1).join(' && ')) : (null, parts.first);
    }
    return (lang.build, lang.run);
  }

  /**
   * Builds (if needed) and runs a source file with its host toolchain,
   * streaming output into [console]. Any run already in progress is stopped.
   *
   * @param file      absolute path of the file to run
   * @param overrides per-extension command overrides
   * @param clear     whether to empty the console first
   */
  Future<void> runFile(
    String file, {
    Map<String, String> overrides = const {},
    bool clear = true,
    Map<String, String> extraEnv = const {},
  }) async {
    await stop(silent: true);
    final gen = ++_generation;
    final (buildCmd, runCmd) = commandsFor(file, overrides);
    final name = p.basename(file);
    if (runCmd == null) {
      console.writeln('${languageFor(file).name} files have no run command. Add one in Settings under Run commands.', LineKind.failure);
      return;
    }
    if (clear) console.clear();
    console.cwd = p.dirname(file);
    console.resetDiagnostics();
    target = name;
    exitCode = null;
    _stopRequested = false;
    _beginClock();

    final vars = templateVars(file);
    if (buildCmd != null || runCmd.contains(r'${out}')) {
      Directory(vars['outDir']!).createSync(recursive: true);
    }
    if ((buildCmd ?? '').contains(r'${stdioHelper}')) vars['stdioHelper'] = await _stdioHelper(extraEnv);

    final skipBuild = buildCmd != null && isUpToDate(file, vars['out']!) && !overrides.containsKey(p.extension(file).toLowerCase());
    if (buildCmd != null && !skipBuild) {
      _set(RunStatus.building);
      final argv = splitCommandLine(expandTemplate(buildCmd, vars));
      console.writeln('Building $name', LineKind.system);
      console.writeln('> ${_display(argv)}', LineKind.system);
      final code = await _exec(argv, p.dirname(file), gen, extraEnv: extraEnv);
      if (gen != _generation) return;
      if (code != 0) {
        _finish(code, built: false);
        return;
      }
    }

    _set(RunStatus.running);
    final argv = splitCommandLine(expandTemplate(runCmd, vars));
    if (buildCmd == null || skipBuild) console.writeln('> ${_display(argv)}', LineKind.system);
    final code = await _exec(argv, p.dirname(file), gen, extraEnv: extraEnv);
    if (gen != _generation) return;
    _finish(code);
  }

  /**
   * Runs a console command through cmd.exe. A temporary batch file
   * carries the command line verbatim, so quoting behaves exactly as it
   * does in a normal Command Prompt.
   *
   * @param command the command line as typed by the user
   * @param cwd     working directory for the command
   */
  Future<void> runShell(String command, String cwd, {Map<String, String> extraEnv = const {}}) async {
    await stop(silent: true);
    final gen = ++_generation;
    console.cwd = cwd;
    console.resetDiagnostics();
    target = command;
    exitCode = null;
    _stopRequested = false;
    _beginClock();
    _set(RunStatus.running);

    List<String> argv;
    File? script;
    if (Platform.isWindows) {
      script = File(p.join(_tempRoot.path, 'cmd_${DateTime.now().microsecondsSinceEpoch}.cmd'));
      script.parent.createSync(recursive: true);
      script.writeAsStringSync('@echo off\r\nchcp 65001 >nul\r\n$command\r\n');
      argv = ['cmd.exe', '/d', '/c', script.path];
    } else {
      argv = ['/bin/sh', '-c', command];
    }
    final code = await _exec(argv, cwd, gen, extraEnv: extraEnv);
    try {
      script?.deleteSync();
    } catch (_) {}
    if (gen != _generation) return;
    _finish(code, quiet: true);
  }

  Future<int?> _exec(List<String> argv, String cwd, int gen, {Map<String, String> extraEnv = const {}}) async {
    if (argv.isEmpty) return -1;
    final env = {
      'PYTHONUNBUFFERED': '1',
      'PYTHONIOENCODING': 'utf-8',
      'PYTHONUTF8': '1',
      ...extraEnv,
    };
    Process proc;
    try {
      proc = await Process.start(argv.first, argv.sublist(1), workingDirectory: cwd, environment: env);
    } on ProcessException {
      // Tools like npx/tsc ship as .cmd shims that CreateProcess can't launch
      // directly; if `where` finds one, go through the shell instead.
      final shim = Platform.isWindows ? await _whereCmdShim(argv.first) : null;
      if (shim == null) {
        console.writeln(
          "Couldn't start \"${argv.first}\". Install it and make sure it is on PATH, "
          'or set a different command in Settings under Run commands.',
          LineKind.failure,
        );
        return null;
      }
      proc = await Process.start(shim, argv.sublist(1), workingDirectory: cwd, environment: env, runInShell: true);
    }
    if (gen != _generation) {
      proc.kill();
      return null;
    }
    _proc = proc;
    proc.stdin.encoding = utf8;
    notifyListeners();
    final out = proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => console.write(s, LineKind.stdout));
    final err = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => console.write(s, LineKind.stderr));
    final code = await proc.exitCode;
    await Future.wait([out.asFuture<void>(), err.asFuture<void>()]).timeout(
      const Duration(seconds: 2),
      onTimeout: () => const [],
    );
    console.endStreams();
    if (identical(_proc, proc)) _proc = null;
    return code;
  }

  static Future<String?> _whereCmdShim(String exe) async {
    try {
      final r = await Process.run('where', [exe]);
      if (r.exitCode != 0) return null;
      final hit = (r.stdout as String)
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .firstWhere((s) => s.toLowerCase().endsWith('.cmd') || s.toLowerCase().endsWith('.bat'), orElse: () => '');
      return hit.isEmpty ? null : hit;
    } catch (_) {
      return null;
    }
  }

  /**
   * Writes one line to the running program's standard input and echoes it
   * in the console.
   *
   * @param line text to send; a newline is appended
   */
  void sendInput(String line) {
    final proc = _proc;
    if (proc == null) return;
    console.write('$line\n', LineKind.input);
    try {
      proc.stdin.writeln(line);
    } catch (_) {
      // The program may have closed stdin or exited between keystrokes.
    }
  }

  /**
   * Signals end-of-input to the running program (Ctrl+Z in a real console).
   */
  Future<void> sendEof() async {
    final proc = _proc;
    if (proc == null) return;
    try {
      await proc.stdin.close();
      console.writeln('^Z (end of input sent)', LineKind.system);
    } catch (_) {}
  }

  /**
   * Kills the running process and all of its children.
   *
   * @param silent when true, no "Stopped" line is written to the console
   */
  Future<void> stop({bool silent = false}) async {
    final proc = _proc;
    if (proc == null && !busy) return;
    _stopRequested = true;
    _generation++;
    if (proc != null) {
      if (Platform.isWindows) {
        // Kill the whole tree: `go run`, `dart run` and cmd spawn children.
        await Process.run('taskkill', ['/PID', '${proc.pid}', '/T', '/F']);
      } else {
        proc.kill(ProcessSignal.sigkill);
      }
      _proc = null;
    }
    console.endStreams();
    _stopClock();
    status = RunStatus.stopped;
    if (!silent) console.writeln('Stopped after ${_fmt(elapsed)}', LineKind.system);
    notifyListeners();
  }

  void _finish(int? code, {bool built = true, bool quiet = false}) {
    _stopClock();
    exitCode = code;
    if (_stopRequested) return;
    final ok = code == 0;
    status = ok ? RunStatus.succeeded : RunStatus.failed;
    if (!built) {
      final e = console.errors;
      console.writeln(
        code == null
            ? 'Build could not start'
            : 'Build failed with ${e == 0 ? 'errors' : e == 1 ? '1 error' : '$e errors'}. Click a location above to jump to it.',
        LineKind.failure,
      );
    } else if (code == null) {
      // Start failure already explained.
    } else if (!quiet || !ok) {
      console.writeln(
        ok ? 'Finished in ${_fmt(elapsed)} with exit code 0' : 'Exited with code $code after ${_fmt(elapsed)}',
        ok ? LineKind.success : LineKind.failure,
      );
    }
    notifyListeners();
  }

  void _set(RunStatus s) {
    status = s;
    notifyListeners();
  }

  void _beginClock() {
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed = DateTime.now().difference(_startedAt!);
      notifyListeners();
    });
  }

  void _stopClock() {
    _ticker?.cancel();
    if (_startedAt != null) elapsed = DateTime.now().difference(_startedAt!);
  }

  static String _fmt(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
    if (d.inSeconds < 60) return '${(d.inMilliseconds / 1000).toStringAsFixed(2)} s';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  static String formatElapsed(Duration d) => _fmt(d);

  static String _display(List<String> argv) =>
      argv.map((a) => a.contains(' ') ? '"$a"' : a).join(' ');

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _proc?.kill();
    super.dispose();
  }
}
