import 'dart:io';

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class ObjectDetectionService {
  late ObjectDetector detector;
  bool _isInitialized = false;

  /// Initialize the object detector with proper model loading
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Use default COCO model with classification enabled
      detector = ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.single,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );
      _isInitialized = true;
      print('✓ Object detection model initialized with classification');
    } catch (e) {
      print('✗ Object detection initialization error: $e');
      // Fallback: Try without classification
      try {
        detector = ObjectDetector(
          options: ObjectDetectorOptions(
            mode: DetectionMode.single,
            classifyObjects: false,
            multipleObjects: true,
          ),
        );
        _isInitialized = true;
        print('✓ Fallback: Using basic detection without classification');
      } catch (e2) {
        print('✗ Even fallback failed: $e2');
        rethrow;
      }
    }
  }

  Future<List<DetectedObject>> detect(File image) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final input = InputImage.fromFile(image);
      final results = await detector.processImage(input);

      // Debug: Log detected objects
      print('═══════════════════════════════════════');
      print('Detected objects count: ${results.length}');
      for (int i = 0; i < results.length; i++) {
        final obj = results[i];
        print('Object $i:');
        print('  Labels count: ${obj.labels.length}');
        print('  BBox: ${obj.boundingBox}');
        for (final label in obj.labels) {
          print(
              '    - ${label.text}: ${(label.confidence * 100).toStringAsFixed(1)}%');
        }
      }
      print('═══════════════════════════════════════');

      return results;
    } catch (e) {
      print('✗ Detection error: $e');
      return [];
    }
  }

  Future<void> dispose() async {
    if (_isInitialized) {
      try {
        await detector.close();
        _isInitialized = false;
        print('Object detection service disposed');
      } catch (e) {
        print('Error disposing detector: $e');
      }
    }
  }
}
