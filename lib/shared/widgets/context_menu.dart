import 'package:flutter/material.dart';

import 'package:simple_ide/shared/tokens.dart';

/**
 * Opens a context menu at a global position.
 */
Future<void> showContextMenu(BuildContext context, Offset at, List<ContextItem> items) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(at);
  final picked = await showMenu<int>(
    context: context,
    color: Tk.raised,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    menuPadding: const EdgeInsets.symmetric(vertical: 4),
    shape: const RoundedRectangleBorder(borderRadius: Tk.radiusLg, side: BorderSide(color: Tk.borderStrong)),
    position: RelativeRect.fromLTRB(local.dx, local.dy, overlay.size.width - local.dx, overlay.size.height - local.dy),
    items: [
      for (var i = 0; i < items.length; i++)
        if (items[i].divider)
          const PopupMenuDivider(height: 9)
        else
          PopupMenuItem<int>(
            value: i,
            height: 28,
            enabled: items[i].onTap != null,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 210,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      items[i].label,
                      style: Tk.ui.copyWith(color: items[i].danger ? Tk.error : (items[i].onTap == null ? Tk.textFaint : Tk.text)),
                    ),
                  ),
                  if (items[i].shortcut != null) Text(items[i].shortcut!, style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
                ],
              ),
            ),
          ),
    ],
  );
  if (picked != null) items[picked].onTap?.call();
}

/**
 * Single action or divider entry in [showContextMenu].
 */
class ContextItem {
  const ContextItem(this.label, this.onTap, {this.shortcut, this.danger = false}) : divider = false;
  const ContextItem.divider()
      : label = '',
        onTap = null,
        shortcut = null,
        danger = false,
        divider = true;

  final String label;
  final VoidCallback? onTap;
  final String? shortcut;
  final bool danger;
  final bool divider;
}
