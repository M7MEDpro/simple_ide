import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/explorer/workspace.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/features/diagnostics/diagnostic_layers.dart';
import 'package:simple_ide/features/project/new_file_dialog.dart';
import 'package:simple_ide/shared/widgets.dart';

const _rowH = 22.0;
const _indent = 12.0;

/**
 * Sidebar directory tree for the open folder.
 */
class ExplorerPanel extends ConsumerStatefulWidget {
  const ExplorerPanel({super.key});

  @override
  ConsumerState<ExplorerPanel> createState() => _ExplorerPanelState();
}

class _ExplorerPanelState extends ConsumerState<ExplorerPanel> {
  final _focus = FocusNode(debugLabel: 'explorer');
  final _scroll = ScrollController();
  String? _selected;

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ide = ref.watch(ideProvider);
    final ws = ide.workspace!;
    return Container(
      color: Tk.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Explorer', style: Tk.ui.copyWith(fontWeight: FontWeight.w600, color: Tk.textStrong)),
                  ),
                  IconBtn(icon: Icons.note_add_outlined, tooltip: 'New file', onPressed: () => _newEntry(context, folder: false)),
                  IconBtn(icon: Icons.create_new_folder_outlined, tooltip: 'New folder', onPressed: () => _newEntry(context, folder: true)),
                  IconBtn(icon: Icons.refresh_rounded, tooltip: 'Refresh', onPressed: () => ws.refresh()),
                  IconBtn(icon: Icons.unfold_less_rounded, tooltip: 'Collapse folders', onPressed: ws.collapseAll),
                ],
              ),
            ),
          ),
          _RootRow(name: ws.name, path: ws.root),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([ws, ide.diagnostics]),
              builder: (context, _) {
                final rows = ws.visibleRows();
                if (rows.isEmpty) return _EmptyFolder(onCreate: () => _newEntry(context, folder: false));
                final dirtyPaths = {
                  for (final d in ide.docs)
                    if (d.isDirty) p.normalize(d.path).toLowerCase(),
                };
                final hasDiags = !ide.diagnostics.isEmpty;
                return Focus(
                  focusNode: _focus,
                  onKeyEvent: (node, e) => _onKey(e, rows, ide),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _focus.requestFocus(),
                    onSecondaryTapUp: (d) => _rootMenu(context, d.globalPosition),
                    child: Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemExtent: _rowH,
                        itemCount: rows.length,
                        itemBuilder: (context, i) => _TreeRowView(
                          row: rows[i],
                          selected: _selected == rows[i].entry.path,
                          activeFile: ide.active?.path,
                          dirty: dirtyPaths.contains(p.normalize(rows[i].entry.path).toLowerCase()),
                          severity: hasDiags
                              ? ide.diagnostics.worstSeverity(rows[i].entry.path, isDir: rows[i].entry.isDir)
                              : null,
                          onTap: () => _activate(rows[i], ide),
                          onMenu: (pos) => _entryMenu(context, rows[i].entry, pos),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _activate(TreeRow row, IdeController ide) {
    setState(() => _selected = row.entry.path);
    _focus.requestFocus();
    if (row.entry.isDir) {
      ide.workspace!.toggle(row.entry.path);
    } else {
      ide.openFile(row.entry.path);
    }
  }

  KeyEventResult _onKey(KeyEvent e, List<TreeRow> rows, IdeController ide) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    var i = rows.indexWhere((r) => r.entry.path == _selected);
    final k = e.logicalKey;
    void select(int n) {
      if (rows.isEmpty) return;
      n = n.clamp(0, rows.length - 1);
      setState(() => _selected = rows[n].entry.path);
      final top = n * _rowH;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + _rowH > _scroll.offset + view) {
        _scroll.jumpTo(top + _rowH - view);
      }
    }

    if (k == LogicalKeyboardKey.arrowDown) {
      select(i + 1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      select(i < 0 ? 0 : i - 1);
    } else if (i < 0) {
      return KeyEventResult.ignored;
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      _activate(rows[i], ide);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      final r = rows[i];
      if (r.entry.isDir && !r.expanded) {
        ide.workspace!.toggle(r.entry.path);
      } else {
        select(i + 1);
      }
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      final r = rows[i];
      if (r.entry.isDir && r.expanded) {
        ide.workspace!.toggle(r.entry.path);
      } else {
        final parent = p.dirname(r.entry.path);
        final pi = rows.indexWhere((x) => x.entry.path == parent);
        if (pi >= 0) select(pi);
      }
    } else if (k == LogicalKeyboardKey.f2) {
      _rename(context, rows[i].entry);
    } else if (k == LogicalKeyboardKey.delete) {
      _delete(context, rows[i].entry);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String _targetDir(IdeController ide) {
    final sel = _selected;
    if (sel == null) return ide.workspace!.root;
    if (FileSystemEntity.isDirectorySync(sel)) return sel;
    return p.dirname(sel);
  }

  static String? _validName(String v) {
    if (v.isEmpty) return 'Enter a name';
    if (RegExp(r'[<>:"|?*]').hasMatch(v)) return 'Names can\'t contain < > : " | ? *';
    return null;
  }

  Future<void> _newEntry(BuildContext context, {required bool folder, String? dir}) async {
    final ide = ref.read(ideProvider);
    final target = dir ?? _targetDir(ide);
    if (!folder) {
      final created = await showNewFileDialog(context, ide, targetDir: target);
      if (created != null && mounted) setState(() => _selected = created);
      return;
    }
    final rel = p.relative(target, from: p.dirname(ide.workspace!.root));
    final name = await showTextPrompt(
      context,
      title: 'New folder in $rel',
      action: 'Create',
      hint: 'folder name',
      validate: _validName,
    );
    if (name == null) return;
    await ide.createEntry(target, name, folder: true);
    if (mounted) setState(() => _selected = p.join(target, name));
  }

  Future<void> _rename(BuildContext context, FsEntry e) async {
    final ide = ref.read(ideProvider);
    final ext = p.extension(e.name);
    final name = await showTextPrompt(
      context,
      title: 'Rename ${e.isDir ? 'folder' : 'file'}',
      action: 'Rename',
      initial: e.name,
      selection: TextSelection(baseOffset: 0, extentOffset: e.isDir || ext.isEmpty ? e.name.length : e.name.length - ext.length),
      validate: _validName,
    );
    if (name == null || name == e.name) return;
    await ide.renameEntry(e, name);
    setState(() => _selected = p.join(p.dirname(e.path), name));
  }

  Future<void> _delete(BuildContext context, FsEntry e) async {
    final ide = ref.read(ideProvider);
    final ok = await showConfirm(
      context,
      title: 'Delete ${e.name}?',
      message: e.isDir
          ? 'The folder and everything inside it will be permanently deleted from disk. This can\'t be undone.'
          : 'The file will be permanently deleted from disk. This can\'t be undone.',
      action: 'Delete',
      danger: true,
    );
    if (ok) await ide.deleteEntry(e);
  }

  void _rootMenu(BuildContext context, Offset pos) {
    final ide = ref.read(ideProvider);
    final root = ide.workspace!.root;
    showContextMenu(context, pos, [
      ContextItem('New file…', () => _newEntry(context, folder: false, dir: root)),
      ContextItem('New folder…', () => _newEntry(context, folder: true, dir: root)),
      const ContextItem.divider(),
      ContextItem('Reveal in File Explorer', () => Process.run('explorer.exe', [root])),
      ContextItem('Refresh', () => ide.workspace!.refresh()),
    ]);
  }

  void _entryMenu(BuildContext context, FsEntry e, Offset pos) {
    setState(() => _selected = e.path);
    final ide = ref.read(ideProvider);
    final dir = e.isDir ? e.path : p.dirname(e.path);
    showContextMenu(context, pos, [
      if (!e.isDir) ContextItem('Open', () => ide.openFile(e.path)),
      if (!e.isDir) ContextItem('Run', () async {
        await ide.openFile(e.path);
        await ide.runActive();
      }, shortcut: 'F5'),
      if (!e.isDir) const ContextItem.divider(),
      ContextItem('New file…', () => _newEntry(context, folder: false, dir: dir)),
      ContextItem('New folder…', () => _newEntry(context, folder: true, dir: dir)),
      const ContextItem.divider(),
      ContextItem('Rename…', () => _rename(context, e), shortcut: 'F2'),
      ContextItem('Delete', () => _delete(context, e), shortcut: 'Del', danger: true),
      const ContextItem.divider(),
      ContextItem('Copy path', () => Clipboard.setData(ClipboardData(text: e.path))),
      ContextItem('Copy relative path', () => Clipboard.setData(ClipboardData(text: p.relative(e.path, from: ide.workspace!.root)))),
      ContextItem('Reveal in File Explorer', () => Process.run('explorer.exe', ['/select,', e.path])),
      if (e.isDir) ContextItem('Open in console', () {
        ide.shellCwd = e.path;
        ide.console.cwd = e.path;
        ide.showConsole();
        ide.focusConsoleRequest.value++;
      }),
    ]);
  }
}

class _RootRow extends StatelessWidget {
  const _RootRow({required this.name, required this.path});
  final String name;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: path,
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 14, right: 10),
        alignment: Alignment.centerLeft,
        child: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: Tk.uiSmall.copyWith(color: Tk.textMuted, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _TreeRowView extends StatefulWidget {
  const _TreeRowView({
    required this.row,
    required this.selected,
    required this.activeFile,
    required this.dirty,
    this.severity,
    required this.onTap,
    required this.onMenu,
  });

  final TreeRow row;
  final bool selected;
  final String? activeFile;
  final bool dirty;
  final Severity? severity;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;

  @override
  State<_TreeRowView> createState() => _TreeRowViewState();
}

class _TreeRowViewState extends State<_TreeRowView> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.row.entry;
    final isActive = widget.activeFile != null && p.equals(widget.activeFile!, e.path);
    final bg = widget.selected
        ? Tk.listActive
        : isActive
            ? Tk.hover
            : _hover
                ? Tk.hover.withValues(alpha: 0.6)
                : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
        child: Container(
          color: bg,
          child: Stack(
            children: [
              // Indent guides.
              for (var d = 0; d < widget.row.depth; d++)
                Positioned(
                  left: 20 + d * _indent,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 1, color: Tk.border),
                ),
              Padding(
                padding: EdgeInsets.only(left: 8 + widget.row.depth * _indent, right: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: e.isDir
                          ? Icon(
                              widget.row.expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                              size: 16,
                              color: Tk.textMuted,
                            )
                          : null,
                    ),
                    const SizedBox(width: 2),
                    LangBadge(path: e.path, isDir: e.isDir, open: widget.row.expanded),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tk.ui.copyWith(
                          color: widget.severity != null && widget.severity != Severity.note
                              ? severityColor(widget.severity!)
                              : (e.hidden ? Tk.textMuted : (isActive ? Tk.textStrong : Tk.text)),
                        ),
                      ),
                    ),
                    if (widget.dirty)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: Tk.accent, shape: BoxShape.circle),
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
}

class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This folder is empty.', style: Tk.ui.copyWith(color: Tk.textMuted)),
          const SizedBox(height: 12),
          GhostButton(label: 'Create a file', onPressed: onCreate),
        ],
      ),
    );
  }
}
