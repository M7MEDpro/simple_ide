import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/features/editor/document.dart';
import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/features/diagnostics/diagnostic_layers.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Open-document tabs above the editor. Drag to reorder, middle-click or
 * Ctrl+W to close, right-click for bulk actions.
 */
class TabStrip extends ConsumerStatefulWidget {
  const TabStrip({super.key, this.onNewFile});
  final VoidCallback? onNewFile;

  @override
  ConsumerState<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends ConsumerState<TabStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ide = ref.watch(ideProvider);
    final diags = ref.watch(diagnosticsProvider);
    final docs = ide.docs;
    final names = <String, int>{};
    for (final d in docs) {
      names[d.name] = (names[d.name] ?? 0) + 1;
    }
    return Container(
      height: 35,
      decoration: const BoxDecoration(
        color: Tk.sidebar,
        border: Border(bottom: BorderSide(color: Tk.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Listener(
              // Vertical wheel scrolls the strip sideways.
              onPointerSignal: (e) {
                if (e is PointerScrollEvent && _scroll.hasClients) {
                  final pos = _scroll.position;
                  _scroll.jumpTo((pos.pixels + e.scrollDelta.dy + e.scrollDelta.dx).clamp(0, pos.maxScrollExtent));
                }
              },
              child: ReorderableListView.builder(
                scrollController: _scroll,
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                itemCount: docs.length,
                onReorderItem: ide.moveTab,
                proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final dupe = (names[d.name] ?? 0) > 1;
                  return ReorderableDelayedDragStartListener(
                    key: ObjectKey(d),
                    index: i,
                    child: _Tab(
                      doc: d,
                      active: i == ide.activeIndex,
                      hint: dupe ? p.basename(p.dirname(d.path)) : null,
                      severity: diags.isEmpty ? null : diags.worstSeverity(d.path),
                      onTap: () => ide.activate(i),
                      onClose: () => ide.closeTab(i),
                      onMenu: (pos) => _menu(context, ide, i, pos),
                    ),
                  );
                },
              ),
            ),
          ),
          if (widget.onNewFile != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: IconBtn(icon: Icons.add_rounded, tooltip: 'New file (Ctrl+N)', onPressed: widget.onNewFile),
            ),
        ],
      ),
    );
  }

  void _menu(BuildContext context, IdeController ide, int i, Offset pos) {
    final d = ide.docs[i];
    showContextMenu(context, pos, [
      ContextItem('Close', () => ide.closeTab(i), shortcut: 'Ctrl+W'),
      ContextItem('Close others', () => ide.closeWhere((x) => x != d)),
      ContextItem('Close to the right', () {
        final keep = ide.docs.sublist(0, i + 1).toSet();
        ide.closeWhere((x) => !keep.contains(x));
      }),
      ContextItem('Close saved', () => ide.closeWhere((x) => !x.isDirty)),
      ContextItem('Close all', () => ide.closeWhere((_) => true)),
      const ContextItem.divider(),
      ContextItem('Copy path', () => Clipboard.setData(ClipboardData(text: d.path))),
      ContextItem('Reveal in File Explorer', () => Process.run('explorer.exe', ['/select,', d.path])),
    ]);
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.doc,
    required this.active,
    required this.hint,
    this.severity,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
  });

  final EditorDocument doc;
  final bool active;
  final String? hint;
  final Severity? severity;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<Offset> onMenu;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    final active = widget.active;
    return Tooltip(
      message: d.path,
      waitDuration: const Duration(milliseconds: 900),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Listener(
          onPointerDown: (e) {
            if (e.buttons == kMiddleMouseButton) widget.onClose();
          },
          child: GestureDetector(
            onTap: widget.onTap,
            onSecondaryTapUp: (e) => widget.onMenu(e.globalPosition),
            child: Container(
              constraints: const BoxConstraints(minWidth: 90, maxWidth: 240),
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: BoxDecoration(
                color: active ? Tk.editor : (_hover ? Tk.hover.withValues(alpha: 0.5) : Colors.transparent),
                border: Border(
                  top: BorderSide(color: active ? Tk.accent : Colors.transparent, width: 2),
                  right: const BorderSide(color: Tk.border),
                  bottom: BorderSide(color: active ? Tk.editor : Colors.transparent),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LangBadge(path: d.path),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tk.ui.copyWith(
                        color: widget.severity != null && widget.severity != Severity.note
                            ? severityColor(widget.severity!)
                            : (active ? Tk.textStrong : Tk.textMuted),
                        fontStyle: d.readOnly ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  if (widget.hint != null) ...[
                    const SizedBox(width: 6),
                    Text(widget.hint!, style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
                  ],
                  const SizedBox(width: 4),
                  _closeOrDirty(d),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _closeOrDirty(EditorDocument d) {
    final showDot = (d.isDirty || d.state == SaveState.failed) && !_hover;
    if (showDot) {
      return SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: d.state == SaveState.failed ? Tk.error : Tk.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    return Opacity(
      opacity: widget.active || _hover ? 1 : 0,
      child: IconBtn(icon: Icons.close_rounded, tooltip: 'Close (Ctrl+W)', size: 14, box: 22, onPressed: widget.onClose),
    );
  }
}
