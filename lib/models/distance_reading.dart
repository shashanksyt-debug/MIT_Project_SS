// lib/models/distance_reading.dart

class DistanceReading {
  final double? distanceCm;
  final DateTime receivedAt;
  final String rawPacket;

  const DistanceReading({
    required this.distanceCm,
    required this.receivedAt,
    required this.rawPacket,
  });

  bool get isError => distanceCm == null;

  factory DistanceReading.fromPacket(String raw) {
    final timestamp = DateTime.now();

    // Strip ALL whitespace variants — \r \n spaces
    final trimmed = raw.replaceAll('\r', '').replaceAll('\n', '').trim();

    if (!trimmed.startsWith('DIST:')) {
      return DistanceReading(
          distanceCm: null, receivedAt: timestamp, rawPacket: raw);
    }

    // Everything after "DIST:" — also trim in case of "DIST: 23.45"
    final valueStr = trimmed.substring(5).trim();

    if (valueStr.isEmpty || valueStr == 'ERROR') {
      return DistanceReading(
          distanceCm: null, receivedAt: timestamp, rawPacket: raw);
    }

    final parsed = double.tryParse(valueStr);
    return DistanceReading(
        distanceCm: parsed, receivedAt: timestamp, rawPacket: raw);
  }

  @override
  String toString() =>
      'DistanceReading(${distanceCm?.toStringAsFixed(1) ?? "ERROR"} cm @ $receivedAt)';
}
