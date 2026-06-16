// lib/screens/home_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/distance_reading.dart';
import '../services/bluetooth_service.dart';
import '../services/tts_service.dart';
import '../models/vibration_reading.dart';
import '../utils/constants.dart';
import '../widgets/distance_gauge.dart';
import '../widgets/status_bar.dart';
import '../widgets/warning_banner.dart';
import '../widgets/camera_detection_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _thresholdCm = AppConstants.defaultWarningThresholdCm;
  final _timeFmt = DateFormat('HH:mm:ss');

  //Added These
  BtConnectionState _previousBtState = BtConnectionState.idle;
  bool _hasSpokenConnected = false;
  // Vibration stream subscription
  StreamSubscription? _vibrationSub;
  VibrationReading? _lastVibration;
  DateTime? _lastVibrationAlertAt;
  static const int _vibrationCooldownMs = 5000;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothService>().addListener(_onBtStateChange);
      // subscribe to vibration stream
      _vibrationSub = context.read<BluetoothService>().vibrationStream.listen((v) {
        setState(() => _lastVibration = v);
        final tts = context.read<TtsService>();

        // Enforce an app-side cooldown to avoid repeated alerts (matches Arduino cooldown)
        final now = DateTime.now();
        if (_lastVibrationAlertAt != null &&
            now.difference(_lastVibrationAlertAt!).inMilliseconds < _vibrationCooldownMs) {
          // still in cooldown window — ignore active alert
          return;
        }

        String? message;
        try {
          switch (v.level) {
            case VibrationLevel.severe:
              message = 'Danger ahead';
              HapticFeedback.heavyImpact();
              break;
            case VibrationLevel.moderate:
              message = 'Warning, bumpy path ahead';
              HapticFeedback.mediumImpact();
              break;
            case VibrationLevel.mild:
              message = 'Be aware: slight bumps ahead';
              HapticFeedback.lightImpact();
              break;
            default:
              message = null;
          }
        } catch (_) {
          try {
            HapticFeedback.vibrate();
          } catch (_) {}
        }

        if (message != null) {
          tts.speakEvent(message);
          _lastVibrationAlertAt = DateTime.now();
        } else if (v.alertMessage != null && v.alertMessage!.isNotEmpty) {
          tts.speakEvent(v.alertMessage!);
          _lastVibrationAlertAt = DateTime.now();
        }
      });
    });
  }

  void _onBtStateChange() {
    final bt = context.read<BluetoothService>();
    final tts = context.read<TtsService>();
    final newState = bt.connectionState;

    // Only act when the state actually CHANGES
    if (newState == _previousBtState) return;
    _previousBtState = newState;

    if (newState == BtConnectionState.connected && !_hasSpokenConnected) {
      _hasSpokenConnected = true;
      tts.speakEvent('Connected to ${bt.connectedDevice?.name ?? "device"}.');
    } else if (newState == BtConnectionState.disconnected) {
      _hasSpokenConnected =
          false; // reset so it speaks again on next connection
      tts.speakEvent('Bluetooth disconnected.');
    } else if (newState == BtConnectionState.error) {
      _hasSpokenConnected = false;
      tts.speakEvent('Connection error.');
    }
  }

  @override
  void dispose() {
    context.read<BluetoothService>().removeListener(_onBtStateChange);
    _vibrationSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final btService = context.read<BluetoothService>();
    final granted = await btService.requestPermissions();
    if (granted) {
      await btService.loadPairedDevices();
    }
  }

  Future<void> _onConnectTap(BluetoothService btService) async {
    if (btService.connectionState == BtConnectionState.connected) {
      await btService.disconnect();
    } else {
      // FIX: properly await the Future<BluetoothState>
      final btState = await FlutterBluetoothSerial.instance.state;
      final enabled = btState == BluetoothState.STATE_ON;
      if (!enabled) {
        await btService.enableBluetooth();
      }
      await btService.connectToHc05Direct();
    }
  }

  void _showThresholdDialog() {
    double temp = _thresholdCm;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.colorCard,
        title: const Text('Warning Threshold',
            style: TextStyle(color: AppConstants.colorTextPrimary)),
        content: StatefulBuilder(
          builder: (ctx, setSt) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${temp.toStringAsFixed(0)} cm',
                style: const TextStyle(
                    color: AppConstants.colorAccent,
                    fontSize: 36,
                    fontWeight: FontWeight.w700),
              ),
              Slider(
                value: temp,
                min: 5,
                max: 200,
                divisions: 39,
                activeColor: AppConstants.colorAccent,
                inactiveColor: AppConstants.colorBorder,
                onChanged: (v) => setSt(() => temp = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel',
                style: TextStyle(color: AppConstants.colorTextSecond)),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text('Apply',
                style: TextStyle(color: AppConstants.colorAccent)),
            onPressed: () {
              setState(() => _thresholdCm = temp);
              // Announce threshold change via TTS
              context.read<TtsService>().speakEvent(
                    'Threshold set to ${temp.toStringAsFixed(0)} centimeters.',
                  );
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final btService = context.watch<BluetoothService>();
    final state = btService.connectionState;
    final isConn = state == BtConnectionState.connected;

    return Scaffold(
      backgroundColor: AppConstants.colorBackground,
      body: SafeArea(
        child: StreamBuilder<DistanceReading>(
          stream: btService.readingStream,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              context.read<TtsService>().onNewReading(
                    snapshot.data!.distanceCm,
                    _thresholdCm,
                  );
            }

            final latest = btService.lastReading;
            final dist = latest?.distanceCm;
            final inWarning = dist != null && dist < _thresholdCm;

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: AppConstants.colorBackground,
                  pinned: true,
                  title: Row(
                    children: [
                      const Icon(Icons.sensors,
                          color: AppConstants.colorAccent, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'BT Distance Meter',
                        style: TextStyle(
                          color: AppConstants.colorTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    // FIX: use toggleTts() instead of calling notifyListeners() directly
                    Consumer<TtsService>(
                      builder: (_, tts, __) => IconButton(
                        icon: Icon(
                          tts.isTtsEnabled ? Icons.volume_up : Icons.volume_off,
                          color: tts.isTtsEnabled
                              ? AppConstants.colorAccent
                              : AppConstants.colorTextSecond,
                        ),
                        tooltip:
                            tts.isTtsEnabled ? 'Mute voice' : 'Enable voice',
                        onPressed: () => tts.toggleTts(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune,
                          color: AppConstants.colorTextSecond),
                      tooltip: 'Warning threshold',
                      onPressed: _showThresholdDialog,
                    ),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Center(
                        child: StatusBar(
                          state: state,
                          deviceName: btService.connectedDevice?.name,
                        ),
                      ),
                      if (btService.errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppConstants.colorDanger.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppConstants.colorDanger, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  btService.errorMessage,
                                  style: const TextStyle(
                                      color: AppConstants.colorDanger,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      Center(
                        child: DistanceGauge(
                          distanceCm: dist,
                          thresholdCm: _thresholdCm,
                          isConnected: isConn,
                        ),
                      ),
                      const SizedBox(height: 24),
                      WarningBanner(
                        visible: inWarning,
                        distanceCm: dist ?? 0,
                        thresholdCm: _thresholdCm,
                      ),
                      const SizedBox(height: 8),
                      // Vibration indicator
                      if (_lastVibration != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _lastVibration!.level == VibrationLevel.severe
                                ? AppConstants.colorDanger.withOpacity(0.1)
                                : _lastVibration!.level == VibrationLevel.moderate
                                    ? AppConstants.colorWarning.withOpacity(0.08)
                                    : AppConstants.colorCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppConstants.colorBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _lastVibration!.level == VibrationLevel.severe
                                    ? Icons.dangerous
                                    : Icons.vibration,
                                color: _lastVibration!.level == VibrationLevel.severe
                                    ? AppConstants.colorDanger
                                    : AppConstants.colorAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _lastVibration!.alertMessage ??
                                      'Vibration ${_lastVibration!.spikePercent}% — ${_lastVibration!.level.toString().split('.').last.toUpperCase()}',
                                  style: const TextStyle(
                                      color: AppConstants.colorTextPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      _InfoCardRow(
                        thresholdCm: _thresholdCm,
                        lastReading: latest,
                        timeFmt: _timeFmt,
                      ),
                      const SizedBox(height: 32),
                      _ConnectButton(
                        state: state,
                        onTap: () => _onConnectTap(btService),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          icon: const Icon(Icons.tune,
                              size: 16, color: AppConstants.colorTextSecond),
                          label: Text(
                            'Threshold: ${_thresholdCm.toStringAsFixed(0)} cm',
                            style: const TextStyle(
                                color: AppConstants.colorTextSecond,
                                fontSize: 13),
                          ),
                          onPressed: _showThresholdDialog,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const CameraDetectionPanel(),
                      const SizedBox(height: 20),
                      _DataFlowChip(),
                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Info cards ────────────────────────────────────────────────
class _InfoCardRow extends StatelessWidget {
  final double thresholdCm;
  final DistanceReading? lastReading;
  final DateFormat timeFmt;

  const _InfoCardRow({
    required this.thresholdCm,
    required this.lastReading,
    required this.timeFmt,
  });

  @override
  Widget build(BuildContext context) {
    final timestamp = lastReading != null
        ? timeFmt.format(lastReading!.receivedAt)
        : '--:--:--';

    return Row(
      children: [
        Expanded(
          child: _InfoCard(
            label: 'THRESHOLD',
            value: '${thresholdCm.toStringAsFixed(0)} cm',
            icon: Icons.warning_amber_outlined,
            color: AppConstants.colorWarning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoCard(
            label: 'LAST UPDATE',
            value: timestamp,
            icon: Icons.access_time,
            color: AppConstants.colorAccent,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _InfoCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppConstants.colorCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppConstants.colorBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    color: AppConstants.colorTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppConstants.fontMono)),
          ],
        ),
      );
}

// ── Connect button ────────────────────────────────────────────
class _ConnectButton extends StatelessWidget {
  final BtConnectionState state;
  final VoidCallback onTap;

  const _ConnectButton({required this.state, required this.onTap});

  bool get _isLoading =>
      state == BtConnectionState.connecting ||
      state == BtConnectionState.scanning;

  bool get _isConnected => state == BtConnectionState.connected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _isLoading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isConnected
                ? AppConstants.colorDanger.withOpacity(0.15)
                : AppConstants.colorAccent,
            foregroundColor: _isConnected
                ? AppConstants.colorDanger
                : AppConstants.colorBackground,
            side: _isConnected
                ? const BorderSide(color: AppConstants.colorDanger)
                : BorderSide.none,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppConstants.colorTextSecond))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isConnected
                        ? Icons.bluetooth_disabled
                        : Icons.bluetooth),
                    const SizedBox(width: 10),
                    Text(
                      _isConnected ? 'Disconnect' : 'Connect to HC-05',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
        ),
      );
}

// ── Decorative data-flow chip ─────────────────────────────────
class _DataFlowChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppConstants.colorCard,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppConstants.colorBorder),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('HC-SR04',
                  style: TextStyle(
                      color: AppConstants.colorTextSecond, fontSize: 11)),
              _Arrow(),
              Text('Arduino',
                  style: TextStyle(
                      color: AppConstants.colorTextSecond, fontSize: 11)),
              _Arrow(),
              Text('HC-05',
                  style: TextStyle(
                      color: AppConstants.colorTextSecond, fontSize: 11)),
              _Arrow(),
              Icon(Icons.phone_android,
                  color: AppConstants.colorAccent, size: 14),
            ],
          ),
        ),
      );
}

class _Arrow extends StatelessWidget {
  const _Arrow();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.arrow_forward_ios,
            color: AppConstants.colorBorder, size: 10),
      );
}
