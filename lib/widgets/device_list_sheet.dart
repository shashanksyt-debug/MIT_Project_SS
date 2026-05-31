// lib/widgets/device_list_sheet.dart
//
// Bottom sheet that lists paired BT devices and lets the user tap one to connect.

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:provider/provider.dart';

import '../services/bluetooth_service.dart';
import '../utils/constants.dart';

class DeviceListSheet extends StatelessWidget {
  const DeviceListSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final btService = context.watch<BluetoothService>();
    final devices = btService.pairedDevices;

    return Container(
      decoration: const BoxDecoration(
        color: AppConstants.colorSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppConstants.colorBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Header ──
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_searching,
                    color: AppConstants.colorAccent),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Paired Devices',
                    style: TextStyle(
                      color: AppConstants.colorTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Refresh button
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: AppConstants.colorTextSecond),
                  onPressed: () =>
                      context.read<BluetoothService>().loadPairedDevices(),
                ),
              ],
            ),
          ),

          const Divider(color: AppConstants.colorBorder, height: 1),

          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: const [
                  Icon(Icons.bluetooth_disabled,
                      color: AppConstants.colorTextSecond, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'No paired devices found.\nPair the HC-05 in Android Bluetooth Settings first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppConstants.colorTextSecond, height: 1.5),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: devices.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppConstants.colorBorder, height: 1),
              itemBuilder: (context, i) => _DeviceTile(device: devices[i]),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Individual device row ─────────────────────────────────────
class _DeviceTile extends StatelessWidget {
  final BluetoothDevice device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final btService = context.read<BluetoothService>();
    final isConnected = btService.connectedDevice?.address == device.address &&
        btService.connectionState == BtConnectionState.connected;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(
        isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
        color: isConnected
            ? AppConstants.colorAccent
            : AppConstants.colorTextSecond,
      ),
      title: Text(
        device.name ?? 'Unknown Device',
        style: const TextStyle(
            color: AppConstants.colorTextPrimary, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        device.address,
        style:
            const TextStyle(color: AppConstants.colorTextSecond, fontSize: 12),
      ),
      trailing: isConnected
          ? const Chip(
              label: Text('Connected',
                  style:
                      TextStyle(color: AppConstants.colorSafe, fontSize: 12)),
              backgroundColor: Color(0x223FB950),
            )
          : const Icon(Icons.chevron_right,
              color: AppConstants.colorTextSecond),
      onTap: () {
        Navigator.pop(context); // close sheet
        btService.connectTo(device);
      },
    );
  }
}
