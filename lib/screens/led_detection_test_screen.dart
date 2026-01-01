import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';
import '../services/camera_service.dart';
import '../services/led_detection_service.dart';
import '../services/settings_service.dart';
import '../widgets/camera_preview_with_cone.dart';
import 'cone_calibration_overlay.dart';

export 'cone_calibration_overlay.dart' show ConeParameters;

class LEDDetectionTestScreen extends StatefulWidget {
  const LEDDetectionTestScreen({super.key});

  @override
  State<LEDDetectionTestScreen> createState() => _LEDDetectionTestScreenState();
}

class _LEDDetectionTestScreenState extends State<LEDDetectionTestScreen> {
  ConeParameters? _coneParams;
  List<DetectedLED> _detectedLEDs = [];
  List<ContourPolygon> _allContours = [];     // All OpenCV contours (for debug)
  List<ContourPolygon> _passedContours = [];  // Contours that passed filters
  bool _isProcessing = false;
  int _testLEDIndex = -1;  // Initialized from settings in didChangeDependencies
  bool _showOverlay = true;
  bool _showContours = true;  // Show raw OpenCV contours
  Size? _streamSize;         // Rotated dimensions for display (e.g., 720x1280)
  bool _keepLedLit = true;  // Keep LED on for easier debugging
  bool _ledIsLit = false;   // Track if LED is currently lit
  int _sensorOrientation = 0;  // Camera sensor rotation (0, 90, 180, 270)

  // Detection parameters
  int _brightnessThreshold = 150;
  double _cameraFovDegrees = 60.0;
  double _minAngularConfidence = 0.2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize to last LED on first build
    if (_testLEDIndex < 0) {
      final settings = Provider.of<SettingsService>(context, listen: false);
      _testLEDIndex = settings.totalLeds - 1;
    }
    // Sensor orientation is now handled by CameraPreviewWithCone via callback
  }

  /// Change the LED index, switching the lit LED if keepLedLit is enabled
  Future<void> _changeLEDIndex(int newIndex, MqttService mqtt) async {
    final oldIndex = _testLEDIndex;
    setState(() => _testLEDIndex = newIndex);

    // If LED is currently lit, switch to the new LED
    if (_ledIsLit && _keepLedLit) {
      await mqtt.setLED(oldIndex, false);
      await mqtt.setLED(newIndex, true);
    }
  }

  @override
  void dispose() {
    // Turn off LED when leaving the screen
    if (_ledIsLit) {
      final mqtt = Provider.of<MqttService>(context, listen: false);
      mqtt.setLED(_testLEDIndex, false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = Provider.of<MqttService>(context);
    final camera = Provider.of<CameraService>(context);
    final settings = Provider.of<SettingsService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LED Detection Test'),
        actions: [
          IconButton(
            icon: Icon(_showOverlay ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(() => _showOverlay = !_showOverlay);
            },
            tooltip: _showOverlay ? 'Hide overlay' : 'Show overlay',
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _showSettingsDialog(context),
            tooltip: 'Detection settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera + Overlays
          Expanded(
            flex: 3,
            child: camera.isInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera preview with cone overlay and detection results
                      CameraPreviewWithCone(
                        camera: camera,
                        settings: settings,
                        showConeOverlay: _showOverlay,
                        coneControlsEnabled: false,
                        showSizeIndicator: _showOverlay,
                        detections: _detectedLEDs,
                        onConeParametersChanged: (params) {
                          setState(() => _coneParams = params);
                        },
                        onStreamSizeChanged: (size) {
                          setState(() => _streamSize = size);
                        },
                        onSensorOrientationChanged: (orientation) {
                          setState(() => _sensorOrientation = orientation);
                        },
                      ),

                      // Processing indicator
                      if (_isProcessing)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Processing...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : const Center(
                    child: Text('Camera not available'),
                  ),
          ),

          // Controls
          Expanded(
            flex: 2,
            child: _buildControls(mqtt, camera, settings),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(MqttService mqtt, CameraService camera, SettingsService settings) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black87,
      child: Column(
        children: [
          // LED selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Test LED:',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              const SizedBox(width: 16),

              // Decrement
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _testLEDIndex > 0
                    ? () => _changeLEDIndex(_testLEDIndex - 1, mqtt)
                    : null,
                color: Colors.white,
              ),

              // LED number
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white54),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_testLEDIndex',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              // Increment
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _testLEDIndex < settings.totalLeds - 1
                    ? () => _changeLEDIndex(_testLEDIndex + 1, mqtt)
                    : null,
                color: Colors.white,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Keep LED lit toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Keep LED lit:',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              Switch(
                value: _keepLedLit,
                onChanged: (value) {
                  setState(() => _keepLedLit = value);
                  // If turning off and LED is currently lit, turn it off
                  if (!value && _ledIsLit) {
                    mqtt.setLED(_testLEDIndex, false);
                    setState(() => _ledIsLit = false);
                  }
                },
                activeTrackColor: Colors.green.shade700,
                activeThumbColor: Colors.green,
              ),
              if (_ledIsLit)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LED ON',
                    style: TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
            ],
          ),

          // Show contours toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Show contours:',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              Switch(
                value: _showContours,
                onChanged: (value) {
                  setState(() => _showContours = value);
                },
                activeTrackColor: Colors.cyan.shade700,
                activeThumbColor: Colors.cyan,
              ),
              if (_allContours.isNotEmpty)
                Text(
                  '${_passedContours.length}/${_allContours.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Test button
          ElevatedButton.icon(
            onPressed: _isProcessing || !mqtt.isConnected || !camera.isInitialized
                ? null
                : () => _testLED(mqtt, camera),
            icon: const Icon(Icons.search, size: 28),
            label: const Text(
              'TEST DETECTION',
              style: TextStyle(fontSize: 18),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
              backgroundColor: Colors.blue,
            ),
          ),

          const SizedBox(height: 8),

          // Connection status
          if (!mqtt.isConnected)
            const Text(
              '⚠️ MQTT not connected',
              style: TextStyle(color: Colors.orange),
            )
          else if (!camera.isInitialized)
            const Text(
              '⚠️ Camera not ready',
              style: TextStyle(color: Colors.orange),
            ),

          const SizedBox(height: 16),

          // Results
          if (_detectedLEDs.isNotEmpty)
            Expanded(
              child: _buildResults(),
            )
          else
            const Expanded(
              child: Center(
                child: Text(
                  'Select an LED and press TEST DETECTION',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    // Sort by detection confidence (best first)
    final sortedDetections = List<DetectedLED>.from(_detectedLEDs)
      ..sort((a, b) => b.detectionConfidence.compareTo(a.detectionConfidence));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Found ${_detectedLEDs.length} detection(s):',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: sortedDetections.length,
            itemBuilder: (context, i) {
              final led = sortedDetections[i];
              final isGoodDetection = led.detectionConfidence > 0.7;

              return Card(
                color: isGoodDetection
                    ? Colors.green.shade900
                    : led.detectionConfidence > 0.4
                        ? Colors.orange.shade900
                        : Colors.red.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isGoodDetection
                                ? Icons.check_circle
                                : Icons.warning,
                            color: isGoodDetection
                                ? Colors.green
                                : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Position: (${led.x.toInt()}, ${led.y.toInt()})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildResultRow('Brightness', '${led.brightness.toInt()}'),
                      _buildResultRow('Area', '${led.area.toInt()} px²'),
                      _buildResultRow(
                        'Detection confidence',
                        '${(led.detectionConfidence * 100).toInt()}%',
                      ),
                      _buildResultRow(
                        'Angular confidence',
                        '${(led.angularConfidence * 100).toInt()}%',
                      ),
                      if (_coneParams != null) ...[
                        _buildResultRow(
                          'Normalized height',
                          '${(led.normalizedHeight * 100).toInt()}%',
                        ),
                        if (!led.inConeBounds)
                          const Text(
                            '⚠️ Outside cone bounds',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testLED(MqttService mqtt, CameraService camera) async {
    final settings = Provider.of<SettingsService>(context, listen: false);

    setState(() {
      _isProcessing = true;
      _detectedLEDs = [];
    });

    // Stream is already running from preview
    try {
      // Turn off all LEDs first (unless LED is already lit from previous test)
      if (!_ledIsLit) {
        await mqtt.turnOffAllLEDs();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Lock camera for consistent exposure
      await camera.lockForCapture();

      // Turn on test LED (if not already lit)
      if (!_ledIsLit) {
        await mqtt.setLED(_testLEDIndex, true);
        setState(() => _ledIsLit = true);

        // Wait for camera exposure adjustment (first LED after dark scene)
        await Future.delayed(const Duration(milliseconds: 800));
      } else {
        // Brief delay to ensure stable frame
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Capture frame from stream with retry logic
      // waitForFresh ensures we get a frame after the LED turned on
      BGRFrame? bgrFrame;
      for (int attempt = 0; attempt < 3; attempt++) {
        bgrFrame = await camera.captureFrameAsBGR(waitForFresh: attempt == 0);
        if (bgrFrame != null) break;
        debugPrint('[LED_TEST] Frame capture attempt ${attempt + 1} failed, retrying...');
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Turn off test LED only if not keeping it lit
      if (!_keepLedLit) {
        await mqtt.setLED(_testLEDIndex, false);
        setState(() => _ledIsLit = false);
      }

      await camera.unlockCapture();

      if (bgrFrame == null) {
        throw Exception('Failed to capture frame after 3 attempts');
      }

      // Pass cone parameters in original preview coordinates
      // The detection service handles coordinate transformation internally
      final scaledConeParams = _coneParams;

      // Detect LEDs with OpenCV (sync version with contours for debug)
      // Note: maxArea needs to be large enough to catch bloomed LEDs
      // A bright LED can bloom to 1000-2000+ pixels in area
      final result = LEDDetectionService.detectLEDsFromBGRSyncWithContours(
        bgrBytes: bgrFrame.bytes,
        width: bgrFrame.width,
        height: bgrFrame.height,
        originalWidth: bgrFrame.originalWidth,
        originalHeight: bgrFrame.originalHeight,
        coneParams: scaledConeParams,
        brightnessThreshold: _brightnessThreshold,
        minArea: 5.0,
        maxArea: 5000.0,  // Increased to catch bloomed LEDs
        cameraFovDegrees: _cameraFovDegrees,
        minAngularConfidence: _minAngularConfidence,
        expectedLedIndex: _testLEDIndex,
        totalLeds: settings.totalLeds,
        sensorOrientation: _sensorOrientation,
      );

      final detections = result.detections;

      // Log detection details for debugging
      debugPrint('=== LED $_testLEDIndex Detection Results ===');
      debugPrint('Stream size: ${_streamSize?.width.toInt()}x${_streamSize?.height.toInt()}');
      debugPrint('BGR frame: ${bgrFrame.width}x${bgrFrame.height} (original: ${bgrFrame.originalWidth}x${bgrFrame.originalHeight})');
      debugPrint('Sensor orientation: $_sensorOrientation degrees');
      if (scaledConeParams != null) {
        debugPrint('Cone (preview): apexY=${scaledConeParams.apexY.toInt()}, baseY=${scaledConeParams.baseY.toInt()}, baseWidth=${scaledConeParams.baseWidth.toInt()}, source=${scaledConeParams.sourceWidth.toInt()}x${scaledConeParams.sourceHeight.toInt()}');
      }
      debugPrint('Contours: ${result.allContours.length} total, ${result.passedContours.length} passed');
      debugPrint('Detections: ${detections.length}');
      for (int i = 0; i < detections.length; i++) {
        final d = detections[i];
        debugPrint('  [$i] pos=(${d.x.toInt()}, ${d.y.toInt()}) '
            'peak=${d.brightness.toInt()} wAvg=${d.weightedAvg.toInt()} uAvg=${d.unweightedAvg.toInt()} '
            'conc=${d.concentration.toStringAsFixed(2)} area=${d.area.toInt()} '
            'conf=${(d.detectionConfidence * 100).toInt()}% angular=${(d.angularConfidence * 100).toInt()}% '
            'normH=${(d.normalizedHeight * 100).toInt()}% inCone=${d.inConeBounds}');
      }
      debugPrint('=== End Detection Results ===');

      setState(() {
        _detectedLEDs = detections;
        _allContours = result.allContours;
        _passedContours = result.passedContours;
        _isProcessing = false;
      });

      // Show summary
      if (!mounted) return;

      final goodDetections = detections.where((d) => d.detectionConfidence > 0.7).length;
      final message = detections.isEmpty
          ? 'No LEDs detected'
          : '$goodDetections high-confidence detection(s) out of ${detections.length} total';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: detections.isEmpty || goodDetections == 0
              ? Colors.orange
              : Colors.green,
        ),
      );

    } catch (e) {
      // Clean up on error
      try {
        await camera.unlockCapture();
      } catch (_) {}

      setState(() => _isProcessing = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detection Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Camera Field of View',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _cameraFovDegrees,
                      min: 45.0,
                      max: 90.0,
                      divisions: 45,
                      label: '${_cameraFovDegrees.toInt()}°',
                      onChanged: (value) {
                        setState(() => _cameraFovDegrees = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${_cameraFovDegrees.toInt()}°',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              const Text(
                'Typical phone: 60-70°',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),

              const SizedBox(height: 16),
              const Text(
                'Minimum Angular Confidence',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _minAngularConfidence,
                      min: 0.1,
                      max: 0.5,
                      divisions: 40,
                      label: '${(_minAngularConfidence * 100).toInt()}%',
                      onChanged: (value) {
                        setState(() => _minAngularConfidence = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${(_minAngularConfidence * 100).toInt()}%',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              const Text(
                'Floor for edge detections',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),

              const SizedBox(height: 16),
              const Text(
                'Brightness Threshold',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _brightnessThreshold.toDouble(),
                      min: 100.0,
                      max: 200.0,
                      divisions: 100,
                      label: _brightnessThreshold.toString(),
                      onChanged: (value) {
                        setState(() => _brightnessThreshold = value.toInt());
                      },
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '$_brightnessThreshold',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              const Text(
                'Min brightness to detect (0-255)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _cameraFovDegrees = 60.0;
                        _minAngularConfidence = 0.2;
                        _brightnessThreshold = 150;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Reset to Defaults'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for detection results overlay
class DetectionResultsPainter extends CustomPainter {
  final List<DetectedLED> detections;
  final Size imageSize;   // Camera image coordinates (e.g., 1280x720)
  final Size canvasSize;  // Preview widget coordinates (phone screen)
  final int sensorOrientation;  // Camera sensor rotation (0, 90, 180, 270)

  DetectionResultsPainter({
    required this.detections,
    required this.imageSize,
    required this.canvasSize,
    this.sensorOrientation = 0,
  });

  /// Transform from camera image coordinates to canvas coordinates.
  /// Must match the scaling and rotation logic in StreamingCameraPreview's _ImagePainter.
  Offset _transformPoint(double imageX, double imageY) {
    // First apply sensor rotation to the image coordinates
    // The sensor captures in one orientation but we display rotated
    double rotatedX = imageX;
    double rotatedY = imageY;
    double effectiveWidth = imageSize.width;
    double effectiveHeight = imageSize.height;

    // Rotate the point based on sensor orientation
    // Camera sensor captures landscape, but phone may be portrait
    switch (sensorOrientation) {
      case 90:
        // 90° clockwise: (x, y) -> (height - y, x)
        rotatedX = imageSize.height - imageY;
        rotatedY = imageX;
        effectiveWidth = imageSize.height;
        effectiveHeight = imageSize.width;
        break;
      case 180:
        // 180°: (x, y) -> (width - x, height - y)
        rotatedX = imageSize.width - imageX;
        rotatedY = imageSize.height - imageY;
        break;
      case 270:
        // 270° clockwise (90° counter-clockwise): (x, y) -> (y, width - x)
        rotatedX = imageY;
        rotatedY = imageSize.width - imageX;
        effectiveWidth = imageSize.height;
        effectiveHeight = imageSize.width;
        break;
      default:
        // 0°: no rotation
        break;
    }

    // Now apply cover/fill scaling (matching _ImagePainter)
    final imageAspect = effectiveWidth / effectiveHeight;
    final canvasAspect = canvasSize.width / canvasSize.height;

    double drawWidth, drawHeight;
    if (imageAspect > canvasAspect) {
      // Image is wider - fit height, crop width
      drawHeight = canvasSize.height;
      drawWidth = canvasSize.height * imageAspect;
    } else {
      // Image is taller - fit width, crop height
      drawWidth = canvasSize.width;
      drawHeight = canvasSize.width / imageAspect;
    }

    // Scale factor from rotated image to drawn size
    final scaleX = drawWidth / effectiveWidth;
    final scaleY = drawHeight / effectiveHeight;

    // Transform point and offset to center
    final offsetX = (canvasSize.width - drawWidth) / 2;
    final offsetY = (canvasSize.height - drawHeight) / 2;

    return Offset(
      rotatedX * scaleX + offsetX,
      rotatedY * scaleY + offsetY,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final led in detections) {
      // Transform detection coordinates from image space to canvas space
      final canvasPoint = _transformPoint(led.x, led.y);

      // Choose color based on detection confidence
      final color = led.detectionConfidence > 0.7
          ? Colors.green
          : led.detectionConfidence > 0.4
              ? Colors.orange
              : Colors.red;

      final paint = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      // Draw circle around detection (scale radius too)
      final scale = size.width / imageSize.width;
      final radius = 25 * scale;
      canvas.drawCircle(canvasPoint, radius, paint);

      // Draw crosshair
      final crosshairPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final crosshairSize = 15 * scale;
      canvas.drawLine(
        Offset(canvasPoint.dx - crosshairSize, canvasPoint.dy),
        Offset(canvasPoint.dx + crosshairSize, canvasPoint.dy),
        crosshairPaint,
      );
      canvas.drawLine(
        Offset(canvasPoint.dx, canvasPoint.dy - crosshairSize),
        Offset(canvasPoint.dx, canvasPoint.dy + crosshairSize),
        crosshairPaint,
      );

      // Draw confidence percentage
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${(led.detectionConfidence * 100).toInt()}%',
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 3),
              Shadow(color: Colors.black, blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(canvasPoint.dx + radius + 5, canvasPoint.dy - 8),
      );

      // Also draw the raw image coordinates for debugging
      final coordPainter = TextPainter(
        text: TextSpan(
          text: '(${led.x.toInt()}, ${led.y.toInt()})',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontFamily: 'monospace',
            shadows: [
              Shadow(color: Colors.black, blurRadius: 2),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      coordPainter.layout();
      coordPainter.paint(
        canvas,
        Offset(canvasPoint.dx + radius + 5, canvasPoint.dy + 8),
      );
    }
  }

  @override
  bool shouldRepaint(DetectionResultsPainter oldDelegate) {
    return oldDelegate.detections != detections ||
           oldDelegate.imageSize != imageSize ||
           oldDelegate.canvasSize != canvasSize ||
           oldDelegate.sensorOrientation != sensorOrientation;
  }
}

/// Custom painter for OpenCV contour overlay (debug visualization)
class ContourOverlayPainter extends CustomPainter {
  final List<ContourPolygon> allContours;     // All contours found
  final List<ContourPolygon> passedContours;  // Contours that passed filters
  final Size imageSize;   // Camera image coordinates
  final Size canvasSize;  // Preview widget coordinates
  final int sensorOrientation;

  ContourOverlayPainter({
    required this.allContours,
    required this.passedContours,
    required this.imageSize,
    required this.canvasSize,
    this.sensorOrientation = 0,
  });

  /// Transform from camera image coordinates to canvas coordinates.
  Offset _transformPoint(double imageX, double imageY) {
    double rotatedX = imageX;
    double rotatedY = imageY;
    double effectiveWidth = imageSize.width;
    double effectiveHeight = imageSize.height;

    switch (sensorOrientation) {
      case 90:
        rotatedX = imageSize.height - imageY;
        rotatedY = imageX;
        effectiveWidth = imageSize.height;
        effectiveHeight = imageSize.width;
        break;
      case 180:
        rotatedX = imageSize.width - imageX;
        rotatedY = imageSize.height - imageY;
        break;
      case 270:
        rotatedX = imageY;
        rotatedY = imageSize.width - imageX;
        effectiveWidth = imageSize.height;
        effectiveHeight = imageSize.width;
        break;
      default:
        break;
    }

    final imageAspect = effectiveWidth / effectiveHeight;
    final canvasAspect = canvasSize.width / canvasSize.height;

    double drawWidth, drawHeight;
    if (imageAspect > canvasAspect) {
      drawHeight = canvasSize.height;
      drawWidth = canvasSize.height * imageAspect;
    } else {
      drawWidth = canvasSize.width;
      drawHeight = canvasSize.width / imageAspect;
    }

    final scaleX = drawWidth / effectiveWidth;
    final scaleY = drawHeight / effectiveHeight;
    final offsetX = (canvasSize.width - drawWidth) / 2;
    final offsetY = (canvasSize.height - drawHeight) / 2;

    return Offset(
      rotatedX * scaleX + offsetX,
      rotatedY * scaleY + offsetY,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Create a set of passed contour centroids for quick lookup
    final passedCentroids = <String>{};
    for (final c in passedContours) {
      passedCentroids.add('${c.cx.toInt()},${c.cy.toInt()}');
    }

    // Draw all contours
    for (final contour in allContours) {
      final isPassed = passedCentroids.contains('${contour.cx.toInt()},${contour.cy.toInt()}');

      // Color: cyan for passed, pink for filtered out
      final color = isPassed ? Colors.cyan : Colors.pinkAccent;

      // Draw contour polygon outline
      if (contour.points.length >= 2) {
        final path = Path();
        final firstPoint = _transformPoint(contour.points[0].x, contour.points[0].y);
        path.moveTo(firstPoint.dx, firstPoint.dy);

        for (int i = 1; i < contour.points.length; i++) {
          final pt = _transformPoint(contour.points[i].x, contour.points[i].y);
          path.lineTo(pt.dx, pt.dy);
        }
        path.close();

        final paint = Paint()
          ..color = color.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPassed ? 2.0 : 1.0;

        canvas.drawPath(path, paint);
      }

      // Draw centroid marker
      final centroid = _transformPoint(contour.cx, contour.cy);
      final markerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(centroid, isPassed ? 4.0 : 2.0, markerPaint);

      // Draw area label for larger contours
      if (contour.area > 50) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${contour.area.toInt()}',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontFamily: 'monospace',
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 2),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(centroid.dx + 5, centroid.dy - 4));
      }
    }

    // Draw legend
    final legendPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 8, 100, 36),
        const Radius.circular(4),
      ),
      legendPaint,
    );

    final cyanDot = Paint()..color = Colors.cyan;
    final pinkDot = Paint()..color = Colors.pinkAccent;

    canvas.drawCircle(const Offset(18, 18), 4, cyanDot);
    canvas.drawCircle(const Offset(18, 34), 4, pinkDot);

    final passedText = TextPainter(
      text: TextSpan(
        text: 'Passed (${passedContours.length})',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    passedText.layout();
    passedText.paint(canvas, const Offset(28, 12));

    final filteredText = TextPainter(
      text: TextSpan(
        text: 'Filtered (${allContours.length - passedContours.length})',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    filteredText.layout();
    filteredText.paint(canvas, const Offset(28, 28));
  }

  @override
  bool shouldRepaint(ContourOverlayPainter oldDelegate) {
    return oldDelegate.allContours != allContours ||
           oldDelegate.passedContours != passedContours ||
           oldDelegate.imageSize != imageSize ||
           oldDelegate.canvasSize != canvasSize ||
           oldDelegate.sensorOrientation != sensorOrientation;
  }
}
