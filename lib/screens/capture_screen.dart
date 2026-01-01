import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';
import '../services/camera_service.dart';
import '../services/capture_service.dart';
import '../services/led_detection_service.dart';
import '../services/settings_service.dart';
import '../widgets/camera_preview_with_cone.dart';
import 'led_detection_test_screen.dart';  // For DetectionResultsPainter, ContourOverlayPainter, ConeParameters

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  int _positionNumber = 1;
  ConeParameters? _coneParams;
  bool _lightsInitialized = false;
  MqttService? _mqtt;
  int _sensorOrientation = 0;     // Camera sensor rotation (0, 90, 180, 270)
  bool _showOverlay = true;       // Show cone overlay
  bool _showContours = true;      // Show raw OpenCV contours

  // Current detection results (updated during capture)
  List<DetectedLED> _currentDetections = [];
  List<ContourPolygon> _allContours = [];
  List<ContourPolygon> _passedContours = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Save reference to MQTT service for use in dispose()
    _mqtt = Provider.of<MqttService>(context, listen: false);

    // Sensor orientation is now handled by CameraPreviewWithCone via callback

    // Turn on dim white LEDs to help user align the cone overlay
    if (!_lightsInitialized) {
      _lightsInitialized = true;
      _turnOnCalibrationLights();
    }
  }

  Future<void> _turnOnCalibrationLights() async {
    if (_mqtt?.isConnected ?? false) {
      // Dim white (about 10% brightness) to show tree shape
      await _mqtt!.turnOnAllLEDs(r: 25, g: 25, b: 25);
    }
  }

  Future<void> _turnOffCalibrationLights() async {
    if (_mqtt?.isConnected ?? false) {
      await _mqtt!.turnOffAllLEDs();
    }
  }

  @override
  void dispose() {
    // Turn off calibration lights when leaving the screen
    _turnOffCalibrationLights();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = Provider.of<MqttService>(context);
    final camera = Provider.of<CameraService>(context);
    final capture = Provider.of<CaptureService>(context);
    final settings = Provider.of<SettingsService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture LEDs'),
        actions: [
          IconButton(
            icon: Icon(_showOverlay ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(() => _showOverlay = !_showOverlay);
            },
            tooltip: _showOverlay ? 'Hide overlay' : 'Show overlay',
          ),
          IconButton(
            icon: Icon(_showContours ? Icons.grid_on : Icons.grid_off),
            onPressed: () {
              setState(() => _showContours = !_showContours);
            },
            tooltip: _showContours ? 'Hide contours' : 'Show contours',
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera Preview with Cone Overlay
          Expanded(
            flex: 3,
            child: camera.isInitialized
                ? CameraPreviewWithCone(
                    camera: camera,
                    settings: settings,
                    showConeOverlay: _showOverlay,
                    coneControlsEnabled: _showOverlay && capture.state == CaptureState.idle,
                    showSizeIndicator: _showOverlay,
                    pausePreview: capture.state == CaptureState.capturing,
                    detections: _currentDetections,
                    showContours: _showContours,
                    allContours: _allContours,
                    passedContours: _passedContours,
                    onConeParametersChanged: (params) {
                      _coneParams = params;
                    },
                    onSensorOrientationChanged: (orientation) {
                      setState(() => _sensorOrientation = orientation);
                    },
                  )
                : const Center(
                    child: Text('Camera not available'),
                  ),
          ),

          // Controls
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black87,
              child: Column(
                children: [
                  // Position Selector
                  if (capture.state == CaptureState.idle) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Camera Position:',
                          style: TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: _positionNumber > 1
                              ? () => setState(() => _positionNumber--)
                              : null,
                        ),
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
                            '$_positionNumber',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => setState(() => _positionNumber++),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Progress
                  if (capture.state != CaptureState.idle) ...[
                    LinearProgressIndicator(
                      value: capture.progress,
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'LED ${capture.currentLED}/${capture.totalLEDs}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Status
                  Text(
                    capture.statusMessage,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  // Action Buttons
                  if (capture.state == CaptureState.idle)
                    ElevatedButton.icon(
                      onPressed: () async {
                        // Turn off calibration lights before starting capture
                        await _turnOffCalibrationLights();
                        // Clear previous detections
                        setState(() {
                          _currentDetections = [];
                          _allContours = [];
                          _passedContours = [];
                        });
                        await capture.startCapture(
                          mqtt: mqtt,
                          camera: camera,
                          positionNumber: _positionNumber,
                          coneParams: _coneParams,
                          sensorOrientation: _sensorOrientation,
                          onDetectionResult: (result) {
                            // Update overlay with latest detection results
                            setState(() {
                              _currentDetections = result.detections;
                              _allContours = result.allContours;
                              _passedContours = result.passedContours;
                            });
                          },
                        );
                      },
                      icon: const Icon(Icons.play_arrow, size: 32),
                      label: const Text(
                        'START CAPTURE',
                        style: TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.green,
                      ),
                    )
                  else if (capture.state == CaptureState.capturing)
                    ElevatedButton.icon(
                      onPressed: () {
                        capture.pauseCapture();
                      },
                      icon: const Icon(Icons.pause, size: 32),
                      label: const Text(
                        'PAUSE',
                        style: TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    )
                  else if (capture.state == CaptureState.paused)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            capture.resumeCapture();
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('RESUME'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            capture.stopCapture();
                          },
                          icon: const Icon(Icons.stop),
                          label: const Text('STOP'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ],
                    )
                  else if (capture.state == CaptureState.completed)
                    Column(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Capture Complete!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                capture.reset();
                                setState(() => _positionNumber++);
                                // Turn calibration lights back on for next position
                                await _turnOnCalibrationLights();
                              },
                              icon: const Icon(Icons.add_location),
                              label: const Text('Next Position'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                capture.reset();
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.done),
                              label: const Text('Done'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                  const SizedBox(height: 8),

                  // Stop button during capture
                  if (capture.state == CaptureState.capturing)
                    TextButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Stop Capture?'),
                            content: const Text(
                              'Are you sure you want to stop the capture?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  capture.stopCapture();
                                  Navigator.pop(context);
                                },
                                child: const Text(
                                  'Stop',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.stop, color: Colors.red),
                      label: const Text(
                        'Stop Capture',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
