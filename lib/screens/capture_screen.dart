import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';
import '../services/camera_service.dart';
import '../services/capture_service.dart';
import '../services/settings_service.dart';
import '../widgets/streaming_camera_preview.dart';
import 'cone_calibration_overlay.dart';

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
  Size? _streamSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Save reference to MQTT service for use in dispose()
    _mqtt = Provider.of<MqttService>(context, listen: false);

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
      ),
      body: Column(
        children: [
          // Camera Preview with Cone Overlay
          Expanded(
            flex: 3,
            child: camera.isInitialized
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final previewSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          StreamingCameraPreview(
                            camera: camera,
                            onStreamSizeChanged: (size) {
                              setState(() => _streamSize = size);
                            },
                            // Pause preview polling during capture to avoid contention
                            pausePreview: capture.state == CaptureState.capturing,
                          ),
                          // Show overlay with controls when idle, just outline during capture
                          if (capture.state == CaptureState.idle)
                            ConeCalibrationOverlay(
                              previewSize: previewSize,
                              onParametersChanged: (params) {
                                _coneParams = params;
                              },
                              settings: settings,
                              showControls: true,
                            )
                          else if (capture.state == CaptureState.capturing ||
                                   capture.state == CaptureState.paused)
                            ConeCalibrationOverlay(
                              previewSize: previewSize,
                              onParametersChanged: (params) {},
                              settings: settings,
                              showControls: false,
                            ),
                          // Stream size indicator during calibration
                          if (capture.state == CaptureState.idle && _streamSize != null)
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
                        ],
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
                        await capture.startCapture(
                          mqtt: mqtt,
                          camera: camera,
                          positionNumber: _positionNumber,
                          coneParams: _coneParams,
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
