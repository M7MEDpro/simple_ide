import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/app/shell_actions.dart';
import 'package:simple_ide/features/project/project_config_dialog.dart';
import 'package:simple_ide/features/runner/build_tools.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Menu bar, quick-open search box, build tool selector, and run controls.
 */
class TopBar extends ConsumerWidget {
  const TopBar({super.key, required this.actions});

  final ShellActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ide = ref.watch(ideProvider);
    final hasDoc = ide.active != null;
    final hasWs = ide.workspace != null;
    final a = actions;
    MenuItemButton item(String label, VoidCallback? onPressed, [MenuSerializableShortcut? sc]) =>
        MenuItemButton(onPressed: onPressed, shortcut: sc, child: Text(label));
    const ctrl = true;

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Tk.chrome,
        border: Border(bottom: BorderSide(color: Tk.border)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final showSearch = hasWs && box.maxWidth >= 520;
          final showDocName = box.maxWidth >= 680;
          return Row(
            children: [
              const SizedBox(width: 4),
              MenuBar(
                children: [
                  SubmenuButton(
                    menuChildren: [
                      item('New project…', a.newProject, const SingleActivator(LogicalKeyboardKey.keyN, control: ctrl, shift: true)),
                      item('New file…', hasWs ? a.newFile : null, const SingleActivator(LogicalKeyboardKey.keyN, control: ctrl)),
                      item('Open folder…', a.openFolder, const SingleActivator(LogicalKeyboardKey.keyO, control: ctrl)),
                      SubmenuButton(
                        menuChildren: [
                          if (ide.settings.recentFolders.isEmpty) item('No recent folders', null),
                          for (final f in ide.settings.recentFolders)
                            MenuItemButton(onPressed: () => ide.openFolder(f), child: Text(f)),
                        ],
                        child: const Text('Open recent'),
                      ),
                      const Divider(height: 9),
                      item('Save', hasDoc ? ide.saveActive : null, const SingleActivator(LogicalKeyboardKey.keyS, control: ctrl)),
                      item('Save all', hasDoc ? ide.saveAll : null, const SingleActivator(LogicalKeyboardKey.keyS, control: ctrl, shift: true)),
                      const Divider(height: 9),
                      item('Close tab', hasDoc ? () => ide.closeTab(ide.activeIndex) : null, const SingleActivator(LogicalKeyboardKey.keyW, control: ctrl)),
                      item('Close folder', hasWs ? ide.closeFolder : null),
                      const Divider(height: 9),
                      item('Settings', a.settings, const SingleActivator(LogicalKeyboardKey.comma, control: ctrl)),
                      const Divider(height: 9),
                      item('Exit', a.exit),
                    ],
                    child: const Text('File'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item('Undo', hasDoc ? () => a.editorIntent(const CodeShortcutUndoIntent()) : null, const SingleActivator(LogicalKeyboardKey.keyZ, control: ctrl)),
                      item('Redo', hasDoc ? () => a.editorIntent(const CodeShortcutRedoIntent()) : null, const SingleActivator(LogicalKeyboardKey.keyY, control: ctrl)),
                      const Divider(height: 9),
                      item('Cut', hasDoc ? () => a.editorIntent(const CodeShortcutCutIntent()) : null, const SingleActivator(LogicalKeyboardKey.keyX, control: ctrl)),
                      item('Copy', hasDoc ? () => a.editorIntent(const CodeShortcutCopyIntent()) : null, const SingleActivator(LogicalKeyboardKey.keyC, control: ctrl)),
                      item('Paste', hasDoc ? () => a.editorIntent(const CodeShortcutPasteIntent()) : null, const SingleActivator(LogicalKeyboardKey.keyV, control: ctrl)),
                      item('Select all', hasDoc ? () => a.editorIntent(const CodeShortcutSelectAllIntent()) : null, const SingleActivator(LogicalKeyboardKey.keyA, control: ctrl)),
                      const Divider(height: 9),
                      item('Find', hasDoc ? () => a.editorIntent(const CodeShortcutFindIntent()) : null, const SingleActivator(LogicalKeyboardKey.keyF, control: ctrl)),
                      item('Replace', hasDoc ? () => a.editorIntent(const CodeShortcutReplaceIntent()) : null, const SingleActivator(LogicalKeyboardKey.keyH, control: ctrl)),
                      item('Toggle line comment', hasDoc ? () => a.editorIntent(const CodeShortcutCommentIntent(true)) : null, const SingleActivator(LogicalKeyboardKey.slash, control: ctrl)),
                      item('Go to line…', hasDoc ? a.goToLine : null, const SingleActivator(LogicalKeyboardKey.keyG, control: ctrl)),
                    ],
                    child: const Text('Edit'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item('Command palette…', a.commandPalette, const SingleActivator(LogicalKeyboardKey.keyP, control: ctrl, shift: true)),
                      item('Go to file…', hasWs ? a.quickOpen : null, const SingleActivator(LogicalKeyboardKey.keyP, control: ctrl)),
                      const Divider(height: 9),
                      CheckboxMenuButton(
                        value: ide.settings.sidebarVisible,
                        onChanged: hasWs ? (_) => ide.toggleSidebar() : null,
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyB, control: ctrl),
                        child: const Text('Explorer'),
                      ),
                      CheckboxMenuButton(
                        value: ide.settings.consoleVisible,
                        onChanged: (_) => ide.toggleConsole(),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyJ, control: ctrl),
                        child: const Text('Console'),
                      ),
                      CheckboxMenuButton(
                        value: ide.settings.wordWrap,
                        onChanged: (_) => ide.toggleWordWrap(),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, alt: true),
                        child: const Text('Word wrap'),
                      ),
                      const Divider(height: 9),
                      item('Zoom in', () => ide.zoom(1), const SingleActivator(LogicalKeyboardKey.equal, control: ctrl)),
                      item('Zoom out', () => ide.zoom(-1), const SingleActivator(LogicalKeyboardKey.minus, control: ctrl)),
                      item('Reset zoom', ide.resetZoom, const SingleActivator(LogicalKeyboardKey.digit0, control: ctrl)),
                    ],
                    child: const Text('View'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item('Run', (hasDoc || (ide.projectConfig.runCommand?.isNotEmpty ?? false)) ? ide.runActive : null, const SingleActivator(LogicalKeyboardKey.f5)),
                      item('Build project', (ide.buildTasks.isNotEmpty || (ide.projectConfig.buildCommand?.isNotEmpty ?? false)) ? ide.runPrimaryBuild : null, const SingleActivator(LogicalKeyboardKey.keyB, control: ctrl, shift: true)),
                      item('Stop', ide.runner.busy ? ide.stopRun : null, const SingleActivator(LogicalKeyboardKey.f5, shift: true)),
                      const Divider(height: 9),
                      item('Focus console input', () {
                        ide.showConsole();
                        ide.focusConsoleRequest.value++;
                      }, const SingleActivator(LogicalKeyboardKey.backquote, control: ctrl)),
                      item('Clear console', ide.console.clear),
                      const Divider(height: 9),
                      item('Project run config…', hasWs ? () => showProjectConfigDialog(context, ide) : null),
                      item('Run commands…', a.settings),
                    ],
                    child: const Text('Run'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item('Keyboard shortcuts', a.shortcuts),
                      item('About SimpleIDE', a.about),
                    ],
                    child: const Text('Help'),
                  ),
                ],
              ),
              Expanded(
                child: showSearch
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Center(
                          child: _SearchBox(
                            label: ide.workspace!.name,
                            showShortcut: box.maxWidth >= 660,
                            onTap: a.quickOpen,
                          ),
                        ),
                      )
                    : const SizedBox(),
              ),
              if (hasWs) _RunControls(ide: ide, showDocName: showDocName, onConfigureRun: a.settings),
              const SizedBox(width: 10),
            ],
          );
        },
      ),
    );
  }
}

class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.label, required this.onTap, this.showShortcut = true});
  final String label;
  final VoidCallback onTap;
  final bool showShortcut;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover ? Tk.hover : Tk.sidebar,
            borderRadius: Tk.radiusLg,
            border: Border.all(color: _hover ? Tk.borderStrong : Tk.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_rounded, size: 15, color: Tk.textMuted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tk.ui.copyWith(color: Tk.textMuted)),
              ),
              if (widget.showShortcut) ...[
                const SizedBox(width: 8),
                Text('Ctrl+P', style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RunControls extends StatelessWidget {
  const _RunControls({required this.ide, this.showDocName = true, required this.onConfigureRun});
  final IdeController ide;
  final bool showDocName;
  final VoidCallback onConfigureRun;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ide.runner,
      builder: (context, _) {
        final doc = ide.active;
        final busy = ide.runner.busy;
        final runnable = doc != null &&
            !doc.binary &&
            (doc.language.runnable || ide.settings.runOverrides.containsKey(p.extension(doc.path).toLowerCase()));
        final canRun = doc != null && !doc.binary;
        return Row(
          children: [
            if (doc != null && showDocName) ...[
              LangBadge(path: doc.path),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tk.ui.copyWith(color: Tk.textMuted)),
              ),
              const SizedBox(width: 10),
            ],
            if (busy) ...[
              _StopButton(onPressed: ide.stopRun),
              const SizedBox(width: 6),
            ],
            if (ide.buildTasks.isNotEmpty && showDocName) ...[
              _BuildToolMenu(tasks: ide.buildTasks, onPick: ide.runBuildTask),
              const SizedBox(width: 6),
            ],
            _RunButton(
              label: busy ? 'Restart' : (canRun && !runnable ? 'Set Run' : 'Run'),
              icon: busy ? Icons.replay_rounded : (canRun && !runnable ? Icons.tune_rounded : Icons.play_arrow_rounded),
              onPressed: canRun ? (runnable ? ide.runActive : onConfigureRun) : null,
            ),
          ],
        );
      },
    );
  }
}

class _BuildToolMenu extends StatelessWidget {
  const _BuildToolMenu({required this.tasks, required this.onPick});
  final List<BuildTask> tasks;
  final ValueChanged<BuildTask> onPick;

  @override
  Widget build(BuildContext context) {
    final primaryTool = tasks.first.tool;
    return PopupMenuButton<BuildTask>(
      tooltip: 'Build tool tasks ($primaryTool)',
      color: Tk.raised,
      surfaceTintColor: Colors.transparent,
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: Tk.radiusLg, side: BorderSide(color: Tk.borderStrong)),
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final t in tasks)
          PopupMenuItem<BuildTask>(
            value: t,
            height: 30,
            child: Row(
              children: [
                Text('${t.tool}: ${t.label}', style: Tk.ui.copyWith(color: Tk.textStrong)),
                const Spacer(),
                const SizedBox(width: 12),
                Text(t.command, style: Tk.code.copyWith(fontSize: 11, color: Tk.textFaint)),
              ],
            ),
          ),
      ],
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Tk.sidebar,
          borderRadius: Tk.radius,
          border: Border.all(color: Tk.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_outlined, size: 13, color: Tk.textMuted),
            const SizedBox(width: 5),
            Text(primaryTool, style: Tk.uiSmall.copyWith(color: Tk.text)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Tk.textMuted),
          ],
        ),
      ),
    );
  }
}

class _RunButton extends StatefulWidget {
  const _RunButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final bg = !enabled
        ? Tk.hover
        : _down
            ? const Color(0xFFCF9A3B)
            : _hover
                ? const Color(0xFFF0BE62)
                : Tk.accent;
    return Tooltip(
      message: enabled ? 'Save all and run the open file (F5)' : 'Open a file to run it',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: Container(
            height: 26,
            padding: const EdgeInsets.only(left: 8, right: 12),
            decoration: BoxDecoration(color: bg, borderRadius: Tk.radius),
            child: Row(
              children: [
                Icon(widget.icon, size: 17, color: enabled ? Tk.accentInk : Tk.textFaint),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: Tk.ui.copyWith(fontWeight: FontWeight.w600, color: enabled ? Tk.accentInk : Tk.textFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Stop (Shift+F5)',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.stop_rounded, size: 16),
        label: const Text('Stop'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Tk.error,
          side: BorderSide(color: Tk.error.withValues(alpha: 0.6)),
          minimumSize: const Size(0, 26),
          maximumSize: const Size(double.infinity, 26),
          padding: const EdgeInsets.only(left: 6, right: 10),
          textStyle: Tk.ui.copyWith(fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: Tk.radius),
        ),
      ),
    );
  }
}
