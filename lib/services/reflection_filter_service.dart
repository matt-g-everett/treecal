import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// A cluster of detections at the same pixel location
class ReflectionCluster {
  final double pixelX;
  final double pixelY;
  final List<int> ledIndices;  // Which LEDs light this spot
  final int cameraIndex;
  
  ReflectionCluster({
    required this.pixelX,
    required this.pixelY,
    required this.ledIndices,
    required this.cameraIndex,
  });
  
  /// Reflection probability (0-1)
  /// More LEDs at same spot = higher probability of reflection
  double get reflectionScore {
    if (ledIndices.length <= 1) return 0.0;
    // 2 LEDs at same spot: 10% reflection
    // 5 LEDs: 40%
    // 10+ LEDs: 90%
    return math.min(0.9, (ledIndices.length - 1) / 10.0);
  }
}

/// Service to filter out reflections from LED detections
class ReflectionFilterService {
  
  /// Filter reflections from all detections
  /// 
  /// Detections at the same pixel location across multiple LEDs
  /// are likely reflections and get confidence reduced.
  static List<Map<String, dynamic>> filterReflections(
    List<Map<String, dynamic>> allDetections, {
    double spatialThreshold = 20.0,
    double minConfidence = 0.3,
  }) {
    // Group detections by camera
    Map<int, List<Map<String, dynamic>>> byCamera = {};
    
    for (final det in allDetections) {
      final camIdx = det['camera_index'] as int;
      byCamera.putIfAbsent(camIdx, () => []).add(det);
    }
    
    // Find reflection clusters for each camera
    Map<int, List<ReflectionCluster>> clustersByCamera = {};
    
    for (final camIdx in byCamera.keys) {
      clustersByCamera[camIdx] = _findClusters(
        byCamera[camIdx]!,
        spatialThreshold,
        camIdx,
      );
    }
    
    // Filter detections based on reflection scores
    List<Map<String, dynamic>> filtered = [];
    int totalFiltered = 0;
    
    for (final det in allDetections) {
      final camIdx = det['camera_index'] as int;
      final detectionsList = det['detections'] as List;
      
      if (detectionsList.isEmpty) continue;
      
      // Get best detection for this LED
      var best = Map<String, dynamic>.from(detectionsList[0] as Map<String, dynamic>);
      final px = best['x'] as double;
      final py = best['y'] as double;
      
      // Check if this detection is in a reflection cluster
      final clusters = clustersByCamera[camIdx] ?? [];
      ReflectionCluster? matchingCluster;
      
      for (final cluster in clusters) {
        if (_distance(cluster.pixelX, cluster.pixelY, px, py) < spatialThreshold) {
          matchingCluster = cluster;
          break;
        }
      }
      
      // Adjust confidence based on reflection score
      if (matchingCluster != null && matchingCluster.reflectionScore > 0) {
        final originalConfidence = best['detection_confidence'] as double;
        final adjustedConfidence = originalConfidence * (1 - matchingCluster.reflectionScore);
        
        best['detection_confidence'] = adjustedConfidence;
        best['is_likely_reflection'] = matchingCluster.reflectionScore > 0.5;
        best['reflection_score'] = matchingCluster.reflectionScore;
        best['cluster_size'] = matchingCluster.ledIndices.length;
      }
      
      // Only include if confidence still high enough
      if ((best['detection_confidence'] as double) >= minConfidence) {
        // Create new detection with updated confidence
        final filteredDet = Map<String, dynamic>.from(det);
        filteredDet['detections'] = [best];
        filtered.add(filteredDet);
      } else {
        totalFiltered++;
      }
    }
    
    debugPrint('Reflection filtering: ${allDetections.length} total, '
          '$totalFiltered filtered out, ${filtered.length} kept');
    
    return filtered;
  }
  
  /// Find clusters of detections at same pixel location
  static List<ReflectionCluster> _findClusters(
    List<Map<String, dynamic>> detections,
    double threshold,
    int cameraIndex,
  ) {
    // Build spatial map: pixel location -> LED indices
    Map<String, List<int>> pixelToLeds = {};
    Map<String, List<double>> pixelCoords = {};
    
    for (final det in detections) {
      final ledIdx = det['led_index'] as int;
      final detectionsList = det['detections'] as List;
      
      if (detectionsList.isEmpty) continue;
      
      final best = detectionsList[0] as Map<String, dynamic>;
      final px = (best['x'] as double);
      final py = (best['y'] as double);
      
      // Round to grid for clustering
      final gridX = (px / threshold).round();
      final gridY = (py / threshold).round();
      final key = '$gridX,$gridY';
      
      pixelToLeds.putIfAbsent(key, () => []).add(ledIdx);
      pixelCoords.putIfAbsent(key, () => [px, py]);
    }
    
    // Convert to clusters (only where multiple LEDs detected)
    List<ReflectionCluster> clusters = [];
    
    for (final entry in pixelToLeds.entries) {
      if (entry.value.length > 1) {
        final coords = pixelCoords[entry.key]!;
        clusters.add(ReflectionCluster(
          pixelX: coords[0],
          pixelY: coords[1],
          ledIndices: entry.value,
          cameraIndex: cameraIndex,
        ));
      }
    }
    
    // Sort by cluster size (largest first)
    clusters.sort((a, b) => b.ledIndices.length.compareTo(a.ledIndices.length));
    
    if (clusters.isNotEmpty) {
      debugPrint('Camera $cameraIndex: Found ${clusters.length} reflection clusters');
      if (clusters.isNotEmpty) {
        final top = clusters.first;
        debugPrint('  Largest cluster: ${top.ledIndices.length} LEDs at '
              '(${top.pixelX.toInt()}, ${top.pixelY.toInt()})');
      }
    }
    
    return clusters;
  }
  
  /// Calculate Euclidean distance between two points
  static double _distance(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  /// Generate reflection analysis report
  static Map<String, dynamic> analyzeReflections(
    List<Map<String, dynamic>> allDetections,
    double spatialThreshold,
  ) {
    final byCamera = <int, List<Map<String, dynamic>>>{};
    
    for (final det in allDetections) {
      final camIdx = det['camera_index'] as int;
      byCamera.putIfAbsent(camIdx, () => []).add(det);
    }
    
    final cameraReports = <Map<String, dynamic>>[];
    int totalClusters = 0;
    int totalReflectionDetections = 0;
    
    for (final camIdx in byCamera.keys) {
      final clusters = _findClusters(byCamera[camIdx]!, spatialThreshold, camIdx);
      totalClusters += clusters.length;
      
      int reflectionCount = 0;
      for (final cluster in clusters) {
        reflectionCount += cluster.ledIndices.length;
      }
      totalReflectionDetections += reflectionCount;
      
      cameraReports.add({
        'camera_index': camIdx,
        'num_clusters': clusters.length,
        'num_reflection_detections': reflectionCount,
        'largest_cluster_size': clusters.isNotEmpty ? clusters.first.ledIndices.length : 0,
      });
    }
    
    return {
      'total_detections': allDetections.length,
      'total_clusters': totalClusters,
      'total_reflection_detections': totalReflectionDetections,
      'cameras': cameraReports,
    };
  }
}
