import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/**
 * User preferences and the last session, stored as JSON under %APPDATA%.
 */
class Settings {
  Settings({
    this.fontSize = 14,
    this.wordWrap = false,
    this.autoSave = true,
    this.autoSaveDelayMs = 800,
    this.tabSize = 4,
    this.clearConsoleOnRun = true,
    this.sidebarWidth = 260,
    this.consoleHeight = 240,
    this.sidebarVisible = true,
    this.consoleVisible = true,
    List<String>? recentFolders,
    Map<String, String>? runOverrides,
    List<String>? extraPath,
    this.lastFolder,
    List<String>? lastOpenFiles,
    this.lastActiveFile,
    this.lastProjectDir,
  })  : recentFolders = recentFolders ?? [],
        runOverrides = runOverrides ?? {},
        extraPath = extraPath ?? [],
        lastOpenFiles = lastOpenFiles ?? [];

  double fontSize;
  bool wordWrap;
  bool autoSave;
  int autoSaveDelayMs;
  int tabSize;
  bool clearConsoleOnRun;
  double sidebarWidth;
  double consoleHeight;
  bool sidebarVisible;
  bool consoleVisible;
  final List<String> recentFolders;

  /**
   * Per-extension run command overrides, e.g. `.py` -> `py -3 -u "${file}"`.
   */
  final Map<String, String> runOverrides;

  /**
   * Extra directories prepended to PATH when probing or running tools.
   */
  final List<String> extraPath;

  String? lastFolder;
  List<String> lastOpenFiles;
  String? lastActiveFile;
  String? lastProjectDir;

  static File get _file {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return File(p.join(base, 'SimpleIDE', 'settings.json'));
  }

  static Settings load() {
    try {
      final f = _file;
      if (!f.existsSync()) return Settings();
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return Settings(
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 14,
        wordWrap: j['wordWrap'] as bool? ?? false,
        autoSave: true,
        autoSaveDelayMs: j['autoSaveDelayMs'] as int? ?? 800,
        tabSize: j['tabSize'] as int? ?? 4,
        clearConsoleOnRun: j['clearConsoleOnRun'] as bool? ?? true,
        sidebarWidth: (j['sidebarWidth'] as num?)?.toDouble() ?? 260,
        consoleHeight: (j['consoleHeight'] as num?)?.toDouble() ?? 240,
        sidebarVisible: j['sidebarVisible'] as bool? ?? true,
        consoleVisible: j['consoleVisible'] as bool? ?? true,
        recentFolders: (j['recentFolders'] as List?)?.cast<String>(),
        runOverrides: (j['runOverrides'] as Map?)?.cast<String, String>(),
        extraPath: (j['extraPath'] as List?)?.cast<String>(),
        lastFolder: j['lastFolder'] as String?,
        lastOpenFiles: (j['lastOpenFiles'] as List?)?.cast<String>(),
        lastActiveFile: j['lastActiveFile'] as String?,
        lastProjectDir: j['lastProjectDir'] as String?,
      );
    } catch (_) {
      // A corrupt settings file must never stop the IDE from opening.
      return Settings();
    }
  }

  void save() {
    try {
      final f = _file;
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'fontSize': fontSize,
        'wordWrap': wordWrap,
        'autoSave': autoSave,
        'autoSaveDelayMs': autoSaveDelayMs,
        'tabSize': tabSize,
        'clearConsoleOnRun': clearConsoleOnRun,
        'sidebarWidth': sidebarWidth,
        'consoleHeight': consoleHeight,
        'sidebarVisible': sidebarVisible,
        'consoleVisible': consoleVisible,
        'recentFolders': recentFolders,
        'runOverrides': runOverrides,
        'extraPath': extraPath,
        'lastFolder': lastFolder,
        'lastOpenFiles': lastOpenFiles,
        'lastActiveFile': lastActiveFile,
        'lastProjectDir': lastProjectDir,
      }));
    } catch (_) {
      // Preferences are best-effort; editing must continue regardless.
    }
  }

  void pushRecent(String folder) {
    recentFolders
      ..removeWhere((f) => p.equals(f, folder))
      ..insert(0, folder);
    if (recentFolders.length > 8) recentFolders.removeRange(8, recentFolders.length);
  }

  /**
   * Returns [extra] prepended to the host's `PATH` environment variable.
   */
  static String buildPath(List<String> extra) {
    final sep = Platform.isWindows ? ';' : ':';
    final base = Platform.environment['PATH'] ?? '';
    final clean = extra.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (clean.isEmpty) return base;
    return base.isEmpty ? clean.join(sep) : '${clean.join(sep)}$sep$base';
  }

  Map<String, String> get pathEnv => extraPath.isEmpty ? const {} : {'PATH': buildPath(extraPath)};
}
