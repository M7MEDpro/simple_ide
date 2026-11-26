import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:simple_ide/features/agent/agent_service.dart';
import 'package:simple_ide/features/runner/build_tools.dart';
import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/features/diagnostics/diagnostics.dart';
import 'package:simple_ide/features/editor/document.dart';
import 'package:simple_ide/features/git/git_service.dart';
import 'package:simple_ide/features/runner/languages.dart';
import 'package:simple_ide/features/runner/runner.dart';
import 'package:simple_ide/features/settings/settings.dart';
import 'package:simple_ide/features/explorer/workspace.dart';
import 'package:simple_ide/features/diagnostics/diagnostic_layers.dart';
import 'package:simple_ide/features/editor/code_suggestions.dart';
import 'package:simple_ide/features/project/new_file_dialog.dart';
import 'package:simple_ide/features/project/new_project_dialog.dart';
import 'package:simple_ide/features/project/project_config.dart';
import 'package:simple_ide/features/search/project_search.dart';
import 'package:simple_ide/app/palette.dart';

void main() {
  group('splitCommandLine', () {
    test('keeps quoted paths with spaces together', () {
      expect(
        splitCommandLine(r'gcc "C:\My Code\main.c" -o "C:\out dir\main.exe" -Wall'),
        ['gcc', r'C:\My Code\main.c', '-o', r'C:\out dir\main.exe', '-Wall'],
      );
    });

    test('collapses repeated whitespace and keeps empty quoted args', () {
      expect(splitCommandLine('  python   -u  ""  x.py '), ['python', '-u', '', 'x.py']);
    });
  });

  test('expandTemplate fills known placeholders and leaves unknown ones', () {
    expect(
      expandTemplate(r'run "${file}" ${missing}', {'file': 'a.c'}),
      r'run "a.c" ${missing}',
    );
  });

  group('languageFor', () {
    test('maps extensions case-insensitively', () {
      expect(languageFor('MAIN.CPP').id, 'cpp');
      expect(languageFor('x.py').runnable, isTrue);
      expect(languageFor('notes.txt').id, 'plaintext');
      expect(languageFor('notes.txt').runnable, isFalse);
    });

    test('C builds before it runs', () {
      final l = languageFor('a.c');
      expect(l.build, contains('gcc'));
      expect(l.run, contains(r'${out}'));
    });
  });

  group('Runner.commandsFor', () {
    test('uses the language default', () {
      final (build, run) = Runner.commandsFor('a.py', const {});
      expect(build, isNull);
      expect(run, contains('python'));
    });

    test('splits an override on &&', () {
      final (build, run) = Runner.commandsFor('a.c', {'.c': r'clang "${file}" -o "${out}" && "${out}"'});
      expect(build, r'clang "${file}" -o "${out}"');
      expect(run, r'"${out}"');
    });
  });

  group('parseSourceLink', () {
    bool any(String _) => true;

    test('gcc error with Windows drive path', () {
      final l = parseSourceLink(r'C:\proj\main.c:5:12: error: expected ;', r'C:\proj', exists: any)!;
      expect(l.path, r'C:\proj\main.c');
      expect(l.line, 5);
      expect(l.column, 12);
      expect(l.severity, Severity.error);
    });

    test('gcc warning with relative path resolves against cwd', () {
      final l = parseSourceLink('main.c:3:1: warning: unused', r'C:\proj', exists: any)!;
      expect(p.normalize(l.path), p.normalize(r'C:\proj\main.c'));
      expect(l.severity, Severity.warning);
    });

    test('python traceback', () {
      final l = parseSourceLink(r'  File "C:\proj\app.py", line 7, in <module>', r'C:\proj', exists: any)!;
      expect(l.line, 7);
    });

    test('java compiler error', () {
      final l = parseSourceLink(r'C:\proj\A.java:4: error: ; expected', r'C:\proj', exists: any)!;
      expect(l.line, 4);
    });

    test('plain output is not a link', () {
      expect(parseSourceLink('Hello: 1:2 world', r'C:\proj', exists: (_) => false), isNull);
      expect(parseSourceLink('Result is 42', r'C:\proj', exists: any), isNull);
    });
  });

  group('ConsoleBuffer', () {
    test('stitches chunks into lines per stream', () async {
      final c = ConsoleBuffer()..cwd = Directory.systemTemp.path;
      c.write('Hel', LineKind.stdout);
      c.write('lo\nWor', LineKind.stdout);
      c.write('oops\n', LineKind.stderr);
      c.write('ld\r\n', LineKind.stdout);
      c.endStreams();
      expect(c.lines.map((l) => l.text), ['Hello', 'World', 'oops']);
      expect(c.lines[2].kind, LineKind.stderr);
      c.dispose();
    });

    test('counts diagnostics', () {
      final tmp = Directory.systemTemp.createTempSync('sid');
      File(p.join(tmp.path, 'm.c')).writeAsStringSync('x');
      final c = ConsoleBuffer()..cwd = tmp.path;
      c.write('m.c:1:1: error: boom\nm.c:2:1: warning: hmm\n', LineKind.stderr);
      expect(c.errors, 1);
      expect(c.warnings, 1);
      expect(c.lines.first.link, isNotNull);
      c.dispose();
      tmp.deleteSync(recursive: true);
    });
  });

  group('EditorDocument', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sid'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('preserves CRLF line endings on save', () async {
      final f = File(p.join(tmp.path, 'a.c'))..writeAsStringSync('int a;\r\nint b;\r\n');
      final d = await EditorDocument.open(f.path);
      expect(d.lineEnding, '\r\n');
      expect(d.isDirty, isFalse);
      d.controller.text = 'int c;\nint d;\n';
      expect(d.isDirty, isTrue);
      expect(await d.save(), isTrue);
      expect(d.isDirty, isFalse);
      expect(f.readAsStringSync(), 'int c;\r\nint d;\r\n');
      d.dispose();
    });

    test('opens binary files read-only', () async {
      final f = File(p.join(tmp.path, 'b.bin'))..writeAsBytesSync([1, 0, 2, 3]);
      final d = await EditorDocument.open(f.path);
      expect(d.binary, isTrue);
      expect(d.readOnly, isTrue);
      d.dispose();
    });
  });

  group('Workspace', () {
    test('lists folders first and supports create/rename/delete', () async {
      final tmp = Directory.systemTemp.createTempSync('sid');
      File(p.join(tmp.path, 'b.txt')).writeAsStringSync('');
      Directory(p.join(tmp.path, 'z_dir')).createSync();
      final ws = Workspace(tmp.path);
      expect(ws.children(tmp.path).map((e) => e.name), ['z_dir', 'b.txt']);

      final f = await ws.createFile(tmp.path, 'a.py');
      expect(File(f).existsSync(), isTrue);
      await expectLater(ws.createFile(tmp.path, 'a.py'), throwsA(isA<FileSystemException>()));

      final renamed = await ws.rename(FsEntry(f, false), 'c.py');
      expect(File(renamed).existsSync(), isTrue);
      await ws.delete(FsEntry(renamed, false));
      expect(File(renamed).existsSync(), isFalse);
      ws.dispose();
      tmp.deleteSync(recursive: true);
    });
  });

  test('fuzzyScore prefers word-start matches', () {
    expect(fuzzyScore('mc', 'src/main.c'), isNotNull);
    expect(fuzzyScore('xyz', 'main.c'), isNull);
    expect(fuzzyScore('main', 'src/main.c')! > fuzzyScore('main', 'src/domain.c')!, isTrue);
  });

  test('Runner runs a real Python program with stdin', () async {
    final py = await Process.run('python', ['--version'], runInShell: true);
    if (py.exitCode != 0) return; // Python not installed on this machine.
    final tmp = Directory.systemTemp.createTempSync('sid');
    final f = File(p.join(tmp.path, 'echo.py'))..writeAsStringSync('n = input("n? ")\nprint(int(n) * 2)\n');
    final console = ConsoleBuffer();
    final runner = Runner(console);
    final done = runner.runFile(f.path, clear: false);
    while (!runner.acceptsInput) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    runner.sendInput('21');
    await done;
    expect(runner.status, RunStatus.succeeded);
    expect(console.plainText, contains('42'));
    runner.dispose();
    console.dispose();
    tmp.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Runner reports a C build error with a clickable location', () async {
    final gcc = await Process.run('gcc', ['--version'], runInShell: true);
    if (gcc.exitCode != 0) return;
    final tmp = Directory.systemTemp.createTempSync('sid');
    final f = File(p.join(tmp.path, 'bad.c'))..writeAsStringSync('int main(void) {\n  int x = 1\n  return x;\n}\n');
    final console = ConsoleBuffer();
    final runner = Runner(console);
    await runner.runFile(f.path, clear: false);
    expect(runner.status, RunStatus.failed);
    expect(console.errors, greaterThan(0));
    expect(console.lines.any((l) => l.link?.line == 2 || l.link?.line == 3), isTrue);
    runner.dispose();
    console.dispose();
    tmp.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('DiagnosticParser parses gcc, python, and rust diagnostics', () {
    final parser = DiagnosticParser(r'C:\proj', exists: (_) => true);
    final diags = parser.parseAll(
      'main.c:4:18: error: expected \';\' before \'return\'\n'
      'main.c:2:9: warning: unused variable \'x\'\n'
      '  File "app.py", line 7, in <module>\n'
      'NameError: name \'foo\' is not defined\n'
      'error[E0425]: cannot find value `bar` in this scope\n'
      ' --> src/main.rs:3:5\n'
      'index.js:3\n'
      'const x = ;\n'
      '          ^\n'
      'SyntaxError: Unexpected token \';\'\n',
    );
    expect(diags.length, 5);
    expect(diags[0].severity, Severity.error);
    expect(diags[0].line, 4);
    expect(diags[0].column, 18);
    expect(diags[1].severity, Severity.warning);
    expect(diags[2].message, "NameError: name 'foo' is not defined");
    expect(diags[2].line, 7);
    expect(diags[3].line, 3);
    expect(diags[3].column, 5);
    expect(diags[4].line, 3);
    expect(diags[4].message, "SyntaxError: Unexpected token ';'");
  });

  test('DiagnosticsStore tracks counts, worstSeverity, and staleness', () {
    final store = DiagnosticsStore();
    const file = r'C:\proj\src\main.c';
    store.add(const Diagnostic(path: file, line: 2, column: 1, severity: Severity.warning, message: 'warn'));
    store.add(const Diagnostic(path: file, line: 4, column: 3, severity: Severity.error, message: 'err'));
    expect(store.errorCount, 1);
    expect(store.warningCount, 1);
    expect(store.worstSeverity(file), Severity.error);
    expect(store.worstSeverity(r'C:\proj\src', isDir: true), Severity.error);
    store.markStale(file);
    expect(store.isStale(file), isTrue);
    store.replaceFile(file, const []);
    expect(store.isEmpty, isTrue);
    expect(store.worstSeverity(file), isNull);
    store.dispose();
  });

  test('underlineRange selects token or non-empty line span', () {
    expect(underlineRange('    ', 1), isNull);
    expect(underlineRange('  int x = 0', 1), (2, 11));
    expect(underlineRange('  printf("%d", total);', 16), (15, 20));
  });

  test('createProject and suggestProjectName create starter files cleanly', () async {
    final tmp = Directory.systemTemp.createTempSync('sid_proj');
    expect(suggestProjectName(tmp.path), 'untitled');
    final py = projectTemplates.firstWhere((t) => t.id == 'python');
    final first = await createProject(parentDir: tmp.path, name: 'untitled', template: py, createSample: true);
    expect(Directory(first.projectDir).existsSync(), isTrue);
    expect(first.entryPath, p.join(tmp.path, 'untitled', 'main.py'));
    expect(File(first.entryPath!).existsSync(), isTrue);
    expect(suggestProjectName(tmp.path), 'untitled1');

    final empty = projectTemplates.firstWhere((t) => t.id == 'empty');
    final second = await createProject(parentDir: tmp.path, name: 'blank', template: empty, createSample: true);
    expect(Directory(second.projectDir).existsSync(), isTrue);
    expect(second.entryPath, isNull);
    tmp.deleteSync(recursive: true);
  });

  test('GitService.parseStatus parses modified, staged, and untracked files', () {
    final changes = GitService.parseStatus(
      ' M src/main.c\n'
      'M  README.md\n'
      '?? new_file.py\n'
      'R  old.txt -> new.txt\n',
      r'C:\proj',
    );
    expect(changes.length, 4);
    expect(changes[0].code, 'M');
    expect(changes[0].staged, isFalse);
    expect(changes[1].staged, isTrue);
    expect(changes[2].untracked, isTrue);
    expect(changes[2].code, 'U');
    expect(changes[3].relativePath, 'new.txt');
  });

  test('Settings.buildPath prepends extra directories', () {
    final built = Settings.buildPath([r'C:\Custom\bin', '  ']);
    expect(built.startsWith(r'C:\Custom\bin'), isTrue);
  });

  test('planNewFiles generates C++ class pair, header, and namespace cleanly', () {
    final cppClass = allNewFileKinds.firstWhere((k) => k.id == 'cpp_class');
    final pair = planNewFiles(kind: cppClass, rawName: 'Player', namespace: 'game::core', headerExt: '.hpp');
    expect(pair.length, 2);
    expect(pair[0].relPath, 'Player.hpp');
    expect(pair[0].content, contains('#pragma once'));
    expect(pair[0].content, contains('namespace game::core'));
    expect(pair[0].content, contains('class Player'));
    expect(pair[1].relPath, 'Player.cpp');
    expect(pair[1].content, contains('#include "Player.hpp"'));

    final cppNs = allNewFileKinds.firstWhere((k) => k.id == 'cpp_namespace');
    final nsFile = planNewFiles(kind: cppNs, rawName: 'math', headerExt: '.hpp');
    expect(nsFile.single.relPath, 'math.hpp');
    expect(nsFile.single.content, contains('namespace math'));

    final ordered = orderedKindsFor('cpp');
    expect(ordered.first.id, 'cpp_class');
  });

  test('IdePromptsBuilder suggests language snippets and buffer identifiers', () {
    final ctrl = CodeLineEditingController.fromText('int playerScore = 0;\npri\n');
    final builder = IdePromptsBuilder(languageId: 'c', controller: ctrl);
    expect(builder, isNotNull);
    ctrl.dispose();
  });

  test('AgentController builds preset and custom CLI commands', () {
    final agent = AgentController();
    expect(agent.buildCommand('explain main.c'), ['claude', '-p', 'explain main.c']);
    agent.selectAgent('gemini');
    expect(agent.buildCommand('fix bug'), ['gemini', '-p', 'fix bug']);
    agent.selectAgent('custom');
    agent.setCustomTemplate(r'ollama run codellama "${prompt}"');
    expect(agent.buildCommand('hello'), ['ollama', 'run', 'codellama', 'hello']);
    agent.dispose();
  });

  test('detectBuildTasks recognizes Gradle, CMake, Cargo, and npm', () {
    final tmp = Directory.systemTemp.createTempSync('sid_build');
    File(p.join(tmp.path, 'build.gradle.kts')).writeAsStringSync('');
    File(p.join(tmp.path, 'gradlew.bat')).writeAsStringSync('');
    File(p.join(tmp.path, 'CMakeLists.txt')).writeAsStringSync('');
    File(p.join(tmp.path, 'Cargo.toml')).writeAsStringSync('');
    final tasks = detectBuildTasks(tmp.path);
    expect(tasks.any((t) => t.tool == 'Gradle' && t.command.contains('gradlew.bat')), isTrue);
    expect(tasks.any((t) => t.tool == 'CMake'), isTrue);
    expect(tasks.any((t) => t.tool == 'Cargo' && t.command == 'cargo run'), isTrue);
    tmp.deleteSync(recursive: true);
  });

  test('createProject initializes Gradle and CMake projects', () async {
    final tmp = Directory.systemTemp.createTempSync('sid_btproj');
    final javaTpl = projectTemplates.firstWhere((t) => t.id == 'java');
    final gradleProj = await createProject(
      parentDir: tmp.path,
      name: 'my_gradle',
      template: javaTpl,
      createSample: true,
      buildTool: 'Gradle',
    );
    expect(File(p.join(gradleProj.projectDir, 'build.gradle.kts')).existsSync(), isTrue);
    expect(File(p.join(gradleProj.projectDir, 'src', 'main', 'java', 'Main.java')).existsSync(), isTrue);

    final cppTpl = projectTemplates.firstWhere((t) => t.id == 'cpp');
    final cmakeProj = await createProject(
      parentDir: tmp.path,
      name: 'my_cmake',
      template: cppTpl,
      createSample: true,
      buildTool: 'CMake',
    );
    expect(File(p.join(cmakeProj.projectDir, 'CMakeLists.txt')).existsSync(), isTrue);
    expect(File(p.join(cmakeProj.projectDir, 'main.cpp')).existsSync(), isTrue);
    tmp.deleteSync(recursive: true);
  });

  test('ProjectRunConfig saves and reloads .simple_ide.json', () async {
    final tmp = Directory.systemTemp.createTempSync('sid_cfg');
    const cfg = ProjectRunConfig(
      runCommand: 'python main.py --port 8080',
      buildCommand: 'pytest',
      cwd: 'src',
      env: {'PORT': '8080', 'ENV': 'dev'},
    );
    await cfg.save(tmp.path);
    final loaded = ProjectRunConfig.load(tmp.path);
    expect(loaded.runCommand, 'python main.py --port 8080');
    expect(loaded.buildCommand, 'pytest');
    expect(loaded.cwd, 'src');
    expect(loaded.env['PORT'], '8080');
    tmp.deleteSync(recursive: true);
  });

  test('searchInProject and replaceInFiles find and update matches', () async {
    final tmp = Directory.systemTemp.createTempSync('sid_search');
    final f1 = File(p.join(tmp.path, 'a.dart'))..writeAsStringSync('void greet() {\n  print("Hello");\n}\n');
    final f2 = File(p.join(tmp.path, 'b.dart'))..writeAsStringSync('// hello world\n');

    final groups = await searchInProject([f1.path, f2.path], 'hello', caseSensitive: false);
    expect(groups.length, 2);
    expect(groups[0].matches.first.line, 2);

    final replaced = await replaceInFiles(groups, 'hello', 'hi', caseSensitive: false);
    expect(replaced, 2);
    expect(f1.readAsStringSync(), contains('print("hi")'));
    expect(f2.readAsStringSync(), contains('// hi world'));
    tmp.deleteSync(recursive: true);
  });

  test('GitService.parseUnifiedDiffLines parses added, modified, and deleted hunks', () {
    const diff = '''
@@ -3,0 +4,2 @@ void foo() {
+  line4
+  line5
@@ -10 +12 @@ void bar() {
-  old
+  new
@@ -15,2 +16,0 @@ void baz() {
''';
    final map = GitService.parseUnifiedDiffLines(diff);
    expect(map[4], GitLineChange.added);
    expect(map[5], GitLineChange.added);
    expect(map[12], GitLineChange.modified);
    expect(map[16], GitLineChange.deleted);
  });
}
