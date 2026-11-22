import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/features/runner/console.dart';
import 'package:simple_ide/features/diagnostics/diagnostics.dart';
import 'package:simple_ide/shared/tokens.dart';

Color severityColor(Severity s) => switch (s) {
      Severity.error => Tk.error,
      Severity.warning => Tk.warning,
      Severity.note => Tk.info,
    };

/**
 * Character range [start, end) to underline for a problem reported at a
 * 1-based column. Tools often point just past the end of a line (a missing
 * semicolon), or at a whole line (Python), so this picks the nearest token.
 *
 * @param text   the line's text
 * @param column 1-based column from the tool
 * @return the range, or null for an empty line
 */
(int, int)? underlineRange(String text, int column) {
  if (text.trim().isEmpty) return null;
  final len = text.length;
  var start = (column - 1).clamp(0, len);
  if (column <= 1) {
    // No useful column: underline the line's content without indentation.
    final first = text.indexOf(RegExp(r'\S'));
    final last = text.trimRight().length;
    return (first, last);
  }
  if (start >= len) start = text.trimRight().length - 1;
  while (start < len && RegExp(r'\s').hasMatch(text[start])) {
    start++;
  }
  if (start >= len) start = len - 1;
  final word = RegExp(r'\w+').matchAsPrefix(text, start);
  final end = word != null ? word.end : start + 1;
  return (start, end);
}

/**
 * Rebuilds a highlighted line span with a wavy underline over [range],
 * preserving the colours from syntax highlighting.
 *
 * @param span  the highlighted span for the line
 * @param base  the editor's base text style
 * @param range character range to underline
 * @param color underline colour
 * @return the new span
 */
TextSpan underlineSpan(TextSpan span, TextStyle base, (int, int) range, Color color) {
  final segments = <(String, TextStyle)>[];
  void walk(InlineSpan s, TextStyle inherited) {
    if (s is! TextSpan) return;
    final style = inherited.merge(s.style);
    if (s.text != null && s.text!.isNotEmpty) segments.add((s.text!, style));
    for (final c in s.children ?? const <InlineSpan>[]) {
      walk(c, style);
    }
  }

  walk(span, base);
  final (from, to) = range;
  final squiggle = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
    decorationColor: color,
    decorationThickness: 1.6,
  );
  final out = <TextSpan>[];
  var pos = 0;
  for (final (text, style) in segments) {
    final segEnd = pos + text.length;
    final a = from.clamp(pos, segEnd);
    final b = to.clamp(pos, segEnd);
    if (a >= b) {
      out.add(TextSpan(text: text, style: style));
    } else {
      if (a > pos) out.add(TextSpan(text: text.substring(0, a - pos), style: style));
      out.add(TextSpan(text: text.substring(a - pos, b - pos), style: style.merge(squiggle)));
      if (b < segEnd) out.add(TextSpan(text: text.substring(b - pos), style: style));
    }
    pos = segEnd;
  }
  return TextSpan(style: base, children: out);
}

/**
 * Narrow gutter column with a dot beside each line that has a problem.
 */
class DiagnosticGutter extends StatelessWidget {
  const DiagnosticGutter({super.key, required this.notifier, required this.problems, required this.stale});

  final CodeIndicatorValueNotifier notifier;
  final List<Diagnostic> Function() problems;
  final bool Function() stale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: double.infinity,
      child: CustomPaint(
        painter: _GutterPainter(notifier, problems, stale),
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  _GutterPainter(this.notifier, this.problems, this.stale) : super(repaint: notifier);
  final CodeIndicatorValueNotifier notifier;
  final List<Diagnostic> Function() problems;
  final bool Function() stale;

  @override
  void paint(Canvas canvas, Size size) {
    final v = notifier.value;
    final list = problems();
    if (v == null || list.isEmpty) return;
    final isStale = stale();
    final worst = <int, Severity>{};
    for (final d in list) {
      final cur = worst[d.line - 1];
      if (cur == null || d.severity.index < cur.index) worst[d.line - 1] = d.severity;
    }
    for (final para in v.paragraphs) {
      final sev = worst[para.index];
      if (sev == null) continue;
      final cy = para.top + para.preferredLineHeight / 2;
      final paint = Paint()..color = severityColor(sev).withValues(alpha: isStale ? 0.4 : 1);
      if (sev == Severity.error) {
        canvas.drawCircle(Offset(size.width / 2 + 1, cy), 3.5, paint);
      } else {
        final path = Path()
          ..moveTo(size.width / 2 + 1, cy - 4)
          ..lineTo(size.width / 2 + 5, cy + 3.5)
          ..lineTo(size.width / 2 - 3, cy + 3.5)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GutterPainter old) =>
      !identical(old.notifier, notifier) || old.problems() != problems() || old.stale() != stale();
}

/**
 * Paints a faint band behind each problem line and the problem's message
 * after the end of the line, like an inline lint in larger IDEs. Sits in a
 * Stack above the editor and ignores the pointer.
 */
class InlineDiagnostics extends StatelessWidget {
  const InlineDiagnostics({
    super.key,
    required this.notifier,
    required this.problems,
    required this.stale,
    required this.textLeft,
    required this.top,
    required this.fontSize,
    required this.repaint,
  });

  final CodeIndicatorValueNotifier notifier;
  final List<Diagnostic> problems;
  final bool stale;

  /** X of the text area's left edge, in this widget's coordinates. */
  final double Function() textLeft;

  /** Y of the editor viewport's top, in this widget's coordinates. */
  final double Function() top;
  final double fontSize;
  final Listenable repaint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _InlinePainter(
          notifier: notifier,
          problems: problems,
          stale: stale,
          textLeft: textLeft,
          top: top,
          fontSize: fontSize,
          repaint: Listenable.merge([notifier, repaint]),
        ),
      ),
    );
  }
}

class _InlinePainter extends CustomPainter {
  _InlinePainter({
    required this.notifier,
    required this.problems,
    required this.stale,
    required this.textLeft,
    required this.top,
    required this.fontSize,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final CodeIndicatorValueNotifier notifier;
  final List<Diagnostic> problems;
  final bool stale;
  final double Function() textLeft;
  final double Function() top;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final v = notifier.value;
    if (v == null || problems.isEmpty) return;
    final byLine = <int, List<Diagnostic>>{};
    for (final d in problems) {
      byLine.putIfAbsent(d.line - 1, () => []).add(d);
    }
    final left = textLeft();
    final dy = top();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(left, 0, size.width, size.height));
    for (final para in v.paragraphs) {
      final list = byLine[para.index];
      if (list == null) continue;
      list.sort((a, b) => a.severity.index.compareTo(b.severity.index));
      final first = list.first;
      final color = severityColor(first.severity);
      final alpha = stale ? 0.4 : 1.0;
      final y = dy + para.top;
      canvas.drawRect(
        Rect.fromLTWH(left, y, size.width - left, para.preferredLineHeight),
        Paint()..color = color.withValues(alpha: 0.07 * alpha),
      );
      final more = list.length > 1 ? '  (+${list.length - 1} more)' : '';
      final x = left + para.offset.dx + para.paragraph.width + 28;
      final maxW = size.width - x - 12;
      if (maxW < 60) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: '${first.message}$more',
          style: Tk.code.copyWith(fontSize: fontSize - 1, color: color.withValues(alpha: 0.85 * alpha), height: 1.2),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxW);
      tp.paint(canvas, Offset(x, y + (para.preferredLineHeight - tp.height) / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InlinePainter old) =>
      !const ListEquality<Diagnostic>().equals(old.problems, problems) ||
      old.stale != stale ||
      old.fontSize != fontSize;
}
