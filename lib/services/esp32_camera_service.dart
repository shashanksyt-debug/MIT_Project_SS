import 'dart:typed_data';

import 'package:http/http.dart' as http;

class Esp32CameraService {
  static const String cameraUrl = 'http://10.109.60.217';

  Future<Uint8List?> getFrame() async {
    try {
      final response = await http
          .get(Uri.parse(cameraUrl))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      print("STATUS = ${response.statusCode}");
      print("BODY LENGTH = ${response.body.length}");

      return null;
    } catch (e) {
      print("CAMERA EXCEPTION: $e");
    }

    return null;
  }
}
