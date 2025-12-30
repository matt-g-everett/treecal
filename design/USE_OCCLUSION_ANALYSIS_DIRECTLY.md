# Using Occlusion Analysis to Filter Triangulation Observations

## The Better Approach

**User's insight:** 
> "We already have front/back surface analysis using neighbors and sequence detection. 
> Why not use that directly instead of detection confidence as a proxy?"

**Absolutely correct!**

---

## What We Have (Or Are Building)

### Per-Camera Occlusion Analysis

**For each camera, analyze LED sequence:**
```
Camera 1 detection sequence:
LED 0:  conf=0.92 ✓
LED 1:  conf=0.89 ✓
LED 2:  conf=0.87 ✓
...
LED 35: conf=0.82 ✓  } Visible segment
LED 36: conf=0.45 ↓
LED 37: conf=0.31 ✗
LED 38: not detected ✗
LED 39: not detected ✗  } Hidden segment (behind tree from this camera)
LED 40: conf=0.28 ✗
LED 41: conf=0.41 ↓
LED 42: conf=0.79 ↑
LED 43: conf=0.86 ✓  } Visible segment
...
```

**This tells us:**
- LEDs 0-35: Camera 1 has direct view
- LEDs 36-41: Camera 1 is blocked (LED facing away)
- LEDs 42+: Camera 1 has direct view again

**This is EXACTLY what we need!**

---

## Current Approach (Just Implemented)

### Using Detection Confidence as Proxy

```dart
// Pick best observation by weight
bestObs = observations.reduce((a, b) => 
  a.weight > b.weight ? a : b  // weight = detection × angular
);
```

**Problems with this:**
- ⚠️ Indirect - using detection as proxy for occlusion
- ⚠️ Doesn't use sequence context
- ⚠️ Doesn't use neighbor information
- ⚠️ Single-LED-at-a-time decision

---

## Better Approach: Use Occlusion Analysis Directly

### Two-Stage Pipeline

**Stage 1: Occlusion Analysis**
```dart
// For each camera, segment LED sequence
for (camera in cameras) {
  sequence = [LED 0 conf, LED 1 conf, ..., LED 199 conf]
  smoothed = movingAverage(sequence, window=5)
  segments = findSegments(smoothed, threshold=0.5)
  
  // Mark each LED as visible or hidden from this camera
  for (led in 0..199) {
    segment = findSegment(led, segments)
    occlusion[camera][led] = (segment.type == 'hidden') ? 1.0 : 0.0
  }
}
```

**Stage 2: Filtered Triangulation**
```dart
// For each LED, filter observations
for (led in 0..199) {
  observations = getAllObservations(led)
  
  // Filter: only use cameras where LED is in visible segment
  filtered = observations.filter(obs => 
    occlusion[obs.camera][led] < 0.5  // Not in hidden segment
  )
  
  if (filtered.isEmpty) {
    // All cameras see it as hidden - use best anyway
    filtered = observations
  }
  
  // Pick best from filtered set
  bestObs = filtered.reduce((a, b) => 
    a.weight > b.weight ? a : b
  )
  
  position = triangulate(bestObs)
}
```

---

## Why This Is Better

### 1. Uses Sequence Context

**Current approach:**
```
LED 42 from Camera 3:
  detection_conf = 0.31 (low)
  → Probably not great
```

**With occlusion analysis:**
```
LED 42 from Camera 3:
  detection_conf = 0.31 (low)
  BUT in context:
    LED 40: 0.28
    LED 41: 0.41
    LED 42: 0.31  ← Part of hidden segment!
    LED 43: 0.35
    LED 44: 0.29
  → Definitely hidden from this camera
  → EXCLUDE completely from triangulation
```

**Uses pattern, not single value!**

### 2. Uses Neighbor Information

**String continuity naturally captured:**
```
If LEDs 36-45 are hidden segment from Camera 1:
  - All these LEDs are facing away from Camera 1
  - Makes sense: they're on the "back" side
  - All should be excluded together
```

**Consistent treatment of neighbors!**

### 3. More Robust

**Single LED with noise:**
```
LED 40: 0.89 ✓
LED 41: 0.91 ✓
LED 42: 0.35 ✗ ← Detection failed (noise)
LED 43: 0.87 ✓
LED 44: 0.90 ✓

Context: Surrounded by visible → Probably still visible
Don't exclude based on single low value
```

**Sequence analysis handles noise better!**

### 4. Direct, Not Proxy

**Current:**
- Detection confidence → Proxy for occlusion → Filter cameras

**Better:**
- Sequence analysis → Direct occlusion measurement → Filter cameras

**No inference needed!**

---

## Implementation

### Step 1: Occlusion Analysis Service

```dart
class OcclusionAnalyzer {
  
  /// Analyze detection sequences to identify occlusion per camera
  /// Returns: occlusion[cameraIndex][ledIndex] = 0.0 (visible) or 1.0 (hidden)
  static Map<int, Map<int, double>> analyzePerCamera({
    required Map<int, List<LEDObservation>> observationsByCamera,
    required int totalLEDs,
    double visibilityThreshold = 0.5,
    int smoothingWindow = 5,
  }) {
    
    final occlusion = <int, Map<int, double>>{};
    
    for (final entry in observationsByCamera.entries) {
      final cameraIndex = entry.key;
      final observations = entry.value;
      
      // Build confidence sequence
      final sequence = List<double>.filled(totalLEDs, 0.0);
      for (final obs in observations) {
        sequence[obs.ledIndex] = obs.detectionConfidence;
      }
      
      // Smooth to reduce noise
      final smoothed = _movingAverage(sequence, smoothingWindow);
      
      // Find segments
      final segments = _findSegments(smoothed, visibilityThreshold);
      
      // Score each LED
      occlusion[cameraIndex] = {};
      for (int led = 0; led < totalLEDs; led++) {
        final segment = segments.firstWhere(
          (s) => s.startLED <= led && led <= s.endLED,
        );
        
        // Hidden segment = high occlusion
        // Visible segment = low occlusion
        occlusion[cameraIndex]![led] = 
          segment.type == 'hidden' ? 1.0 : 0.0;
      }
    }
    
    return occlusion;
  }
  
  static List<double> _movingAverage(List<double> data, int window) {
    final result = <double>[];
    for (int i = 0; i < data.length; i++) {
      final start = max(0, i - window ~/ 2);
      final end = min(data.length, i + window ~/ 2 + 1);
      final avg = data.sublist(start, end).reduce((a, b) => a + b) / (end - start);
      result.add(avg);
    }
    return result;
  }
  
  static List<Segment> _findSegments(List<double> smoothed, double threshold) {
    final segments = <Segment>[];
    bool inVisible = smoothed[0] > threshold;
    int segmentStart = 0;
    
    for (int i = 1; i < smoothed.length; i++) {
      final wasVisible = inVisible;
      final isVisible = smoothed[i] > threshold;
      
      if (wasVisible != isVisible) {
        // Segment boundary
        segments.add(Segment(
          startLED: segmentStart,
          endLED: i - 1,
          type: wasVisible ? 'visible' : 'hidden',
        ));
        segmentStart = i;
        inVisible = isVisible;
      }
    }
    
    // Add final segment
    segments.add(Segment(
      startLED: segmentStart,
      endLED: smoothed.length - 1,
      type: inVisible ? 'visible' : 'hidden',
    ));
    
    return segments;
  }
}

class Segment {
  final int startLED;
  final int endLED;
  final String type;  // 'visible' or 'hidden'
  
  Segment({
    required this.startLED,
    required this.endLED,
    required this.type,
  });
}
```

### Step 2: Update Triangulation to Use Occlusion

```dart
class TriangulationService {
  
  static List<LED3DPosition> triangulate({
    required List<Map<String, dynamic>> allDetections,
    required List<CameraPosition> cameraPositions,
    // ... other params
  }) {
    
    // Group observations by camera and LED
    final observationsByCamera = <int, List<LEDObservation>>{};
    final observationsByLed = <int, List<LEDObservation>>{};
    
    for (final detection in allDetections) {
      // ... parse detection ...
      final obs = LEDObservation(...);
      
      observationsByCamera
        .putIfAbsent(obs.cameraIndex, () => [])
        .add(obs);
      
      observationsByLed
        .putIfAbsent(obs.ledIndex, () => [])
        .add(obs);
    }
    
    // STEP 1: Analyze occlusion patterns
    final occlusion = OcclusionAnalyzer.analyzePerCamera(
      observationsByCamera: observationsByCamera,
      totalLEDs: 200,
    );
    
    // STEP 2: Triangulate each LED with filtered observations
    final positions = <LED3DPosition>[];
    
    for (int ledIndex = 0; ledIndex < 200; ledIndex++) {
      final observations = observationsByLed[ledIndex];
      if (observations == null || observations.isEmpty) continue;
      
      // Filter: only cameras where LED is visible
      final filtered = observations.where((obs) {
        final occlusionScore = occlusion[obs.cameraIndex]?[ledIndex] ?? 0.5;
        return occlusionScore < 0.5;  // Not in hidden segment
      }).toList();
      
      // If all cameras see it as hidden, use best anyway
      final toUse = filtered.isNotEmpty ? filtered : observations;
      
      // Pick best from filtered set
      final triangulated = _triangulateWithRayCone(
        toUse,
        cameraPositions,
        // ...
      );
      
      if (triangulated != null) {
        positions.add(triangulated);
      }
    }
    
    return positions;
  }
}
```

---

## Example: LED 42

### Current Approach (Detection Confidence)

```
LED 42 observations:

Camera 1: det_conf=0.92, ang_conf=0.87 → weight=0.80 ✓
Camera 2: det_conf=0.88, ang_conf=0.76 → weight=0.67
Camera 3: det_conf=0.31, ang_conf=0.92 → weight=0.29
Camera 4: det_conf=0.85, ang_conf=0.71 → weight=0.60
Camera 5: det_conf=0.89, ang_conf=0.85 → weight=0.76

Picks: Camera 1 (weight=0.80)
```

**Good, but doesn't use sequence context.**

### Better Approach (Occlusion Analysis)

```
LED 42 observations with occlusion:

Camera 1: weight=0.80, occlusion=0.0 (visible segment) ✓
Camera 2: weight=0.67, occlusion=0.0 (visible segment) ✓
Camera 3: weight=0.29, occlusion=1.0 (HIDDEN segment) ✗ FILTERED OUT!
Camera 4: weight=0.60, occlusion=0.0 (visible segment) ✓
Camera 5: weight=0.76, occlusion=0.0 (visible segment) ✓

Filtered to: [Camera 1, 2, 4, 5]
Picks: Camera 1 (weight=0.80)
```

**Better! Camera 3 excluded because LED 42 is in a hidden segment (LEDs 36-45 all low confidence).**

---

## Benefits Summary

### Using Occlusion Analysis Directly

✅ **Uses sequence patterns** (not single values)
✅ **Uses neighbor context** (string continuity)
✅ **More robust to noise** (smoothing, segments)
✅ **Direct measurement** (not proxy)
✅ **Consistent with neighbors** (whole segments filtered)

### vs Using Detection Confidence

⚠️ Single-value decision
⚠️ No neighbor context
⚠️ Indirect (proxy)
⚠️ More sensitive to noise

---

## Implementation Priority

**Order:**
1. ✅ Simple best-observation (DONE)
2. → Implement `OcclusionAnalyzer` service
3. → Update triangulation to filter using occlusion
4. → Test and validate

**This is the right way!**

---

## Summary

**User's insight:** 
> "We already analyze front/back with neighbors and sequence detection. 
> Use that directly instead of detection confidence."

**You're absolutely right!**

**Why this is better:**
- Uses the sequence analysis we've been designing
- Takes neighbor context into account
- More robust than single-value proxy
- Direct measurement, not inference

**Next step:** Implement `OcclusionAnalyzer` to segment sequences, then use it to filter triangulation observations.

**This completes the design properly!** 🎯✨
