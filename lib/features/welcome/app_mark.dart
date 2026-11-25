import 'package:flutter/material.dart';

import 'package:simple_ide/shared/tokens.dart';

/**
 * The SimpleIDE mark: a play triangle set inside a pair of code brackets.
 */
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkPainter()));
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = Paint()
      ..color = Tk.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = s.width, h = s.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.22, h * 0.14)
        ..lineTo(w * 0.06, h * 0.14)
        ..lineTo(w * 0.06, h * 0.86)
        ..lineTo(w * 0.22, h * 0.86),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.78, h * 0.14)
        ..lineTo(w * 0.94, h * 0.14)
        ..lineTo(w * 0.94, h * 0.86)
        ..lineTo(w * 0.78, h * 0.86),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.38, h * 0.28)
        ..lineTo(w * 0.72, h * 0.5)
        ..lineTo(w * 0.38, h * 0.72)
        ..close(),
      Paint()..color = Tk.accent,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
