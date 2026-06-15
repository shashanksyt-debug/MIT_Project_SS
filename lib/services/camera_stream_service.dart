import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class CameraStreamService {
  final String streamUrl;
  StreamSubscription? _subscription;
  final void Function(Uint8List frameBytes) onFrameReceived;
  final void Function(String error) onError;

  CameraStreamService({
    required this.streamUrl,
    required this.onFrameReceived,
    required this.onError,
  });

  Future<void> start() async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(streamUrl));
      request.headers['Accept'] = 'multipart/x-mixed-replace';

      final response = await client.send(request).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          onError('Connection timed out.');
          throw Exception('Timeout');
        },
      );

      List<int> buffer = [];

      _subscription = response.stream.listen(
        (chunk) {
          buffer.addAll(chunk);

          while (true) {
            // Find JPEG start (FFD8)
            int start = -1;
            for (int i = 0; i < buffer.length - 1; i++) {
              if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
                start = i;
                break;
              }
            }

            if (start == -1) {
              buffer = [];
              break;
            }

            // Find JPEG end (FFD9)
            int end = -1;
            for (int i = start + 2; i < buffer.length - 1; i++) {
              if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
                end = i + 2;
                break;
              }
            }

            if (end == -1) break; // Wait for more data

            // Extract complete JPEG frame
            final frameBytes = Uint8List.fromList(buffer.sublist(start, end));
            buffer = buffer.sublist(end);
            onFrameReceived(frameBytes);
          }

          // Prevent buffer overflow
          if (buffer.length > 200000) {
            buffer = [];
          }
        },
        onError: (e) => onError(e.toString()),
        onDone: () => onError('Stream ended. ESP32 disconnected.'),
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  void stop() {
    _subscription?.cancel();
  }
}
