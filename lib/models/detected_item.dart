import 'dart:ui';

class DetectedItem {
  final String label;
  final double confidence;
  final Rect bbox; // in image coordinates

  DetectedItem(
      {required this.label, required this.confidence, required this.bbox});
}
