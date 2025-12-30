import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_compass/flutter_compass.dart';

/// Service for reading phone compass/magnetometer
/// Used for automatic camera angle detection during calibration
class CompassService {
  static StreamSubscription<CompassEvent>? _subscription;
  static double _currentHeading = 0.0;
  static bool _isListening = false;
  
  /// Start listening to compass updates
  static Future<void> startListening() async {
    if (_isListening) return;
    
    _subscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        _currentHeading = event.heading!;
      }
    });
    
    _isListening = true;
  }
  
  /// Stop listening to compass
  static Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }
  
  /// Get current compass heading (0-360°)
  /// 0° = North, 90° = East, 180° = South, 270° = West
  static double getCurrentHeading() {
    return _currentHeading;
  }
  
  /// Get average heading over a period for stability
  /// Uses circular mean to handle angle wraparound correctly
  static Future<double> getAverageHeading({
    Duration duration = const Duration(seconds: 2),
    int samples = 20,
  }) async {
    final headings = <double>[];
    final interval = duration.inMilliseconds ~/ samples;
    
    // Collect samples
    for (int i = 0; i < samples; i++) {
      headings.add(_currentHeading);
      await Future.delayed(Duration(milliseconds: interval));
    }
    
    // Use circular mean to properly average angles
    // This handles wraparound (e.g., average of 10° and 350° = 0°, not 180°)
    double sumSin = 0;
    double sumCos = 0;
    
    for (final heading in headings) {
      final rad = heading * math.pi / 180;
      sumSin += math.sin(rad);
      sumCos += math.cos(rad);
    }
    
    final avgRad = math.atan2(sumSin / samples, sumCos / samples);
    final avgHeading = (avgRad * 180 / math.pi + 360) % 360;
    
    return avgHeading;
  }
  
  /// Calculate relative angle from bearing1 to bearing2
  /// Returns angle in range [0, 360)
  /// 
  /// Example:
  ///   relativeBearing(10, 50) = 40°  (50° is 40° clockwise from 10°)
  ///   relativeBearing(350, 10) = 20° (10° is 20° clockwise from 350°)
  static double relativeBearing(double bearing1, double bearing2) {
    double diff = (bearing2 - bearing1) % 360;
    if (diff < 0) diff += 360;
    return diff;
  }
  
  /// Check if compass is available on this device
  static Future<bool> isAvailable() async {
    try {
      final events = FlutterCompass.events;
      return events != null;
    } catch (e) {
      return false;
    }
  }
  
  /// Get standard deviation of recent heading readings
  /// Higher values indicate noisy/unstable readings
  static Future<double> getHeadingStability({
    Duration duration = const Duration(seconds: 2),
    int samples = 20,
  }) async {
    final headings = <double>[];
    final interval = duration.inMilliseconds ~/ samples;
    
    // Collect samples
    for (int i = 0; i < samples; i++) {
      headings.add(_currentHeading);
      await Future.delayed(Duration(milliseconds: interval));
    }
    
    // Calculate circular standard deviation
    final avgHeading = await getAverageHeading(
      duration: duration,
      samples: samples,
    );
    
    double sumSquaredDiff = 0;
    for (final heading in headings) {
      double diff = (heading - avgHeading).abs();
      if (diff > 180) diff = 360 - diff;  // Handle wraparound
      sumSquaredDiff += diff * diff;
    }
    
    return math.sqrt(sumSquaredDiff / samples);
  }
}
