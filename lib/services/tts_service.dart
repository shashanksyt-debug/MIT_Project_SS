// lib/services/tts_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  // ── Settings ──────────────────────────────────────────────────
  bool isTtsEnabled = true;
  double speechRate = 0.5;
  double volume = 1.0;
  double pitch = 1.0;
  Duration announceInterval = const Duration(seconds: 3);

  // ── Internal state ────────────────────────────────────────────
  bool _isSpeaking = false;
  bool _wasInWarning = false; // true while object is within threshold
  DateTime? _lastAnnounce; // last time a warning was spoken
  DateTime? _lastEventSpoken; // debounce for connection events

  TtsService() {
    _init();
  }

  Future<void> _init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(speechRate);
    await _tts.setVolume(volume);
    await _tts.setPitch(pitch);
    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setErrorHandler((_) => _isSpeaking = false);
  }

  // ── Called on every new Bluetooth distance reading ────────────
  //
  // Behaviour:
  //   • Silent when distance >= threshold (safe zone)
  //   • Speaks ONCE the moment object enters danger zone
  //   • Repeats every announceInterval while object stays close
  //   • Resets when object moves away — warns again on next approach
  //   • Never speaks "Sensor error" — silently ignores null readings
  Future<void> onNewReading(double? distanceCm, double thresholdCm) async {
    if (!isTtsEnabled) return;

    // ── Ignore sensor errors silently ────────────────────────
    if (distanceCm == null) {
      // Only reset warning state so it can fire again when sensor recovers
      _wasInWarning = false;
      return;
    }

    final inWarning = distanceCm < thresholdCm;

    // ── Object moved away → reset, stay silent ────────────────
    if (!inWarning) {
      _wasInWarning = false;
      return; // silent in safe zone
    }

    // ── Object just entered danger zone → speak immediately ───
    if (!_wasInWarning) {
      _wasInWarning = true;
      _lastAnnounce = DateTime.now();
      await _speak(
        'Warning! Obstacle at ${distanceCm.toStringAsFixed(0)} centimetres.',
        force: true,
      );
      return;
    }

    // ── Object still in danger zone → repeat every interval ───
    final now = DateTime.now();
    final shouldRepeat = _lastAnnounce == null ||
        now.difference(_lastAnnounce!) >= announceInterval;

    if (shouldRepeat) {
      _lastAnnounce = now;
      await _speak(
        'Obstacle still close. ${distanceCm.toStringAsFixed(0)} centimetres.',
      );
    }
  }

  // ── Speak a one-off connection/disconnection event ────────────
  // Debounced to 3 seconds — prevents "connected connected..." bug
  Future<void> speakEvent(String message) async {
    if (!isTtsEnabled) return;
    final now = DateTime.now();
    if (_lastEventSpoken != null &&
        now.difference(_lastEventSpoken!) < const Duration(seconds: 3)) {
      return;
    }
    _lastEventSpoken = now;
    await _speak(message, force: true);
  }

  // ── Core speak helper ─────────────────────────────────────────
  Future<void> _speak(String text, {bool force = false}) async {
    if (_isSpeaking && !force) return;
    if (_isSpeaking && force) await _tts.stop();
    await _tts.speak(text);
  }

  // ── Stop all speech immediately ───────────────────────────────
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  // ── Toggle TTS on/off ─────────────────────────────────────────
  void toggleTts() {
    isTtsEnabled = !isTtsEnabled;
    if (!isTtsEnabled) stop();
    notifyListeners();
  }

  // ── Apply settings at runtime ─────────────────────────────────
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
    if (interval != null) {
      announceInterval = interval;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
