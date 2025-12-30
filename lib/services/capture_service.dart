import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'mqtt_service.dart';
import 'camera_service.dart';
import 'led_detection_service.dart';
import 'triangulation_service_proper.dart';
import 'calibration_service.dart';
import 'reflection_filter_service.dart';
import 'settings_service.dart';
import '../screens/cone_calibration_overlay.dart';

enum CaptureState {
  idle,
  capturing,
  paused,
  processing,
  completed,
  error
}

class CaptureService extends ChangeNotifier {
  CaptureState _state = CaptureState.idle;
  int _currentLED = 0;
  int _currentPosition = 0;
  int _totalCaptured = 0;
  String _statusMessage = '';

  // All captured detections (across all positions)
  final List<Map<String, dynamic>> _allDetections = [];

  // Final LED positions
  List<LED3DPosition>? _finalPositions;

  // Reference to settings (injected via configure)
  SettingsService? _settings;

  /// Configure the service with settings.
  void configure(SettingsService settings) {
    _settings = settings;
  }

  // Configuration (from settings, with fallback defaults)
  int get totalLEDs => _settings?.totalLeds ?? 500;
  int get cameraAdjustmentDelay => _settings?.cameraAdjustmentDelay ?? 1000;

  // Getters
  CaptureState get state => _state;
  int get currentLED => _currentLED;
  int get currentPosition => _currentPosition;
  int get totalCaptured => _totalCaptured;
  String get statusMessage => _statusMessage;
  List<LED3DPosition>? get finalPositions => _finalPositions;
  int get numDetections => _allDetections.length;
  double get progress => totalLEDs > 0 ? _currentLED / totalLEDs : 0;
  
  Future<String> getCaptureDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final captureDir = Directory(path.join(appDir.path, 'led_captures'));
    if (!await captureDir.exists()) {
      await captureDir.create(recursive: true);
    }
    return captureDir.path;
  }
  
  Future<List<String>> getCapturedPositions() async {
    final captureDir = await getCaptureDirectory();
    final dir = Directory(captureDir);

    if (!await dir.exists()) return [];

    final positions = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory && entity.path.contains('camera')) {
        positions.add(path.basename(entity.path));
      }
    }

    positions.sort();
    return positions;
  }

  Future<int> getImageCount(String position) async {
    final captureDir = await getCaptureDirectory();
    final positionDir = Directory(path.join(captureDir, position));

    if (!await positionDir.exists()) return 0;

    int count = 0;
    await for (final entity in positionDir.list()) {
      if (entity is File && entity.path.endsWith('.jpg')) {
        count++;
      }
    }
    return count;
  }
  
  /// Start capture for a camera position with real-time detection
  Future<void> startCapture({
    required MqttService mqtt,
    required CameraService camera,
    required int positionNumber,
    ConeParameters? coneParams,
  }) async {
    if (_state == CaptureState.capturing) return;
    
    _state = CaptureState.capturing;
    _currentPosition = positionNumber;
    _currentLED = 0;
    _totalCaptured = 0;
    _updateStatus('Starting capture at position $positionNumber...');
    
    try {
      final captureDir = await getCaptureDirectory();
      final positionDir = Directory(path.join(captureDir, 'camera$positionNumber'));
      
      if (!await positionDir.exists()) {
        await positionDir.create(recursive: true);
      }

      // Turn off all LEDs first
      _updateStatus('Preparing...');
      await mqtt.turnOffAllLEDs();

      // Lock camera focus/exposure for fast capture
      _updateStatus('Locking camera focus...');
      await camera.lockForCapture();

      // Start image stream for fast frame capture
      _updateStatus('Starting camera stream...');
      await camera.startStreamCapture();

      // === Capture each LED with detection ===
      for (int i = 0; i < totalLEDs; i++) {
        if (_state != CaptureState.capturing) break;

        _currentLED = i;
        _updateStatus('Capturing LED $i/$totalLEDs...');

        // --- TIMING INSTRUMENTATION START ---
        final loopStart = DateTime.now();
        Stopwatch sw = Stopwatch();

        // Turn on this LED
        sw.start();
        await mqtt.setLED(i, true);
        final setLedOnTime = sw.elapsedMilliseconds;
        sw.reset();

        // Wait for camera exposure adjustment on first LED only
        // (switching from all-on bright scene to single LED dim scene)
        int exposureDelayTime = 0;
        if (i == 0) {
          sw.start();
          await Future.delayed(Duration(milliseconds: cameraAdjustmentDelay));
          exposureDelayTime = sw.elapsedMilliseconds;
          sw.reset();
        }

        // Capture frame from stream as BGR (no JPEG encoding/file I/O)
        sw.start();
        final bgrFrame = await camera.captureFrameAsBGR();
        final captureTime = sw.elapsedMilliseconds;
        sw.reset();

        // Detect LED with OpenCV (direct BGR path - no file I/O, no isolate)
        int detectTime = 0;
        try {
          if (bgrFrame == null) {
            debugPrint('Error capturing frame for LED $i');
          } else {
            sw.start();
            // Use sync version to avoid isolate spawn overhead (~200ms savings)
            final detections = LEDDetectionService.detectLEDsFromBGRSync(
              bgrBytes: bgrFrame.bytes,
              width: bgrFrame.width,
              height: bgrFrame.height,
              originalWidth: bgrFrame.originalWidth,
              originalHeight: bgrFrame.originalHeight,
              coneParams: coneParams,
            );
            detectTime = sw.elapsedMilliseconds;
            sw.reset();

            // Store detection
            _allDetections.add({
              'led_index': i,
              'camera_index': positionNumber,
              'detections': detections.map((d) => d.toJson()).toList(),
              'timestamp': DateTime.now().toIso8601String(),
            });

            _totalCaptured++;
          }
        } catch (e) {
          detectTime = sw.elapsedMilliseconds;
          sw.reset();
          debugPrint('Error detecting LED $i: $e');
        }

        // Turn off LED (MQTT ack handles pacing)
        sw.start();
        await mqtt.setLED(i, false);
        final setLedOffTime = sw.elapsedMilliseconds;
        sw.reset();

        sw.start();
        notifyListeners();
        final notifyTime = sw.elapsedMilliseconds;

        final totalTime = DateTime.now().difference(loopStart).inMilliseconds;

        debugPrint('[TIMING] LED $i: '
          'setOn=${setLedOnTime}ms, '
          '${exposureDelayTime > 0 ? "exposureDelay=${exposureDelayTime}ms, " : ""}'
          'capture=${captureTime}ms, '
          'detect=${detectTime}ms, '
          'setOff=${setLedOffTime}ms, '
          'notify=${notifyTime}ms, '
          'TOTAL=${totalTime}ms');
        // --- TIMING INSTRUMENTATION END ---
      }
      
      // Clean up
      await mqtt.turnOffAllLEDs();
      await camera.stopStreamCapture();
      await camera.unlockCapture();
      
      // Save detections for this position
      final detectionsFile = File(path.join(positionDir.path, 'detections.json'));
      final positionDetections = _allDetections
        .where((d) => d['camera_index'] == positionNumber)
        .toList();
        
      await detectionsFile.writeAsString(jsonEncode({
        'camera_position': positionNumber,
        'total_leds': totalLEDs,
        'captured': _totalCaptured,
        'cone_params': coneParams?.toJson(),
        'detections': positionDetections,
      }));
      
      if (_state == CaptureState.capturing) {
        _state = CaptureState.completed;
        _updateStatus('Position $positionNumber complete! '
          '$_totalCaptured LEDs detected. Ready for next position or processing.');
      }
      
    } catch (e) {
      _state = CaptureState.error;
      _updateStatus('Error: $e');
    }
    
    notifyListeners();
  }
  
  void pauseCapture() {
    if (_state == CaptureState.capturing) {
      _state = CaptureState.paused;
      _updateStatus('Paused at LED $_currentLED');
      notifyListeners();
    }
  }
  
  void resumeCapture() {
    if (_state == CaptureState.paused) {
      _state = CaptureState.capturing;
      notifyListeners();
    }
  }
  
  void stopCapture() {
    _state = CaptureState.idle;
    _currentLED = 0;
    _updateStatus('Capture stopped');
    notifyListeners();
  }
  
  void reset() {
    _state = CaptureState.idle;
    _currentLED = 0;
    _currentPosition = 0;
    _totalCaptured = 0;
    _statusMessage = '';
    _allDetections.clear();
    _finalPositions = null;
    notifyListeners();
  }
  
  /// Process all captured detections and generate final LED positions
  Future<void> processAllDetections({
    required CalibrationService calibration,
    required double treeHeight,
  }) async {
    if (_allDetections.isEmpty) {
      _state = CaptureState.error;
      _statusMessage = 'No detections to process. Capture from at least one position first.';
      notifyListeners();
      return;
    }
    
    _state = CaptureState.processing;
    _updateStatus('Processing ${_allDetections.length} detections...');
    notifyListeners();
    
    try {
      // Get camera positions from calibration
      final cameraPositions = calibration.calibrations.values.map((cal) =>
        CameraPosition(
          index: cal.positionNumber,
          x: cal.distanceFromCenter * math.cos(cal.angleFromFront * math.pi / 180),
          y: cal.distanceFromCenter * math.sin(cal.angleFromFront * math.pi / 180),
          z: cal.heightFromGround,
          angle: cal.angleFromFront,
        )
      ).toList();
      
      if (cameraPositions.isEmpty) {
        throw Exception('No camera calibrations found. Please calibrate camera positions.');
      }
      
      // Step 1: Filter reflections
      _updateStatus('Filtering reflections...');
      await Future.delayed(const Duration(milliseconds: 100)); // Let UI update
      
      final filtered = await compute(_filterReflectionsIsolate, {
        'detections': _allDetections,
      });
      
      debugPrint('Filtered: ${_allDetections.length} → ${filtered.length} detections');
      
      // Step 2: Triangulate
      _updateStatus('Triangulating from ${cameraPositions.length} cameras...');
      await Future.delayed(const Duration(milliseconds: 100));
      
      final triangulated = await compute(_triangulateIsolate, {
        'detections': filtered,
        'cameraPositions': cameraPositions.map((c) => c.toJson()).toList(),
        'treeHeight': treeHeight,
      });
      
      debugPrint('Triangulated: ${triangulated.length} LEDs');
      
      // Step 3: Fill gaps
      _updateStatus('Filling gaps with sequential prediction...');
      await Future.delayed(const Duration(milliseconds: 100));
      
      final complete = await compute(_fillGapsIsolate, {
        'knownPositions': triangulated.map((p) => p.toJson()).toList(),
        'totalLeds': totalLEDs,
      });
      
      debugPrint('Complete: ${complete.length} LEDs (${triangulated.length} observed, '
        '${complete.length - triangulated.length} predicted)');
      
      _finalPositions = complete;
      
      // Save to file
      final captureDir = await getCaptureDirectory();
      final outputFile = File(path.join(captureDir, 'led_positions.json'));
      await outputFile.writeAsString(jsonEncode({
        'total_leds': totalLEDs,
        'tree_height': treeHeight,
        'num_cameras': cameraPositions.length,
        'num_observed': triangulated.length,
        'num_predicted': complete.length - triangulated.length,
        'camera_positions': cameraPositions.map((c) => c.toJson()).toList(),
        'positions': complete.map((p) => p.toJson()).toList(),
        'timestamp': DateTime.now().toIso8601String(),
      }));
      
      _state = CaptureState.completed;
      _updateStatus('✓ Processing complete! ${triangulated.length} observed, '
        '${complete.length - triangulated.length} predicted');
      
    } catch (e, stack) {
      debugPrint('Processing error: $e');
      debugPrint(stack.toString());
      _state = CaptureState.error;
      _updateStatus('Processing error: $e');
    }
    
    notifyListeners();
  }
  
  void _updateStatus(String status) {
    _statusMessage = status;
    notifyListeners();
  }
  
  // Isolate functions for heavy computation
  
  static List<Map<String, dynamic>> _filterReflectionsIsolate(Map<String, dynamic> params) {
    final detections = params['detections'] as List;
    return ReflectionFilterService.filterReflections(
      detections.cast<Map<String, dynamic>>(),
    );
  }
  
  static List<LED3DPosition> _triangulateIsolate(Map<String, dynamic> params) {
    final detections = params['detections'] as List;
    final cameraPositionsJson = params['cameraPositions'] as List;
    final treeHeight = params['treeHeight'] as double;
    
    final cameraPositions = cameraPositionsJson
      .map((json) => CameraPosition.fromJson(json as Map<String, dynamic>))
      .toList();
    
    return TriangulationService.triangulate(
      allDetections: detections.cast<Map<String, dynamic>>(),
      cameraPositions: cameraPositions,
      treeHeight: treeHeight,
    );
  }
  
  static List<LED3DPosition> _fillGapsIsolate(Map<String, dynamic> params) {
    final knownJson = params['knownPositions'] as List;
    final totalLeds = params['totalLeds'] as int;
    
    final known = knownJson.map((json) {
      final j = json as Map<String, dynamic>;
      return LED3DPosition(
        ledIndex: j['led_index'] as int,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        z: (j['z'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        angle: (j['angle'] as num).toDouble(),
        radius: (j['radius'] as num).toDouble(),
        confidence: (j['confidence'] as num).toDouble(),
        numObservations: j['num_observations'] as int,
        predicted: j['predicted'] as bool? ?? false,
      );
    }).toList();
    
    return TriangulationService.fillGaps(known, totalLeds);
  }
}
