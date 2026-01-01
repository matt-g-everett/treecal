import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/camera_service.dart';

/// A camera preview widget that displays frames from the camera stream.
/// This ensures the preview matches exactly what detection sees,
/// which is critical for accurate cone calibration on multi-lens devices.
class StreamingCameraPreview extends StatefulWidget {
  final CameraService camera;

  /// Called when stream size changes. Reports the rotated dimensions
  /// (what appears on screen, e.g., 720x1280 for portrait).
  final void Function(Size streamSize)? onStreamSizeChanged;

  /// Called when raw camera size is available. Reports the original camera
  /// dimensions before rotation (e.g., 1280x720 for landscape sensor).
  final void Function(Size rawCameraSize)? onRawCameraSizeChanged;

  /// When true, pauses frame polling to reduce contention during capture.
  /// The last displayed frame will remain visible.
  final bool pausePreview;

  const StreamingCameraPreview({
    super.key,
    required this.camera,
    this.onStreamSizeChanged,
    this.onRawCameraSizeChanged,
    this.pausePreview = false,
  });

  @override
  State<StreamingCameraPreview> createState() => _StreamingCameraPreviewState();
}

class _StreamingCameraPreviewState extends State<StreamingCameraPreview> {
  ui.Image? _currentImage;
  bool _isStreaming = false;
  Size? _streamSize;
  Size? _rawCameraSize;  // Original camera dimensions before rotation
  int _sensorOrientation = 0;  // Degrees to rotate the image

  // Reusable RGBA buffer to reduce GC pressure
  Uint8List? _rgbaBuffer;

  @override
  void initState() {
    super.initState();
    _startStreamPreview();
  }

  @override
  void dispose() {
    _stopStreamPreview();
    super.dispose();
  }

  Future<void> _startStreamPreview() async {
    if (_isStreaming) return;
    if (!widget.camera.isInitialized) return;

    _isStreaming = true;

    // Get sensor orientation from the camera controller
    final controller = widget.camera.controller;
    if (controller != null) {
      _sensorOrientation = controller.description.sensorOrientation;
      debugPrint('[StreamPreview] Sensor orientation: $_sensorOrientation°');
    }

    // Start the camera stream if not already streaming
    if (!widget.camera.isStreaming) {
      await widget.camera.startStreamCapture();
    }

    // Poll for frames and convert to displayable images
    _pollFrames();
  }

  void _pollFrames() async {
    while (_isStreaming && mounted) {
      // Skip polling when paused (during capture) to avoid contention
      if (widget.pausePreview) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      try {
        final bgrFrame = await widget.camera.captureFrameAsBGR();
        if (bgrFrame != null && mounted) {
          // Report raw camera size (before rotation) for coordinate transformation
          final newRawSize = Size(
            bgrFrame.originalWidth.toDouble(),
            bgrFrame.originalHeight.toDouble(),
          );
          if (_rawCameraSize != newRawSize) {
            _rawCameraSize = newRawSize;
            widget.onRawCameraSizeChanged?.call(newRawSize);
          }

          // Report stream size if changed (use rotated dimensions for portrait display)
          final bool isRotated90or270 = _sensorOrientation == 90 || _sensorOrientation == 270;
          final newSize = Size(
            isRotated90or270 ? bgrFrame.originalHeight.toDouble() : bgrFrame.originalWidth.toDouble(),
            isRotated90or270 ? bgrFrame.originalWidth.toDouble() : bgrFrame.originalHeight.toDouble(),
          );
          if (_streamSize != newSize) {
            _streamSize = newSize;
            widget.onStreamSizeChanged?.call(newSize);
          }

          // Convert BGR to RGBA for display
          final rgbaBytes = _bgrToRgba(
            bgrFrame.bytes,
            bgrFrame.width,
            bgrFrame.height,
          );

          // Decode to ui.Image
          final completer = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            rgbaBytes,
            bgrFrame.width,
            bgrFrame.height,
            ui.PixelFormat.rgba8888,
            (image) => completer.complete(image),
          );

          final image = await completer.future;
          if (mounted) {
            setState(() {
              _currentImage?.dispose();
              _currentImage = image;
            });
          } else {
            image.dispose();
          }
        }
      } catch (e) {
        debugPrint('[StreamPreview] Frame error: $e');
      }

      // Limit frame rate to ~15 fps to reduce CPU load
      await Future.delayed(const Duration(milliseconds: 66));
    }
  }

  Uint8List _bgrToRgba(Uint8List bgr, int width, int height) {
    // Reuse buffer if possible to reduce GC pressure
    final requiredSize = width * height * 4;
    if (_rgbaBuffer == null || _rgbaBuffer!.length != requiredSize) {
      _rgbaBuffer = Uint8List(requiredSize);
    }
    final rgba = _rgbaBuffer!;

    for (int i = 0; i < width * height; i++) {
      rgba[i * 4 + 0] = bgr[i * 3 + 2]; // R = B
      rgba[i * 4 + 1] = bgr[i * 3 + 1]; // G = G
      rgba[i * 4 + 2] = bgr[i * 3 + 0]; // B = R
      rgba[i * 4 + 3] = 255;            // A = 255
    }
    return rgba;
  }

  Future<void> _stopStreamPreview() async {
    _isStreaming = false;
    _currentImage?.dispose();
    _currentImage = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.camera.isInitialized || widget.camera.controller == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_currentImage != null) {
      return CustomPaint(
        painter: _ImagePainter(_currentImage!, _sensorOrientation),
        size: Size.infinite,
      );
    }

    // Show loading indicator while waiting for first stream frame
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 8),
            Text(
              'Starting camera...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter that draws a ui.Image scaled to fill the canvas with rotation
class _ImagePainter extends CustomPainter {
  final ui.Image image;
  final int sensorOrientation;  // 0, 90, 180, or 270 degrees

  _ImagePainter(this.image, this.sensorOrientation);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    // Apply rotation based on sensor orientation
    // Most phone cameras have 90° or 270° sensor orientation
    final rotationRadians = sensorOrientation * 3.14159265359 / 180.0;

    // For 90° or 270° rotation, the image dimensions are swapped
    final bool isRotated90or270 = sensorOrientation == 90 || sensorOrientation == 270;

    // Get effective image dimensions after rotation
    final double imageW = isRotated90or270 ? image.height.toDouble() : image.width.toDouble();
    final double imageH = isRotated90or270 ? image.width.toDouble() : image.height.toDouble();
    final imageAspect = imageW / imageH;
    final canvasAspect = size.width / size.height;

    double drawWidth, drawHeight;
    if (imageAspect > canvasAspect) {
      // Image is wider - fit height, crop width
      drawHeight = size.height;
      drawWidth = size.height * imageAspect;
    } else {
      // Image is taller - fit width, crop height
      drawWidth = size.width;
      drawHeight = size.width / imageAspect;
    }

    // Move to center, rotate, then draw
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotationRadians);

    // After rotation, offset to center the image
    final destRect = Rect.fromCenter(
      center: Offset.zero,
      width: isRotated90or270 ? drawHeight : drawWidth,
      height: isRotated90or270 ? drawWidth : drawHeight,
    );

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.sensorOrientation != sensorOrientation;
  }
}
