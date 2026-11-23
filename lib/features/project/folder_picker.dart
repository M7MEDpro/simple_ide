import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * In-app folder chooser. Runs entirely on dart:io, so the IDE needs no
 * native plugins.
 */
Future<String?> pickFolder(BuildContext context, {String? start}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black45,
    builder: (_) => _FolderPicker(start: start),
  );
}

class _FolderPicker extends StatefulWidget {
  const _FolderPicker({this.start});
  final String? start;

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _Place {
  const _Place(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

class _FolderPickerState extends State<_FolderPicker> {
  late String _dir;
  final _path = TextEditingController();
  final _scroll = ScrollController();
  List<Directory> _children = [];
  String? _selected;
  String? _error;
  late final List<_Place> _places;

  static String get _home => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;

  @override
  void initState() {
    super.initState();
    final home = _home;
    _places = [
      _Place('Home', home, Icons.home_outlined),
      _Place('Desktop', p.join(home, 'Desktop'), Icons.desktop_windows_outlined),
      _Place('Documents', p.join(home, 'Documents'), Icons.description_outlined),
      _Place('Downloads', p.join(home, 'Downloads'), Icons.download_outlined),
    ].where((x) => Directory(x.path).existsSync()).toList();
    if (Platform.isWindows) {
      for (var c = 'C'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final d = '${String.fromCharCode(c)}:\\';
        if (Directory(d).existsSync()) _places.add(_Place('Drive ${String.fromCharCode(c)}:', d, Icons.storage_rounded));
      }
    }
    final start = widget.start;
    _go(start != null && Directory(start).existsSync() ? start : home);
  }

  @override
  void dispose() {
    _path.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _go(String dir) {
    final norm = p.normalize(dir);
    try {
      final kids = Directory(norm)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith(r'$'))
          .toList()
        ..sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      setState(() {
        _dir = norm;
        _children = kids;
        _selected = null;
        _error = null;
        _path.text = norm;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on FileSystemException catch (e) {
      setState(() => _error = 'Can\'t open ${p.basename(norm).isEmpty ? norm : p.basename(norm)}: ${e.osError?.message.trim() ?? e.message}');
    }
  }

  void _up() {
    final parent = p.dirname(_dir);
    if (parent != _dir) _go(parent);
  }

  String get _choice => _selected ?? _dir;

  Future<void> _newFolder() async {
    final name = await showTextPrompt(context, title: 'New folder in ${p.basename(_dir).isEmpty ? _dir : p.basename(_dir)}', action: 'Create', hint: 'folder name');
    if (name == null) return;
    try {
      final d = Directory(p.join(_dir, name))..createSync();
      _go(_dir);
      setState(() => _selected = d.path);
    } on FileSystemException catch (e) {
      setState(() => _error = 'Can\'t create $name: ${e.osError?.message.trim() ?? e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final choiceName = p.basename(_choice).isEmpty ? _choice : p.basename(_choice);
    return Dialog(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.backspace, alt: true): _up,
          const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _up,
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                child: Row(
                  children: [
                    Text('Open folder', style: Tk.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.textStrong)),
                    const Spacer(),
                    IconBtn(icon: Icons.close_rounded, tooltip: 'Cancel', onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    IconBtn(icon: Icons.arrow_upward_rounded, tooltip: 'Parent folder (Alt+Up)', onPressed: _up, box: 32),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _path,
                        style: Tk.code.copyWith(fontSize: 12.5),
                        decoration: const InputDecoration(hintText: 'Type a path and press Enter'),
                        onSubmitted: (v) {
                          final t = v.trim().replaceAll('"', '');
                          if (Directory(t).existsSync()) {
                            _go(t);
                          } else {
                            setState(() => _error = 'No folder at $t');
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: Tk.border))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 180,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            for (final pl in _places)
                              _Row(
                                icon: pl.icon,
                                label: pl.label,
                                selected: p.equals(pl.path, _dir),
                                onTap: () => _go(pl.path),
                              ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, color: Tk.border),
                      Expanded(
                        child: _children.isEmpty
                            ? Center(child: Text('No folders here', style: Tk.ui.copyWith(color: Tk.textFaint)))
                            : Scrollbar(
                                controller: _scroll,
                                child: ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  itemExtent: 28,
                                  itemCount: _children.length,
                                  itemBuilder: (context, i) {
                                    final d = _children[i];
                                    return _Row(
                                      icon: Icons.folder_rounded,
                                      iconColor: const Color(0xFF8A9BB8),
                                      label: p.basename(d.path),
                                      selected: _selected == d.path,
                                      onTap: () => setState(() => _selected = d.path),
                                      onDoubleTap: () => _go(d.path),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    GhostButton(label: 'New folder', onPressed: _newFolder),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error ?? 'Double-click a folder to look inside it.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Tk.uiSmall.copyWith(color: _error != null ? Tk.error : Tk.textFaint),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: PrimaryButton(label: 'Open $choiceName', onPressed: () => Navigator.pop(context, _choice)),
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

class _Row extends StatefulWidget {
  const _Row({required this.icon, required this.label, required this.selected, required this.onTap, this.onDoubleTap, this.iconColor});
  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.selected ? Tk.listActive : (_hover ? Tk.hover : Colors.transparent),
            borderRadius: Tk.radius,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: widget.iconColor ?? Tk.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tk.ui.copyWith(color: widget.selected ? Tk.textStrong : Tk.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
