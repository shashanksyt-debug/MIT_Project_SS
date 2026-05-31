// lib/services/tts_service.dart
//
// Wraps flutter_tts to speak distance readings aloud.
// Features:
//   • Configurable announcement interval (default: every 3 seconds)
//   • Immediate alert when distance crosses the warning threshold
//   • Debounce: won't interrupt a sentence already in progress
//   • Toggle on/off at runtime

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  // ── Settings (all adjustable at runtime) ─────────────────────
  bool   isTtsEnabled       = true;
  bool   announceWarnings   = true;  // speak immediately when threshold crossed
  double speechRate         = 0.5;   // 0.0–1.0
  double volume             = 1.0;   // 0.0–1.0
  double pitch              = 1.0;   // 0.5–2.0
  Duration announceInterval = const Duration(seconds: 3);

  // ── State ─────────────────────────────────────────────────────
  bool      _isSpeaking   = false;
  bool      _wasInWarning = false;  // tracks threshold crossing
  DateTime? _lastAnnounce;
  DateTime? _lastEventSpoken;       // debounce for connection events

  TtsService() {
    _init();
  }

  Future<void> _init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(speechRate);
    await _tts.setVolume(volume);
    await _tts.setPitch(pitch);

    _tts.setStartHandler(()  { _isSpeaking = true;  });
    _tts.setCompletionHandler(() { _isSpeaking = false; });
    _tts.setErrorHandler((_) { _isSpeaking = false; });
  }

  // ── Called on every new Bluetooth distance reading ────────────
  //
  // [distanceCm]  – measured value (null = sensor error)
  // [thresholdCm] – user-configured warning threshold
  Future<void> onNewReading(double? distanceCm, double thresholdCm) async {
    if (!isTtsEnabled) return;

    // ── Sensor error ──────────────────────────────────────────
    if (distanceCm == null) {
      if (!_wasInWarning) {
        await _speak('Sensor error');
      }
      _wasInWarning = false;  // FIX: reset so warnings fire again after error clears
      return;
    }

    final inWarning = distanceCm < thresholdCm;

    // ── Threshold crossing alert (immediate, highest priority) ──
    // Only fires once per crossing — not on every packet while close
    if (announceWarnings && inWarning && !_wasInWarning) {
      _wasInWarning = true;
      _lastAnnounce = DateTime.now();  // FIX: prevent immediate periodic follow-up
      await _speak(
        'Warning! Object at ${distanceCm.toStringAsFixed(0)} centimetres.',
        force: true,
      );
      return;
    }

    // Reset warning flag once object moves away
    if (!inWarning) _wasInWarning = false;

    // ── Periodic announcement (every announceInterval) ────────
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

  // ── Speak a one-off connection event ─────────────────────────
  // Debounced: ignores calls within 3 seconds of the last event.
  // This prevents the "connected connected connected..." repeat bug.
  Future<void> speakEvent(String message) async {
    if (!isTtsEnabled) return;

    final now = DateTime.now();
    if (_lastEventSpoken != null &&
        now.difference(_lastEventSpoken!) < const Duration(seconds: 3)) {
      return;  // debounce — too soon after last event
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

  // ── Stop immediately ──────────────────────────────────────────
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

  // ── Apply updated settings ────────────────────────────────────
  Future<void> applySettings({
    double?   rate,
    double?   vol,
    double?   p,
    Duration? interval,
  }) async {
    if (rate     != null) { speechRate = rate; await _tts.setSpeechRate(rate); }
    if (vol      != null) { volume     = vol;  await _tts.setVolume(vol);      }
    if (p        != null) { pitch      = p;    await _tts.setPitch(p);         }
    if (interval != null) { announceInterval = interval;                        }
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
