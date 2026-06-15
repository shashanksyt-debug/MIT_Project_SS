import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:path_provider/path_provider.dart';
import '../services/camera_stream_service.dart';
import '../painters/bounding_box_painter.dart';
import 'package:flutter/services.dart';

class StreamDetectionPage extends StatefulWidget {
  const StreamDetectionPage({super.key});

  @override
  State<StreamDetectionPage> createState() => _StreamDetectionPageState();
}

class _StreamDetectionPageState extends State<StreamDetectionPage> {
  Uint8List? _imageBytes;
  List<DetectedObject> _objects = [];
  Size _imageSize = Size.zero;
  bool _isProcessing = false;
  bool _isConnected = false;
  String? _errorMessage;

  // ← Replace with your ESP32-CAM IP
  final String streamUrl = 'http://10.100.125.217/stream';

  late final CameraStreamService _streamService;
  late final ObjectDetector _detector;

  @override
  void initState() {
    super.initState();
    _initDetector();
    _initStream();
  }

  void _initDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _detector = ObjectDetector(options: options);
  }

  void _initStream() {
    _streamService = CameraStreamService(
      streamUrl: streamUrl,
      onFrameReceived: _processFrame,
      onError: (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e;
            _isConnected = false;
          });
        }
      },
    );

    setState(() => _isConnected = true);
    _streamService.start();
  }

  Future<void> _processFrame(Uint8List jpegBytes) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Write JPEG to temp file for ML Kit
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/frame.jpg');
      await file.writeAsBytes(jpegBytes);

      final inputImage = InputImage.fromFilePath(file.path);
      final objects = await _detector.processImage(inputImage);

      // Get image size for bounding box scaling
      final decoded = await decodeImageFromList(jpegBytes);

      if (mounted) {
        setState(() {
          _imageBytes = jpegBytes;
          _objects = objects;
          _imageSize = Size(
            decoded.width.toDouble(),
            decoded.height.toDouble(),
          );
        });
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _streamService.stop();
    _detector.close();
    super.dispose();
  }

  Widget _buildStream(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Image.memory(
              _imageBytes!,
              gaplessPlayback: true,
              fit: BoxFit.contain,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            ),
            if (_imageSize != Size.zero)
              CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: BoundingBoxPainter(
                  objects: _objects,
                  imageSize: _imageSize,
                  widgetSize: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatus() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_errorMessage != null) ...[
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _isConnected = false;
              });
              _initStream();
            },
            child: const Text('Retry'),
          ),
        ] else ...[
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(
            _isConnected ? 'Waiting for frames...' : 'Connecting to ESP32...',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Object Detection'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              Icons.circle,
              color: _isConnected ? Colors.greenAccent : Colors.red,
              size: 14,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: _imageBytes != null ? _buildStream(context) : _buildStatus(),
      ),
    );
  }
}
