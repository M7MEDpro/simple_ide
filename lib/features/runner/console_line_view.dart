import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/shared/tokens.dart';

/**
 * Single rendered line in the console output list, with clickable source links
 * when compiler diagnostics are attached.
 */
class ConsoleLineView extends StatefulWidget {
  const ConsoleLineView({
    super.key,
    required this.line,
    required this.fontSize,
    required this.onOpen,
  });

  final ConsoleLine line;
  final double fontSize;
  final ValueChanged<SourceLink> onOpen;

  @override
  State<ConsoleLineView> createState() => _ConsoleLineViewState();
}

class _ConsoleLineViewState extends State<ConsoleLineView> {
  bool _hover = false;

  static Color _color(ConsoleLine l) => switch (l.kind) {
        LineKind.stdout => Tk.text,
        LineKind.stderr => l.link?.severity == Severity.warning ? Tk.warning : const Color(0xFFEB8F91),
        LineKind.input => Tk.accent,
        LineKind.system => Tk.textMuted,
        LineKind.success => Tk.success,
        LineKind.failure => Tk.error,
      };

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final style = Tk.code.copyWith(fontSize: widget.fontSize, color: _color(l), height: 1.45);
    final link = l.link;
    if (link == null) {
      return Text(l.text.isEmpty ? ' ' : l.text, style: style);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.onOpen(link),
        child: Tooltip(
          message: 'Open ${p.basename(link.path)} at line ${link.line}',
          waitDuration: const Duration(milliseconds: 600),
          child: Text(
            l.text,
            style: style.copyWith(
              decoration: _hover ? TextDecoration.underline : TextDecoration.none,
              decorationColor: style.color,
            ),
          ),
        ),
      ),
    );
  }
}
