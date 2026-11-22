import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/features/diagnostics/diagnostics.dart';
import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/features/diagnostics/diagnostic_layers.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * All current problems, grouped by file. Clicking one opens the file at
 * that line.
 */
class ProblemsView extends ConsumerWidget {
  const ProblemsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ide = ref.read(ideProvider);
    final store = ref.watch(diagnosticsProvider);
    if (store.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Text('No problems in open files.', style: Tk.ui.copyWith(color: Tk.textFaint)),
      );
    }
    final rows = <Widget>[];
    final root = ide.workspace?.root;
    for (final file in store.files) {
      final items = store.forFile(file);
      final stale = store.isStale(file);
      rows.add(_FileRow(
        path: file,
        detail: root != null && p.isWithin(root, file) ? p.relative(p.dirname(file), from: root) : p.dirname(file),
        count: items.length,
        stale: stale,
      ));
      for (final d in items) {
        rows.add(_ProblemRow(
          d: d,
          stale: stale,
          onTap: () => ide.openFile(d.path, line: d.line, column: d.column),
        ));
      }
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: rows);
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.path, required this.detail, required this.count, required this.stale});
  final String path;
  final String detail;
  final int count;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            LangBadge(path: path),
            const SizedBox(width: 6),
            Text(p.basename(path), style: Tk.ui.copyWith(color: Tk.textStrong)),
            const SizedBox(width: 8),
            if (detail != '.') Text(detail, style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
            const SizedBox(width: 8),
            Text('$count', style: Tk.uiSmall.copyWith(color: Tk.textMuted)),
            if (stale) ...[
              const SizedBox(width: 10),
              Text('edited since last check', style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProblemRow extends StatefulWidget {
  const _ProblemRow({required this.d, required this.stale, required this.onTap});
  final Diagnostic d;
  final bool stale;
  final VoidCallback onTap;

  @override
  State<_ProblemRow> createState() => _ProblemRowState();
}

class _ProblemRowState extends State<_ProblemRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final color = severityColor(d.severity);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 24,
          color: _hover ? Tk.hover : Colors.transparent,
          padding: const EdgeInsets.only(left: 38, right: 14),
          child: Opacity(
            opacity: widget.stale ? 0.55 : 1,
            child: Row(
              children: [
                Icon(
                  d.severity == Severity.error ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(d.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tk.ui),
                ),
                const SizedBox(width: 10),
                Text('${d.line}:${d.column}', style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
