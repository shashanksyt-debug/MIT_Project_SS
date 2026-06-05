import 'dart:typed_data';

import 'package:http/http.dart' as http;

class Esp32CameraService {
  static const String cameraUrl = 'http://10.159.98.217/capture';

  Future<Uint8List?> getFrame() async {
    try {
      print("Requesting image from $cameraUrl");

      final response = await http.get(
        Uri.parse(cameraUrl),
      );

      print("Status: ${response.statusCode}");
      print("Bytes: ${response.bodyBytes.length}");

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      print("Camera error: $e");
    }

    return null;
  }
}
