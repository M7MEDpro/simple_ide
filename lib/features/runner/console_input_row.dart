import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/runner/runner.dart';
import 'package:simple_ide/shared/tokens.dart';

/**
 * Bottom input bar of the console panel. Routes input to the running process's
 * stdin when active, or executes a shell command in the workspace otherwise.
 */
class ConsoleInputRow extends StatelessWidget {
  const ConsoleInputRow({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.ide,
    required this.onSubmit,
    required this.onKey,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final IdeController ide;
  final VoidCallback onSubmit;
  final KeyEventResult Function(KeyEvent) onKey;

  @override
  Widget build(BuildContext context) {
    final stdin = ide.runner.acceptsInput;
    final busyBuilding = ide.runner.status == RunStatus.building;
    final prompt = stdin ? 'stdin ›' : _shortPrompt(ide);
    final hint = stdin ? 'input for ${ide.runner.target}' : '';
    final fs = (ide.settings.fontSize - 1).clamp(10.0, 28.0);
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 14, right: 10),
      decoration: BoxDecoration(
        color: stdin ? Tk.accent.withValues(alpha: 0.06) : Tk.sidebar,
        border: Border(top: BorderSide(color: stdin ? Tk.accent.withValues(alpha: 0.5) : Tk.border)),
      ),
      child: Row(
        children: [
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Tooltip(
                message: stdin ? 'Input goes to the running program' : 'Working directory: ${ide.shellCwd ?? ''}',
                child: Text(
                  prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tk.code.copyWith(fontSize: fs, color: stdin ? Tk.accent : Tk.info),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Focus(
              onKeyEvent: (_, e) => onKey(e),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !busyBuilding,
                style: Tk.code.copyWith(fontSize: fs, color: Tk.textStrong),
                cursorColor: Tk.accent,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: Tk.code.copyWith(fontSize: fs, color: Tk.textFaint),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => onSubmit(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _shortPrompt(IdeController ide) {
    final cwd = ide.shellCwd ?? ide.workspace?.root ?? '';
    final root = ide.workspace?.root;
    if (root != null && (p.equals(root, cwd) || p.isWithin(root, cwd))) {
      final rel = p.relative(cwd, from: p.dirname(root));
      return '$rel>';
    }
    return '$cwd>';
  }
}
