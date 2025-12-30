import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';

/// A camera preview widget that uses the native CameraPreview.
/// During capture, the image stream is used instead (handled by CaptureService).
class StreamingCameraPreview extends StatelessWidget {
  final CameraService camera;

  const StreamingCameraPreview({
    super.key,
    required this.camera,
  });

  @override
  Widget build(BuildContext context) {
    if (!camera.isInitialized || camera.controller == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Use native camera preview (high performance)
    return CameraPreview(camera.controller!);
  }
}
