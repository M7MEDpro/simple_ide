import 'package:flutter/material.dart';

import 'package:simple_ide/shared/tokens.dart';

/**
 * Primary amber button. Reserved for running code and confirming dialogs.
 */
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.danger = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: danger ? Tk.error : Tk.accent,
        foregroundColor: Tk.accentInk,
        disabledBackgroundColor: Tk.hover,
        textStyle: Tk.ui.copyWith(fontWeight: FontWeight.w600),
        padding: EdgeInsets.only(left: icon == null ? 16 : 12, right: 16),
        minimumSize: const Size(0, 32),
        shape: const RoundedRectangleBorder(borderRadius: Tk.radius),
      ),
    );
  }
}

/**
 * Outlined secondary button used for cancel and utility actions.
 */
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Tk.text,
        side: const BorderSide(color: Tk.borderStrong),
        textStyle: Tk.ui,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const RoundedRectangleBorder(borderRadius: Tk.radius),
      ),
      child: Text(label),
    );
  }
}
