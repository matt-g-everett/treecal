import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import '../services/led_detection_service.dart';
import '../services/settings_service.dart';
import '../screens/cone_calibration_overlay.dart';
import '../screens/led_detection_test_screen.dart';
import 'streaming_camera_preview.dart';

/// A camera preview widget with cone calibration overlay and detection overlays.
/// Combines StreamingCameraPreview, ConeCalibrationOverlay, and detection painters
/// into a single reusable widget that handles coordinate systems and size tracking.
class CameraPreviewWithCone extends StatefulWidget {
  final CameraService camera;
  final SettingsService settings;

  /// Whether to show the cone overlay at all.
  final bool showConeOverlay;

  /// Whether the cone overlay controls (swipe to adjust) are enabled.
  /// Only relevant when [showConeOverlay] is true.
  final bool coneControlsEnabled;

  /// Called when cone parameters change (from user adjustment or initial load).
  final void Function(ConeParameters params)? onConeParametersChanged;

  /// Called when the raw camera size is available.
  /// Reports original camera dimensions before rotation (e.g., 1280x720).
  final void Function(Size rawCameraSize)? onRawCameraSizeChanged;

  /// Called when the stream size changes.
  /// Reports rotated dimensions for display (e.g., 720x1280 for portrait).
  final void Function(Size streamSize)? onStreamSizeChanged;

  /// Called when sensor orientation is determined.
  final void Function(int sensorOrientation)? onSensorOrientationChanged;

  /// When true, pauses frame polling to reduce contention during capture.
  final bool pausePreview;

  /// Whether to show the stream/widget size indicator in the corner.
  final bool showSizeIndicator;

  /// Detection results to display as overlay markers.
  final List<DetectedLED> detections;

  /// Whether to show the contour overlay (for debugging).
  final bool showContours;

  /// All contours found by OpenCV (for debugging).
  final List<ContourPolygon> allContours;

  /// Contours that passed the area filters (for debugging).
  final List<ContourPolygon> passedContours;

  const CameraPreviewWithCone({
    super.key,
    required this.camera,
    required this.settings,
    this.showConeOverlay = true,
    this.coneControlsEnabled = true,
    this.onConeParametersChanged,
    this.onRawCameraSizeChanged,
    this.onStreamSizeChanged,
    this.onSensorOrientationChanged,
    this.pausePreview = false,
    this.showSizeIndicator = false,
    this.detections = const [],
    this.showContours = false,
    this.allContours = const [],
    this.passedContours = const [],
  });

  @override
  State<CameraPreviewWithCone> createState() => _CameraPreviewWithConeState();
}

class _CameraPreviewWithConeState extends State<CameraPreviewWithCone> {
  Size? _streamSize;
  Size? _rawCameraSize;
  int _sensorOrientation = 0;

  @override
  void initState() {
    super.initState();
    _initSensorOrientation();
  }

  void _initSensorOrientation() {
    if (widget.camera.isInitialized && widget.camera.controller != null) {
      final orientation = widget.camera.controller!.description.sensorOrientation;
      if (orientation != _sensorOrientation) {
        _sensorOrientation = orientation;
        // Defer callback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onSensorOrientationChanged?.call(orientation);
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(CameraPreviewWithCone oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check sensor orientation if camera changed
    if (oldWidget.camera != widget.camera) {
      _initSensorOrientation();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.camera.isInitialized || widget.camera.controller == null) {
      return const Center(
        child: Text('Camera not available'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview
              Positioned.fill(
                child: StreamingCameraPreview(
                  camera: widget.camera,
                  pausePreview: widget.pausePreview,
                  onStreamSizeChanged: (size) {
                    setState(() => _streamSize = size);
                    widget.onStreamSizeChanged?.call(size);
                  },
                  onRawCameraSizeChanged: (size) {
                    setState(() => _rawCameraSize = size);
                    widget.onRawCameraSizeChanged?.call(size);
                  },
                ),
              ),

              // Cone calibration overlay
              if (widget.showConeOverlay)
                Positioned.fill(
                  child: ConeCalibrationOverlay(
                    previewSize: widgetSize,
                    onParametersChanged: (params) {
                      widget.onConeParametersChanged?.call(params);
                    },
                    settings: widget.settings,
                    showControls: widget.coneControlsEnabled,
                  ),
                ),

              // Contour overlay (all OpenCV contours for debugging)
              if (widget.showContours && widget.allContours.isNotEmpty && _rawCameraSize != null)
                Positioned.fill(
                  child: CustomPaint(
                    size: widgetSize,
                    painter: ContourOverlayPainter(
                      allContours: widget.allContours,
                      passedContours: widget.passedContours,
                      imageSize: _rawCameraSize!,
                      canvasSize: widgetSize,
                      sensorOrientation: _sensorOrientation,
                    ),
                  ),
                ),

              // Detection results overlay
              if (widget.detections.isNotEmpty && _rawCameraSize != null)
                Positioned.fill(
                  child: CustomPaint(
                    size: widgetSize,
                    painter: DetectionResultsPainter(
                      detections: widget.detections,
                      imageSize: _rawCameraSize!,
                      canvasSize: widgetSize,
                      sensorOrientation: _sensorOrientation,
                    ),
                  ),
                ),

              // Stream size indicator
              if (widget.showSizeIndicator && _streamSize != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Stream: ${_streamSize!.width.toInt()}x${_streamSize!.height.toInt()} '
                      'Widget: ${widgetSize.width.toInt()}x${widgetSize.height.toInt()}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Get the current sensor orientation (for use by parent widgets).
  int get sensorOrientation => _sensorOrientation;

  /// Get the current raw camera size (for use by parent widgets).
  Size? get rawCameraSize => _rawCameraSize;
}
