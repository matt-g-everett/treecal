import 'dart:math' as math;
import 'ray_cone_geometry.dart';
import 'triangulation_service_proper.dart';

/// Candidate LED position (either front or back surface)
class LEDPositionCandidate {
  final int ledIndex;
  
  // PRIMARY: Cone coordinates (what we work with)
  final double normalizedHeight;  // 0-1
  final double angleDegrees;      // 0-360
  final double radius;            // meters from center axis
  
  // DERIVED: Cartesian coordinates (for export/visualization)
  final double x, y, z;
  
  final double confidence;
  final int numObservations;
  final String surface;  // 'front' or 'back'
  
  LEDPositionCandidate({
    required this.ledIndex,
    required this.normalizedHeight,
    required this.angleDegrees,
    required this.radius,
    required this.x,
    required this.y,
    required this.z,
    required this.confidence,
    required this.numObservations,
    required this.surface,
  });
  
  /// Calculate distance to another candidate in CONE SPACE
  /// 
  /// This is the key method for continuity scoring!
  /// Works in (height, angle) space and handles wraparound correctly.
  double coneDistanceTo(LEDPositionCandidate other, double treeHeight) {
    // Height component (vertical separation)
    final dh = (normalizedHeight - other.normalizedHeight).abs();
    final heightDist = dh * treeHeight;  // meters
    
    // Angular component (horizontal separation)
    // CRITICAL: Handle wraparound (0° = 360°)
    final rawDtheta = (angleDegrees - other.angleDegrees).abs();
    final dtheta = math.min(rawDtheta, 360 - rawDtheta);
    
    // Arc length at average radius
    final avgRadius = (radius + other.radius) / 2;
    final dthetaRad = dtheta * math.pi / 180;
    final arcDist = avgRadius * dthetaRad;  // meters
    
    // Combined distance (2D on unrolled cone surface)
    return math.sqrt(heightDist * heightDist + arcDist * arcDist);
  }
  
  /// Cartesian distance (for reference only - don't use for continuity!)
  double cartesianDistanceTo(LEDPositionCandidate other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

/// Result of front/back determination
class SurfaceDeterminationResult {
  final LED3DPosition position;
  final double frontConfidence;  // 0-1, higher = more likely front
  final String determinedSurface;  // 'front' or 'back'
  final String reason;  // Why this determination was made
  
  SurfaceDeterminationResult({
    required this.position,
    required this.frontConfidence,
    required this.determinedSurface,
    required this.reason,
  });
}

/// Service to determine if LEDs are on front or back surface
class FrontBackDeterminationService {
  
  /// Determine front/back surface for all LEDs using string continuity
  /// 
  /// Strategy:
  /// 1. Generate both front and back candidates for each LED
  /// 2. Score each candidate based on continuity with WIDER WINDOW of neighbors
  /// 3. Select surface with higher score (simple greedy with context)
  /// 4. Return final positions with front/back confidence
  /// 
  /// Uses sliding window (not just immediate neighbors!) to determine
  /// which surface entire SEQUENCES are on, not just individual LEDs.
  static List<SurfaceDeterminationResult> determineSurfaces({
    required Map<int, List<DualRayConeIntersection>> dualIntersections,
    required int totalLeds,
    required double treeHeight,
    double maxNeighborDistance = 0.15,  // Max distance between consecutive LEDs (meters)
    int windowSize = 5,  // Check ±5 neighbors (11 LEDs total) - wider context!
  }) {
    
    // Generate candidates (front and back) for each LED
    final candidates = _generateCandidates(dualIntersections);
    
    // Score candidates based on string continuity (in cone space, wider window!)
    final scored = _scoreContinuity(
      candidates, 
      totalLeds, 
      maxNeighborDistance, 
      treeHeight, 
      windowSize,  // Use sliding window for wider context
    );
    
    // Select best surface for each LED (greedy with wider context)
    final results = _selectBestSurface(scored, candidates);
    
    return results;
  }
  
  /// Generate front and back candidates for each LED
  static Map<int, Map<String, LEDPositionCandidate>> _generateCandidates(
    Map<int, List<DualRayConeIntersection>> dualIntersections,
  ) {
    final candidates = <int, Map<String, LEDPositionCandidate>>{};
    
    for (final entry in dualIntersections.entries) {
      final ledIndex = entry.key;
      final intersections = entry.value;
      
      if (intersections.isEmpty) continue;
      
      // Average front intersections
      final frontIntersections = intersections.map((i) => i.front).toList();
      final frontAvg = _averageIntersections(frontIntersections);
      
      if (frontAvg != null) {
        candidates[ledIndex] = {
          'front': LEDPositionCandidate(
            ledIndex: ledIndex,
            // Cone coordinates (PRIMARY)
            normalizedHeight: frontAvg.normalizedHeight,
            angleDegrees: frontAvg.angleDegrees,
            radius: math.sqrt(frontAvg.position3D.x * frontAvg.position3D.x + 
                            frontAvg.position3D.y * frontAvg.position3D.y),
            // Cartesian coordinates (DERIVED)
            x: frontAvg.position3D.x,
            y: frontAvg.position3D.y,
            z: frontAvg.position3D.z,
            confidence: 1.0 / (1.0 + intersections.length),
            numObservations: intersections.length,
            surface: 'front',
          ),
        };
      }
      
      // Average back intersections (if they exist)
      final backIntersections = intersections
        .where((i) => i.back != null)
        .map((i) => i.back!)
        .toList();
      
      if (backIntersections.isNotEmpty) {
        final backAvg = _averageIntersections(backIntersections);
        
        if (backAvg != null) {
          candidates[ledIndex]!['back'] = LEDPositionCandidate(
            ledIndex: ledIndex,
            // Cone coordinates (PRIMARY)
            normalizedHeight: backAvg.normalizedHeight,
            angleDegrees: backAvg.angleDegrees,
            radius: math.sqrt(backAvg.position3D.x * backAvg.position3D.x + 
                            backAvg.position3D.y * backAvg.position3D.y),
            // Cartesian coordinates (DERIVED)
            x: backAvg.position3D.x,
            y: backAvg.position3D.y,
            z: backAvg.position3D.z,
            confidence: 1.0 / (1.0 + backIntersections.length),
            numObservations: backIntersections.length,
            surface: 'back',
          );
        }
      }
    }
    
    return candidates;
  }
  
  /// Average multiple intersections using circular mean for angles
  static RayConeIntersection? _averageIntersections(
    List<RayConeIntersection> intersections,
  ) {
    if (intersections.isEmpty) return null;
    
    double sumHeight = 0;
    double sumAngleSin = 0;
    double sumAngleCos = 0;
    double sumDist = 0;
    
    for (final intersection in intersections) {
      sumHeight += intersection.normalizedHeight;
      
      final angleRad = intersection.angleDegrees * math.pi / 180;
      sumAngleSin += math.sin(angleRad);
      sumAngleCos += math.cos(angleRad);
      
      sumDist += intersection.distance;
    }
    
    final count = intersections.length;
    final avgHeight = sumHeight / count;
    final avgAngleRad = math.atan2(sumAngleSin / count, sumAngleCos / count);
    final avgAngle = (avgAngleRad * 180 / math.pi + 360) % 360;
    final avgDist = sumDist / count;
    
    // Reconstruct 3D position from averaged cone coordinates
    // Use first intersection's position as reference, adjust by averages
    final ref = intersections.first;
    final avgRadius = math.sqrt(ref.position3D.x * ref.position3D.x + 
                                ref.position3D.y * ref.position3D.y);
    
    final avgX = avgRadius * math.cos(avgAngleRad);
    final avgY = avgRadius * math.sin(avgAngleRad);
    final avgZ = ref.position3D.z;  // Use reference Z (could be improved)
    
    return RayConeIntersection(
      normalizedHeight: avgHeight,
      angleDegrees: avgAngle,
      position3D: Vector3(avgX, avgY, avgZ),
      distance: avgDist,
    );
  }
  
  /// Score candidates based on string continuity with WIDER CONTEXT
  /// 
  /// Uses sliding window to look at multiple neighbors (not just immediate)
  /// This allows determining which surface a SEQUENCE is on, not just individual LEDs
  static Map<int, Map<String, double>> _scoreContinuity(
    Map<int, Map<String, LEDPositionCandidate>> candidates,
    int totalLeds,
    double maxDistance,
    double treeHeight,
    int windowSize, // How many neighbors to check on each side
  ) {
    final scores = <int, Map<String, double>>{};
    
    for (final entry in candidates.entries) {
      final ledIndex = entry.key;
      final ledCandidates = entry.value;
      
      scores[ledIndex] = {};
      
      // Score each surface (front/back)
      for (final surface in ledCandidates.keys) {
        final candidate = ledCandidates[surface]!;
        
        double score = 0;
        int neighborCount = 0;
        
        // Check WINDOW of neighbors (±windowSize)
        // Gives us wider context to determine if sequence is front or back
        for (int offset = -windowSize; offset <= windowSize; offset++) {
          if (offset == 0) continue; // Skip self
          
          final neighborIndex = ledIndex + offset;
          
          if (neighborIndex < 0 || neighborIndex >= totalLeds) continue;
          
          final neighborCandidates = candidates[neighborIndex];
          if (neighborCandidates == null) continue;
          
          // Check if neighbor's same surface is close
          final neighborSameSurface = neighborCandidates[surface];
          if (neighborSameSurface != null) {
            // CRITICAL: Use CONE distance, not Cartesian!
            final distance = candidate.coneDistanceTo(neighborSameSurface, treeHeight);
            
            // Weight by proximity: closer neighbors matter more
            final proximityWeight = 1.0 - (offset.abs() / windowSize);
            
            // Closer neighbors = higher score
            if (distance < maxDistance) {
              final continuityScore = (1.0 - distance / maxDistance) * proximityWeight;
              score += continuityScore;
              neighborCount++;
            }
          }
        }
        
        // Average score across neighbors
        scores[ledIndex]![surface] = neighborCount > 0 
          ? score / neighborCount 
          : 0.5;  // No neighbors = neutral score
      }
    }
    
    return scores;
  }
  
  /// Select best surface for each LED using greedy algorithm
  /// 
  /// Simple approach: Pick surface with higher continuity score
  /// Mark confidence based on score ratio
  static List<SurfaceDeterminationResult> _selectBestSurface(
    Map<int, Map<String, double>> scores,
    Map<int, Map<String, LEDPositionCandidate>> candidates,
  ) {
    final results = <SurfaceDeterminationResult>[];
    
    for (final entry in scores.entries) {
      final ledIndex = entry.key;
      final surfaceScores = entry.value;
      
      if (surfaceScores.isEmpty) continue;
      
      final frontScore = surfaceScores['front'] ?? 0.0;
      final backScore = surfaceScores['back'] ?? 0.0;
      final totalScore = frontScore + backScore;
      
      if (totalScore == 0) continue;
      
      // Simple greedy: pick higher score
      final bestSurface = frontScore >= backScore ? 'front' : 'back';
      final frontConfidence = frontScore / totalScore;
      
      // Get the candidate
      final candidate = candidates[ledIndex]?[bestSurface];
      if (candidate == null) continue;
      
      // Convert to LED3DPosition
      final position = LED3DPosition(
        ledIndex: ledIndex,
        x: candidate.x,
        y: candidate.y,
        z: candidate.z,
        height: candidate.normalizedHeight,
        angle: candidate.angleDegrees,
        radius: candidate.radius,
        confidence: candidate.confidence,
        numObservations: candidate.numObservations,
        predicted: false,
      );
      
      // Determine reason
      String reason;
      if (frontConfidence > 0.8) {
        reason = 'Strong continuity with neighbors on $bestSurface (score: ${frontScore.toStringAsFixed(2)})';
      } else if (frontConfidence < 0.2) {
        reason = 'Strong continuity with neighbors on $bestSurface (score: ${backScore.toStringAsFixed(2)})';
      } else if (frontConfidence > 0.6) {
        reason = 'Moderate continuity with neighbors on $bestSurface';
      } else if (frontConfidence < 0.4) {
        reason = 'Moderate continuity with neighbors on $bestSurface';
      } else {
        reason = 'Ambiguous - similar continuity on both surfaces';
      }
      
      results.add(SurfaceDeterminationResult(
        position: position,
        frontConfidence: frontConfidence,
        determinedSurface: bestSurface,
        reason: reason,
      ));
    }
    
    return results;
  }
}
