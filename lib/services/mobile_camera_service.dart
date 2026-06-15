import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../utils/camera_permission_helper.dart';

/// Service to handle mobile device camera streaming and frame capture.
/// Provides continuous access to camera frames for object detection.
class MobileCameraService {
  late CameraController _controller;
  CameraDescription? _selectedCamera;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  CameraController get controller => _controller;

  /// Initialize camera service with the first available camera (back camera preferred)
  Future<bool> initialize() async {
    try {
      // Request camera permission
      final hasPermission =
          await CameraPermissionHelper.requestCameraPermission();
      if (!hasPermission) {
        print('Camera permission denied');
        return false;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        print('No cameras available');
        return false;
      }

      // Prefer back camera
      _selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        _selectedCamera!,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller.initialize();
      _isInitialized = true;
      return true;
    } catch (e) {
      print('Camera initialization error: $e');
      return false;
    }
  }

  /// Capture a single frame from the camera and save it as a file
  Future<File?> captureFrame() async {
    if (!_isInitialized) {
      print('Camera not initialized');
      return null;
    }

    try {
      final XFile xFile = await _controller.takePicture();
      return File(xFile.path);
    } catch (e) {
      print('Error capturing frame: $e');
      return null;
    }
  }

  /// Get camera preview widget
  Widget getCameraPreview() {
    if (!_isInitialized) {
      return const Center(
        child: Text('Camera not initialized'),
      );
    }
    return CameraPreview(_controller);
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (_isInitialized) {
      try {
        await _controller.dispose();
      } catch (e) {
        print('Error disposing camera: $e');
      }
      _isInitialized = false;
    }
  }

  /// Start camera streaming/preview
  Future<void> startCamera() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Stop camera streaming/preview
  Future<void> stopCamera() async {
    await dispose();
  }
}
