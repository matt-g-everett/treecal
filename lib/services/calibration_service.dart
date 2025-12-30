import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class CameraCalibration {
  final int positionNumber;
  double distanceFromCenter; // meters
  double angleFromFront; // degrees (0-360)
  double heightFromGround; // meters
  String? notes;
  
  CameraCalibration({
    required this.positionNumber,
    this.distanceFromCenter = 1.5,
    this.angleFromFront = 0.0,
    this.heightFromGround = 1.0,
    this.notes,
  });
  
  Map<String, dynamic> toJson() => {
    'position_number': positionNumber,
    'distance_from_center': distanceFromCenter,
    'angle_from_front': angleFromFront,
    'height_from_ground': heightFromGround,
    'notes': notes,
  };
  
  factory CameraCalibration.fromJson(Map<String, dynamic> json) {
    return CameraCalibration(
      positionNumber: json['position_number'],
      distanceFromCenter: json['distance_from_center'] ?? 1.5,
      angleFromFront: json['angle_from_front'] ?? 0.0,
      heightFromGround: json['height_from_ground'] ?? 1.0,
      notes: json['notes'],
    );
  }
}

class CalibrationService extends ChangeNotifier {
  Map<int, CameraCalibration> _calibrations = {};
  
  Map<int, CameraCalibration> get calibrations => _calibrations;
  
  void setCalibration(int position, CameraCalibration calibration) {
    _calibrations[position] = calibration;
    notifyListeners();
    _saveCalibrations();
  }
  
  CameraCalibration? getCalibration(int position) {
    return _calibrations[position];
  }
  
  Future<void> _saveCalibrations() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(path.join(appDir.path, 'camera_calibrations.json'));
      
      final data = {
        'calibrations': _calibrations.values.map((c) => c.toJson()).toList(),
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving calibrations: $e');
    }
  }
  
  Future<void> loadCalibrations() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(path.join(appDir.path, 'camera_calibrations.json'));
      
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = jsonDecode(contents);
        
        _calibrations = {};
        for (var calJson in data['calibrations']) {
          final cal = CameraCalibration.fromJson(calJson);
          _calibrations[cal.positionNumber] = cal;
        }
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading calibrations: $e');
    }
  }
  
  Future<void> exportCalibrations(String outputPath) async {
    final data = {
      'calibrations': _calibrations.values.map((c) => c.toJson()).toList(),
    };

    final file = File(outputPath);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data));
  }
  
  void clear() {
    _calibrations.clear();
    notifyListeners();
  }
}
