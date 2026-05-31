// lib/widgets/status_bar.dart
//
// Compact horizontal status strip shown at the top of the home screen.

import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../utils/constants.dart';

class StatusBar extends StatelessWidget {
  final BtConnectionState state;
  final String? deviceName;

  const StatusBar({super.key, required this.state, this.deviceName});

  (String label, Color color, IconData icon) get _info {
    switch (state) {
      case BtConnectionState.idle:
        return ('Not connected', AppConstants.colorTextSecond, Icons.bluetooth);
      case BtConnectionState.scanning:
        return (
          'Scanning…',
          AppConstants.colorAccent,
          Icons.bluetooth_searching
        );
      case BtConnectionState.connecting:
        return (
          'Connecting…',
          AppConstants.colorWarning,
          Icons.bluetooth_searching
        );
      case BtConnectionState.connected:
        return (
          'Connected · ${deviceName ?? ""}',
          AppConstants.colorSafe,
          Icons.bluetooth_connected,
        );
      case BtConnectionState.disconnected:
        return (
          'Disconnected',
          AppConstants.colorWarning,
          Icons.bluetooth_disabled
        );
      case BtConnectionState.error:
        return ('Error', AppConstants.colorDanger, Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _info;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing dot for connecting state
          if (state == BtConnectionState.connecting ||
              state == BtConnectionState.scanning) ...[
            _PulsingDot(color: color),
          ] else ...[
            Icon(icon, color: color, size: 16),
          ],
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Opacity(
          opacity: _anim.value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}
