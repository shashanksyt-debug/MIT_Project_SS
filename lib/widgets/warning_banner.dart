// lib/widgets/warning_banner.dart
//
// Animated proximity warning shown when distance < threshold.

import 'package:flutter/material.dart';
import '../utils/constants.dart';

class WarningBanner extends StatefulWidget {
  final bool visible;
  final double distanceCm;
  final double thresholdCm;

  const WarningBanner({
    super.key,
    required this.visible,
    required this.distanceCm,
    required this.thresholdCm,
  });

  @override
  State<WarningBanner> createState() => _WarningBannerState();
}

class _WarningBannerState extends State<WarningBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, anim) => SizeTransition(
        sizeFactor: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: widget.visible
          ? AnimatedBuilder(
              key: const ValueKey('warning'),
              animation: _pulse,
              builder: (_, __) => Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppConstants.colorDanger
                      .withOpacity(0.1 + 0.1 * _pulse.value),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppConstants.colorDanger
                        .withOpacity(0.5 + 0.5 * _pulse.value),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppConstants.colorDanger, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PROXIMITY ALERT',
                            style: TextStyle(
                              color: AppConstants.colorDanger,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Object at ${widget.distanceCm.toStringAsFixed(1)} cm '
                            '— threshold ${widget.thresholdCm.toStringAsFixed(0)} cm',
                            style: const TextStyle(
                              color: AppConstants.colorTextSecond,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('no-warning')),
    );
  }
}
