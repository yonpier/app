import 'package:flutter/material.dart';

/// Paints vertical grid lines for the Gantt timeline.
///
/// One line per day, matching the [dayWidth] pixel spacing.
class ContainerPatternPainter extends CustomPainter {
  final Color color;
  final double dayWidth;
  final int totalDays;

  ContainerPatternPainter({
    required this.color,
    required this.dayWidth,
    required this.totalDays,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    for (int i = 0; i <= totalDays; i++) {
      canvas.drawLine(
        Offset(i * dayWidth, 0),
        Offset(i * dayWidth, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ContainerPatternPainter oldDelegate) {
    return oldDelegate.dayWidth != dayWidth ||
        oldDelegate.totalDays != totalDays ||
        oldDelegate.color != color;
  }
}
