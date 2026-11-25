import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/app/shell_actions.dart';
import 'package:simple_ide/features/editor/document.dart';
import 'package:simple_ide/features/runner/console_panel.dart';
import 'package:simple_ide/features/runner/runner.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Bottom status bar showing run state, problem counts, cursor position, and
 * document metadata.
 */
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key, required this.actions});

  final ShellActions actions;

  static const _s = TextStyle(
    fontFamily: Tk.uiFont,
    fontFamilyFallback: Tk.uiFallback,
    fontSize: 12,
    color: Tk.textMuted,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ide = ref.watch(ideProvider);
    final doc = ide.active;
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        color: Tk.chrome,
        border: Border(top: BorderSide(color: Tk.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListenableBuilder(
                      listenable: ide.runner,
                      builder: (context, _) => ide.runner.status == RunStatus.idle
                          ? const SizedBox.shrink()
                          : _Seg(
                              onTap: ide.showConsole,
                              tooltip: 'Show console',
                              child: RunStateChip(runner: ide.runner, compact: true),
                            ),
                    ),
                    ListenableBuilder(
                      listenable: ide.diagnostics,
                      builder: (context, _) {
                        final c = ide.diagnostics;
                        if (c.isEmpty) return const SizedBox.shrink();
                        return _Seg(
                          onTap: ide.showProblems,
                          tooltip: 'Show problems',
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 13, color: Tk.error),
                              const SizedBox(width: 3),
                              Text('${c.errorCount}', style: _s),
                              const SizedBox(width: 8),
                              const Icon(Icons.warning_amber_rounded, size: 13, color: Tk.warning),
                              const SizedBox(width: 3),
                              Text('${c.warningCount}', style: _s),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (doc != null) ...[
                      _SaveState(doc: doc),
                      FrameSafeBuilder(
                        listenable: doc.controller,
                        builder: (context) {
                          final sel = doc.controller.selection;
                          final selected = sel.isCollapsed ? 0 : doc.controller.selectedText.length;
                          return _Seg(
                            onTap: actions.goToLine,
                            tooltip: 'Go to line (Ctrl+G)',
                            child: Text(
                              'Ln ${sel.extentIndex + 1}, Col ${sel.extentOffset + 1}${selected > 0 ? '  ($selected selected)' : ''}',
                              style: _s,
                            ),
                          );
                        },
                      ),
                      _Seg(child: Text(doc.lineEnding == '\r\n' ? 'CRLF' : 'LF', style: _s)),
                      _Seg(child: Text('UTF-8', style: _s)),
                      _Seg(child: Text(doc.language.name, style: _s)),
                    ],
                    const _Seg(
                      tooltip: 'Auto-save is always enabled',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_done_outlined, size: 13, color: Tk.textMuted),
                          SizedBox(width: 5),
                          Text('Auto-save', style: _s),
                        ],
                      ),
                    ),
                    if (ide.workspace != null)
                      _Seg(
                        tooltip: ide.workspace!.root,
                        child: Text(p.basename(ide.workspace!.root), style: _s),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveState extends StatelessWidget {
  const _SaveState({required this.doc});
  final EditorDocument doc;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: doc,
      builder: (context, _) {
        final (label, color) = switch (doc.state) {
          SaveState.saved => (doc.readOnly ? 'Read-only' : 'Saved', Tk.textMuted),
          SaveState.dirty => ('Unsaved', Tk.accent),
          SaveState.saving => ('Saving…', Tk.textMuted),
          SaveState.failed => ('Save failed', Tk.error),
        };
        return _Seg(
          tooltip: doc.lastError ?? doc.path,
          child: Text(label, style: StatusBar._s.copyWith(color: color)),
        );
      },
    );
  }
}

class _Seg extends StatefulWidget {
  const _Seg({required this.child, this.onTap, this.tooltip});

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  State<_Seg> createState() => _SegState();
}

class _SegState extends State<_Seg> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget w = MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          color: widget.onTap != null && _hover ? Tk.hover : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return w;
  }
}
