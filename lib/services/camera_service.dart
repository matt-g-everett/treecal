import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// BGR frame data for direct processing (no JPEG encoding)
class BGRFrame {
  final Uint8List bytes;
  final int width;
  final int height;
  final int originalWidth;   // Pre-downscale width (for coordinate scaling)
  final int originalHeight;  // Pre-downscale height

  BGRFrame({
    required this.bytes,
    required this.width,
    required this.height,
    int? originalWidth,
    int? originalHeight,
  }) : originalWidth = originalWidth ?? width,
       originalHeight = originalHeight ?? height;

  /// Scale factor applied (1.0 = no scaling)
  double get scaleFactor => originalWidth / width;
}

class CameraService extends ChangeNotifier {
  CameraController? _controller;
  bool _isInitialized = false;
  String _statusMessage = 'Camera not initialized';
  bool _isLockedForCapture = false;
  bool _isStreaming = false;
  BGRFrame? _latestBGRFrame;  // Pre-converted BGR frame (safe from GC)
  Completer<BGRFrame>? _frameCompleter;

  /// Downscale factor for capture frames (2.0 = half resolution)
  /// Applied immediately after BGR conversion to reduce memory and processing
  static const double captureDownscaleFactor = 2.0;

  bool get isInitialized => _isInitialized;
  String get statusMessage => _statusMessage;
  CameraController? get controller => _controller;
  bool get isLockedForCapture => _isLockedForCapture;
  bool get isStreaming => _isStreaming;
  
  Future<bool> initialize(CameraDescription camera) async {
    try {
      _updateStatus('Initializing camera...');

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        // Use YUV for streaming during capture
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      // Set exposure, focus, and flash modes for better LED detection
      try {
        await _controller!.setExposureMode(ExposureMode.auto);
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('Could not set camera modes: $e');
      }

      _isInitialized = true;
      _updateStatus('Camera ready');
      return true;
    } catch (e) {
      _isInitialized = false;
      _updateStatus('Camera error: $e');
      return false;
    }
  }
  
  Future<String?> takePicture(String filepath) async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Camera not initialized');
    }

    try {
      final XFile file = await _controller!.takePicture();

      // Move to desired location
      await File(file.path).copy(filepath);
      await File(file.path).delete();

      return filepath;
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return null;
    }
  }

  /// Lock focus and exposure for fast repeated captures.
  /// Call this before starting a capture sequence, then use takePictureFast().
  Future<void> lockForCapture() async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Camera not initialized');
    }

    try {
      // Lock focus at current position
      await _controller!.setFocusMode(FocusMode.locked);
      // Lock exposure at current level
      await _controller!.setExposureMode(ExposureMode.locked);
      _isLockedForCapture = true;
      debugPrint('[CAMERA] Focus and exposure locked for capture');
    } catch (e) {
      debugPrint('[CAMERA] Could not lock focus/exposure: $e');
    }
  }

  /// Unlock focus and exposure after capture sequence.
  Future<void> unlockCapture() async {
    if (!_isInitialized || _controller == null) return;

    try {
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      _isLockedForCapture = false;
      debugPrint('[CAMERA] Focus and exposure unlocked');
    } catch (e) {
      debugPrint('[CAMERA] Could not unlock focus/exposure: $e');
    }
  }

  /// Take a picture without autofocus sequence (for locked capture mode).
  /// Much faster than takePicture() when focus/exposure are locked.
  Future<String?> takePictureFast(String filepath) async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Camera not initialized');
    }

    try {
      // takePicture() still triggers focus sequence in the camera plugin,
      // but with locked focus mode the camera should skip the focus wait
      final XFile file = await _controller!.takePicture();

      // Move to desired location
      await File(file.path).copy(filepath);
      await File(file.path).delete();

      return filepath;
    } catch (e) {
      debugPrint('Error taking fast picture: $e');
      return null;
    }
  }

  /// Start image streaming for ultra-fast frame capture.
  Future<void> startStreamCapture() async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Camera not initialized');
    }
    if (_isStreaming) return;

    _isStreaming = true;
    _latestBGRFrame = null;

    await _controller!.startImageStream((CameraImage image) {
      // Convert to BGR IMMEDIATELY in the callback before GC can collect the buffer
      // This must be synchronous - no async, no isolate
      try {
        final bgrFrame = _convertCameraImageToBGRSync(image);
        if (bgrFrame != null) {
          _latestBGRFrame = bgrFrame;

          // If someone is waiting for a frame, complete immediately
          if (_frameCompleter != null && !_frameCompleter!.isCompleted) {
            _frameCompleter!.complete(bgrFrame);
            _frameCompleter = null;
          }
        }
      } catch (e) {
        debugPrint('[CAMERA] Error converting frame in callback: $e');
      }
    });

    debugPrint('[CAMERA] Image stream started for capture');
  }

  /// Stop image streaming.
  Future<void> stopStreamCapture() async {
    if (!_isInitialized || _controller == null) return;
    if (!_isStreaming) return;

    await _controller!.stopImageStream();
    _isStreaming = false;
    _latestBGRFrame = null;
    _frameCompleter = null;

    debugPrint('[CAMERA] Image stream stopped');
  }

  /// Convert CameraImage to BGR synchronously (must run in stream callback)
  /// This accesses native memory directly without copying first
  BGRFrame? _convertCameraImageToBGRSync(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToBGRSync(image);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        // iOS BGRA format
        final bgraMat = cv.Mat.fromList(
          image.height,
          image.width,
          cv.MatType.CV_8UC4,
          image.planes[0].bytes,
        );
        cv.Mat bgrMat = cv.cvtColor(bgraMat, cv.COLOR_BGRA2BGR);
        bgraMat.dispose();

        // Downscale immediately to reduce memory and speed up detection
        final originalWidth = bgrMat.cols;
        final originalHeight = bgrMat.rows;

        if (captureDownscaleFactor > 1.0) {
          final newWidth = (originalWidth / captureDownscaleFactor).round();
          final newHeight = (originalHeight / captureDownscaleFactor).round();
          final resized = cv.resize(bgrMat, (newWidth, newHeight), interpolation: cv.INTER_AREA);
          bgrMat.dispose();
          bgrMat = resized;
        }

        final result = BGRFrame(
          bytes: Uint8List.fromList(bgrMat.data),
          width: bgrMat.cols,
          height: bgrMat.rows,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
        );
        bgrMat.dispose();
        return result;
      } else {
        debugPrint('[CAMERA] Unsupported format: ${image.format.group}');
        return null;
      }
    } catch (e) {
      debugPrint('[CAMERA] Sync conversion error: $e');
      return null;
    }
  }

  /// Convert YUV420 to BGR synchronously
  /// Downscales YUV BEFORE color conversion for maximum efficiency
  BGRFrame? _convertYUV420ToBGRSync(CameraImage image) {
    final originalWidth = image.width;
    final originalHeight = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    // Access bytes directly (no copy) - must complete before callback returns
    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    final uvPixelStride = uPlane.bytesPerPixel ?? 2;
    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;

    // Calculate downscaled dimensions (must be even for YUV)
    final scale = captureDownscaleFactor > 1.0 ? captureDownscaleFactor.toInt() : 1;
    final width = (originalWidth / scale) ~/ 2 * 2;  // Ensure even
    final height = (originalHeight / scale) ~/ 2 * 2;

    // Build NV21 format at reduced resolution
    final nv21Size = width * height + (width * height ~/ 2);
    final nv21Bytes = Uint8List(nv21Size);

    // Subsample Y plane (take every Nth pixel)
    int dstOffset = 0;
    for (int row = 0; row < height; row++) {
      final srcRow = row * scale;
      final srcRowOffset = srcRow * yRowStride;
      for (int col = 0; col < width; col++) {
        final srcCol = col * scale;
        nv21Bytes[dstOffset++] = yBytes[srcRowOffset + srcCol];
      }
    }

    // Subsample and interleave V and U
    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;

    if (uvPixelStride == 2) {
      // Interleaved UV (common on Android)
      for (int row = 0; row < uvHeight; row++) {
        final srcRow = row * scale;
        final srcRowOffset = srcRow * uvRowStride;
        for (int col = 0; col < uvWidth; col++) {
          final srcCol = col * scale;
          final srcOffset = srcRowOffset + srcCol * uvPixelStride;
          nv21Bytes[dstOffset++] = vBytes[srcOffset];
          nv21Bytes[dstOffset++] = uBytes[srcOffset];
        }
      }
    } else {
      // Planar UV
      for (int row = 0; row < uvHeight; row++) {
        final srcRow = row * scale;
        final srcRowOffset = srcRow * uvRowStride;
        for (int col = 0; col < uvWidth; col++) {
          final srcCol = col * scale;
          nv21Bytes[dstOffset++] = vBytes[srcRowOffset + srcCol];
          nv21Bytes[dstOffset++] = uBytes[srcRowOffset + srcCol];
        }
      }
    }

    // Convert downscaled YUV to BGR with OpenCV
    final yuvMat = cv.Mat.fromList(
      height + height ~/ 2,
      width,
      cv.MatType.CV_8UC1,
      nv21Bytes,
    );

    final bgrMat = cv.cvtColor(yuvMat, cv.COLOR_YUV2BGR_NV21);
    yuvMat.dispose();

    final result = BGRFrame(
      bytes: Uint8List.fromList(bgrMat.data),
      width: bgrMat.cols,
      height: bgrMat.rows,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    );
    bgrMat.dispose();

    return result;
  }

  /// Capture a frame from the stream and save as JPEG.
  /// Ultra-fast - just grabs the latest frame, no camera operations.
  Future<String?> captureFrameFromStream(String filepath) async {
    final result = await captureFrameAsBGR();
    if (result == null) return null;

    try {
      // Convert BGR to JPEG and write to file
      final bgrMat = cv.Mat.fromList(
        result.height,
        result.width,
        cv.MatType.CV_8UC3,
        result.bytes,
      );
      final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 85]);
      final (success, jpegBytes) = cv.imencode('.jpg', bgrMat, params: params);
      params.dispose();
      bgrMat.dispose();

      if (!success) {
        debugPrint('[CAMERA] JPEG encoding failed');
        return null;
      }

      await File(filepath).writeAsBytes(jpegBytes);
      return filepath;
    } catch (e) {
      debugPrint('[CAMERA] Error saving frame: $e');
      return null;
    }
  }

  /// Capture a frame from the stream as BGR bytes (no file I/O).
  /// Returns null if no frame available or conversion fails.
  Future<BGRFrame?> captureFrameAsBGR() async {
    if (!_isStreaming) {
      debugPrint('[CAMERA] Not streaming');
      return null;
    }

    // Frame is already converted to BGR in the stream callback - safe from GC
    BGRFrame? bgrFrame = _latestBGRFrame;

    if (bgrFrame == null) {
      // Wait for a frame if we don't have one
      _frameCompleter = Completer<BGRFrame>();
      try {
        bgrFrame = await _frameCompleter!.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw Exception('Timeout waiting for camera frame'),
        );
      } catch (e) {
        debugPrint('[CAMERA] Error waiting for frame: $e');
        return null;
      }
    }

    return bgrFrame;
  }
  
  void _updateStatus(String status) {
    _statusMessage = status;
    notifyListeners();
  }
  
  @override
  void dispose() {
    if (_isStreaming && _controller != null) {
      _controller!.stopImageStream();
    }
    _controller?.dispose();
    super.dispose();
  }
}
