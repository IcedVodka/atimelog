import 'dart:math' as math;

import 'package:flutter/material.dart';

class PieSliceData {
  PieSliceData({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;
}

class SimplePieChart extends StatelessWidget {
  const SimplePieChart({
    super.key,
    required this.slices,
    this.size = 220,
    this.centerLabel,
    this.highlightedIndex,
    this.onSliceTap,
  });

  final List<PieSliceData> slices;
  final double size;
  final String? centerLabel;
  final int? highlightedIndex;
  final ValueChanged<int>? onSliceTap;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (prev, e) => prev + e.value);
    if (total <= 0) {
      return SizedBox(
        height: size,
        child: const Center(child: Text('暂无数据')),
      );
    }
    final outerRadius = size / 2 - 20;
    final maxStroke = size * 0.22;
    final innerRadius = outerRadius - maxStroke;
    Widget chart = CustomPaint(
      size: Size.square(size),
      painter: _PiePainter(slices, highlightedIndex),
    );
    if (onSliceTap != null) {
      chart = GestureDetector(
        onTapDown: (details) {
          final local = details.localPosition;
          final center = Offset(size / 2, size / 2);
          final dx = local.dx - center.dx;
          final dy = local.dy - center.dy;
          final distance = math.sqrt(dx * dx + dy * dy);
          if (distance < innerRadius ||
              distance > outerRadius + maxStroke / 2) {
            return;
          }
          double angle = math.atan2(dy, dx);
          angle = (angle + 2 * math.pi) % (2 * math.pi);
          double cursor = -math.pi / 2;
          for (var i = 0; i < slices.length; i++) {
            final sweep = (slices[i].value / total) * 2 * math.pi;
            if (angle >= cursor && angle <= cursor + sweep) {
              onSliceTap!(i);
              break;
            }
            cursor += sweep;
          }
        },
        child: chart,
      );
    }
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          chart,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centerLabel != null)
                Text(
                  centerLabel!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              Text(
                '共 ${slices.length} 类',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.slices, this.highlightedIndex);

  final List<PieSliceData> slices;
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(20);
    final paint = Paint()..style = PaintingStyle.stroke;
    final baseStroke = size.width * 0.18;
    final highlightStroke = size.width * 0.22;
    final total = slices.fold<double>(0, (prev, e) => prev + e.value);
    double startRadian = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final sweep = (slice.value / total) * 2 * math.pi;
      paint.color = slice.color;
      paint.strokeWidth = i == highlightedIndex ? highlightStroke : baseStroke;
      canvas.drawArc(rect, startRadian, sweep, false, paint);
      startRadian += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.highlightedIndex != highlightedIndex;
  }
}
