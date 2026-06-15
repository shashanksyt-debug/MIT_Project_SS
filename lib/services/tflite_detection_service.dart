import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detected_item.dart';

class TfliteDetectionService {
  late Interpreter _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;
  double confidenceThreshold = 0.3;

  // Non-maximum suppression IoU threshold
  double iouThreshold = 0.5;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load interpreter from assets
      _interpreter = await Interpreter.fromAsset('assets/models/detect.tflite');

      // Load labels
      final raw = await rootBundle.loadString('assets/models/labelmap.txt');
      _labels = raw
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      _isInitialized = true;
      print('TFLite model loaded (${_labels.length} labels)');
    } catch (e) {
      print('TFLite initialization error: $e');
      rethrow;
    }
  }

  Future<List<DetectedItem>> detect(File imageFile) async {
    if (!_isInitialized) await initialize();

    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes)!;

    // Model input size for EfficientDet-Lite3
    const inputSize = 384;
    final resized = img.copyResize(image, width: inputSize, height: inputSize);

    // Prepare input buffer (float32) RGB normalized to 0..1
    final input = Float32List(inputSize * inputSize * 3);
    int idx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input[idx++] = img.getRed(pixel) / 255.0;
        input[idx++] = img.getGreen(pixel) / 255.0;
        input[idx++] = img.getBlue(pixel) / 255.0;
      }
    }

    // Prepare output buffers for SSD Mobilenet-like models: locations, classes, scores, num
    // EfficientDet produces up to 100 detections
    final outputLocations =
        List.generate(1, (_) => List.generate(100, (_) => List.filled(4, 0.0)));
    final outputClasses = List.generate(1, (_) => List.filled(100, 0.0));
    final outputScores = List.generate(1, (_) => List.filled(100, 0.0));
    final numDetections = List.filled(1, 0.0);

  Future<List<DetectedItem>> detect(File imageFile) async {
    if (!_isInitialized) await initialize();

    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes)!;

    // First try: EfficientDet-Lite3 config (384x384 float input)
    try {
      final res = await _detectWithConfig(image, inputSize: 384, isFloat: true, maxResults: 100);
      if (res.isNotEmpty) return res;
    } catch (e) {
      print('Primary detect attempt failed: $e');
    }

    // Fallback: SSD-MobileNet config (300x300 uint8 input, up to 10 results)
    try {
      final res = await _detectWithConfig(image, inputSize: 300, isFloat: false, maxResults: 10);
      return res;
    } catch (e) {
      print('Fallback detect attempt failed: $e');
      return [];
    }
  }

  Future<List<DetectedItem>> _detectWithConfig(img.Image image, {required int inputSize, required bool isFloat, required int maxResults}) async {
    final resized = img.copyResize(image, width: inputSize, height: inputSize);

    // Prepare input buffer
    Object input;
    if (isFloat) {
      final buffer = Float32List(inputSize * inputSize * 3);
      int idx = 0;
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          buffer[idx++] = img.getRed(pixel) / 255.0;
          buffer[idx++] = img.getGreen(pixel) / 255.0;
          buffer[idx++] = img.getBlue(pixel) / 255.0;
        }
      }
      input = buffer;
    } else {
      final buffer = Uint8List(inputSize * inputSize * 3);
      int idx = 0;
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          buffer[idx++] = img.getRed(pixel);
          buffer[idx++] = img.getGreen(pixel);
          buffer[idx++] = img.getBlue(pixel);
        }
      }
      input = buffer;
    }

    // Prepare outputs
    final outputLocations = List.generate(1, (_) => List.generate(maxResults, (_) => List.filled(4, 0.0)));
    final outputClasses = List.generate(1, (_) => List.filled(maxResults, 0.0));
    final outputScores = List.generate(1, (_) => List.filled(maxResults, 0.0));
    final numDetections = List.filled(1, 0.0);

    final outputs = <int, Object>{
      0: outputLocations,
      1: outputClasses,
      2: outputScores,
      3: numDetections,
    };

    // Run interpreter
    try {
      _interpreter.runForMultipleInputs([input], outputs);
    } catch (e) {
      print('Interpreter run error for config (size=$inputSize,isFloat=$isFloat): $e');
      return [];
    }

    final detCount = numDetections[0].toInt();
    final rawResults = <DetectedItem>[];

    for (int i = 0; i < detCount && i < maxResults; i++) {
      final score = outputScores[0][i];
      if (score < confidenceThreshold) continue;
      final classId = outputClasses[0][i].toInt();
      final labelIndex = classId > 0 ? classId - 1 : classId;
      final label = (labelIndex >= 0 && labelIndex < _labels.length) ? _labels[labelIndex] : 'unknown';
      final bbox = outputLocations[0][i]; // [ymin, xmin, ymax, xmax]

      // Convert to normalized rect coordinates (0..1)
      final ymin = bbox[0];
      final xmin = bbox[1];
      final ymax = bbox[2];
      final xmax = bbox[3];
      final rect = Rect.fromLTRB(xmin, ymin, xmax, ymax);

      rawResults.add(DetectedItem(label: label, confidence: score, bbox: rect));
    }

    // Apply NMS
    final results = _nonMaxSuppression(rawResults, iouThreshold);
    return results;
  }
