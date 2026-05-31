// lib/models/distance_reading.dart
//
// Represents a single distance measurement received from the Arduino.

class DistanceReading {
  /// Measured distance in centimetres. Null means a sensor error was received.
  final double? distanceCm;

  /// When this reading was received on the phone.
  final DateTime receivedAt;

  /// Raw string received over Bluetooth (for debugging / logging).
  final String rawPacket;

  const DistanceReading({
    required this.distanceCm,
    required this.receivedAt,
    required this.rawPacket,
  });

  /// True when the Arduino reported an error (out-of-range / timeout).
  bool get isError => distanceCm == null;

  // ── Factory: parse "DIST:23.45" or "DIST:ERROR" ──────────────
  factory DistanceReading.fromPacket(String raw) {
    final timestamp = DateTime.now();
    final trimmed = raw.trim();

    if (!trimmed.startsWith('DIST:')) {
      // Not a recognised packet → treat as error
      return DistanceReading(
        distanceCm: null,
        receivedAt: timestamp,
        rawPacket: raw,
      );
    }

    final valueStr = trimmed.substring(5); // everything after "DIST:"

    if (valueStr == 'ERROR') {
      return DistanceReading(
        distanceCm: null,
        receivedAt: timestamp,
        rawPacket: raw,
      );
    }

    final parsed = double.tryParse(valueStr);
    return DistanceReading(
      distanceCm: parsed, // null if parsing fails
      receivedAt: timestamp,
      rawPacket: raw,
    );
  }

  @override
  String toString() =>
      'DistanceReading(${distanceCm?.toStringAsFixed(1) ?? "ERROR"} cm @ $receivedAt)';
}
