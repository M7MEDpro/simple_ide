import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/features/git/git_service.dart';
import 'package:simple_ide/shared/tokens.dart';

/**
 * Thin vertical strip in the editor gutter showing Git line changes
 * (added, modified, deleted) relative to `HEAD`.
 */
class GitGutter extends StatelessWidget {
  const GitGutter({super.key, required this.notifier, required this.changes});

  final CodeIndicatorValueNotifier notifier;
  final Map<int, GitLineChange> Function() changes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 6,
      height: double.infinity,
      child: CustomPaint(
        painter: _GitGutterPainter(notifier, changes),
      ),
    );
  }
}

class _GitGutterPainter extends CustomPainter {
  _GitGutterPainter(this.notifier, this.changes)
      : _lastChanges = Map.of(changes()),
        super(repaint: notifier);

  final CodeIndicatorValueNotifier notifier;
  final Map<int, GitLineChange> Function() changes;
  final Map<int, GitLineChange> _lastChanges;

  @override
  void paint(Canvas canvas, Size size) {
    final value = notifier.value;
    final map = changes();
    if (value == null || map.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in value.paragraphs) {
      final kind = map[p.index + 1];
      if (kind == null) continue;
      final top = p.offset.dy;
      final h = p.height;

      switch (kind) {
        case GitLineChange.added:
          paint.color = Tk.success.withValues(alpha: 0.85);
          canvas.drawRect(Rect.fromLTWH(2, top + 1, 2.5, (h - 2).clamp(2.0, h)), paint);
        case GitLineChange.modified:
          paint.color = Tk.info.withValues(alpha: 0.85);
          canvas.drawRect(Rect.fromLTWH(2, top + 1, 2.5, (h - 2).clamp(2.0, h)), paint);
        case GitLineChange.deleted:
          paint.color = Tk.error.withValues(alpha: 0.9);
          final path = Path()
            ..moveTo(1, top + h - 4)
            ..lineTo(5.5, top + h - 1)
            ..lineTo(1, top + h + 2)
            ..close();
          canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GitGutterPainter old) =>
      !identical(old.notifier, notifier) ||
      !const MapEquality<int, GitLineChange>().equals(old._lastChanges, changes());
}
