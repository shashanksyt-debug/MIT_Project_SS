import 'dart:async';

import 'package:flutter/material.dart';
import '../models/detected_item.dart';
import 'package:provider/provider.dart';

import '../services/mobile_camera_service.dart';
import '../services/tflite_detection_service.dart';
import '../services/object_speech_service.dart';
import '../services/tts_service.dart';
import '../utils/constants.dart';

class CameraDetectionPanel extends StatefulWidget {
  const CameraDetectionPanel({super.key});

  @override
  State<CameraDetectionPanel> createState() => _CameraDetectionPanelState();
}

class _BoundingBoxPainter extends CustomPainter {
  final List<DetectedItem> detections;
  final Color boxColor;

  _BoundingBoxPainter({required this.detections, required this.boxColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = boxColor;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final d in detections) {
      // d.bbox is normalized (0..1)
      final left = d.bbox.left * size.width;
      final top = d.bbox.top * size.height;
      final right = d.bbox.right * size.width;
      final bottom = d.bbox.bottom * size.height;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRect(rect, paint);

      final label = '${d.label} ${(d.confidence * 100).toStringAsFixed(0)}%';
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
            color: boxColor, fontSize: 12, backgroundColor: Colors.black54),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(left + 4, top + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}

class _CameraDetectionPanelState extends State<CameraDetectionPanel> {
  final MobileCameraService _cameraService = MobileCameraService();
  final TfliteDetectionService _detectionService = TfliteDetectionService();
  late ObjectSpeechService _speechService;

  List<DetectedItem> _detectedObjects = [];
  bool _isCameraActive = false;
  bool _isProcessing = false;
  Timer? _frameProcessingTimer;
  // For temporal smoothing: track consecutive appearances
  final Map<String, int> _stabilityCounts = {};
  int _stabilityRequired = 2;
  double _confidenceThreshold = 0.3;

  @override
  void initState() {
    super.initState();
    final ttsService = context.read<TtsService>();
    _speechService = ObjectSpeechService(ttsService);
    _initializeDetectionService();
  }

  Future<void> _initializeDetectionService() async {
    try {
      await _detectionService.initialize();
      print('Detection service initialized');
    } catch (e) {
      print('Failed to initialize detection service: $e');
    }
  }

  @override
  void dispose() {
    _stopCamera();
    _detectionService.dispose();
    _frameProcessingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final initialized = await _cameraService.initialize();
      if (initialized && mounted) {
        setState(() => _isCameraActive = true);
        _startContinuousDetection();
      }
    } catch (e) {
      print('Camera initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize camera: $e')),
        );
      }
    }
  }

  Future<void> _stopCamera() async {
    _frameProcessingTimer?.cancel();
    await _cameraService.dispose();
    if (mounted) {
      setState(() {
        _isCameraActive = false;
        _detectedObjects = [];
      });
    }
  }

  void _startContinuousDetection() {
    // Process frames every 500ms to avoid excessive processing
    _frameProcessingTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _processFrame(),
    );
  }

  Future<void> _processFrame() async {
    if (_isProcessing || !_isCameraActive) return;

    _isProcessing = true;

    try {
      final frameFile = await _cameraService.captureFrame();
      if (frameFile != null) {
        print('Frame captured: ${frameFile.path}');
        final detectedObjects = await _detectionService.detect(frameFile);
        print('Objects detected: ${detectedObjects.length}');

        if (mounted) {
          setState(() => _detectedObjects = detectedObjects);

          // Update stability counts for temporal smoothing
          final presentLabels = detectedObjects
              .map((d) => d.label.trim().toLowerCase().split(' ').first)
              .where((s) => s.isNotEmpty)
              .toSet();

          // Increment counts for present labels
          for (final l in presentLabels) {
            _stabilityCounts[l] = (_stabilityCounts[l] ?? 0) + 1;
            if (_stabilityCounts[l]! > _stabilityRequired) {
              _stabilityCounts[l] = _stabilityRequired;
            }
          }

          // Reset counts for labels no longer present
          final keys = List<String>.from(_stabilityCounts.keys);
          for (final k in keys) {
            if (!presentLabels.contains(k)) {
              _stabilityCounts.remove(k);
            }
          }
        }

        // Find and speak only the nearest object (largest bounding box)
        if (detectedObjects.isNotEmpty) {
          // Filter objects with valid labels
          final validObjects =
              detectedObjects.where((obj) => obj.label.isNotEmpty).toList();

          if (validObjects.isNotEmpty) {
            // Sort by bounding box area (larger = closer)
            validObjects.sort((a, b) {
              final areaA = a.bbox.width * a.bbox.height;
              final areaB = b.bbox.width * b.bbox.height;
              return areaB.compareTo(areaA); // Descending order
            });

            final nearestObject = validObjects.first;
            var label = nearestObject.label;
            print('Raw label text: "$label"');

            // Clean up label - remove extra info and take only first word
            label = label.trim().toLowerCase().split(' ').first;
            print('Cleaned label: "$label"');

            if (label.isNotEmpty) {
              // Temporal smoothing: only speak if detected for N consecutive frames
              _stabilityCounts[label] = (_stabilityCounts[label] ?? 0) + 1;
              if (_stabilityCounts[label]! >= _stabilityRequired) {
                await _speechService.speakObject(label);
                // reset counts to avoid repeated announcements
                _stabilityCounts.clear();
              }
            }
          }
        }
      } else {
        print('Frame is null');
      }
    } catch (e) {
      print('Frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppConstants.colorCard,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Live Object Detection",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.colorTextPrimary,
                  ),
                ),
                Text(
                  _detectedObjects.length.toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.colorAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Camera Preview or Camera Placeholder
            Container(
              height: 280,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: AppConstants.colorBorder),
                borderRadius: BorderRadius.circular(8),
                color: Colors.black,
              ),
              child: _isCameraActive
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _cameraService.getCameraPreview(),
                          // Overlay for bounding boxes
                          CustomPaint(
                            painter: _BoundingBoxPainter(
                                detections: _detectedObjects,
                                boxColor: AppConstants.colorAccent),
                          ),
                        ],
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt,
                            size: 48,
                            color: AppConstants.colorTextSecond,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Camera not active',
                            style: TextStyle(
                              color: AppConstants.colorTextSecond,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            // Detected Objects List
            if (_detectedObjects.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.colorBackground,
                  border: Border.all(color: AppConstants.colorBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detected Objects:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppConstants.colorTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_detectedObjects.length, (i) {
                      final obj = _detectedObjects[i];
                      var label = obj.label.isNotEmpty ? obj.label : 'Unknown';
                      // Clean label - only take first word
                      label = label.trim().toLowerCase().split(' ').first;

                      final confidence = obj.confidence;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 8,
                              color: AppConstants.colorAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: const TextStyle(
                                color: AppConstants.colorTextPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${(confidence * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: AppConstants.colorAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              )
            else if (_isCameraActive)
              const Text(
                'No objects detected',
                style: TextStyle(
                  color: AppConstants.colorTextSecond,
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 16),
            // Camera Control Button
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Confidence:'),
                Expanded(
                  child: Slider(
                    value: _confidenceThreshold,
                    min: 0.1,
                    max: 0.9,
                    divisions: 16,
                    label:
                        '${(_confidenceThreshold * 100).toStringAsFixed(0)}%',
                    onChanged: (v) {
                      setState(() {
                        _confidenceThreshold = v;
                        _detectionService.confidenceThreshold = v;
                      });
                    },
                  ),
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCameraActive ? _stopCamera : _initializeCamera,
                icon: Icon(
                  _isCameraActive ? Icons.stop : Icons.videocam,
                ),
                label: Text(
                  _isCameraActive ? 'Stop Camera' : 'Start Camera',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isCameraActive ? Colors.red : AppConstants.colorAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
