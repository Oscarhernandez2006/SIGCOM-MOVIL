import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Anillo de avance con marca del ritmo esperado (`pace`).
class RingGaugePainter extends CustomPainter {
  RingGaugePainter({required this.progress, required this.pace, required this.color, required this.track});

  final double progress;
  final double? pace;
  final Color color;
  final Color track;

  static const _stroke = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint..color = track);
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    if (sweep > 0) canvas.drawArc(rect, start, sweep, false, paint..color = color);

    final p = pace;
    if (p != null) {
      final angle = start + 2 * math.pi * p.clamp(0.0, 1.0);
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + dir * (radius - _stroke / 2 - 3),
        center + dir * (radius + _stroke / 2 + 3),
        Paint()
          ..color = const Color(0xFF111827)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(RingGaugePainter old) => old.progress != progress || old.pace != pace || old.color != color;
}

/// Área de ventas diarias con línea de meta y punto seleccionado.
class TrendChartPainter extends CustomPainter {
  TrendChartPainter({
    required this.values,
    required this.selected,
    required this.goal,
    required this.progress,
    required this.color,
  });

  final List<double> values;
  final int selected;
  final double? goal;
  final double progress;
  final Color color;

  static const _goalColor = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const top = 8.0;
    const bottom = 4.0;
    final height = size.height - top - bottom;
    final maxValue = math.max(values.reduce(math.max), goal ?? 0);
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.12;

    double x(int i) => values.length == 1 ? size.width / 2 : size.width * i / (values.length - 1);
    double y(double v) => top + height - (v.clamp(0, maxY) / maxY) * height;

    final grid = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final gy = top + height * i / 3;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final line = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      final px = x(i - 1);
      final cx = x(i);
      final midX = (px + cx) / 2;
      line.cubicTo(midX, y(values[i - 1]), midX, y(values[i]), cx, y(values[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(values.length - 1), top + height)
      ..lineTo(x(0), top + height)
      ..close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, top, size.width, height)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    final g = goal;
    if (g != null) {
      final gy = y(g);
      final dash = Paint()
        ..color = _goalColor
        ..strokeWidth = 1.6;
      for (double dx = 0; dx < size.width; dx += 9) {
        canvas.drawLine(Offset(dx, gy), Offset(math.min(dx + 5, size.width), gy), dash);
      }
    }

    if (progress >= 1 && selected >= 0 && selected < values.length) {
      final sx = x(selected);
      final sy = y(values[selected]);
      canvas.drawLine(
        Offset(sx, top),
        Offset(sx, top + height),
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(Offset(sx, sy), 7, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(sx, sy),
        7,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(TrendChartPainter old) =>
      old.values != values || old.selected != selected || old.goal != goal || old.progress != progress;
}
