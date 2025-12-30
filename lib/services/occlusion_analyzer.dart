import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Segment of LED sequence (visible or hidden)
class OcclusionSegment {
  final int startLED;
  final int endLED;
  final String type;  // 'visible' or 'hidden'
  final double avgConfidence;
  
  OcclusionSegment({
    required this.startLED,
    required this.endLED,
    required this.type,
    required this.avgConfidence,
  });
  
  bool contains(int ledIndex) {
    return ledIndex >= startLED && ledIndex <= endLED;
  }
  
  @override
  String toString() => 'Segment($type, LEDs $startLED-$endLED, conf=${avgConfidence.toStringAsFixed(2)})';
}

/// Analyzes LED detection sequences to identify occlusion patterns
/// 
/// This is the key insight: each camera independently analyzes the LED string
/// sequence to identify which LEDs are visible vs hidden (behind tree).
/// 
/// Uses:
/// - Sequence patterns (not single values)
/// - Neighbor context (string continuity)
/// - Smoothing (robust to noise)
class OcclusionAnalyzer {
  
  /// Analyze detection sequences per camera to identify visible/hidden segments
  /// 
  /// For each camera:
  /// 1. Build confidence sequence [LED 0, LED 1, ..., LED 199]
  /// 2. Smooth with moving average (reduce noise)
  /// 3. Segment into visible/hidden regions
  /// 4. Score each LED based on its segment
  /// 
  /// Returns: occlusion[cameraIndex][ledIndex] = 0.0 (visible) to 1.0 (hidden)
  static Map<int, Map<int, double>> analyzePerCamera({
    required List<Map<String, dynamic>> allDetections,
    required int totalLEDs,
    double visibilityThreshold = 0.5,
    int smoothingWindow = 5,
  }) {
    
    // Group detections by camera
    final detectionsByCamera = <int, List<Map<String, dynamic>>>{};
    for (final detection in allDetections) {
      final cameraIndex = detection['camera_index'] as int;
      detectionsByCamera
        .putIfAbsent(cameraIndex, () => [])
        .add(detection);
    }
    
    // Analyze each camera independently
    final occlusion = <int, Map<int, double>>{};
    
    for (final entry in detectionsByCamera.entries) {
      final cameraIndex = entry.key;
      final detections = entry.value;
      
      // Build confidence sequence
      final sequence = _buildConfidenceSequence(detections, totalLEDs);
      
      // Smooth to reduce noise
      final smoothed = _movingAverage(sequence, smoothingWindow);
      
      // Find segments
      final segments = _findSegments(smoothed, visibilityThreshold);
      
      // Debug: print segments
      debugPrint('Camera $cameraIndex segments:');
      for (final segment in segments) {
        debugPrint('  $segment');
      }
      
      // Score each LED based on its segment
      occlusion[cameraIndex] = _scoreOcclusion(segments, totalLEDs);
    }
    
    return occlusion;
  }
  
  /// Build confidence sequence for a camera
  /// Returns array where sequence[ledIndex] = detection confidence (0-1)
  static List<double> _buildConfidenceSequence(
    List<Map<String, dynamic>> detections,
    int totalLEDs,
  ) {
    final sequence = List<double>.filled(totalLEDs, 0.0);
    
    for (final detection in detections) {
      final ledIndex = detection['led_index'] as int;
      
      if (ledIndex < 0 || ledIndex >= totalLEDs) continue;
      
      final detectionsList = detection['detections'] as List?;
      if (detectionsList == null || detectionsList.isEmpty) continue;
      
      // Use best detection for this LED
      final bestDetection = detectionsList
        .map((d) => d as Map<String, dynamic>)
        .reduce((a, b) =>
          (a['detection_confidence'] as double) > (b['detection_confidence'] as double)
            ? a : b);
      
      sequence[ledIndex] = (bestDetection['detection_confidence'] as num).toDouble();
    }
    
    return sequence;
  }
  
  /// Apply moving average smoothing to reduce noise
  /// 
  /// Example: [0.9, 0.9, 0.1, 0.9, 0.9] with window=5
  ///       -> [0.9, 0.9, 0.74, 0.9, 0.9]
  /// The single low value (noise) gets smoothed out
  static List<double> _movingAverage(List<double> data, int window) {
    if (window <= 1) return List.from(data);
    
    final result = <double>[];
    final halfWindow = window ~/ 2;
    
    for (int i = 0; i < data.length; i++) {
      final start = math.max(0, i - halfWindow);
      final end = math.min(data.length, i + halfWindow + 1);
      
      double sum = 0;
      for (int j = start; j < end; j++) {
        sum += data[j];
      }
      
      result.add(sum / (end - start));
    }
    
    return result;
  }
  
  /// Find visible/hidden segments in smoothed sequence
  /// 
  /// Segments alternate: visible → hidden → visible → hidden ...
  /// This follows the spiral pattern of LEDs around tree
  static List<OcclusionSegment> _findSegments(
    List<double> smoothed,
    double threshold,
  ) {
    if (smoothed.isEmpty) return [];
    
    final segments = <OcclusionSegment>[];
    bool inVisible = smoothed[0] > threshold;
    int segmentStart = 0;
    List<double> segmentValues = [smoothed[0]];
    
    for (int i = 1; i < smoothed.length; i++) {
      final wasVisible = inVisible;
      final isVisible = smoothed[i] > threshold;
      
      if (wasVisible != isVisible) {
        // Segment boundary - save current segment
        final avgConf = segmentValues.reduce((a, b) => a + b) / segmentValues.length;
        
        segments.add(OcclusionSegment(
          startLED: segmentStart,
          endLED: i - 1,
          type: wasVisible ? 'visible' : 'hidden',
          avgConfidence: avgConf,
        ));
        
        // Start new segment
        segmentStart = i;
        inVisible = isVisible;
        segmentValues = [smoothed[i]];
      } else {
        segmentValues.add(smoothed[i]);
      }
    }
    
    // Add final segment
    final avgConf = segmentValues.reduce((a, b) => a + b) / segmentValues.length;
    segments.add(OcclusionSegment(
      startLED: segmentStart,
      endLED: smoothed.length - 1,
      type: inVisible ? 'visible' : 'hidden',
      avgConfidence: avgConf,
    ));
    
    return segments;
  }
  
  /// Score occlusion for each LED based on which segment it's in
  /// 
  /// Visible segment: low occlusion (0.0-0.3)
  /// Hidden segment: high occlusion (0.7-1.0)
  static Map<int, double> _scoreOcclusion(
    List<OcclusionSegment> segments,
    int totalLEDs,
  ) {
    final scores = <int, double>{};
    
    for (int led = 0; led < totalLEDs; led++) {
      // Find which segment this LED is in
      final segment = segments.firstWhere(
        (s) => s.contains(led),
        orElse: () => OcclusionSegment(
          startLED: led,
          endLED: led,
          type: 'hidden',
          avgConfidence: 0.0,
        ),
      );
      
      if (segment.type == 'visible') {
        // Visible segment: low occlusion
        // Higher avgConfidence = more visible = lower occlusion
        scores[led] = 1.0 - segment.avgConfidence;
      } else {
        // Hidden segment: high occlusion
        // Lower avgConfidence = more hidden = higher occlusion
        scores[led] = 0.7 + (0.3 * (1.0 - segment.avgConfidence));
      }
    }
    
    return scores;
  }
}
