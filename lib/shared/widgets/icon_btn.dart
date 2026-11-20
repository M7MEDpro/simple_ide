import 'package:flutter/material.dart';

import 'package:simple_ide/shared/tokens.dart';

/**
 * Compact icon button with a hover surface, used across all toolbars.
 */
class IconBtn extends StatefulWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 16,
    this.box = 26,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double box;
  final Color? color;
  final bool active;

  @override
  State<IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? Tk.textFaint
        : widget.color ?? (widget.active || _hover ? Tk.textStrong : Tk.textMuted);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: widget.box,
            height: widget.box,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled && (_hover || widget.active) ? Tk.hover : Colors.transparent,
              borderRadius: Tk.radius,
            ),
            child: Icon(widget.icon, size: widget.size, color: color),
          ),
        ),
      ),
    );
  }
}
