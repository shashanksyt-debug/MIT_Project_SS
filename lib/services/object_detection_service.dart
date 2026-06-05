import 'dart:io';

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class ObjectDetectionService {
  final ObjectDetector detector = ObjectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );

  Future<List<DetectedObject>> detect(
    File image,
  ) async {
    final input = InputImage.fromFile(image);

    return await detector.processImage(input);
  }

  Future<void> dispose() async {
    await detector.close();
  }
}
