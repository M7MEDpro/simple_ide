import 'package:flutter/material.dart';

import 'package:simple_ide/shared/tokens.dart';

/**
 * Drag handle between two panes. Shows an accent line while hovered or
 * dragged so the resize affordance is discoverable.
 */
class Splitter extends StatefulWidget {
  const Splitter({super.key, required this.axis, required this.onDrag, this.onDoubleTap});

  /**
   * [Axis.horizontal] resizes widths (vertical bar); [Axis.vertical] heights.
   */
  final Axis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDoubleTap;

  @override
  State<Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<Splitter> {
  bool _hot = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.axis == Axis.horizontal;
    final lit = _hot || _drag;
    return MouseRegion(
      cursor: h ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragStart: h ? (_) => setState(() => _drag = true) : null,
        onHorizontalDragUpdate: h ? (d) => widget.onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: h ? (_) => setState(() => _drag = false) : null,
        onVerticalDragStart: h ? null : (_) => setState(() => _drag = true),
        onVerticalDragUpdate: h ? null : (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: h ? null : (_) => setState(() => _drag = false),
        child: SizedBox(
          width: h ? 5 : double.infinity,
          height: h ? double.infinity : 5,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: h ? (lit ? 2 : 1) : double.infinity,
              height: h ? double.infinity : (lit ? 2 : 1),
              color: lit ? Tk.accent : Tk.border,
            ),
          ),
        ),
      ),
    );
  }
}
