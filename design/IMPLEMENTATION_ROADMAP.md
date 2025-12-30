# Implementation Roadmap - Next Steps

## Current Status Summary

### ✅ Implemented (Working)
- Capture & Detection (OpenCV blob detection)
- Reflection filtering (spatial clustering)
- Camera calibration
- Ray-cone geometry (with dual intersection support)
- **Triangulation (best observation)** ← Just completed!
- Gap filling (interpolation/extrapolation)
- JSON export
- 3D visualization (flutter_gl)

### ❌ Not Implemented (Missing)
- **OcclusionAnalyzer** ← Critical missing piece!
- Occlusion-weighted triangulation integration
- Comprehensive validation
- Quality metrics dashboard

### ⚠️ Needs Enhancement
- Error handling
- Testing infrastructure
- Documentation

---

## Priority 1: Implement OcclusionAnalyzer 🎯

**Why this first:**
- Cornerstone of remaining work
- Blocks occlusion-weighted triangulation
- Contains the key insight (per-camera sequence analysis)
- Once done, everything else flows naturally

**What it does:**
```
For each camera:
  1. Build confidence sequence [LED 0, LED 1, ..., LED 199]
  2. Smooth with moving average (reduce noise)
  3. Segment into visible/hidden regions
  4. Score each LED: 0.0 (visible) to 1.0 (hidden)

Output: occlusion[cameraIndex][ledIndex] = score
```

**Where it goes:**
- New file: `lib/services/occlusion_analyzer.dart`

**Estimated time:** 4-6 hours

---

## Implementation Guide: OcclusionAnalyzer

### Step 1: Create the Service File

**File:** `lib/services/occlusion_analyzer.dart`

```dart
import 'dart:math' as math;

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
}

/// Analyzes LED detection sequences to identify occlusion patterns
class OcclusionAnalyzer {
  
  /// Analyze detection sequences per camera to identify visible/hidden segments
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
      
      // Score each LED based on its segment
      occlusion[cameraIndex] = _scoreOcclusion(segments, totalLEDs);
    }
    
    return occlusion;
  }
  
  /// Build confidence sequence for a camera
  static List<double> _buildConfidenceSequence(
    List<Map<String, dynamic>> detections,
    int totalLEDs,
  ) {
    final sequence = List<double>.filled(totalLEDs, 0.0);
    
    for (final detection in detections) {
      final ledIndex = detection['led_index'] as int;
      final detectionsList = detection['detections'] as List;
      
      if (detectionsList.isNotEmpty) {
        // Use best detection for this LED
        final bestDetection = (detectionsList as List<dynamic>)
          .map((d) => d as Map<String, dynamic>)
          .reduce((a, b) => 
            (a['detection_confidence'] as double) > (b['detection_confidence'] as double)
              ? a : b);
        
        sequence[ledIndex] = (bestDetection['detection_confidence'] as num).toDouble();
      }
    }
    
    return sequence;
  }
  
  /// Apply moving average smoothing
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
  
  /// Score occlusion for each LED based on segments
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
```

---

### Step 2: Add Unit Tests

**File:** `test/unit/occlusion_analyzer_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:led_mapper_app/services/occlusion_analyzer.dart';

void main() {
  group('OcclusionAnalyzer', () {
    
    test('builds confidence sequence correctly', () {
      final detections = [
        {
          'camera_index': 0,
          'led_index': 0,
          'detections': [
            {'detection_confidence': 0.9},
          ],
        },
        {
          'camera_index': 0,
          'led_index': 1,
          'detections': [
            {'detection_confidence': 0.8},
          ],
        },
      ];
      
      final result = OcclusionAnalyzer.analyzePerCamera(
        allDetections: detections,
        totalLEDs: 10,
      );
      
      expect(result[0]?[0], lessThan(0.5));  // High conf = low occlusion
      expect(result[0]?[1], lessThan(0.5));  // High conf = low occlusion
    });
    
    test('identifies visible segment', () {
      final detections = _createDetections(
        cameraIndex: 0,
        ledRange: [0, 10],
        confidence: 0.9,
      );
      
      final result = OcclusionAnalyzer.analyzePerCamera(
        allDetections: detections,
        totalLEDs: 20,
      );
      
      // LEDs 0-10 should be visible (low occlusion)
      for (int i = 0; i <= 10; i++) {
        expect(result[0]![i], lessThan(0.5), reason: 'LED $i should be visible');
      }
    });
    
    test('identifies hidden segment', () {
      final detections = _createMixedDetections(
        cameraIndex: 0,
        visibleRange: [0, 10],
        hiddenRange: [11, 20],
      );
      
      final result = OcclusionAnalyzer.analyzePerCamera(
        allDetections: detections,
        totalLEDs: 30,
      );
      
      // LEDs 0-10: visible (low occlusion)
      for (int i = 0; i <= 10; i++) {
        expect(result[0]![i], lessThan(0.5));
      }
      
      // LEDs 11-20: hidden (high occlusion)
      for (int i = 11; i <= 20; i++) {
        expect(result[0]![i], greaterThan(0.5));
      }
    });
    
    test('smoothing reduces noise', () {
      final detections = [
        {'camera_index': 0, 'led_index': 0, 'detections': [{'detection_confidence': 0.9}]},
        {'camera_index': 0, 'led_index': 1, 'detections': [{'detection_confidence': 0.9}]},
        {'camera_index': 0, 'led_index': 2, 'detections': [{'detection_confidence': 0.1}]},  // Noise!
        {'camera_index': 0, 'led_index': 3, 'detections': [{'detection_confidence': 0.9}]},
        {'camera_index': 0, 'led_index': 4, 'detections': [{'detection_confidence': 0.9}]},
      ];
      
      final result = OcclusionAnalyzer.analyzePerCamera(
        allDetections: detections,
        totalLEDs: 10,
        smoothingWindow: 5,
      );
      
      // LED 2 should not be marked as hidden (smoothing should reduce noise)
      expect(result[0]![2], lessThan(0.6), reason: 'Smoothing should reduce noise');
    });
  });
}

List<Map<String, dynamic>> _createDetections({
  required int cameraIndex,
  required List<int> ledRange,
  required double confidence,
}) {
  final detections = <Map<String, dynamic>>[];
  for (int i = ledRange[0]; i <= ledRange[1]; i++) {
    detections.add({
      'camera_index': cameraIndex,
      'led_index': i,
      'detections': [
        {'detection_confidence': confidence},
      ],
    });
  }
  return detections;
}

List<Map<String, dynamic>> _createMixedDetections({
  required int cameraIndex,
  required List<int> visibleRange,
  required List<int> hiddenRange,
}) {
  final detections = <Map<String, dynamic>>[];
  
  // Visible range
  detections.addAll(_createDetections(
    cameraIndex: cameraIndex,
    ledRange: visibleRange,
    confidence: 0.9,
  ));
  
  // Hidden range
  detections.addAll(_createDetections(
    cameraIndex: cameraIndex,
    ledRange: hiddenRange,
    confidence: 0.2,
  ));
  
  return detections;
}
```

---

### Step 3: Integrate with Triangulation

**Update:** `lib/services/triangulation_service_proper.dart`

```dart
import 'occlusion_analyzer.dart';  // Add import

class TriangulationService {
  
  static List<LED3DPosition> triangulate({
    required List<Map<String, dynamic>> allDetections,
    required List<CameraPosition> cameraPositions,
    required double treeHeight,
    // ... other params
  }) {
    
    // Parse detections and build observation lists
    final observationsByLed = <int, List<LEDObservation>>{};
    // ... existing parsing code ...
    
    // STEP 1: Analyze occlusion patterns (NEW!)
    final occlusion = OcclusionAnalyzer.analyzePerCamera(
      allDetections: allDetections,
      totalLEDs: 200,
    );
    
    // STEP 2: Triangulate with occlusion weighting
    final positions = <LED3DPosition>[];
    
    for (int ledIndex = 0; ledIndex < 200; ledIndex++) {
      final observations = observationsByLed[ledIndex];
      if (observations == null || observations.isEmpty) continue;
      
      // Pass occlusion to triangulation
      final triangulated = _triangulateWithRayCone(
        observations,
        cameraPositions,
        cameraGeometry,
        cone,
        occlusion,      // NEW!
        ledIndex,       // NEW!
      );
      
      if (triangulated != null) {
        positions.add(triangulated);
      }
    }
    
    return positions;
  }
  
  static LED3DPosition? _triangulateWithRayCone(
    List<LEDObservation> observations,
    List<CameraPosition> cameraPositions,
    CameraGeometry cameraGeometry,
    ConeModel cone,
    Map<int, Map<int, double>> occlusion,  // NEW parameter
    int ledIndex,                           // NEW parameter
  ) {
    if (observations.isEmpty) return null;
    
    // Find observation with highest occlusion-adjusted weight
    var bestObs = observations.first;
    var bestWeight = 0.0;
    
    for (final obs in observations) {
      final baseWeight = obs.weight;  // detection × angular
      
      // Get occlusion score for this camera/LED
      final occlusionScore = occlusion[obs.cameraIndex]?[ledIndex] ?? 0.5;
      
      // Soft weighting: visible (0.0) = no penalty, hidden (1.0) = full penalty
      final finalWeight = baseWeight * (1.0 - occlusionScore);
      
      if (finalWeight > bestWeight) {
        bestWeight = finalWeight;
        bestObs = obs;
      }
    }
    
    // Continue with ray-cone intersection using best observation
    // ... existing code ...
  }
}
```

---

### Step 4: Test Integration

**Manual test:**
```dart
// In a test or debug screen:
final positions = TriangulationService.triangulate(
  allDetections: capturedDetections,
  cameraPositions: cameras,
  treeHeight: 2.0,
);

// Check results
for (final pos in positions) {
  print('LED ${pos.ledIndex}: confidence=${pos.confidence}');
}

// Should see:
// - Higher confidence for clearly visible LEDs
// - Lower confidence for ambiguous LEDs
// - Positions using best visible-segment cameras
```

---

## Priority 2: Enhanced Validation

**After OcclusionAnalyzer works:**

Add quality metrics:
```dart
class ValidationMetrics {
  final double detectionRate;        // % LEDs observed
  final double avgConfidence;        // Average confidence
  final int numPredicted;            // Number of interpolated LEDs
  final double maxNeighborDistance;  // Max cone distance between neighbors
  final List<int> lowConfidenceLEDs; // LEDs to review
}
```

**Estimated time:** 2-3 hours

---

## Priority 3: Error Handling

Add comprehensive error handling:
- Try-catch around all service calls
- User-friendly error messages
- Recovery suggestions
- Retry mechanisms

**Estimated time:** 3-4 hours

---

## Priority 4: Testing Infrastructure

Create test suite:
- Unit tests for each service
- Integration test for complete pipeline
- Sample data fixtures

**Estimated time:** 4-6 hours

---

## Timeline Estimate

**This week:**
- Day 1-2: OcclusionAnalyzer (4-6 hours)
- Day 2-3: Integration & testing (3-4 hours)
- Day 3: Validation metrics (2-3 hours)

**Total: ~10-13 hours of focused work**

**After this, the core pipeline is complete!**

---

## Summary

**Next step: Implement OcclusionAnalyzer**

**Why:**
- Missing critical component
- Enables occlusion-weighted triangulation
- Contains key insight (sequence analysis)
- Everything else depends on it

**What you get:**
- Per-camera occlusion scores
- Soft weighting in triangulation
- Better camera selection
- Complete pipeline!

**Ready to start?** I've provided:
- ✅ Complete implementation code
- ✅ Unit tests
- ✅ Integration guide
- ✅ Testing strategy

Let me know if you want to start implementing or if you have questions about any part! 🎯
