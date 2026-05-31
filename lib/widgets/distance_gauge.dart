// lib/widgets/distance_gauge.dart
//
// Animated circular gauge that visualises the current distance reading.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class DistanceGauge extends StatelessWidget {
  final double? distanceCm; // null = error / no data
  final double thresholdCm;
  final bool isConnected;

  const DistanceGauge({
    super.key,
    required this.distanceCm,
    required this.thresholdCm,
    required this.isConnected,
  });

  Color get _arcColor {
    if (!isConnected || distanceCm == null) return AppConstants.colorBorder;
    if (distanceCm! < thresholdCm) return AppConstants.colorDanger;
    if (distanceCm! < thresholdCm * 1.5) return AppConstants.colorWarning;
    return AppConstants.colorSafe;
  }

  /// Sweep fraction: 0.0–1.0 (mapped to 0–400 cm max range).
  double get _fraction {
    if (distanceCm == null) return 0;
    return (distanceCm! / 400.0).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: CustomPaint(
        painter: _GaugePainter(
          fraction: _fraction,
          arcColor: _arcColor,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Distance value ──
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  distanceCm != null ? distanceCm!.toStringAsFixed(1) : '--',
                  key: ValueKey(distanceCm?.toStringAsFixed(1)),
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    color: _arcColor,
                    fontFamily: AppConstants.fontMono,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'cm',
                style: TextStyle(
                  fontSize: 18,
                  color: _arcColor.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Arc painter ───────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double fraction;
  final Color arcColor;

  _GaugePainter({required this.fraction, required this.arcColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 12;
    const startAngle = math.pi * 0.75;
    const sweepTotal = math.pi * 1.5;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // ── Background track ──
    canvas.drawArc(
      rect,
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = AppConstants.colorBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round,
    );

    // ── Filled arc ──
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        startAngle,
        sweepTotal * fraction,
        false,
        Paint()
          ..color = arcColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.arcColor != arcColor;
}
