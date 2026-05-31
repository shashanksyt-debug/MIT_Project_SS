// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/distance_reading.dart';
import '../services/bluetooth_service.dart';
import '../services/tts_service.dart';
import '../utils/constants.dart';
import '../widgets/device_list_sheet.dart';
import '../widgets/distance_gauge.dart';
import '../widgets/status_bar.dart';
import '../widgets/warning_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _thresholdCm = AppConstants.defaultWarningThresholdCm;
  final _timeFmt = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothService>().addListener(_onBtStateChange);
    });
  }

  void _onBtStateChange() {
    final bt = context.read<BluetoothService>();
    final tts = context.read<TtsService>();
    if (bt.connectionState == BtConnectionState.connected) {
      tts.speakEvent('Connected to ${bt.connectedDevice?.name ?? "device"}.');
    } else if (bt.connectionState == BtConnectionState.disconnected) {
      tts.speakEvent('Bluetooth disconnected.');
    }
  }

  @override
  void dispose() {
    context.read<BluetoothService>().removeListener(_onBtStateChange);
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
      await btService.loadPairedDevices();
      if (!mounted) return;
      _showDeviceSheet();
    }
  }

  void _showDeviceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const DeviceListSheet(),
    );
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
    final reading = btService.lastReading;

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
