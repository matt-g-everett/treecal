import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';
import '../services/camera_service.dart';
import '../services/led_detection_service.dart';
import '../services/settings_service.dart';
import '../widgets/streaming_camera_preview.dart';
import 'cone_calibration_overlay.dart';

class LEDDetectionTestScreen extends StatefulWidget {
  const LEDDetectionTestScreen({super.key});

  @override
  State<LEDDetectionTestScreen> createState() => _LEDDetectionTestScreenState();
}

class _LEDDetectionTestScreenState extends State<LEDDetectionTestScreen> {
  ConeParameters? _coneParams;
  List<DetectedLED> _detectedLEDs = [];
  bool _isProcessing = false;
  int _testLEDIndex = -1;  // Initialized from settings in didChangeDependencies
  bool _showOverlay = true;
  Size? _streamSize;

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
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final previewSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Camera preview (always uses stream for accurate calibration)
                            Positioned.fill(
                              child: StreamingCameraPreview(
                                camera: camera,
                                onStreamSizeChanged: (size) {
                                  setState(() => _streamSize = size);
                                },
                              ),
                            ),

                            // Cone calibration overlay
                            if (_showOverlay)
                              ConeCalibrationOverlay(
                                previewSize: previewSize,
                                onParametersChanged: (params) {
                                  setState(() => _coneParams = params);
                                },
                                settings: settings,
                              ),

                            // Detection results overlay
                            if (_detectedLEDs.isNotEmpty)
                              CustomPaint(
                                size: previewSize,
                                painter: DetectionResultsPainter(
                                  detections: _detectedLEDs,
                                ),
                              ),

                            // Stream size indicator
                            if (_showOverlay && _streamSize != null)
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
                                    'Stream: ${_streamSize!.width.toInt()}x${_streamSize!.height.toInt()}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
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
                        ),
                      );
                    },
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
                    ? () => setState(() => _testLEDIndex--)
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
                    ? () => setState(() => _testLEDIndex++)
                    : null,
                color: Colors.white,
              ),
            ],
          ),

          const SizedBox(height: 16),

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
    setState(() {
      _isProcessing = true;
      _detectedLEDs = [];
    });

    // Stream is already running from preview
    try {
      // Turn off all LEDs first
      await mqtt.turnOffAllLEDs();
      await Future.delayed(const Duration(milliseconds: 200));

      // Lock camera for consistent exposure
      await camera.lockForCapture();

      // Turn on test LED
      await mqtt.setLED(_testLEDIndex, true);

      // Wait for camera exposure adjustment (first LED after dark scene)
      await Future.delayed(const Duration(milliseconds: 800));

      // Capture frame from stream (waitForFresh ensures we get frame after LED turned on)
      final bgrFrame = await camera.captureFrameAsBGR(waitForFresh: true);

      // Turn off test LED
      await mqtt.setLED(_testLEDIndex, false);

      await camera.unlockCapture();

      if (bgrFrame == null) {
        throw Exception('Failed to capture frame from camera stream');
      }

      // Scale cone parameters from preview coordinates to camera image coordinates
      final scaledConeParams = _coneParams?.scaledTo(
        bgrFrame.originalWidth.toDouble(),
        bgrFrame.originalHeight.toDouble(),
      );

      // Detect LEDs with OpenCV (sync version - no isolate overhead)
      final detections = LEDDetectionService.detectLEDsFromBGRSync(
        bgrBytes: bgrFrame.bytes,
        width: bgrFrame.width,
        height: bgrFrame.height,
        originalWidth: bgrFrame.originalWidth,
        originalHeight: bgrFrame.originalHeight,
        coneParams: scaledConeParams,
        brightnessThreshold: _brightnessThreshold,
        minArea: 5.0,
        maxArea: 100.0,
        cameraFovDegrees: _cameraFovDegrees,
        minAngularConfidence: _minAngularConfidence,
      );

      setState(() {
        _detectedLEDs = detections;
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

  DetectionResultsPainter({
    required this.detections,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final led in detections) {
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

      // Draw circle around detection
      canvas.drawCircle(
        Offset(led.x, led.y),
        25,
        paint,
      );

      // Draw crosshair
      final crosshairPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(led.x - 15, led.y),
        Offset(led.x + 15, led.y),
        crosshairPaint,
      );
      canvas.drawLine(
        Offset(led.x, led.y - 15),
        Offset(led.x, led.y + 15),
        crosshairPaint,
      );

      // Draw confidence percentage
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${(led.detectionConfidence * 100).toInt()}%',
          style: TextStyle(
            color: color,
            fontSize: 16,
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
        Offset(led.x + 30, led.y - 8),
      );
    }
  }

  @override
  bool shouldRepaint(DetectionResultsPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
