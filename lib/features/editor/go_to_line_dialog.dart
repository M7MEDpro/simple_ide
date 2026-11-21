import 'package:flutter/widgets.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/editor/document.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Moves the cursor to a line typed by the user (Ctrl+G).
 */
Future<void> showGoToLine(BuildContext context, IdeController ide, EditorDocument doc) async {
  final total = doc.controller.lineCount;
  final cur = doc.controller.selection.extentIndex + 1;
  final v = await showTextPrompt(
    context,
    title: 'Go to line',
    action: 'Go',
    hint: 'Line number, or line:column (1 to $total)',
    initial: '$cur',
    validate: (s) {
      final m = RegExp(r'^(\d+)(?::(\d+))?$').firstMatch(s);
      if (m == null) return 'Type a line number like 42 or 42:7';
      final n = int.parse(m[1]!);
      if (n < 1 || n > total) return 'This file has $total lines';
      return null;
    },
  );
  if (v == null) return;
  final m = RegExp(r'^(\d+)(?::(\d+))?$').firstMatch(v)!;
  ide.revealLine(doc, int.parse(m[1]!), int.tryParse(m[2] ?? '') ?? 1);
  ide.focusEditorRequest.value++;
}
