# Per-Camera Occlusion Detection Using String Sequences

## Why Cross-Camera Approach is Wrong

### The Flaw in My Thinking

**I said:**
```
"Count how many cameras saw the LED"
"More cameras = front surface"
"Fewer cameras = back surface"
```

**Why this is wrong:**

```
        Camera 1 (0°)
            |
            |
           🎄
          /   \
    LED 42    LED 43
    (visible) (hidden)
            
        Camera 3 (180°)
            |
            |
           🎄
          /   \
    LED 42    LED 43
    (hidden)  (visible)
```

**From Camera 1:** LED 42 is front, LED 43 is back
**From Camera 3:** LED 42 is back, LED 43 is front

**"Front" and "back" are camera-relative, not absolute!**

Counting cameras that saw an LED doesn't tell us which surface it's on in absolute space.

---

## Your Better Approach: Per-Camera Sequence Analysis

### Key Insight: String Continuity PER CAMERA

**The LED string spirals around the tree:**
```
LED sequence: 0 → 1 → 2 → 3 → ... → 199

From any single camera:
- Some LEDs are visible (facing camera)
- Some LEDs are hidden (behind tree)
- Pattern is sequential due to spiral!
```

**Example from Camera 1:**
```
LEDs 0-35:   Visible (high confidence)
LEDs 36-45:  Hidden (low/no confidence) ← Behind tree!
LEDs 46-80:  Visible (high confidence)
LEDs 81-90:  Hidden (low/no confidence) ← Behind tree!
LEDs 91-125: Visible (high confidence)
...
```

**This is a SEQUENCE pattern!**

### Detection Pattern Analysis

**Per camera, analyze the string sequence:**

```dart
For Camera N:
  sequence = [LED 0 confidence, LED 1 confidence, ..., LED 199 confidence]
  
  Identify segments:
    - Visible segment: Consecutive high-confidence detections
    - Hidden segment: Consecutive low/missing detections
  
  Mark each LED:
    - If in visible segment → "visible from camera N"
    - If in hidden segment → "hidden from camera N"
```

**Example:**
```
Camera 1 sequence:
LED   0: 0.92 ✓
LED   1: 0.89 ✓
LED   2: 0.87 ✓
LED   3: 0.91 ✓  } Visible segment
LED   4: 0.88 ✓
LED   5: 0.85 ✓
LED   6: 0.82 ✓
LED   7: 0.45 ↓
LED   8: 0.31 ✗
LED   9: not detected ✗  } Hidden segment
LED  10: 0.28 ✗
LED  11: 0.41 ↓
LED  12: 0.79 ↑
LED  13: 0.86 ✓
LED  14: 0.91 ✓  } Visible segment
...
```

**Pattern is clear: Visible → Hidden → Visible → Hidden**

This follows the spiral!

---

## Algorithm: Per-Camera Occlusion Detection

### Step 1: Segment Detection Sequence

```dart
class Segment {
  final int startLED;
  final int endLED;
  final String type;  // 'visible' or 'hidden'
  final double avgConfidence;
}

List<Segment> segmentSequence(List<Detection> detections, int totalLEDs) {
  final confidence = List<double>.filled(totalLEDs, 0.0);
  
  // Fill confidence array
  for (final detection in detections) {
    confidence[detection.ledIndex] = detection.confidence;
  }
  
  // Smooth with moving average to reduce noise
  final smoothed = movingAverage(confidence, windowSize: 5);
  
  // Find segments
  final segments = <Segment>[];
  bool inVisible = smoothed[0] > 0.5;
  int segmentStart = 0;
  
  for (int i = 1; i < totalLEDs; i++) {
    final wasVisible = inVisible;
    final isVisible = smoothed[i] > 0.5;
    
    if (wasVisible != isVisible) {
      // Segment boundary
      segments.add(Segment(
        startLED: segmentStart,
        endLED: i - 1,
        type: wasVisible ? 'visible' : 'hidden',
        avgConfidence: average(confidence[segmentStart..i]),
      ));
      
      segmentStart = i;
      inVisible = isVisible;
    }
  }
  
  // Add final segment
  segments.add(Segment(
    startLED: segmentStart,
    endLED: totalLEDs - 1,
    type: inVisible ? 'visible' : 'hidden',
    avgConfidence: average(confidence[segmentStart..]),
  ));
  
  return segments;
}
```

### Step 2: Per-LED Occlusion Score

```dart
double occlusionScore(int ledIndex, List<Segment> segments) {
  // Find which segment this LED is in
  final segment = segments.firstWhere(
    (s) => s.startLED <= ledIndex && ledIndex <= s.endLED
  );
  
  if (segment.type == 'visible') {
    return 1.0 - segment.avgConfidence;  // High conf = low occlusion
  } else {
    return 0.8 + 0.2 * (1.0 - segment.avgConfidence);  // Hidden segment
  }
}
```

### Step 3: Aggregate Across Cameras

```dart
Map<int, double> aggregateOcclusion(
  Map<int, List<Detection>> detectionsByCamera,
  int totalLEDs,
) {
  final occlusionScores = <int, List<double>>{};
  
  // For each camera
  for (final cameraDetections in detectionsByCamera.values) {
    final segments = segmentSequence(cameraDetections, totalLEDs);
    
    for (int led = 0; led < totalLEDs; led++) {
      final score = occlusionScore(led, segments);
      occlusionScores.putIfAbsent(led, () => []).add(score);
    }
  }
  
  // Average occlusion across cameras
  return occlusionScores.map(
    (led, scores) => MapEntry(led, average(scores))
  );
}
```

---

## Why This is Better

### 1. Respects Camera-Relative Nature

**Each camera independently analyzes its own view:**
- "From my angle, LEDs 36-45 are hidden"
- "From my angle, LEDs 0-35 are visible"

**No confusion about absolute "front" vs "back"**

### 2. Uses Sequential Structure

**Spiral pattern creates natural segments:**
```
Camera view: V V V V H H H V V V V V H H H V V V
             └─────┘ └───┘ └───────┘ └───┘ └───┘
             visible hidden  visible  hidden visible
```

**Gaps in sequence = occlusion!**

### 3. Handles Noise Better

**Single missed detection:**
```
LED 40: 0.89 ✓
LED 41: 0.91 ✓
LED 42: not detected ✗ ← Noise? Or occlusion?
LED 43: 0.87 ✓
LED 44: 0.90 ✓

Context: Surrounded by visible → Probably noise
         (Detection failed, but LED is visible)
```

**Sequential gap:**
```
LED 40: 0.89 ✓
LED 41: 0.91 ✓
LED 42: not detected ✗
LED 43: 0.31 ✗
LED 44: 0.28 ✗  ← Clear pattern!
LED 45: not detected ✗
LED 46: 0.42 ↓
LED 47: 0.79 ✓

Context: Sequential gap → Definitely occlusion
         (LEDs 42-46 hidden behind tree)
```

### 4. Smooth Transitions

**Segment boundaries aren't sharp:**
```
Visible segment:  ...0.89, 0.91, 0.87, 0.82, 0.76 ← Fading
Transition:                                   0.64, 0.51, 0.43 ← Edge
Hidden segment:                                           0.31, 0.28, not detected...
```

**Moving average smooths this:**
```
Smoothed: ...0.89, 0.88, 0.85, 0.78, 0.69, 0.58, 0.47, 0.34...
          └────────────────visible─────────┘  └────hidden────┘
                                        threshold (0.5)
```

---

## Example: Complete Analysis

### Camera 1 View (at 0°)

**Raw detections:**
```
LEDs   0-30:  High confidence (0.8-0.95)
LEDs  31-35:  Decreasing (0.75, 0.68, 0.54, 0.47, 0.39)
LEDs  36-50:  Low/missing (0.2-0.3 or not detected)
LEDs  51-55:  Increasing (0.38, 0.51, 0.66, 0.79, 0.87)
LEDs  56-85:  High confidence (0.8-0.95)
LEDs  86-90:  Decreasing...
LEDs  91-105: Low/missing...
LEDs 106-110: Increasing...
LEDs 111-199: High confidence...
```

**Segmentation:**
```
Segment 1: LEDs   0-30  (visible, avg conf 0.88)
Segment 2: LEDs  31-55  (transition/hidden, avg conf 0.42)
Segment 3: LEDs  56-85  (visible, avg conf 0.89)
Segment 4: LEDs  86-110 (transition/hidden, avg conf 0.45)
Segment 5: LEDs 111-199 (visible, avg conf 0.90)
```

**Occlusion scores:**
```
LEDs   0-30:  Low occlusion (0.12)
LEDs  31-55:  High occlusion (0.58)  ← Hidden from camera 1
LEDs  56-85:  Low occlusion (0.11)
LEDs  86-110: High occlusion (0.55)  ← Hidden from camera 1
LEDs 111-199: Low occlusion (0.10)
```

### Combine with Geometry

```dart
For LED 42 (in hidden segment from camera 1):

Per-camera evidence:
  Camera 1: High occlusion (0.58)
  Camera 2: Moderate occlusion (0.41)
  Camera 3: Low occlusion (0.15)  ← Visible from opposite side!
  Camera 4: Moderate occlusion (0.48)
  Camera 5: High occlusion (0.62)
  
  Average occlusion: 0.45 (moderately hidden overall)

Geometric evidence:
  front_candidate: h=0.52, θ=60°
  back_candidate: h=0.51, θ=65°
  
  Neighbors suggest front

Combined decision:
  Moderate occlusion + front geometry
  → Front surface (but mark confidence 0.6 due to occlusion)
```

---

## Implementation

### New Function: Sequence Segmentation

```dart
class OcclusionAnalyzer {
  
  /// Analyze detection sequence for occlusion patterns
  static Map<int, double> analyzeOcclusion({
    required Map<int, List<LEDObservation>> observationsByCamera,
    required int totalLEDs,
    double visibilityThreshold = 0.5,
    int smoothingWindow = 5,
  }) {
    
    final occlusionByLED = <int, List<double>>{};
    
    // Analyze each camera independently
    for (final cameraObs in observationsByCamera.values) {
      final segments = _segmentSequence(
        cameraObs, 
        totalLEDs, 
        visibilityThreshold,
        smoothingWindow,
      );
      
      // Score each LED based on its segment
      for (int led = 0; led < totalLEDs; led++) {
        final score = _occlusionScore(led, segments);
        occlusionByLED.putIfAbsent(led, () => []).add(score);
      }
    }
    
    // Average across cameras
    return occlusionByLED.map(
      (led, scores) => MapEntry(
        led, 
        scores.reduce((a, b) => a + b) / scores.length
      ),
    );
  }
  
  static List<Segment> _segmentSequence(
    List<LEDObservation> observations,
    int totalLEDs,
    double threshold,
    int window,
  ) {
    // Build confidence array
    final confidence = List<double>.filled(totalLEDs, 0.0);
    for (final obs in observations) {
      confidence[obs.ledIndex] = obs.detectionConfidence;
    }
    
    // Smooth with moving average
    final smoothed = _movingAverage(confidence, window);
    
    // Find segments
    return _findSegments(smoothed, threshold);
  }
  
  static double _occlusionScore(int ledIndex, List<Segment> segments) {
    final segment = segments.firstWhere(
      (s) => s.startLED <= ledIndex && ledIndex <= s.endLED,
      orElse: () => Segment(0, 0, 'visible', 1.0),
    );
    
    if (segment.type == 'visible') {
      return 1.0 - segment.avgConfidence;
    } else {
      return 0.7 + 0.3 * (1.0 - segment.avgConfidence);
    }
  }
}
```

---

## Advantages Summary

### Your Approach vs Mine

**My approach (wrong):**
- ❌ Count cameras that saw LED
- ❌ Treats "front/back" as absolute
- ❌ Ignores sequential structure
- ❌ Cross-camera comparison

**Your approach (better):**
- ✅ Analyze sequence per camera
- ✅ Respects camera-relative occlusion
- ✅ Uses spiral pattern
- ✅ Per-camera independent analysis

### Why It Works

1. **Physical basis:** LEDs spiral around tree
2. **Observable pattern:** Visible → Hidden → Visible segments
3. **Noise robust:** Uses sequence context
4. **Camera independent:** Each camera analyzes its own view
5. **Aggregatable:** Average occlusion scores across cameras

---

## Example Output

```json
{
  "led_index": 42,
  "occlusion_analysis": {
    "camera_1": {
      "segment": "hidden",
      "segment_confidence": 0.31,
      "occlusion_score": 0.69
    },
    "camera_2": {
      "segment": "transition",
      "segment_confidence": 0.54,
      "occlusion_score": 0.46
    },
    "camera_3": {
      "segment": "visible",
      "segment_confidence": 0.89,
      "occlusion_score": 0.11
    },
    "camera_4": {
      "segment": "hidden",
      "segment_confidence": 0.28,
      "occlusion_score": 0.72
    },
    "camera_5": {
      "segment": "hidden",
      "segment_confidence": 0.35,
      "occlusion_score": 0.65
    },
    "average_occlusion": 0.53
  }
}
```

---

## Conclusion

**You're absolutely right!**

- ❌ Cross-camera counting doesn't work (front/back is relative)
- ✅ Per-camera sequence analysis does work (uses spiral structure)

**Key insight:** Each camera independently analyzes the LED string sequence to identify occlusion patterns, respecting that visibility is camera-relative.

**This is much smarter!** 🎯✨
