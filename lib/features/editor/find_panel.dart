import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Find & replace bar, docked top-right of the editor.
 */
class FindPanel extends StatelessWidget implements PreferredSizeWidget {
  const FindPanel({super.key, required this.controller, required this.readOnly});

  final CodeFindController controller;
  final bool readOnly;

  static const _rowH = 30.0;

  @override
  Size get preferredSize {
    final v = controller.value;
    if (v == null) return Size.zero;
    return Size(double.infinity, (v.replaceMode ? _rowH * 2 + 4 : _rowH) + 16);
  }

  @override
  Widget build(BuildContext context) {
    final v = controller.value;
    if (v == null) return const SizedBox.shrink();
    final r = v.result;
    final count = r == null
        ? (controller.findInputController.text.isEmpty ? '' : 'No results')
        : '${r.index + 1} of ${r.matches.length}';
    return Align(
      alignment: Alignment.topRight,
      child: Container(
        margin: const EdgeInsets.only(top: 4, right: 18),
        padding: const EdgeInsets.all(4),
        width: 440,
        decoration: BoxDecoration(
          color: Tk.raised,
          borderRadius: Tk.radiusLg,
          border: Border.all(color: Tk.borderStrong),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconBtn(
                  icon: v.replaceMode ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                  tooltip: 'Toggle replace',
                  onPressed: readOnly ? null : controller.toggleMode,
                ),
                Expanded(
                  child: _Field(
                    controller: controller.findInputController,
                    focusNode: controller.findInputFocusNode,
                    hint: 'Find',
                    trailing: [
                      _Toggle(
                        label: 'Aa',
                        tooltip: 'Match case',
                        on: v.option.caseSensitive,
                        onTap: controller.toggleCaseSensitive,
                      ),
                      _Toggle(
                        label: '.*',
                        tooltip: 'Use regular expression',
                        on: v.option.regex,
                        onTap: controller.toggleRegex,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 74,
                  child: Text(
                    count,
                    textAlign: TextAlign.center,
                    style: Tk.uiSmall.copyWith(color: r == null && count.isNotEmpty ? Tk.error : Tk.textMuted),
                  ),
                ),
                IconBtn(
                  icon: Icons.arrow_upward_rounded,
                  tooltip: 'Previous match (Shift+Enter)',
                  onPressed: r == null ? null : controller.previousMatch,
                ),
                IconBtn(
                  icon: Icons.arrow_downward_rounded,
                  tooltip: 'Next match (Enter)',
                  onPressed: r == null ? null : controller.nextMatch,
                ),
                IconBtn(icon: Icons.close_rounded, tooltip: 'Close (Esc)', onPressed: controller.close),
              ],
            ),
            if (v.replaceMode) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const SizedBox(width: 26),
                  Expanded(
                    child: _Field(
                      controller: controller.replaceInputController,
                      focusNode: controller.replaceInputFocusNode,
                      hint: 'Replace',
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconBtn(
                    icon: Icons.find_replace_rounded,
                    tooltip: 'Replace',
                    onPressed: r == null ? null : controller.replaceMatch,
                  ),
                  IconBtn(
                    icon: Icons.done_all_rounded,
                    tooltip: 'Replace all',
                    onPressed: r == null ? null : controller.replaceAllMatches,
                  ),
                  const SizedBox(width: 52),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.focusNode, required this.hint, this.trailing = const []});

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: FindPanel._rowH,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: Tk.code.copyWith(fontSize: 13),
        cursorColor: Tk.accent,
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          suffixIcon: trailing.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: trailing),
          suffixIconConstraints: const BoxConstraints(minHeight: 24),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.tooltip, required this.on, required this.onTap});

  final String label;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            margin: const EdgeInsets.only(right: 3),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: on ? Tk.accent.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: Tk.radius,
              border: Border.all(color: on ? Tk.accent : Colors.transparent),
            ),
            child: Text(label, style: Tk.code.copyWith(fontSize: 11.5, color: on ? Tk.accent : Tk.textMuted)),
          ),
        ),
      ),
    );
  }
}
