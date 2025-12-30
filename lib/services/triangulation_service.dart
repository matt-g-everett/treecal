import 'dart:math' as math;

/// Camera position and orientation
class CameraPosition {
  final int index;
  final double x;      // meters from tree center
  final double y;      // meters from tree center
  final double z;      // height from ground
  final double angle;  // degrees around tree (0-360)
  
  CameraPosition({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.angle,
  });
  
  Map<String, dynamic> toJson() => {
    'index': index,
    'x': x,
    'y': y,
    'z': z,
    'angle': angle,
  };
  
  factory CameraPosition.fromJson(Map<String, dynamic> json) => CameraPosition(
    index: json['index'] as int,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
    angle: (json['angle'] as num).toDouble(),
  );
}

/// LED observation from a single camera
class LEDObservation {
  final int ledIndex;
  final int cameraIndex;
  final double pixelX;
  final double pixelY;
  final double detectionConfidence;
  final double angularConfidence;
  
  LEDObservation({
    required this.ledIndex,
    required this.cameraIndex,
    required this.pixelX,
    required this.pixelY,
    required this.detectionConfidence,
    required this.angularConfidence,
  });
  
  double get weight => detectionConfidence * angularConfidence;
}

/// Final LED position in 3D space
class LED3DPosition {
  final int ledIndex;
  final double x;
  final double y;
  final double z;
  final double height;        // Normalized [0, 1]
  final double angle;         // Degrees [0, 360)
  final double radius;        // meters from center axis
  final double confidence;
  final int numObservations;
  final bool predicted;       // True if interpolated/extrapolated
  
  LED3DPosition({
    required this.ledIndex,
    required this.x,
    required this.y,
    required this.z,
    required this.height,
    required this.angle,
    required this.radius,
    required this.confidence,
    required this.numObservations,
    this.predicted = false,
  });
  
  Map<String, dynamic> toJson() => {
    'led_index': ledIndex,
    'x': x,
    'y': y,
    'z': z,
    'height': height,
    'angle': angle,
    'radius': radius,
    'confidence': confidence,
    'num_observations': numObservations,
    'predicted': predicted,
  };
}

/// Triangulation service - converts pixel observations to 3D positions
class TriangulationService {
  
  /// Triangulate LED positions from multiple camera observations
  static List<LED3DPosition> triangulate({
    required List<Map<String, dynamic>> allDetections,  // From all cameras
    required List<CameraPosition> cameraPositions,
    required double treeHeight,
    double minConfidence = 0.5,
  }) {
    
    // Group detections by LED index
    Map<int, List<LEDObservation>> observationsByLed = {};
    
    for (final detection in allDetections) {
      final ledIndex = detection['led_index'] as int;
      final cameraIndex = detection['camera_index'] as int;
      final detectionsList = detection['detections'] as List;
      
      if (detectionsList.isEmpty) continue;
      
      // Use best detection for this LED from this camera
      final bestDetection = detectionsList
        .map((d) => d as Map<String, dynamic>)
        .reduce((a, b) =>
          (a['detection_confidence'] as double) > (b['detection_confidence'] as double)
            ? a : b);
      
      final obs = LEDObservation(
        ledIndex: ledIndex,
        cameraIndex: cameraIndex,
        pixelX: (bestDetection['x'] as num).toDouble(),
        pixelY: (bestDetection['y'] as num).toDouble(),
        detectionConfidence: (bestDetection['detection_confidence'] as num).toDouble(),
        angularConfidence: (bestDetection['angular_confidence'] as num).toDouble(),
      );
      
      // Only use high-confidence observations
      if (obs.detectionConfidence >= minConfidence) {
        observationsByLed.putIfAbsent(ledIndex, () => []).add(obs);
      }
    }
    
    // Triangulate each LED
    List<LED3DPosition> positions = [];
    
    for (int ledIndex = 0; ledIndex < 200; ledIndex++) {
      final observations = observationsByLed[ledIndex];
      
      if (observations == null || observations.isEmpty) {
        // No observations - will predict later
        continue;
      }
      
      if (observations.length == 1) {
        // Single observation - can't triangulate, use basic estimate
        final obs = observations[0];
        final cam = cameraPositions.firstWhere((c) => c.index == obs.cameraIndex);
        
        final estimated = _estimateFromSingleCamera(obs, cam, treeHeight);
        positions.add(estimated);
        
      } else {
        // Multiple observations - proper triangulation
        final triangulated = _triangulateMultiCamera(
          observations,
          cameraPositions,
          treeHeight,
        );
        positions.add(triangulated);
      }
    }
    
    return positions;
  }
  
  /// Estimate position from single camera (less accurate)
  static LED3DPosition _estimateFromSingleCamera(
    LEDObservation obs,
    CameraPosition cam,
    double treeHeight,
  ) {
    // Very rough estimate - assume LED is on cone surface
    // Use camera angle as LED angle (not accurate but better than nothing)
    
    final angle = cam.angle;
    final height = treeHeight * 0.5; // Guess middle height
    final radius = 0.4; // Guess typical radius
    
    final x = radius * math.cos(angle * math.pi / 180);
    final y = radius * math.sin(angle * math.pi / 180);
    final z = height;
    
    return LED3DPosition(
      ledIndex: obs.ledIndex,
      x: x,
      y: y,
      z: z,
      height: height / treeHeight,
      angle: angle,
      radius: radius,
      confidence: obs.weight * 0.3, // Low confidence for single camera
      numObservations: 1,
    );
  }
  
  /// Triangulate from multiple cameras (weighted)
  static LED3DPosition _triangulateMultiCamera(
    List<LEDObservation> observations,
    List<CameraPosition> cameraPositions,
    double treeHeight,
  ) {
    // Simplified triangulation - weighted average of ray intersections
    // For production, use proper least-squares triangulation
    
    double sumX = 0, sumY = 0, sumZ = 0;
    double sumWeight = 0;
    
    for (final obs in observations) {
      final cam = cameraPositions.firstWhere((c) => c.index == obs.cameraIndex);
      
      // Simplified: assume pixel position maps to angle/height
      // In reality, need proper camera projection model
      
      final weight = obs.weight;
      
      // Rough estimate of LED position from this camera's view
      // This is simplified - real implementation needs camera matrices
      final estimatedAngle = cam.angle + (obs.pixelX - 960) * 0.05; // Rough pixel to angle
      final estimatedHeight = treeHeight * (1 - obs.pixelY / 1080); // Rough pixel to height
      final estimatedRadius = 0.4; // Assume cone radius
      
      final x = estimatedRadius * math.cos(estimatedAngle * math.pi / 180);
      final y = estimatedRadius * math.sin(estimatedAngle * math.pi / 180);
      final z = estimatedHeight;
      
      sumX += x * weight;
      sumY += y * weight;
      sumZ += z * weight;
      sumWeight += weight;
    }
    
    final x = sumX / sumWeight;
    final y = sumY / sumWeight;
    final z = sumZ / sumWeight;
    
    // Convert to cylindrical coordinates
    final radius = math.sqrt(x * x + y * y);
    final angle = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    final height = z / treeHeight;
    
    // Average confidence weighted by number of observations
    final avgConfidence = sumWeight / observations.length;
    
    return LED3DPosition(
      ledIndex: observations.first.ledIndex,
      x: x,
      y: y,
      z: z,
      height: height,
      angle: angle,
      radius: radius,
      confidence: avgConfidence,
      numObservations: observations.length,
    );
  }
  
  /// Fill gaps using sequential prediction
  static List<LED3DPosition> fillGaps(
    List<LED3DPosition> knownPositions,
    int totalLeds,
  ) {
    final result = List<LED3DPosition?>.filled(totalLeds, null);
    
    // Place known positions
    for (final pos in knownPositions) {
      result[pos.ledIndex] = pos;
    }
    
    // Fill gaps by interpolation/extrapolation
    for (int i = 0; i < totalLeds; i++) {
      if (result[i] != null) continue;
      
      // Find nearest known LEDs before and after
      int? before, after;
      
      for (int j = i - 1; j >= 0; j--) {
        if (result[j] != null) {
          before = j;
          break;
        }
      }
      
      for (int j = i + 1; j < totalLeds; j++) {
        if (result[j] != null) {
          after = j;
          break;
        }
      }
      
      if (before != null && after != null) {
        // Interpolate
        result[i] = _interpolate(result[before]!, result[after]!, i);
      } else if (before != null) {
        // Extrapolate forward
        final step = before > 0 && result[before - 1] != null
          ? _calculateStep(result[before - 1]!, result[before]!)
          : _defaultStep();
        result[i] = _extrapolate(result[before]!, step, i - before);
      } else if (after != null) {
        // Extrapolate backward
        final step = after < totalLeds - 1 && result[after + 1] != null
          ? _calculateStep(result[after]!, result[after + 1]!)
          : _defaultStep();
        result[i] = _extrapolate(result[after]!, step, i - after);
      }
    }
    
    return result.whereType<LED3DPosition>().toList();
  }
  
  static LED3DPosition _interpolate(LED3DPosition before, LED3DPosition after, int index) {
    final t = (index - before.ledIndex) / (after.ledIndex - before.ledIndex);
    
    return LED3DPosition(
      ledIndex: index,
      x: before.x + (after.x - before.x) * t,
      y: before.y + (after.y - before.y) * t,
      z: before.z + (after.z - before.z) * t,
      height: before.height + (after.height - before.height) * t,
      angle: before.angle + (after.angle - before.angle) * t,
      radius: before.radius + (after.radius - before.radius) * t,
      confidence: (before.confidence + after.confidence) / 2 * (1 - (t - 0.5).abs() * 2),
      numObservations: 0,
      predicted: true,
    );
  }
  
  static Map<String, double> _calculateStep(LED3DPosition from, LED3DPosition to) {
    final steps = (to.ledIndex - from.ledIndex).abs();
    return {
      'x': (to.x - from.x) / steps,
      'y': (to.y - from.y) / steps,
      'z': (to.z - from.z) / steps,
      'height': (to.height - from.height) / steps,
      'angle': (to.angle - from.angle) / steps,
      'radius': (to.radius - from.radius) / steps,
    };
  }
  
  static Map<String, double> _defaultStep() {
    return {'x': 0.01, 'y': 0.01, 'z': 0.01, 'height': 0.005, 'angle': 1.8, 'radius': 0.001};
  }
  
  static LED3DPosition _extrapolate(
    LED3DPosition from,
    Map<String, double> step,
    int distance,
  ) {
    return LED3DPosition(
      ledIndex: from.ledIndex + distance,
      x: from.x + step['x']! * distance,
      y: from.y + step['y']! * distance,
      z: from.z + step['z']! * distance,
      height: (from.height + step['height']! * distance).clamp(0.0, 1.0),
      angle: (from.angle + step['angle']! * distance) % 360,
      radius: math.max(0, from.radius + step['radius']! * distance),
      confidence: math.max(0.2, from.confidence - distance * 0.05),
      numObservations: 0,
      predicted: true,
    );
  }
}
