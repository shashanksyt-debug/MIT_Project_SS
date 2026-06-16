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
  double confidenceThreshold = 0.10;
  double iouThreshold = 0.45;
  bool applySigmoid = false;
  bool applySoftmax = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/detect.tflite');

      // Log input/output tensor info for debugging
      try {
        final inTensor = _interpreter.getInputTensor(0);
        print('TFLite input shape: ${inTensor.shape}, type: ${inTensor.type}');
      } catch (_) {}
      try {
        final outTensor = _interpreter.getOutputTensor(0);
        print('TFLite output shape: ${outTensor.shape}, type: ${outTensor.type}');
      } catch (_) {}

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

    // Prepare input according to model input type (float32 normalized 0..1 or uint8 0..255)
    final inTensor = _interpreter.getInputTensor(0);
    final isUint8 = inTensor.type.toString().toLowerCase().contains('uint8');

    Object input;
    // Build a 4D nested list: [1][H][W][3] which matches NHWC layout
    if (isUint8) {
      final List<List<List<List<int>>>> nested = List.generate(1, (_) =>
          List.generate(inputHeight, (_) =>
              List.generate(inputWidth, (_) => List.filled(3, 0))));
      for (int y = 0; y < inputHeight; y++) {
        for (int x = 0; x < inputWidth; x++) {
          final pixel = resized.getPixel(x, y);
          nested[0][y][x][0] = img.getRed(pixel);
          nested[0][y][x][1] = img.getGreen(pixel);
          nested[0][y][x][2] = img.getBlue(pixel);
        }
      }
      input = nested;
    } else {
      final List<List<List<List<double>>>> nested = List.generate(
          1,
          (_) => List.generate(
              inputHeight,
              (_) => List.generate(inputWidth, (_) => List.filled(3, 0.0))));
      for (int y = 0; y < inputHeight; y++) {
        for (int x = 0; x < inputWidth; x++) {
          final pixel = resized.getPixel(x, y);
          nested[0][y][x][0] = img.getRed(pixel) / 255.0;
          nested[0][y][x][1] = img.getGreen(pixel) / 255.0;
          nested[0][y][x][2] = img.getBlue(pixel) / 255.0;
        }
      }
      input = nested;
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
    bool hasObjectness = true;
    final int expectedWithObj = _labels.length + 5;
    final int expectedNoObj = _labels.length + 4;
    if (outShape.length >= 3) {
      final int a = outShape[1];
      final int b = outShape[2];
      if ((a == expectedWithObj && b > expectedWithObj) || (b == expectedWithObj && a > expectedWithObj)) {
        // one axis matches attrs with objectness
        if (a == expectedWithObj) {
          numAttrs = a;
          numBoxes = b;
        } else {
          numAttrs = b;
          numBoxes = a;
        }
        hasObjectness = true;
      } else if ((a == expectedNoObj && b > expectedNoObj) || (b == expectedNoObj && a > expectedNoObj)) {
        // one axis matches attrs without objectness
        if (a == expectedNoObj) {
          numAttrs = a;
          numBoxes = b;
        } else {
          numAttrs = b;
          numBoxes = a;
        }
        hasObjectness = false;
      } else {
        // fallback: assume smaller dim = attrs, larger = boxes
        if (a <= b) {
          numAttrs = a;
          numBoxes = b;
        } else {
          numAttrs = b;
          numBoxes = a;
        }
        hasObjectness = (numAttrs == expectedWithObj);
      }
    } else if (outShape.length == 2) {
      numAttrs = _labels.length + 5;
      numBoxes = (outShape[1] / numAttrs).floor();
      hasObjectness = true;
    } else {
      // unexpected shape
      numBoxes = 25200;
      numAttrs = _labels.length + 5;
      hasObjectness = true;
    }

    print('Parsed output dims -> numBoxes=$numBoxes numAttrs=$numAttrs hasObjectness=$hasObjectness');

    // Allocate output buffer exactly matching interpreter's reported outShape
    final int dim0 = outShape.length > 0 ? outShape[0] : 1;
    final int dim1 = outShape.length > 1 ? outShape[1] : 1;
    final int dim2 = outShape.length > 2 ? outShape[2] : 1;
    final outputs = List.generate(dim0, (_) => List.generate(dim1, (_) => List.filled(dim2, 0.0)));

    final outputMap = <int, Object>{0: outputs};

    try {
      // Debug: print input tensor expected info and a tiny sample
      try {
        final inT = _interpreter.getInputTensor(0);
        print('Running interpreter with input tensor shape=${inT.shape}, type=${inT.type}');
      } catch (_) {}
      try {
        final nested = input as List;
        print('Input nested dims: [${nested.length}][${(nested.isNotEmpty ? (nested[0] as List).length : 0)}][${(nested.isNotEmpty ? ((nested[0] as List).isNotEmpty ? ((nested[0] as List)[0] as List).length : 0) : 0)}][3]');
        try {
          print('Input sample pixel [0][0][0]: ${(nested[0][0][0] as List).take(3).toList()}');
        } catch (_) {}
      } catch (_) {}

      try {
        _interpreter.runForMultipleInputs([input], outputMap);
      } catch (e, st) {
        print('Interpreter run error: $e');
        print(st.toString());
        return [];
      }
    } catch (e) {
      print('Unexpected interpreter invocation error: $e');
      return [];
    }

    // Normalize interpreter output into rawOut[numBoxes][numAttrs]
    List<List<double>> rawOut = List.generate(numBoxes, (_) => List.filled(numAttrs, 0.0));
    if (outShape.length >= 3) {
      // outputs[0] shape is [dim1][dim2]
      if (dim1 == numBoxes && dim2 == numAttrs) {
        // output is [1, numBoxes, numAttrs]
        for (int i = 0; i < numBoxes; i++) {
          for (int j = 0; j < numAttrs; j++) rawOut[i][j] = outputs[0][i][j];
        }
      } else if (dim1 == numAttrs && dim2 == numBoxes) {
        // output is [1, numAttrs, numBoxes] -> transpose
        for (int i = 0; i < numBoxes; i++) {
          for (int j = 0; j < numAttrs; j++) rawOut[i][j] = outputs[0][j][i];
        }
      } else {
        // fallback: try to map first dim2 as attrs
        final int tryAttrs = dim2;
        final int tryBoxes = dim1;
        if (tryBoxes == numBoxes && tryAttrs == numAttrs) {
          for (int i = 0; i < numBoxes; i++) {
            for (int j = 0; j < numAttrs; j++) rawOut[i][j] = outputs[0][i][j];
          }
        } else {
          print('Warning: unexpected output dims $outShape — attempting best-effort reshape');
          // attempt flatten & split
          final flat = <double>[];
          for (final a in outputs[0]) {
            for (final b in a) flat.add(b as double);
          }
          final expected = numBoxes * numAttrs;
          if (flat.length >= expected) {
            for (int i = 0; i < numBoxes; i++) {
              for (int j = 0; j < numAttrs; j++) rawOut[i][j] = flat[i * numAttrs + j];
            }
          }
        }
      }
    } else if (outShape.length == 2) {
      // flat second dim contains boxes*attrs
      final flat = outputs[0][0];
      for (int i = 0; i < numBoxes; i++) {
        for (int j = 0; j < numAttrs; j++) rawOut[i][j] = flat[i * numAttrs + j];
      }
    } else {
      print('Unsupported outShape: $outShape');
    }

    // Debug: compute best score per box and print top few to diagnose
    try {
      final classStartForDebug = (numAttrs == (_labels.length + 5)) ? 5 : 4;
      final scores = <Map<String, dynamic>>[];
      for (int i = 0; i < numBoxes; i++) {
        final attrs = rawOut[i];
        double best = 0.0;
        for (int c = classStartForDebug; c < attrs.length; c++) {
          if (attrs[c] > best) best = attrs[c];
        }
        scores.add({'idx': i, 'score': best, 'attrs': attrs.take(10).toList()});
      }
      scores.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      final top = scores.take(5).toList();
      print('Top detection scores (idx,score,sample attrs): $top');
    } catch (_) {}

    // Debug: print a few raw output values to help diagnose detection issues
    try {
      final sample = (rawOut.length > 0 && rawOut[0].length > 0) ? rawOut[0].take(min<int>(10, rawOut[0].length)).toList() : <double>[];
      print('TFLite rawOut[0] sample: $sample');
      double minVal = double.infinity, maxVal = -double.infinity;
      final sampleBoxes = min<int>(rawOut.length, 10);
      for (int i = 0; i < sampleBoxes; i++) {
        for (final v in rawOut[i]) {
          if (v < minVal) minVal = v;
          if (v > maxVal) maxVal = v;
        }
      }
      if (minVal.isFinite && maxVal.isFinite) {
        print('Sample output attr range (first $sampleBoxes boxes): min=$minVal max=$maxVal');
      }
    } catch (_) {}
    // Optionally apply activations if model outputs logits
    if (applySigmoid || applySoftmax) {
      for (int i = 0; i < rawOut.length; i++) {
        final attrs = rawOut[i];
        int classStart = hasObjectness ? 5 : 4;
        // Apply sigmoid to objectness and bbox coords if requested
        if (applySigmoid && attrs.length > 4) {
          // apply sigmoid to objectness
          attrs[4] = _sigmoid(attrs[4]);
        }
        // Apply sigmoid to class logits if requested (before softmax)
        if (applySigmoid) {
          for (int c = classStart; c < attrs.length; c++) {
            attrs[c] = _sigmoid(attrs[c]);
          }
        }
        // Optionally apply softmax across class logits
        if (applySoftmax) {
          final scores = attrs.sublist(classStart);
          final soft = _softmax(scores);
          for (int c = 0; c < soft.length; c++) attrs[classStart + c] = soft[c];
        }
      }
    }
    final detections = <DetectedItem>[];


    for (int i = 0; i < numBoxes; i++) {
      final attrs = rawOut[i];
      if (attrs.length < 4) continue;
      final cx = attrs[0];
      final cy = attrs[1];
      final w = attrs[2];
      final h = attrs[3];

      int classStart = hasObjectness ? 5 : 4;
      double objectness = hasObjectness && attrs.length > 4 ? attrs[4] : 1.0;

      // class scores follow
      double bestScore = 0.0;
      int bestClass = 0;
      for (int c = classStart; c < attrs.length; c++) {
        if (attrs[c] > bestScore) {
          bestScore = attrs[c];
          bestClass = c - classStart;
        }
      }

      final score = hasObjectness ? objectness * bestScore : bestScore;
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

  double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  List<double> _softmax(List<double> vals) {
    if (vals.isEmpty) return vals;
    final maxV = vals.reduce(max);
    final exps = vals.map((v) => exp(v - maxV)).toList();
    final sum = exps.reduce((a, b) => a + b);
    if (sum == 0) return List.filled(vals.length, 0.0);
    return exps.map((e) => e / sum).toList();
  }

  /// Release interpreter resources
  void dispose() {
    try {
      _interpreter.close();
    } catch (_) {
      // ignore
    }
  }

}
