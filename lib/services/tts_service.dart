// lib/services/tts_service.dart
//
// Wraps flutter_tts to speak distance readings aloud.
// Features:
//   • Configurable announcement interval (default: every 3 seconds)
//   • Immediate alert when distance crosses the warning threshold
//   • Debounce: won't interrupt a sentence already in progress
//   • Toggle on/off at runtime

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  // ── Settings (all adjustable at runtime) ─────────────────────
  bool isTtsEnabled = true;
  bool announceWarnings = true; // speak immediately when threshold crossed
  double speechRate = 0.5; // 0.0–1.0
  double volume = 1.0; // 0.0–1.0
  double pitch = 1.0; // 0.5–2.0
  Duration announceInterval = const Duration(seconds: 3);

  // ── State ─────────────────────────────────────────────────────
  bool _isSpeaking = false;
  bool _wasInWarning = false; // tracks threshold crossing
  DateTime? _lastAnnounce;
  Timer? _periodicTimer;

  TtsService() {
    _init();
  }

  Future<void> _init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(speechRate);
    await _tts.setVolume(volume);
    await _tts.setPitch(pitch);

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
    });
  }

  // ── Called by BluetoothService on every new reading ───────────
  //
  // [distanceCm]   – the measured value (null = sensor error)
  // [thresholdCm]  – the user-configured warning threshold
  Future<void> onNewReading(double? distanceCm, double thresholdCm) async {
    if (!isTtsEnabled) return;

    if (distanceCm == null) {
      // Only speak sensor errors once, not repeatedly
      if (!_wasInWarning) {
        await _speak('Sensor error');
      }
      return;
    }

    final inWarning = distanceCm < thresholdCm;

    // ── Threshold crossing alert (immediate, highest priority) ──
    if (announceWarnings && inWarning && !_wasInWarning) {
      _wasInWarning = true;
      await _speak(
        'Warning! Object at ${distanceCm.toStringAsFixed(0)} centimetres.',
        force: true,
      );
      return;
    }

    if (!inWarning) _wasInWarning = false;

    // ── Periodic announcement ─────────────────────────────────
    final now = DateTime.now();
    final shouldAnnounce = _lastAnnounce == null ||
        now.difference(_lastAnnounce!) >= announceInterval;

    if (shouldAnnounce) {
      _lastAnnounce = now;
      final text = inWarning
          ? 'Distance: ${distanceCm.toStringAsFixed(0)} centimetres. Too close.'
          : 'Distance: ${distanceCm.toStringAsFixed(0)} centimetres.';
      await _speak(text);
    }
  }

  // ── Speak a connection event ──────────────────────────────────
  Future<void> speakEvent(String message) async {
    if (!isTtsEnabled) return;
    await _speak(message, force: true);
  }

  // ── Core speak helper ─────────────────────────────────────────
  Future<void> _speak(String text, {bool force = false}) async {
    if (_isSpeaking && !force) return;
    if (_isSpeaking && force) await _tts.stop();
    await _tts.speak(text);
  }

  // ── Stop immediately ──────────────────────────────────────────
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  // ── Apply updated settings ────────────────────────────────────
  Future<void> applySettings({
    double? rate,
    double? vol,
    double? p,
    Duration? interval,
  }) async {
    if (rate != null) {
      speechRate = rate;
      await _tts.setSpeechRate(rate);
    }
    if (vol != null) {
      volume = vol;
      await _tts.setVolume(vol);
    }
    if (p != null) {
      pitch = p;
      await _tts.setPitch(p);
    }
    if (interval != null) announceInterval = interval;
    notifyListeners();
  }

  void toggleTts() {
    isTtsEnabled = !isTtsEnabled;
    if (!isTtsEnabled) stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    _periodicTimer?.cancel();
    super.dispose();
  }
}
