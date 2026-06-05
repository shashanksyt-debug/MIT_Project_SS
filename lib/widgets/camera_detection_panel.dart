import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/esp32_camera_service.dart';

class CameraDetectionPanel extends StatefulWidget {
  const CameraDetectionPanel({super.key});

  @override
  State<CameraDetectionPanel> createState() => _CameraDetectionPanelState();
}

class _CameraDetectionPanelState extends State<CameraDetectionPanel> {
  final camera = Esp32CameraService();

  Uint8List? frame;

  bool loading = false;

  Future<void> _fetchImage() async {
    if (loading) return;

    loading = true;

    final imageBytes = await camera.getFrame();

    if (mounted) {
      setState(() {
        frame = imageBytes;
      });
    }

    loading = false;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "ESP32-CAM Preview",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (frame != null)
              Image.memory(
                frame!,
                height: 220,
                fit: BoxFit.cover,
              )
            else
              const SizedBox(
                height: 220,
                child: Center(
                  child: Text(
                    "No Image",
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchImage,
              child: const Text(
                "Capture Frame",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
