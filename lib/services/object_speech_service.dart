import 'tts_service.dart';

class ObjectSpeechService {
  final TtsService tts;

  String? _lastObject;
  DateTime? _lastSpoken;

  ObjectSpeechService(this.tts);

  Future<void> speakObject(
    String objectName,
  ) async {
    final now = DateTime.now();

    if (_lastObject == objectName &&
        _lastSpoken != null &&
        now.difference(_lastSpoken!).inSeconds < 5) {
      return;
    }

    _lastObject = objectName;
    _lastSpoken = now;

    await tts.speakEvent(
      "Detected $objectName",
    );
  }
}
