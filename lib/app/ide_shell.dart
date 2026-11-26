import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/app/bars.dart';
import 'package:simple_ide/features/agent/agent_panel.dart';
import 'package:simple_ide/features/runner/console_panel.dart';
import 'package:simple_ide/features/editor/editor_pane.dart';
import 'package:simple_ide/features/explorer/explorer_panel.dart';
import 'package:simple_ide/features/project/folder_picker.dart';
import 'package:simple_ide/features/git/git_panel.dart';
import 'package:simple_ide/features/project/new_file_dialog.dart';
import 'package:simple_ide/features/project/new_project_dialog.dart';
import 'package:simple_ide/features/project/project_config_dialog.dart';
import 'package:simple_ide/features/search/search_panel.dart';
import 'package:simple_ide/app/palette.dart';
import 'package:simple_ide/features/settings/settings_dialog.dart';
import 'package:simple_ide/features/editor/tab_strip.dart';
import 'package:simple_ide/features/welcome/welcome_page.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * The main window layout and global keyboard shortcuts.
 */
class IdeShell extends ConsumerStatefulWidget {
  const IdeShell({super.key});

  @override
  ConsumerState<IdeShell> createState() => _IdeShellState();
}

class _IdeShellState extends ConsumerState<IdeShell> {
  late final AppLifecycleListener _lifecycle;
  late final ShellActions _actions;

  IdeController get ide => ref.read(ideProvider);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _lifecycle = AppLifecycleListener(
      // Flush buffers whenever the window loses focus or closes.
      onInactive: () => ide.saveAll(),
      onHide: () => ide.saveAll(),
      onExitRequested: () async {
        await ide.shutdown();
        return AppExitResponse.exit;
      },
    );
    _actions = ShellActions(
      newProject: _newProject,
      openFolder: _openFolder,
      newFile: _newFile,
      quickOpen: () => showPalette(context, commands: _commands()),
      commandPalette: () => showPalette(context, commands: _commands(), commandMode: true),
      settings: () => showSettings(context),
      goToLine: _goToLine,
      editorIntent: _editorIntent,
      shortcuts: _showShortcuts,
      about: _showAbout,
      exit: () async {
        await ide.shutdown();
        await SystemNavigator.pop();
      },
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _lifecycle.dispose();
    super.dispose();
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _newProject() => showNewProjectDialog(context, ide);

  Future<void> _openFolder() async {
    final dir = await pickFolder(context, start: ide.workspace?.root ?? ide.settings.recentFolders.firstOrNull);
    if (dir != null) await ide.openFolder(dir);
  }

  Future<void> _newFile() async {
    final ws = ide.workspace;
    if (ws == null) {
      ide.notify('Open a folder first, so the new file has somewhere to live.');
      return;
    }
    final activeDir = ide.active != null && p.isWithin(ws.root, ide.active!.path) ? p.dirname(ide.active!.path) : ws.root;
    await showNewFileDialog(context, ide, targetDir: activeDir);
  }

  void _goToLine() {
    final d = ide.active;
    if (d != null && !d.binary) showGoToLine(context, ide, d);
  }

  /**
   * Sends an editing intent to the active editor, focusing it first.
   */
  void _editorIntent(Intent intent) {
    ide.focusEditorRequest.value++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx != null) Actions.maybeInvoke(ctx, intent);
    });
  }

  List<PaletteCommand> _commands() {
    final i = ide;
    return [
      PaletteCommand('Run file', i.runActive, shortcut: 'F5', group: 'Run'),
      PaletteCommand('Build project', i.runPrimaryBuild, shortcut: 'Ctrl+Shift+B', group: 'Run'),
      PaletteCommand('Stop', i.stopRun, shortcut: 'Shift+F5', group: 'Run'),
      PaletteCommand('Clear console', i.console.clear, group: 'Run'),
      PaletteCommand('Focus console input', () {
        i.showConsole();
        i.focusConsoleRequest.value++;
      }, shortcut: 'Ctrl+`', group: 'Run'),
      PaletteCommand('Project run config…', () => showProjectConfigDialog(context, i), group: 'Run'),
      PaletteCommand('Edit run commands', () => showSettings(context), group: 'Run'),
      PaletteCommand('New project', _newProject, shortcut: 'Ctrl+Shift+N', group: 'File'),
      PaletteCommand('New file', _newFile, shortcut: 'Ctrl+N', group: 'File'),
      PaletteCommand('Open folder', _openFolder, shortcut: 'Ctrl+O', group: 'File'),
      PaletteCommand('Save', i.saveActive, shortcut: 'Ctrl+S', group: 'File'),
      PaletteCommand('Save all', i.saveAll, shortcut: 'Ctrl+Shift+S', group: 'File'),
      PaletteCommand('Close tab', () => i.closeTab(i.activeIndex), shortcut: 'Ctrl+W', group: 'File'),
      PaletteCommand('Close all tabs', () => i.closeWhere((_) => true), group: 'File'),
      PaletteCommand('Close folder', i.closeFolder, group: 'File'),
      PaletteCommand('Find', () => _editorIntent(const CodeShortcutFindIntent()), shortcut: 'Ctrl+F', group: 'Edit'),
      PaletteCommand('Replace', () => _editorIntent(const CodeShortcutReplaceIntent()), shortcut: 'Ctrl+H', group: 'Edit'),
      PaletteCommand('Go to line', _goToLine, shortcut: 'Ctrl+G', group: 'Edit'),
      PaletteCommand('Toggle line comment', () => _editorIntent(const CodeShortcutCommentIntent(true)), shortcut: 'Ctrl+/', group: 'Edit'),
      PaletteCommand('Toggle explorer', () => i.selectSidebar(SidebarTab.explorer), shortcut: 'Ctrl+B', group: 'View'),
      PaletteCommand('Search in project', () => i.selectSidebar(SidebarTab.search), shortcut: 'Ctrl+Shift+F', group: 'View'),
      PaletteCommand('Source Control (Git / GitHub)', () => i.selectSidebar(SidebarTab.git), shortcut: 'Ctrl+Shift+G', group: 'View'),
      PaletteCommand('Agent CLI chat', () => i.selectSidebar(SidebarTab.agent), shortcut: 'Ctrl+Shift+A', group: 'View'),
      PaletteCommand('Toggle console', i.toggleConsole, shortcut: 'Ctrl+J', group: 'View'),
      PaletteCommand('Toggle word wrap', i.toggleWordWrap, shortcut: 'Alt+Z', group: 'View'),
      PaletteCommand('Zoom in', () => i.zoom(1), shortcut: 'Ctrl+=', group: 'View'),
      PaletteCommand('Zoom out', () => i.zoom(-1), shortcut: 'Ctrl+-', group: 'View'),
      PaletteCommand('Reset zoom', i.resetZoom, shortcut: 'Ctrl+0', group: 'View'),
      PaletteCommand('Reveal active file in explorer', () {
        final d = i.active;
        if (d == null || i.workspace == null) return;
        if (!i.settings.sidebarVisible) i.toggleSidebar();
        i.workspace!.reveal(d.path);
      }, group: 'View'),
      PaletteCommand('Settings', () => showSettings(context), shortcut: 'Ctrl+,', group: 'Preferences'),
      PaletteCommand('Keyboard shortcuts', _showShortcuts, group: 'Help'),
    ];
  }

  void _showShortcuts() {
    showDialog(
      context: context,
      barrierColor: Colors.black45,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 16, 8),
                child: Row(
                  children: [
                    Text('Keyboard shortcuts', style: Tk.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.textStrong)),
                    const Spacer(),
                    IconBtn(icon: Icons.close_rounded, tooltip: 'Close', onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                  children: [
                    for (final c in [
                      ..._commands().where((c) => c.shortcut != null),
                      PaletteCommand('Next / previous tab', () {}, shortcut: 'Ctrl+Tab', group: 'View'),
                      PaletteCommand('Command history in console', () {}, shortcut: 'Up', group: 'Run'),
                      PaletteCommand('Send end of input', () {}, shortcut: 'Ctrl+Z', group: 'Run'),
                      PaletteCommand('Fold or unfold block', () {}, shortcut: 'Click gutter', group: 'Edit'),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(width: 90, child: Text(c.group, style: Tk.uiSmall.copyWith(color: Tk.textFaint))),
                            Expanded(child: Text(c.label, style: Tk.ui)),
                            KeyHint(c.shortcut!),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      barrierColor: Colors.black45,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppMark(size: 36),
                const SizedBox(height: 16),
                Text('SimpleIDE 1.0', style: Tk.ui.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: Tk.textStrong)),
                const SizedBox(height: 8),
                Text(
                  'A lightweight desktop IDE: code editor, file explorer, tabs, one-click run, an interactive console, '
                  'and auto-save. Programs are built and run by the compilers already installed on this computer.',
                  style: Tk.ui.copyWith(color: Tk.textMuted, height: 1.55),
                ),
                const SizedBox(height: 20),
                Align(alignment: Alignment.centerRight, child: PrimaryButton(label: 'Close', onPressed: () => Navigator.pop(ctx))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Global shortcuts ----------------------------------------------------

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final k = HardwareKeyboard.instance;
    final ctrl = k.isControlPressed;
    final shift = k.isShiftPressed;
    final alt = k.isAltPressed;
    final key = e.logicalKey;
    final i = ide;

    void run(FutureOr<void> Function() f) => f();

    if (key == LogicalKeyboardKey.f5 && !ctrl && !alt) {
      run(shift ? i.stopRun : i.runActive);
      return true;
    }
    if (alt && !ctrl && key == LogicalKeyboardKey.keyZ) {
      i.toggleWordWrap();
      return true;
    }
    if (!ctrl || alt) return false;

    final handlers = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.keyS: () => shift ? i.saveAll() : i.saveActive(),
      LogicalKeyboardKey.keyO: _openFolder,
      LogicalKeyboardKey.keyN: shift ? _newProject : _newFile,
      LogicalKeyboardKey.keyW: () => i.closeTab(i.activeIndex),
      LogicalKeyboardKey.keyB: () {
        if (shift) {
          i.runPrimaryBuild();
        } else if (i.workspace != null) {
          i.toggleSidebar();
        }
      },
      LogicalKeyboardKey.keyJ: i.toggleConsole,
      LogicalKeyboardKey.backquote: () {
        i.showConsole();
        i.focusConsoleRequest.value++;
      },
      LogicalKeyboardKey.keyP: () => showPalette(context, commands: _commands(), commandMode: shift),
      if (shift)
        LogicalKeyboardKey.keyF: () {
          if (i.workspace != null) i.selectSidebar(SidebarTab.search);
        },
      LogicalKeyboardKey.keyG: shift
          ? () {
              if (i.workspace != null) i.selectSidebar(SidebarTab.git);
            }
          : _goToLine,
      if (shift)
        LogicalKeyboardKey.keyA: () {
          if (i.workspace != null) i.selectSidebar(SidebarTab.agent);
        },
      LogicalKeyboardKey.comma: () => showSettings(context),
      LogicalKeyboardKey.tab: () => i.cycleTabs(shift ? -1 : 1),
      LogicalKeyboardKey.equal: () => i.zoom(1),
      LogicalKeyboardKey.add: () => i.zoom(1),
      LogicalKeyboardKey.numpadAdd: () => i.zoom(1),
      LogicalKeyboardKey.minus: () => i.zoom(-1),
      LogicalKeyboardKey.numpadSubtract: () => i.zoom(-1),
      LogicalKeyboardKey.digit0: i.resetZoom,
    };
    final h = handlers[key];
    if (h == null) return false;
    h();
    return true;
  }

  // --- Layout --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ide = ref.watch(ideProvider);
    final s = ide.settings;
    final ws = ide.workspace;
    return Scaffold(
      backgroundColor: Tk.editor,
      body: Stack(
        children: [
          Column(
            children: [
              TopBar(actions: _actions),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, shellBox) {
                    final maxSidebar = (shellBox.maxWidth - 260).clamp(140.0, 560.0);
                    final sidebarW = s.sidebarWidth.clamp(140.0, maxSidebar);
                    final showSidebar = ws != null && s.sidebarVisible && shellBox.maxWidth >= 420;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ActivityRail(actions: _actions),
                        if (showSidebar) ...[
                          SizedBox(
                            width: sidebarW,
                            child: switch (ide.sidebarTab) {
                              SidebarTab.explorer => ExplorerPanel(key: ValueKey(ws)),
                              SidebarTab.search => SearchPanel(key: ValueKey(('search', ws))),
                              SidebarTab.git => GitPanel(key: ValueKey(('git', ws))),
                              SidebarTab.agent => AgentPanel(key: ValueKey(('agent', ws))),
                            },
                          ),
                          Splitter(axis: Axis.horizontal, onDrag: (dx) => ide.setSidebarWidth(sidebarW + dx)),
                        ],
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final maxConsole = (box.maxHeight - 120).clamp(90.0, 2000.0);
                              final consoleH = s.consoleHeight.clamp(90.0, maxConsole);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: _editorArea(ide)),
                                  if (s.consoleVisible && ws != null) ...[
                                    Splitter(
                                      axis: Axis.vertical,
                                      onDrag: (dy) => ide.setConsoleHeight(consoleH - dy),
                                      onDoubleTap: () => ide.setConsoleHeight(consoleH < maxConsole * 0.6 ? maxConsole * 0.7 : 240),
                                    ),
                                    SizedBox(height: consoleH, child: const ConsolePanel()),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              StatusBar(actions: _actions),
            ],
          ),
          Positioned(right: 16, bottom: 36, child: _NoticeHost(notice: ide.notice)),
        ],
      ),
    );
  }

  Widget _editorArea(IdeController ide) {
    if (ide.workspace == null && ide.docs.isEmpty) return WelcomePage(onOpenFolder: _openFolder, onNewProject: _newProject);
    if (ide.active == null) {
      return EmptyEditor(
        onNewFile: _newFile,
        onQuickOpen: _actions.quickOpen,
        onCommandPalette: _actions.commandPalette,
        onSettings: _actions.settings,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabStrip(onNewFile: _newFile),
        const Expanded(child: EditorPane()),
      ],
    );
  }
}

/**
 * Transient message in the bottom-right corner.
 */
class _NoticeHost extends StatefulWidget {
  const _NoticeHost({required this.notice});
  final ValueNotifier<Notice?> notice;

  @override
  State<_NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends State<_NoticeHost> {
  Timer? _timer;
  Notice? _shown;

  @override
  void initState() {
    super.initState();
    widget.notice.addListener(_onNotice);
  }

  void _onNotice() {
    final n = widget.notice.value;
    if (n == null) return;
    setState(() => _shown = n);
    _timer?.cancel();
    _timer = Timer(Duration(seconds: n.error ? 7 : 3), () {
      if (mounted) setState(() => _shown = null);
    });
  }

  @override
  void dispose() {
    widget.notice.removeListener(_onNotice);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _shown;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: n == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(n.at),
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                color: Tk.raised,
                borderRadius: Tk.radiusLg,
                border: Border(
                  left: BorderSide(color: n.error ? Tk.error : Tk.info, width: 3),
                  top: const BorderSide(color: Tk.borderStrong),
                  right: const BorderSide(color: Tk.borderStrong),
                  bottom: const BorderSide(color: Tk.borderStrong),
                ),
                boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 6))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(n.error ? Icons.error_outline_rounded : Icons.info_outline_rounded, size: 16, color: n.error ? Tk.error : Tk.info),
                  const SizedBox(width: 10),
                  Flexible(child: Text(n.message, style: Tk.ui.copyWith(color: Tk.textStrong))),
                  const SizedBox(width: 6),
                  IconBtn(icon: Icons.close_rounded, tooltip: 'Dismiss', size: 14, box: 22, onPressed: () => setState(() => _shown = null)),
                ],
              ),
            ),
    );
  }
}
