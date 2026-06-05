// lib/services/bluetooth_service.dart
//
// Manages the full Bluetooth lifecycle:
//   • Permission requests
//   • Device scanning (paired devices list for HC-05 Classic BT)
//   • Connecting / disconnecting
//   • Streaming incoming data
//   • Parsing DistanceReading objects

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/distance_reading.dart';

// Connection state enum exposed to the UI layer.
enum BtConnectionState {
  idle, // App just opened, nothing attempted yet
  scanning, // Fetching paired devices list
  connecting, // TCP-style handshake in progress
  connected, // Active SPP connection
  disconnected, // Was connected, now lost
  error, // Fatal error (BT off, permission denied, …)
}

class BluetoothService extends ChangeNotifier {
  // ── Public state ──────────────────────────────────────────────
  BtConnectionState connectionState = BtConnectionState.idle;
  List<BluetoothDevice> pairedDevices = [];
  BluetoothDevice? connectedDevice;
  DistanceReading? lastReading;
  String errorMessage = '';

  // ── Private internals ─────────────────────────────────────────
  BluetoothConnection? _connection;
  StreamSubscription? _dataSubscription;
  final StreamController<DistanceReading> _readingController =
      StreamController<DistanceReading>.broadcast();

  /// Stream of parsed DistanceReading objects — subscribe in your UI.
  Stream<DistanceReading> get readingStream => _readingController.stream;

  // Accumulates partial bytes between BT packets
  String _buffer = '';

  // ─────────────────────────────────────────────────────────────
  // PERMISSIONS
  // ─────────────────────────────────────────────────────────────

  /// Requests all Bluetooth (and location) permissions.
  /// Returns true if all are granted.
  Future<bool> requestPermissions() async {
    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final statuses = await permissions.request();

    final allGranted = statuses.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );

    if (!allGranted) {
      _setError('Bluetooth/Location permissions are required.');
    }
    return allGranted;
  }

  // ─────────────────────────────────────────────────────────────
  // BLUETOOTH ON/OFF CHECK
  // ─────────────────────────────────────────────────────────────

  Future<bool> _isBluetoothEnabled() async {
    final state = await FlutterBluetoothSerial.instance.state;
    return state == BluetoothState.STATE_ON;
  }

  /// Prompts the user to enable Bluetooth if it is off.
  Future<void> enableBluetooth() async {
    await FlutterBluetoothSerial.instance.requestEnable();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // SCANNING (PAIRED DEVICES)
  // ─────────────────────────────────────────────────────────────

  /// Loads the list of already-paired Bluetooth devices.
  /// HC-05 must be paired with the phone in Android Settings first.
  Future<void> loadPairedDevices() async {
    try {
      _setState(BtConnectionState.scanning);
      errorMessage = '';

      final enabled = await _isBluetoothEnabled();
      if (!enabled) {
        _setError('Bluetooth is turned off. Please enable it.');
        return;
      }

      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

      for (final d in devices) {
        debugPrint('DEVICE FOUND => ${d.name} | ${d.address}');
      }

      pairedDevices = devices;

      _setState(BtConnectionState.idle);
    } catch (e) {
      _setError('Failed to load paired devices: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CONNECTION
  // ─────────────────────────────────────────────────────────────

  /// Opens an SPP connection to [device].
  Future<void> connectTo(BluetoothDevice device) async {
    try {
      _setState(BtConnectionState.connecting);
      errorMessage = '';

      // If already connected to something else, disconnect first
      await disconnect(notify: false);

      _connection = await BluetoothConnection.toAddress(device.address).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Connection timed out'),
      );

      connectedDevice = device;
      _setState(BtConnectionState.connected);

      // Start listening to the incoming byte stream
      _startListening();
    } on TimeoutException {
      _setError('Connection timed out. Is the HC-05 powered on?');
    } catch (e) {
      _setError('Connection failed: $e');
    }
  }

  Future<void> connectToHc05Direct() async {
    try {
      _setState(BtConnectionState.connecting);

      await disconnect(notify: false);

      _connection = await BluetoothConnection.toAddress(
        "00:25:02:01:21:06",
      );

      connectedDevice = BluetoothDevice(
        address: "00:25:02:01:21:06",
        name: "HC-05",
        type: BluetoothDeviceType.classic,
      );

      _setState(BtConnectionState.connected);

      _startListening();
    } catch (e) {
      _setError("Direct HC-05 connection failed: $e");
    }
  }

  /// Gracefully closes the current connection.
  Future<void> disconnect({bool notify = true}) async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;

    try {
      await _connection?.close();
    } catch (_) {/* ignore close errors */}
    _connection = null;

    connectedDevice = null;
    _buffer = '';

    if (notify) {
      _setState(BtConnectionState.disconnected);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DATA RECEPTION & PARSING
  // ─────────────────────────────────────────────────────────────

  void _startListening() {
    // _connection!.input is a Stream<Uint8List>
    _dataSubscription = _connection!.input!.listen(
      _onData,
      onError: _onStreamError,
      onDone: _onStreamDone,
      cancelOnError: false,
    );
  }

  /// Called for every chunk of bytes received from the Arduino.
  void _onData(Uint8List bytes) {
    // Decode bytes → UTF-8 string and append to rolling buffer
    _buffer += utf8.decode(bytes, allowMalformed: true);

    // The Arduino sends one packet per line ending with \n (or \r\n).
    // Process all complete lines in the buffer.
    while (_buffer.contains('\n')) {
      final idx = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1); // keep remainder

      if (line.isNotEmpty) {
        _processLine(line);
      }
    }
  }

  void _processLine(String line) {
    final reading = DistanceReading.fromPacket(line);

    // Only update lastReading if it's a valid value
    // If it's an error, keep the previous good reading but still emit
    // the event so the timestamp updates
    if (!reading.isError) {
      lastReading = reading;
    }

    if (!_readingController.isClosed) {
      _readingController.add(reading);
    }
    notifyListeners();
  }

  void _onStreamError(Object error) {
    debugPrint('BT stream error: $error');
    _setError('Bluetooth error: $error');
    disconnect();
  }

  void _onStreamDone() {
    debugPrint('BT stream closed by remote device.');
    if (connectionState == BtConnectionState.connected) {
      // Device disconnected unexpectedly
      _setError('Device disconnected unexpectedly.');
      disconnect();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  void _setState(BtConnectionState state) {
    connectionState = state;
    notifyListeners();
  }

  void _setError(String msg) {
    errorMessage = msg;
    connectionState = BtConnectionState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect(notify: false);
    _readingController.close();
    super.dispose();
  }
}
