import 'package:permission_handler/permission_handler.dart';

/// Helper class for managing camera permissions
class CameraPermissionHelper {
  /// Request camera permission from the user
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();

    return status.isGranted;
  }

  /// Check if camera permission is already granted
  static Future<bool> isCameraPermissionGranted() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Open app settings to allow user to grant permissions manually
  static Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
