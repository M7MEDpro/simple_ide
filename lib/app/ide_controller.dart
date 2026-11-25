import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/features/runner/build_tools.dart';
import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/features/agent/agent_service.dart';
import 'package:simple_ide/features/diagnostics/diagnostics.dart';
import 'package:simple_ide/features/editor/document.dart';
import 'package:simple_ide/features/project/project_config.dart';
import 'package:simple_ide/features/runner/runner.dart';
import 'package:simple_ide/features/settings/settings.dart';
import 'package:simple_ide/features/explorer/workspace.dart';

enum BottomTab { console, problems }

enum SidebarTab { explorer, search, git, agent }

class Notice {
  Notice(this.message, {this.error = false});
  final String message;
  final bool error;
  final DateTime at = DateTime.now();
}

/**
 * Application state: the workspace, open documents, auto-save, and the run
 * pipeline. Widgets listen to this for structure (tabs, layout) and to the
 * individual [EditorDocument]s, [Runner] and [ConsoleBuffer] for detail.
 */
class IdeController extends ChangeNotifier {
  IdeController(this.settings) {
    runner = Runner(console);
    console.onDiagnostic = diagnostics.add;
  }

  final Settings settings;
  final ConsoleBuffer console = ConsoleBuffer();

  /** Which tab the bottom panel shows. */
  final ValueNotifier<BottomTab> bottomTab = ValueNotifier(BottomTab.console);

  /** Which panel the left sidebar shows. */
  SidebarTab sidebarTab = SidebarTab.explorer;

  /**
   * Switches the sidebar to [tab], or toggles it closed when already active.
   */
  void selectSidebar(SidebarTab tab) {
    if (settings.sidebarVisible && sidebarTab == tab) {
      settings.sidebarVisible = false;
    } else {
      sidebarTab = tab;
      settings.sidebarVisible = true;
    }
    _persist();
    notifyListeners();
  }

  /** Opens the bottom panel on the Problems tab. */
  void showProblems() {
    bottomTab.value = BottomTab.problems;
    showConsole();
  }

  /** Problems from the last run and from syntax checks after each save. */
  final DiagnosticsStore diagnostics = DiagnosticsStore();
  final AgentController agent = AgentController();
  final SyntaxChecker _checker = SyntaxChecker();
  late final Runner runner;
  final ValueNotifier<Notice?> notice = ValueNotifier(null);

  /**
   * Bumped to ask the console input to take focus.
   */
  final ValueNotifier<int> focusConsoleRequest = ValueNotifier(0);

  /**
   * Bumped to ask the active editor to take focus.
   */
  final ValueNotifier<int> focusEditorRequest = ValueNotifier(0);

  Workspace? workspace;
  List<BuildTask> buildTasks = const [];
  ProjectRunConfig projectConfig = const ProjectRunConfig();
  final List<EditorDocument> docs = [];
  int _active = -1;
  final Map<EditorDocument, Timer> _saveTimers = {};
  Timer? _persistTimer;
  String? shellCwd;

  EditorDocument? get active => _active >= 0 && _active < docs.length ? docs[_active] : null;
  int get activeIndex => _active;

  // --- Workspace -----------------------------------------------------------

  Future<void> openFolder(String path, {bool restoreTabs = false}) async {
    if (!Directory(path).existsSync()) {
      notify('That folder no longer exists: $path', error: true);
      settings.recentFolders.remove(path);
      settings.save();
      notifyListeners();
      return;
    }
    await saveAll();
    await runner.stop(silent: true);
    diagnostics.clear();
    for (final d in List.of(docs)) {
      _disposeDoc(d);
    }
    docs.clear();
    _active = -1;
    workspace?.dispose();
    final ws = Workspace(p.normalize(path));
    ws.onFilesChanged = _onDiskChange;
    workspace = ws;
    buildTasks = detectBuildTasks(ws.root);
    projectConfig = ProjectRunConfig.load(ws.root);
    shellCwd = ws.root;
    console.cwd = ws.root;
    settings
      ..lastFolder = ws.root
      ..pushRecent(ws.root);
    if (restoreTabs) {
      for (final f in settings.lastOpenFiles) {
        if (File(f).existsSync()) await openFile(f, persist: false);
      }
      final idx = docs.indexWhere((d) => d.path == settings.lastActiveFile);
      if (idx >= 0) _active = idx;
    }
    _persistNow();
    notifyListeners();
  }

  Future<void> closeFolder() async {
    await saveAll();
    await runner.stop(silent: true);
    diagnostics.clear();
    for (final d in List.of(docs)) {
      _disposeDoc(d);
    }
    docs.clear();
    _active = -1;
    workspace?.dispose();
    workspace = null;
    buildTasks = const [];
    projectConfig = const ProjectRunConfig();
    settings.lastFolder = null;
    _persistNow();
    notifyListeners();
  }

  void removeRecent(String folder) {
    settings.recentFolders.removeWhere((f) => p.equals(f, folder));
    settings.save();
    notifyListeners();
  }

  Future<void> restoreSession() async {
    final last = settings.lastFolder;
    if (last != null && Directory(last).existsSync()) {
      await openFolder(last, restoreTabs: true);
    }
  }

  void _onDiskChange(Set<String> paths) {
    for (final d in docs) {
      if (paths.any((x) => p.equals(x, d.path))) d.reloadIfClean();
    }
  }

  // --- Documents -----------------------------------------------------------

  /**
   * Opens a file in a tab, or switches to its tab if already open.
   *
   * @param path    absolute path of the file
   * @param line    1-based line to reveal, if any
   * @param column  1-based column to place the cursor at
   * @param persist whether to record the change in the saved session
   * @return the document, or null when the file couldn't be read
   */
  Future<EditorDocument?> openFile(String path, {int? line, int? column, bool persist = true}) async {
    var idx = docs.indexWhere((d) => p.equals(d.path, path));
    if (idx < 0) {
      final EditorDocument doc;
      try {
        doc = await EditorDocument.open(path);
      } catch (e) {
        notify("Couldn't open ${p.basename(path)}: ${_reason(e)}", error: true);
        return null;
      }
      doc.onTextChanged = () {
        diagnostics.markStale(doc.path);
        _scheduleAutoSave(doc);
      };
      doc.onSaved = () => checkSyntax(doc);
      doc.addListener(notifyListeners);
      checkSyntax(doc);
      idx = _active < 0 ? docs.length : _active + 1;
      docs.insert(idx, doc);
    }
    _active = idx;
    final doc = docs[idx];
    if (line != null) revealLine(doc, line, column ?? 1);
    if (persist) _persist();
    notifyListeners();
    focusEditorRequest.value++;
    return doc;
  }

  void revealLine(EditorDocument doc, int line, int column) {
    final c = doc.controller;
    final index = (line - 1).clamp(0, c.lineCount - 1);
    final offset = (column - 1).clamp(0, c.codeLines[index].text.length);
    c.selection = CodeLineSelection.collapsed(index: index, offset: offset);
    // The editor for this doc may not be mounted yet; wait two frames.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          c.makePositionCenterIfInvisible(CodeLinePosition(index: index, offset: offset));
        } catch (_) {}
      });
    });
  }

  /**
   * Runs the language's syntax-only check on the saved file and replaces
   * that file's problems with the result. No-op for languages without one.
   *
   * @param doc the document that was just saved or opened
   */
  void checkSyntax(EditorDocument doc) {
    if (doc.binary || doc.isDirty) return;
    final path = doc.path;
    _checker.check(path, (found) {
      if (docs.contains(doc) && !doc.isDirty) diagnostics.replaceFile(path, found);
    }, extraEnv: settings.pathEnv);
  }

  void activate(int index) {
    if (index < 0 || index >= docs.length || index == _active) return;
    _active = index;
    _persist();
    notifyListeners();
    focusEditorRequest.value++;
  }

  void cycleTabs(int delta) {
    if (docs.length < 2) return;
    activate((_active + delta) % docs.length);
  }

  void moveTab(int from, int to) {
    if (from == to) return;
    final activeDoc = active;
    final d = docs.removeAt(from);
    docs.insert(to.clamp(0, docs.length), d);
    _active = activeDoc == null ? -1 : docs.indexOf(activeDoc);
    _persist();
    notifyListeners();
  }

  /**
   * Closes a tab. Unsaved changes are written first unless discarded;
   * if that save fails, the tab stays open.
   *
   * @param index   position of the tab
   * @param discard close without saving
   */
  Future<void> closeTab(int index, {bool discard = false}) async {
    if (index < 0 || index >= docs.length) return;
    final doc = docs[index];
    if (!discard && doc.isDirty) {
      final ok = await doc.save();
      if (!ok) {
        notify("Couldn't save ${doc.name}, so it stayed open: ${doc.lastError}", error: true);
        return;
      }
    }
    docs.removeAt(index);
    _disposeDoc(doc);
    if (_active >= docs.length) _active = docs.length - 1;
    if (index < _active) _active--;
    _persist();
    notifyListeners();
  }

  Future<void> closeWhere(bool Function(EditorDocument d) test) async {
    for (var i = docs.length - 1; i >= 0; i--) {
      if (test(docs[i])) await closeTab(i);
    }
  }

  void _disposeDoc(EditorDocument d) {
    _saveTimers.remove(d)?.cancel();
    d.removeListener(notifyListeners);
    d.dispose();
  }

  // --- Saving --------------------------------------------------------------

  void _scheduleAutoSave(EditorDocument doc) {
    if (!doc.isDirty) return;
    _saveTimers[doc]?.cancel();
    _saveTimers[doc] = Timer(Duration(milliseconds: settings.autoSaveDelayMs), () async {
      _saveTimers.remove(doc);
      if (!docs.contains(doc)) return;
      final ok = await doc.save();
      if (!ok) notify("Auto-save couldn't write ${doc.name}: ${doc.lastError}", error: true);
    });
  }

  Future<void> saveActive() async {
    final d = active;
    if (d == null) return;
    _saveTimers.remove(d)?.cancel();
    final ok = await d.save(force: true);
    if (!ok) notify("Couldn't save ${d.name}: ${d.lastError}", error: true);
  }

  /**
   * Flushes every modified buffer to disk.
   *
   * @return false if any write failed
   */
  Future<bool> saveAll() async {
    var ok = true;
    for (final d in List.of(docs)) {
      _saveTimers.remove(d)?.cancel();
      if (d.isDirty && !await d.save()) {
        ok = false;
        notify("Couldn't save ${d.name}: ${d.lastError}", error: true);
      }
    }
    return ok;
  }

  int get dirtyCount => docs.where((d) => d.isDirty).length;

  // --- Run -----------------------------------------------------------------

  Map<String, String> get _runEnv => {...settings.pathEnv, ...projectConfig.env};

  Future<void> saveProjectConfig(ProjectRunConfig cfg) async {
    final ws = workspace;
    if (ws == null) return;
    await cfg.save(ws.root);
    projectConfig = cfg;
    notifyListeners();
  }

  /**
   * One-click run: flush all buffers to disk, then run the project's custom
   * command if configured, or hand the active file to its external compiler
   * or interpreter.
   */
  Future<void> runActive() async {
    final customRun = projectConfig.runCommand?.trim();
    if (customRun != null && customRun.isNotEmpty && workspace != null) {
      if (!await saveAll()) {
        console.writeln('Run cancelled: some files could not be saved.', LineKind.failure);
        return;
      }
      showConsole();
      bottomTab.value = BottomTab.console;
      focusConsoleRequest.value++;
      if (settings.clearConsoleOnRun) console.clear();
      final cwd = projectConfig.resolveCwd(workspace!.root);
      console.writeln('> $customRun', LineKind.system);
      await runner.runShell(customRun, cwd, extraEnv: _runEnv);
      return;
    }

    final d = active;
    if (d == null) {
      notify('Open a file to run it.');
      return;
    }
    if (!d.language.runnable && !settings.runOverrides.containsKey(p.extension(d.path).toLowerCase())) {
      notify('${d.language.name} files have no run command. Add one in Settings.');
      return;
    }
    if (!await saveAll()) {
      console.writeln('Run cancelled: some files could not be saved.', LineKind.failure);
      return;
    }
    showConsole();
    bottomTab.value = BottomTab.console;
    focusConsoleRequest.value++;
    diagnostics.replaceFile(d.path, const []);
    await runner.runFile(
      d.path,
      overrides: settings.runOverrides,
      clear: settings.clearConsoleOnRun,
      extraEnv: _runEnv,
    );
  }

  Future<void> stopRun() => runner.stop();

  /**
   * Executes a detected project-level build task (Gradle, CMake, Cargo, etc.)
   * in the workspace root directory.
   */
  Future<void> runBuildTask(BuildTask task) async {
    final ws = workspace;
    if (ws == null) return;
    if (!await saveAll()) {
      console.writeln('Build cancelled: some files could not be saved.', LineKind.failure);
      return;
    }
    showConsole();
    bottomTab.value = BottomTab.console;
    focusConsoleRequest.value++;
    if (settings.clearConsoleOnRun) console.clear();
    console.writeln('${task.tool}: ${task.label}', LineKind.system);
    console.writeln('> ${task.command}', LineKind.system);
    await runner.runShell(task.command, projectConfig.resolveCwd(ws.root), extraEnv: _runEnv);
  }

  Future<void> runPrimaryBuild() async {
    final customBuild = projectConfig.buildCommand?.trim();
    if (customBuild != null && customBuild.isNotEmpty && workspace != null) {
      await runBuildTask(BuildTask(tool: 'Project', label: 'Custom build', command: customBuild));
      return;
    }
    if (buildTasks.isEmpty) {
      notify('No build tool (Gradle, Maven, CMake, Cargo, npm, etc.) found in this folder.');
      return;
    }
    await runBuildTask(buildTasks.first);
  }

  /**
   * Handles a line typed into the console: goes to the running program's
   * stdin, or runs as a command when nothing is running.
   *
   * @param line the text the user entered
   */
  Future<void> submitConsole(String line) async {
    if (runner.acceptsInput) {
      runner.sendInput(line);
      return;
    }
    final cmd = line.trim();
    final cwd = shellCwd ?? workspace?.root ?? Directory.current.path;
    if (cmd.isEmpty) return;
    console.writeln('${_promptFor(cwd)}$cmd', LineKind.input);
    if (cmd == 'cls' || cmd == 'clear') {
      console.clear();
      return;
    }
    final cd = RegExp(r'^cd(?:\s+/d)?\s*(.*)$', caseSensitive: false).firstMatch(cmd);
    if (cd != null) {
      final arg = cd[1]!.trim().replaceAll('"', '');
      if (arg.isEmpty) {
        console.writeln(cwd, LineKind.stdout);
        return;
      }
      final target = p.normalize(p.isAbsolute(arg) ? arg : p.join(cwd, arg));
      if (Directory(target).existsSync()) {
        shellCwd = target;
        console.cwd = target;
        notifyListeners();
      } else {
        console.writeln('The system cannot find the path specified: $target', LineKind.stderr);
      }
      return;
    }
    await saveAll();
    await runner.runShell(cmd, cwd, extraEnv: settings.pathEnv);
  }

  String get shellPrompt => _promptFor(shellCwd ?? workspace?.root ?? Directory.current.path);
  String _promptFor(String cwd) => '$cwd> ';

  // --- Workspace file operations that touch open tabs ----------------------

  Future<void> renameEntry(FsEntry e, String newName) async {
    final ws = workspace;
    if (ws == null) return;
    try {
      // Save first so the rename carries the latest text.
      await saveAll();
      final target = await ws.rename(e, newName);
      if (!e.isDir) {
        diagnostics.replaceFile(e.path, const []);
      } else {
        for (final f in diagnostics.files) {
          if (p.isWithin(e.path, f)) diagnostics.replaceFile(f, const []);
        }
      }
      for (final d in docs) {
        if (p.equals(d.path, e.path)) {
          d.path = target;
          checkSyntax(d);
        } else if (e.isDir && p.isWithin(e.path, d.path)) {
          d.path = p.join(target, p.relative(d.path, from: e.path));
          checkSyntax(d);
        }
      }
      _persist();
      notifyListeners();
    } catch (err) {
      notify("Couldn't rename ${e.name}: ${_reason(err)}", error: true);
    }
  }

  Future<void> deleteEntry(FsEntry e) async {
    final ws = workspace;
    if (ws == null) return;
    await closeWhere((d) => p.equals(d.path, e.path) || (e.isDir && p.isWithin(e.path, d.path)));
    try {
      await ws.delete(e);
      if (!e.isDir) diagnostics.replaceFile(e.path, const []);
    } catch (err) {
      notify("Couldn't delete ${e.name}: ${_reason(err)}", error: true);
    }
  }

  Future<void> createEntry(String dir, String name, {required bool folder}) async {
    final ws = workspace;
    if (ws == null) return;
    try {
      if (folder) {
        await ws.createFolder(dir, name);
      } else {
        final path = await ws.createFile(dir, name);
        await openFile(path);
      }
    } catch (err) {
      notify("Couldn't create $name: ${_reason(err)}", error: true);
    }
  }

  // --- Layout & preferences ------------------------------------------------

  void toggleSidebar() {
    settings.sidebarVisible = !settings.sidebarVisible;
    _persist();
    notifyListeners();
  }

  void toggleConsole() {
    settings.consoleVisible = !settings.consoleVisible;
    _persist();
    notifyListeners();
    if (settings.consoleVisible) focusConsoleRequest.value++;
  }

  void showConsole() {
    if (settings.consoleVisible) return;
    settings.consoleVisible = true;
    _persist();
    notifyListeners();
  }

  void setSidebarWidth(double w) {
    settings.sidebarWidth = w.clamp(170, 560);
    notifyListeners();
    _persist();
  }

  void setConsoleHeight(double h) {
    settings.consoleHeight = h.clamp(90, 900);
    notifyListeners();
    _persist();
  }

  void zoom(double delta) {
    settings.fontSize = (settings.fontSize + delta).clamp(9, 32);
    _persist();
    notifyListeners();
  }

  void resetZoom() {
    settings.fontSize = 14;
    _persist();
    notifyListeners();
  }

  void toggleWordWrap() {
    settings.wordWrap = !settings.wordWrap;
    _persist();
    notifyListeners();
  }

  void updateSettings(void Function(Settings s) change) {
    change(settings);
    _persist();
    notifyListeners();
  }

  void notify(String message, {bool error = false}) => notice.value = Notice(message, error: error);

  void _persist() {
    settings
      ..lastOpenFiles = docs.map((d) => d.path).toList()
      ..lastActiveFile = active?.path;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), settings.save);
  }

  void _persistNow() {
    _persistTimer?.cancel();
    settings
      ..lastOpenFiles = docs.map((d) => d.path).toList()
      ..lastActiveFile = active?.path
      ..save();
  }

  /**
   * Synchronous flush used on app exit.
   */
  Future<void> shutdown() async {
    await saveAll();
    await runner.stop(silent: true);
    _persistTimer?.cancel();
    settings
      ..lastOpenFiles = docs.map((d) => d.path).toList()
      ..lastActiveFile = active?.path
      ..save();
  }

  static String _reason(Object e) {
    if (e is FileSystemException) {
      return e.osError?.message.trim().isNotEmpty == true ? e.osError!.message.trim() : e.message;
    }
    return e.toString();
  }

  @override
  void dispose() {
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    workspace?.dispose();
    agent.dispose();
    runner.dispose();
    diagnostics.dispose();
    console.dispose();
    super.dispose();
  }
}

/**
 * Root Riverpod provider for the application's [IdeController].
 */
final ideProvider = ChangeNotifierProvider<IdeController>((ref) => IdeController(Settings.load()));

/**
 * Riverpod provider for the active [Runner] instance.
 */
final runnerProvider = ChangeNotifierProvider<Runner>((ref) => ref.read(ideProvider).runner);

/**
 * Riverpod provider for the integrated [ConsoleBuffer].
 */
final consoleProvider = ChangeNotifierProvider<ConsoleBuffer>((ref) => ref.read(ideProvider).console);

/**
 * Riverpod provider for the [DiagnosticsStore].
 */
final diagnosticsProvider = ChangeNotifierProvider<DiagnosticsStore>((ref) => ref.read(ideProvider).diagnostics);
