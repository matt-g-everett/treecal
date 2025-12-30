import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'ray_cone_geometry.dart';
import 'occlusion_analyzer.dart';

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
  
  Vector3 get position3D => Vector3(x, y, z);
  
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

/// Triangulation service using proper ray-cone intersection
class TriangulationService {
  
  /// Triangulate LED positions from multiple camera observations
  static List<LED3DPosition> triangulate({
    required List<Map<String, dynamic>> allDetections,
    required List<CameraPosition> cameraPositions,
    required double treeHeight,
    double imageWidth = 1920,
    double imageHeight = 1080,
    double fovDegrees = 60.0,
    double minConfidence = 0.5,
    double baseRadius = 0.5,     // Estimated base radius
    double topRadius = 0.05,     // Estimated top radius (nearly point)
  }) {
    
    // Create cone model
    final cone = ConeModel(
      baseRadius: baseRadius,
      topRadius: topRadius,
      height: treeHeight,
    );
    
    // Create camera geometry
    final cameraGeometry = CameraGeometry(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      fovHorizontalDegrees: fovDegrees,
    );
    
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
    
    // Analyze occlusion patterns per camera
    debugPrint('Analyzing occlusion patterns...');
    final occlusion = OcclusionAnalyzer.analyzePerCamera(
      allDetections: allDetections,
      totalLEDs: 200,
      visibilityThreshold: 0.5,
      smoothingWindow: 5,
    );
    debugPrint('Occlusion analysis complete for ${occlusion.length} cameras');
    
    // Triangulate each LED with occlusion weighting
    List<LED3DPosition> positions = [];
    
    for (int ledIndex = 0; ledIndex < 200; ledIndex++) {
      final observations = observationsByLed[ledIndex];
      
      if (observations == null || observations.isEmpty) {
        continue; // Will be predicted later
      }
      
      final triangulated = _triangulateWithRayCone(
        observations,
        cameraPositions,
        cameraGeometry,
        cone,
        occlusion,
        ledIndex,
      );
      
      if (triangulated != null) {
        positions.add(triangulated);
      }
    }
    
    return positions;
  }
  
  /// Triangulate using proper ray-cone intersection
  /// Uses BEST observation (highest weight = detection × angular × occlusion adjustment)
  static LED3DPosition? _triangulateWithRayCone(
    List<LEDObservation> observations,
    List<CameraPosition> cameraPositions,
    CameraGeometry cameraGeometry,
    ConeModel cone,
    Map<int, Map<int, double>> occlusion,
    int ledIndex,
  ) {
    if (observations.isEmpty) return null;
    
    // Find observation with highest occlusion-adjusted weight
    var bestObs = observations.first;
    var bestWeight = 0.0;
    
    for (final obs in observations) {
      // Base weight: detection quality × angular quality
      final baseWeight = obs.weight;  // detection × angular
      
      // Get occlusion score for this camera/LED combination
      final occlusionScore = occlusion[obs.cameraIndex]?[ledIndex] ?? 0.5;
      
      // Soft weighting: apply penalty based on occlusion
      // visible (0.0) = no penalty → full weight
      // hidden (1.0) = full penalty → zero weight
      // marginal (0.5) = 50% penalty → half weight
      final finalWeight = baseWeight * (1.0 - occlusionScore);
      
      if (finalWeight > bestWeight) {
        bestWeight = finalWeight;
        bestObs = obs;
      }
    }
    
    // Debug: print selection
    if (ledIndex % 20 == 0) {  // Print every 20th LED
      debugPrint('LED $ledIndex: selected camera ${bestObs.cameraIndex} '
            'base_weight=${bestObs.weight.toStringAsFixed(2)} '
            'final_weight=${bestWeight.toStringAsFixed(2)}');
    }
    
    // Get camera position
    final cam = cameraPositions.firstWhere((c) => c.index == bestObs.cameraIndex);
    
    // Get ray direction in camera space
    final rayCamera = cameraGeometry.pixelToRayDirection(bestObs.pixelX, bestObs.pixelY);
    
    // Transform to world space
    // Camera coordinate system:
    //   Camera looks toward tree center (origin)
    //   Camera position is (cam.x, cam.y, cam.z)
    //   Need to rotate ray to point toward tree
    
    // Direction from camera to tree center
    final toTree = Vector3(-cam.x, -cam.y, -cam.z).normalized;
    
    // Camera's right vector (perpendicular to toTree in XY plane)
    final right = Vector3(-toTree.y, toTree.x, 0).normalized;
    
    // Camera's up vector
    final up = right.cross(toTree);
    
    // Transform ray: camera +X → right, camera +Y → down, camera +Z → forward
    final rayWorld = (
      right * rayCamera.x +
      up * (-rayCamera.y) +  // Flip Y (image Y is down, world Y is up)
      toTree * rayCamera.z
    ).normalized;
    
    // Intersect with cone - get BOTH surfaces (front and back)
    final dualIntersection = RayConeIntersector.intersectDual(
      rayOrigin: cam.position3D,
      rayDirection: rayWorld,
      cone: cone,
    );
    
    if (dualIntersection == null) {
      return null;
    }
    
    // Get occlusion score for this camera and LED
    final occlusionScore = occlusion[bestObs.cameraIndex]?[bestObs.ledIndex] ?? 0.5;
    
    // Select surface based on occlusion analysis
    // Low occlusion (< 0.5) = LED facing camera = front surface
    // High occlusion (>= 0.5) = LED facing away = back surface
    final intersection = occlusionScore < 0.5
        ? dualIntersection.front
        : (dualIntersection.back ?? dualIntersection.front);
    
    // Debug: print surface selection for sample LEDs
    if (ledIndex % 20 == 0) {
      debugPrint('LED $ledIndex: occlusion=${occlusionScore.toStringAsFixed(2)} '
            'surface=${occlusionScore < 0.5 ? "FRONT" : "BACK"} '
            'camera=${bestObs.cameraIndex}');
    }
    
    // Use position from selected surface
    final radius = math.sqrt(
      intersection.position3D.x * intersection.position3D.x + 
      intersection.position3D.y * intersection.position3D.y
    );
    
    // Use occlusion-adjusted weight as confidence
    // This reflects: detection quality × angular quality × visibility
    final confidence = bestWeight;
    
    return LED3DPosition(
      ledIndex: bestObs.ledIndex,
      x: intersection.position3D.x,
      y: intersection.position3D.y,
      z: intersection.position3D.z,
      height: intersection.normalizedHeight,
      angle: intersection.angleDegrees,
      radius: radius,
      confidence: confidence,
      numObservations: observations.length,
      predicted: false,
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
    
    // Interpolate in CARTESIAN space (automatically accounts for varying radius/angle)
    final x = before.x + (after.x - before.x) * t;
    final y = before.y + (after.y - before.y) * t;
    final z = before.z + (after.z - before.z) * t;
    
    // DERIVE cone coordinates from Cartesian position
    // This naturally handles varying angular step due to cone geometry
    final radius = math.sqrt(x * x + y * y);
    final angleRad = math.atan2(y, x);
    final angleDeg = (angleRad * 180 / math.pi + 360) % 360;
    final height = before.height + (after.height - before.height) * t;
    
    return LED3DPosition(
      ledIndex: index,
      x: x,
      y: y,
      z: z,
      height: height,
      angle: angleDeg,  // Derived from x, y (not interpolated!)
      radius: radius,
      confidence: (before.confidence + after.confidence) / 2 * (1 - (t - 0.5).abs() * 2),
      numObservations: 0,
      predicted: true,
    );
  }
  
  static Map<String, double> _calculateStep(LED3DPosition from, LED3DPosition to) {
    final steps = (to.ledIndex - from.ledIndex).abs();
    
    // Calculate step in Cartesian space
    // Don't calculate angle/radius steps - these will be derived
    return {
      'x': (to.x - from.x) / steps,
      'y': (to.y - from.y) / steps,
      'z': (to.z - from.z) / steps,
      'height': (to.height - from.height) / steps,
    };
  }
  
  static Map<String, double> _defaultStep() {
    // Default step in Cartesian space
    // Assumes ~1cm spacing in each dimension, typical for LED strings
    // Angle and radius will be derived, not stored
    return {
      'x': 0.01,      // 1cm in x direction
      'y': 0.01,      // 1cm in y direction  
      'z': 0.01,      // 1cm in z direction (vertical)
      'height': 0.005, // 0.5% of normalized height
    };
  }
  
  static LED3DPosition _extrapolate(
    LED3DPosition from,
    Map<String, double> step,
    int distance,
  ) {
    // Extrapolate in Cartesian space
    final x = from.x + step['x']! * distance;
    final y = from.y + step['y']! * distance;
    final z = from.z + step['z']! * distance;
    final height = (from.height + step['height']! * distance).clamp(0.0, 1.0);
    
    // Derive cone coordinates from Cartesian position
    // This automatically handles varying angular step with radius
    final radius = math.sqrt(x * x + y * y);
    final angleRad = math.atan2(y, x);
    final angleDeg = (angleRad * 180 / math.pi + 360) % 360;
    
    return LED3DPosition(
      ledIndex: from.ledIndex + distance,
      x: x,
      y: y,
      z: z,
      height: height,
      angle: angleDeg,  // Derived from x, y
      radius: math.max(0, radius),
      confidence: math.max(0.2, from.confidence - distance * 0.05),
      numObservations: 0,
      predicted: true,
    );
  }
}
