import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets/app_button.dart';
import 'package:simple_ide/shared/widgets/icon_btn.dart';

/**
 * Standard top header bar for IDE modal dialogs.
 */
class DialogHeader extends StatelessWidget {
  const DialogHeader({super.key, required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 20, right: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.border))),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tk.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.textStrong),
            ),
          ),
          IconBtn(icon: Icons.close_rounded, tooltip: 'Close', onPressed: onClose),
        ],
      ),
    );
  }
}

/**
 * Compact selectable pill used for build tools, extensions, and toggles.
 */
class OptionPill extends StatelessWidget {
  const OptionPill({super.key, required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: active ? Tk.accent.withValues(alpha: 0.16) : Tk.editor,
            borderRadius: Tk.radius,
            border: Border.all(color: active ? Tk.accent : Tk.borderStrong),
          ),
          child: Text(label, style: Tk.uiSmall.copyWith(color: active ? Tk.accent : Tk.text)),
        ),
      ),
    );
  }
}

/**
 * Asks for a single line of text, e.g. a new folder name.
 */
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  String? hint,
  String? Function(String value)? validate,
  TextSelection? selection,
}) {
  final ctrl = TextEditingController(text: initial);
  ctrl.selection = selection ?? TextSelection(baseOffset: 0, extentOffset: initial.length);
  String? error;
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black38,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final v = ctrl.text.trim();
          final e = validate?.call(v) ?? (v.isEmpty ? 'Enter a name' : null);
          if (e != null) {
            setState(() => error = e);
            return;
          }
          Navigator.of(ctx).pop(v);
        }

        return Dialog(
          child: SizedBox(
            width: 420,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Tk.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.textStrong)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: Tk.code.copyWith(fontSize: 13),
                    decoration: InputDecoration(hintText: hint, errorText: error),
                    onChanged: (_) {
                      if (error != null) setState(() => error = null);
                    },
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
                      const SizedBox(width: 8),
                      PrimaryButton(label: action, onPressed: submit),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/**
 * Confirmation dialog with Enter-to-confirm support.
 */
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black38,
    builder: (ctx) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): () => Navigator.of(ctx).pop(true)},
      child: Focus(
        autofocus: true,
        child: Dialog(
          child: SizedBox(
            width: 420,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Tk.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.textStrong)),
                  const SizedBox(height: 10),
                  Text(message, style: Tk.ui.copyWith(color: Tk.textMuted, height: 1.5)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
                      const SizedBox(width: 8),
                      PrimaryButton(label: action, danger: danger, onPressed: () => Navigator.of(ctx).pop(true)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return r ?? false;
}
