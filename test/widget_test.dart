import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/features/diagnostics/diagnostics.dart';
import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/settings/settings.dart';
import 'package:simple_ide/main.dart';

void main() {
  testWidgets('shows the welcome page with no folder open', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ide = IdeController(Settings());
    await tester.pumpWidget(SimpleIdeApp(controller: ide));
    expect(find.text('Toolchains'), findsOneWidget);
    expect(find.text('Edit PATH…'), findsOneWidget);
    expect(find.text('New Project…'), findsOneWidget);
    expect(find.text('Open Folder…'), findsOneWidget);
    expect(find.text('Console'), findsNothing);
    // Let toolchain probes time out in fake time.
    await tester.pump(const Duration(seconds: 8));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('opens a folder and a file into a tab', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('sid_ui');
    final file = File(p.join(tmp.path, 'main.c'))..writeAsStringSync('int main(void) { return 0; }\n');
    final ide = IdeController(Settings()..autoSave = false);
    await tester.pumpWidget(SimpleIdeApp(controller: ide));
    await tester.runAsync(() async {
      await ide.openFolder(tmp.path);
      await ide.openFile(file.path);
    });
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('main.c'), findsWidgets);
    expect(find.text('Saved'), findsOneWidget);
    await tester.runAsync(() async {
      await ide.closeFolder();
    });
    ide.workspace?.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 25));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('renders diagnostics in editor, status bar, and problems tab', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('sid_diag');
    final file = File(p.join(tmp.path, 'broken.c'))..writeAsStringSync('int main(void) {\n  int x = 0\n  return x;\n}\n');
    final ide = IdeController(Settings()..autoSave = false);
    await tester.pumpWidget(SimpleIdeApp(controller: ide));
    await tester.runAsync(() async {
      await ide.openFolder(tmp.path);
      await ide.openFile(file.path);
    });
    ide.diagnostics.replaceFile(file.path, [
      Diagnostic(path: file.path, line: 2, column: 12, severity: Severity.error, message: 'expected ;'),
    ]);
    ide.showProblems();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Problems'), findsOneWidget);
    expect(find.text('expected ;'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    await tester.runAsync(() async {
      await ide.closeFolder();
    });
    ide.workspace?.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 25));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('New Project dialog creates and opens a Python project', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('sid_newproj');
    final ide = IdeController(Settings()..autoSave = false);
    await tester.pumpWidget(SimpleIdeApp(controller: ide));
    await tester.tap(find.text('New Project…'));
    await tester.pumpAndSettle();

    expect(find.text('New Project'), findsOneWidget);
    await tester.tap(find.text('Python').last);
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'demo_py');
    await tester.enterText(fields.at(1), tmp.path);
    await tester.pump();

    await tester.ensureVisible(find.text('Create'));
    await tester.tap(find.text('Create'));
    await tester.pump();
    for (var i = 0; i < 40 && ide.active == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(File(p.join(tmp.path, 'demo_py', 'main.py')).existsSync(), isTrue);
    expect(ide.active?.name, 'main.py');

    await tester.runAsync(() async {
      await ide.closeFolder();
    });
    ide.workspace?.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 25));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('IDE shell and New Project dialog stay overflow-free on small windows', (tester) async {
    tester.view.physicalSize = const Size(520, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('sid_resp');
    final file = File(p.join(tmp.path, 'src', 'very_long_nested_file_name.c'))
      ..createSync(recursive: true)
      ..writeAsStringSync('int main(void) {\n  return 0;\n}\n');
    final ide = IdeController(Settings()..autoSave = false);
    await tester.pumpWidget(SimpleIdeApp(controller: ide));
    await tester.runAsync(() async {
      await ide.openFolder(tmp.path);
      await ide.openFile(file.path);
    });
    ide.diagnostics.replaceFile(file.path, [
      Diagnostic(path: file.path, line: 2, column: 3, severity: Severity.warning, message: 'sample warning'),
    ]);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await ide.closeFolder();
    });
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('New Project…'));
    await tester.pumpAndSettle();
    expect(find.text('New Project'), findsOneWidget);
    expect(tester.takeException(), isNull);

    ide.workspace?.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 25));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('switches sidebar to Source Control (GitHub / Git) panel', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('sid_git');
    final ide = IdeController(Settings()..autoSave = false);
    await tester.pumpWidget(SimpleIdeApp(controller: ide));
    await tester.runAsync(() => ide.openFolder(tmp.path));
    await tester.pump(const Duration(milliseconds: 50));

    ide.selectSidebar(SidebarTab.git);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Source Control'), findsOneWidget);

    ide.selectSidebar(SidebarTab.agent);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Agent CLI'), findsOneWidget);

    await tester.runAsync(() => ide.closeFolder());
    ide.workspace?.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 25));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('New file popup creates a C++ Class (.h + .cpp) in a C++ project', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('sid_cppnew');
    final mainCpp = File(p.join(tmp.path, 'main.cpp'))..writeAsStringSync('int main() { return 0; }\n');
    final ide = IdeController(Settings()..autoSave = false);
    await tester.pumpWidget(SimpleIdeApp(controller: ide));
    await tester.runAsync(() async {
      await ide.openFolder(tmp.path);
      await ide.openFile(mainCpp.path);
    });
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('New file'));
    await tester.pumpAndSettle();

    expect(find.text('C++ Class'), findsWidgets);
    final dialogField = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first;
    await tester.enterText(dialogField, 'Player');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump();
    for (var i = 0; i < 40 && ide.active?.name != 'Player.h'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(File(p.join(tmp.path, 'Player.h')).existsSync(), isTrue);
    expect(File(p.join(tmp.path, 'Player.cpp')).existsSync(), isTrue);
    expect(ide.active?.name, 'Player.h');

    await tester.runAsync(() => ide.closeFolder());
    ide.workspace?.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 25));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
