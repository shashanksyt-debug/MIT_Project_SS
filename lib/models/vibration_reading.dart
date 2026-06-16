// lib/models/vibration_reading.dart

enum VibrationLevel { none, mild, moderate, severe }

class VibrationReading {
  final int spikePercent;
  final VibrationLevel level;
  final String? alertMessage;
  final DateTime receivedAt;
  final String rawPacket;

  VibrationReading({
    required this.spikePercent,
    required this.level,
    this.alertMessage,
    required this.receivedAt,
    required this.rawPacket,
  });

  @override
  String toString() =>
      'Vibration($spikePercent% ${level.toString().split('.').last.toUpperCase()} @ $receivedAt)';
}
