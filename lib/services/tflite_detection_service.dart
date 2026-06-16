import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detected_item.dart';

class TfliteDetectionService {
  late Interpreter _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;
  double confidenceThreshold = 0.25;
  double iouThreshold = 0.45;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/detect.tflite');

      final raw = await rootBundle.loadString('assets/models/labelmap.txt');
      _labels = raw
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      _isInitialized = true;
      print('TFLite YOLO model loaded (${_labels.length} labels)');
    } catch (e) {
      print('TFLite initialization error: $e');
      rethrow;
    }
  }

  Future<List<DetectedItem>> detect(File imageFile) async {
    if (!_isInitialized) await initialize();

    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes)!;

    // Determine model input size from interpreter if possible
    int inputHeight = 640;
    int inputWidth = 640;
    try {
      final inShape = _interpreter.getInputTensor(0).shape; // e.g. [1, H, W, 3]
      if (inShape.length >= 3) {
        inputHeight = inShape[inShape.length - 3];
        inputWidth = inShape[inShape.length - 2];
      }
    } catch (_) {
      // keep defaults
    }

    final resized = img.copyResize(image, width: inputWidth, height: inputHeight);

    // Prepare input (float32 NHWC normalized 0..1)
    final input = Float32List(inputWidth * inputHeight * 3);
    int idx = 0;
    for (int y = 0; y < inputHeight; y++) {
      for (int x = 0; x < inputWidth; x++) {
        final pixel = resized.getPixel(x, y);
        input[idx++] = img.getRed(pixel) / 255.0;
        input[idx++] = img.getGreen(pixel) / 255.0;
        input[idx++] = img.getBlue(pixel) / 255.0;
      }
    }

    // Prepare output buffer according to model's output shape
    List<int> outShape;
    try {
      outShape = _interpreter.getOutputTensor(0).shape;
    } catch (e) {
      print('Unable to read output tensor shape: $e');
      // fallback to common YOLOv5/8 shape for 640: [1,25200,85]
      outShape = [1, 25200, _labels.length + 5];
    }

    int numBoxes = 0;
    int numAttrs = 0;
    if (outShape.length >= 3) {
      numBoxes = outShape[1];
      numAttrs = outShape[2];
    } else if (outShape.length == 2) {
      numAttrs = _labels.length + 5;
      numBoxes = (outShape[1] / numAttrs).floor();
    } else {
      // unexpected shape
      numBoxes = 25200;
      numAttrs = _labels.length + 5;
    }

    final outputs = List.generate(1, (_) => List.generate(numBoxes, (_) => List.filled(numAttrs, 0.0)));

    final outputMap = <int, Object>{0: outputs};

    try {
      _interpreter.runForMultipleInputs([input], outputMap);
    } catch (e) {
      print('Interpreter run error: $e');
      return [];
    }

    final rawOut = outputs[0];
    final detections = <DetectedItem>[];

    for (int i = 0; i < numBoxes; i++) {
      final attrs = rawOut[i];
      if (attrs.length < 5) continue;
      final cx = attrs[0];
      final cy = attrs[1];
      final w = attrs[2];
      final h = attrs[3];
      final objectness = attrs[4];

      // class scores follow
      double bestScore = 0.0;
      int bestClass = 0;
      for (int c = 5; c < attrs.length; c++) {
        if (attrs[c] > bestScore) {
          bestScore = attrs[c];
          bestClass = c - 5;
        }
      }

      final score = objectness * bestScore;
      if (score < confidenceThreshold) continue;

      // coords are expected normalized (0..1) center x,y,w,h. If not, results will be wrong — user should convert model accordingly.
      final xmin = max(0.0, cx - w / 2);
      final ymin = max(0.0, cy - h / 2);
      final xmax = min(1.0, cx + w / 2);
      final ymax = min(1.0, cy + h / 2);

      final rect = Rect.fromLTRB(xmin, ymin, xmax, ymax);
      final label = (bestClass >= 0 && bestClass < _labels.length) ? _labels[bestClass] : 'class_$bestClass';

      detections.add(DetectedItem(label: label, confidence: score, bbox: rect));
    }

    // Apply class-wise NMS
    final results = _nonMaxSuppressionByClass(detections, iouThreshold);
    return results;
  }

  List<DetectedItem> _nonMaxSuppressionByClass(List<DetectedItem> items, double iouThresh) {
    final byClass = <String, List<DetectedItem>>{};
    for (final it in items) {
      byClass.putIfAbsent(it.label, () => []).add(it);
    }

    final kept = <DetectedItem>[];
    for (final entry in byClass.entries) {
      final list = entry.value;
      list.sort((a, b) => b.confidence.compareTo(a.confidence));
      while (list.isNotEmpty) {
        final best = list.removeAt(0);
        kept.add(best);
        list.removeWhere((other) => _iou(best.bbox, other.bbox) > iouThresh);
      }
    }
    return kept;
  }

  double _iou(Rect a, Rect b) {
    final interLeft = max(a.left, b.left);
    final interTop = max(a.top, b.top);
    final interRight = min(a.right, b.right);
    final interBottom = min(a.bottom, b.bottom);
    final interW = max(0.0, interRight - interLeft);
    final interH = max(0.0, interBottom - interTop);
    final interArea = interW * interH;
    final areaA = (a.width) * (a.height);
    final areaB = (b.width) * (b.height);
    final union = areaA + areaB - interArea;
    if (union <= 0) return 0.0;
    return interArea / union;
  }
