import 'package:flutter/material.dart';

import 'package:simple_ide/shared/tokens.dart';

/**
 * Editor area when a folder is open but no file tab is active.
 */
class EmptyEditor extends StatelessWidget {
  const EmptyEditor({
    super.key,
    this.onNewFile,
    this.onQuickOpen,
    this.onCommandPalette,
    this.onSettings,
  });

  final VoidCallback? onNewFile;
  final VoidCallback? onQuickOpen;
  final VoidCallback? onCommandPalette;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Go to File', 'Ctrl+P', onQuickOpen),
      ('Show All Commands', 'Ctrl+Shift+P', onCommandPalette),
      ('New File', 'Ctrl+N', onNewFile),
      ('Run Commands & Settings', 'Ctrl+,', onSettings),
    ];
    return Container(
      color: Tk.editor,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, keys, onTap) in rows)
            _EmptyActionRow(label: label, keys: keys, onTap: onTap),
        ],
      ),
    );
  }
}

class _EmptyActionRow extends StatefulWidget {
  const _EmptyActionRow({required this.label, required this.keys, this.onTap});

  final String label;
  final String keys;
  final VoidCallback? onTap;

  @override
  State<_EmptyActionRow> createState() => _EmptyActionRowState();
}

class _EmptyActionRowState extends State<_EmptyActionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: _hover && widget.onTap != null ? Tk.hover : Colors.transparent,
            borderRadius: Tk.radius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 170,
                child: Text(
                  widget.label,
                  textAlign: TextAlign.right,
                  style: Tk.ui.copyWith(color: _hover ? Tk.textStrong : Tk.textMuted),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 110,
                child: Text(widget.keys, style: Tk.ui.copyWith(color: Tk.textFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
