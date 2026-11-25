import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

class PaletteCommand {
  const PaletteCommand(this.label, this.run, {this.shortcut, this.group = 'General'});
  final String label;
  final String? shortcut;
  final String group;
  final VoidCallback run;
}

/**
 * Scores [query] as a subsequence of [text]. Higher is better; null means
 * no match. Rewards consecutive runs and matches at word starts.
 *
 * @param query what the user typed
 * @param text  candidate, e.g. a relative file path
 * @return a score where higher is better, or null when there is no match
 */
int? fuzzyScore(String query, String text) {
  if (query.isEmpty) return 0;
  final q = query.toLowerCase();
  final t = text.toLowerCase();
  var score = 0;
  var ti = 0;
  var run = 0;
  for (var qi = 0; qi < q.length; qi++) {
    final c = q[qi];
    if (c == ' ') continue;
    var found = false;
    while (ti < t.length) {
      if (t[ti] == c) {
        final boundary = ti == 0 || const ['/', '\\', '_', '-', '.', ' '].contains(t[ti - 1]);
        run++;
        score += 1 + run * 2 + (boundary ? 6 : 0);
        ti++;
        found = true;
        break;
      }
      run = 0;
      ti++;
    }
    if (!found) return null;
  }
  return score - (t.length ~/ 12);
}

/**
 * Quick open (files) and command palette (prefix with `>`).
 */
Future<void> showPalette(BuildContext context, {required List<PaletteCommand> commands, bool commandMode = false}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (ctx, _, _) => Consumer(
      builder: (_, ref, _) => _Palette(ide: ref.read(ideProvider), commands: commands, commandMode: commandMode),
    ),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.ide, required this.commands, required this.commandMode});
  final IdeController ide;
  final List<PaletteCommand> commands;
  final bool commandMode;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _Item {
  _Item({required this.title, this.detail, this.shortcut, required this.onRun, this.path});
  final String title;
  final String? detail;
  final String? shortcut;
  final String? path;
  final VoidCallback onRun;
}

class _PaletteState extends State<_Palette> {
  late final TextEditingController _q = TextEditingController(text: widget.commandMode ? '> ' : '');
  final _scroll = ScrollController();
  late final List<String> _files = widget.ide.workspace?.allFiles() ?? const [];
  List<_Item> _items = [];
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    _q.addListener(_update);
    _update();
  }

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _update() {
    final raw = _q.text;
    final ide = widget.ide;
    List<_Item> items;
    if (raw.startsWith('>')) {
      final q = raw.substring(1).trim();
      final scored = <(int, PaletteCommand)>[];
      for (final c in widget.commands) {
        final s = fuzzyScore(q, '${c.group}: ${c.label}');
        if (s != null) scored.add((s, c));
      }
      if (q.isNotEmpty) scored.sort((a, b) => b.$1.compareTo(a.$1));
      items = [
        for (final (_, c) in scored)
          _Item(title: c.label, detail: c.group, shortcut: c.shortcut, onRun: c.run),
      ];
    } else if (raw.startsWith(':')) {
      final n = int.tryParse(raw.substring(1).trim());
      final doc = ide.active;
      items = [
        if (doc != null && n != null)
          _Item(
            title: 'Go to line $n',
            detail: doc.name,
            onRun: () {
              ide.revealLine(doc, n, 1);
              ide.focusEditorRequest.value++;
            },
          )
        else
          _Item(title: doc == null ? 'Open a file first' : 'Type a line number', onRun: () {}),
      ];
    } else {
      final root = ide.workspace?.root;
      final q = raw.trim();
      final scored = <(int, String)>[];
      for (final f in _files) {
        final rel = root == null ? f : p.relative(f, from: root);
        var s = fuzzyScore(q, rel);
        if (s == null) continue;
        final nameScore = fuzzyScore(q, p.basename(f));
        if (nameScore != null) s += nameScore + 10;
        // Recently open files float up when the query is empty.
        if (ide.docs.any((d) => p.equals(d.path, f))) s += q.isEmpty ? 1000 : 4;
        scored.add((s, f));
      }
      scored.sort((a, b) => b.$1.compareTo(a.$1));
      items = [
        for (final (_, f) in scored.take(200))
          _Item(
            title: p.basename(f),
            detail: root == null ? p.dirname(f) : p.relative(p.dirname(f), from: root),
            path: f,
            onRun: () => ide.openFile(f),
          ),
      ];
    }
    setState(() {
      _items = items;
      _sel = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int d) {
    if (_items.isEmpty) return;
    setState(() => _sel = (_sel + d) % _items.length);
    const h = 30.0;
    final top = _sel * h;
    if (!_scroll.hasClients) return;
    if (top < _scroll.offset) _scroll.jumpTo(top);
    if (top + h > _scroll.offset + _scroll.position.viewportDimension) {
      _scroll.jumpTo(top + h - _scroll.position.viewportDimension);
    }
  }

  void _run(int i) {
    if (i < 0 || i >= _items.length) return;
    final item = _items[i];
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => item.onRun());
  }

  @override
  Widget build(BuildContext context) {
    final cmd = _q.text.startsWith('>');
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 46),
        child: Material(
          color: Tk.raised,
          elevation: 16,
          shadowColor: Colors.black,
          shape: const RoundedRectangleBorder(borderRadius: Tk.radiusLg, side: BorderSide(color: Tk.borderStrong)),
          child: SizedBox(
            width: 620,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
                const SingleActivator(LogicalKeyboardKey.enter): () => _run(_sel),
                const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: _q,
                      autofocus: true,
                      style: Tk.ui.copyWith(fontSize: 14, color: Tk.textStrong),
                      decoration: InputDecoration(
                        hintText: 'Search files by name. Type > for commands, : for a line number',
                        prefixIcon: Icon(cmd ? Icons.chevron_right_rounded : Icons.search_rounded, size: 18, color: Tk.textMuted),
                        prefixIconConstraints: const BoxConstraints(minWidth: 34),
                      ),
                    ),
                  ),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Text(
                        cmd ? 'No matching commands' : (widget.ide.workspace == null ? 'Open a folder to search its files' : 'No matching files'),
                        style: Tk.ui.copyWith(color: Tk.textMuted),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 6),
                        itemExtent: 30,
                        itemCount: _items.length,
                        itemBuilder: (context, i) => _ItemView(
                          item: _items[i],
                          selected: i == _sel,
                          onTap: () => _run(i),
                          onHover: () => setState(() => _sel = i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemView extends StatelessWidget {
  const _ItemView({required this.item, required this.selected, required this.onTap, required this.onHover});
  final _Item item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (_) {
        if (!selected) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: selected ? Tk.listActive : Colors.transparent, borderRadius: Tk.radius),
          child: Row(
            children: [
              if (item.path != null) ...[
                LangBadge(path: item.path!),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tk.ui.copyWith(color: Tk.textStrong)),
              ),
              if (item.detail != null && item.detail != '.') ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
                ),
              ] else
                const Spacer(),
              if (item.shortcut != null) KeyHint(item.shortcut!),
            ],
          ),
        ),
      ),
    );
  }
}
