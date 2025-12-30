# Occlusion Handling: Weighting vs Hard Filtering

## The Distinction

### What I Suggested (Wrong)

**Hard filtering - completely exclude hidden segments:**
```dart
// EXCLUDE hidden segment observations
filtered = observations.where(obs => 
  occlusion[obs.camera][led] < 0.5  // Only visible
)

if (filtered.isEmpty) {
  // Fallback to all if none visible
  filtered = observations
}

bestObs = filtered.max_by(weight)
```

**Problem:** Binary decision - use or don't use

---

### What User Suggests (Better)

**Soft weighting - prefer visible but allow hidden as fallback:**
```dart
// KEEP all observations
// But weight them by visibility

bestObs = observations.max_by(obs => {
  final visibilityWeight = occlusion[obs.camera][led] < 0.5 
    ? 1.0   // Visible segment
    : 0.2;  // Hidden segment (5× penalty)
  
  return obs.weight × visibilityWeight;
})
```

**Benefit:** Graceful degradation

---

## Why Weighting Is Better

### 1. Handles Edge Cases

**Scenario: LED on exact side of tree (90° from all cameras)**

```
All 5 cameras mark LED as "in transition" or "hidden segment"

With hard filtering:
  filtered = []  (all excluded!)
  Fallback to all observations
  → Same as if we hadn't done occlusion analysis!

With weighting:
  All get low weight (× 0.2)
  Still pick best of bad options
  → At least uses relative quality
```

**Weighting handles this naturally!**

### 2. Smooth Transitions

**Scenario: LED gradually rotating from visible to hidden**

```
Camera 1 view as LED rotates:

LED at θ=45° (mostly facing camera):
  Visible segment, high detection confidence
  Adjusted weight = 0.92 × 1.0 = 0.92 ✓

LED at θ=75° (edge of visible):
  Still visible segment (but borderline)
  Adjusted weight = 0.68 × 1.0 = 0.68 ✓

LED at θ=95° (just past edge):
  Hidden segment starts
  Adjusted weight = 0.52 × 0.2 = 0.104 ↓

LED at θ=120° (clearly hidden):
  Hidden segment
  Adjusted weight = 0.31 × 0.2 = 0.062 ↓
```

**Smooth degradation, not cliff edge!**

### 3. Multiple Cameras Agreement

**Scenario: Some cameras see it, some don't**

```
LED 42:

Camera 1: visible segment, weight=0.89 → adjusted=0.89 × 1.0 = 0.89
Camera 2: visible segment, weight=0.76 → adjusted=0.76 × 1.0 = 0.76
Camera 3: hidden segment,  weight=0.82 → adjusted=0.82 × 0.2 = 0.164
Camera 4: visible segment, weight=0.71 → adjusted=0.71 × 1.0 = 0.71
Camera 5: visible segment, weight=0.85 → adjusted=0.85 × 1.0 = 0.85

Best: Camera 1 (adjusted=0.89) ✓
```

**Even though Camera 3 has decent raw weight (0.82), the visibility penalty (×0.2) makes it lose to visible-segment cameras.**

**But if ALL cameras were in hidden segments:**
```
Camera 1: hidden, weight=0.45 → adjusted=0.09
Camera 2: hidden, weight=0.38 → adjusted=0.076
Camera 3: hidden, weight=0.52 → adjusted=0.104 ← Best of bad options
Camera 4: hidden, weight=0.41 → adjusted=0.082
Camera 5: hidden, weight=0.47 → adjusted=0.094

Best: Camera 3 (adjusted=0.104)
```

**Still picks the relatively best camera, even though all are hidden!**

---

## Implementation

### Adjusted Weight Calculation

```dart
double calculateAdjustedWeight(
  LEDObservation obs,
  Map<int, Map<int, double>> occlusion,
  int ledIndex,
) {
  // Base weight (already exists)
  final baseWeight = obs.detectionConfidence × obs.angularConfidence;
  
  // Visibility multiplier based on occlusion analysis
  final occlusionScore = occlusion[obs.cameraIndex]?[ledIndex] ?? 0.5;
  
  // Visible segment (low occlusion) = 1.0 multiplier
  // Hidden segment (high occlusion) = 0.2 multiplier (5× penalty)
  final visibilityMultiplier = occlusionScore < 0.5 
    ? 1.0           // Visible
    : 0.2;          // Hidden (strong penalty)
  
  return baseWeight × visibilityMultiplier;
}
```

### Triangulation with Weighted Selection

```dart
static LED3DPosition? _triangulateWithRayCone(
  List<LEDObservation> observations,
  List<CameraPosition> cameraPositions,
  CameraGeometry cameraGeometry,
  ConeModel cone,
  Map<int, Map<int, double>> occlusion,  // NEW parameter
  int ledIndex,                           // NEW parameter
) {
  if (observations.isEmpty) return null;
  
  // Pick observation with highest ADJUSTED weight
  // Accounts for: detection quality × viewing angle × visibility
  final bestObs = observations.reduce((a, b) {
    final weightA = calculateAdjustedWeight(a, occlusion, ledIndex);
    final weightB = calculateAdjustedWeight(b, occlusion, ledIndex);
    return weightA > weightB ? a : b;
  });
  
  // ... rest of triangulation using bestObs ...
}
```

---

## Choosing the Penalty Factor

### Different Penalty Options

**Very strong penalty (0.1):**
```
visible = 1.0
hidden = 0.1  (10× difference)

Effect: Almost never uses hidden segments
Good for: Very confident occlusion analysis
Risk: Edge cases might suffer
```

**Strong penalty (0.2):**
```
visible = 1.0
hidden = 0.2  (5× difference)

Effect: Strong preference for visible, but hidden usable
Good for: Normal operation (RECOMMENDED)
Balance: Visible wins unless much lower quality
```

**Moderate penalty (0.5):**
```
visible = 1.0
hidden = 0.5  (2× difference)

Effect: Visible preferred but not dominant
Good for: Conservative approach
Risk: Might pick hidden when shouldn't
```

**Recommendation: Start with 0.2 (5× penalty)**

---

## Example Scenarios

### Scenario 1: Clear Winner

```
LED 42:
  Camera 1: visible, base_weight=0.92 → adjusted=0.92
  Camera 3: hidden,  base_weight=0.85 → adjusted=0.17

Even though Camera 3 has good base weight (0.85),
visible Camera 1 wins easily (0.92 >> 0.17) ✓
```

### Scenario 2: Poor Visible vs Good Hidden

```
LED 42:
  Camera 1: visible, base_weight=0.31 → adjusted=0.31
  Camera 3: hidden,  base_weight=0.88 → adjusted=0.176

Visible Camera 1 still wins (0.31 > 0.176)
Even though Camera 3 has much better raw quality! ✓

This is correct: visible segment more trustworthy
even with lower raw detection
```

### Scenario 3: All Hidden (Edge Case)

```
LED 90 (on exact side of tree):
  Camera 1: hidden, base_weight=0.45 → adjusted=0.09
  Camera 2: hidden, base_weight=0.52 → adjusted=0.104 ← Best
  Camera 3: hidden, base_weight=0.38 → adjusted=0.076
  Camera 4: hidden, base_weight=0.41 → adjusted=0.082
  Camera 5: hidden, base_weight=0.47 → adjusted=0.094

Picks Camera 2 (best of bad options) ✓
Doesn't fail completely
```

### Scenario 4: Very Poor Visible vs Very Good Hidden

```
LED 42:
  Camera 1: visible, base_weight=0.12 → adjusted=0.12
  Camera 3: hidden,  base_weight=0.95 → adjusted=0.19

Hidden Camera 3 wins! (0.19 > 0.12)

This is rare but correct: if visible camera has terrible quality
and hidden camera has excellent quality, use the hidden one.
```

**System is flexible enough to handle edge cases!**

---

## Continuous Occlusion Score

### Even Better: Use Continuous Value

**Instead of binary threshold:**
```dart
// Binary:
visibilityMultiplier = occlusion < 0.5 ? 1.0 : 0.2

// Continuous:
// occlusion ranges from 0.0 (clearly visible) to 1.0 (clearly hidden)
// Map to multiplier range [1.0 to 0.2]
visibilityMultiplier = 1.0 - (occlusion × 0.8)

Examples:
  occlusion=0.0 (visible) → multiplier=1.0
  occlusion=0.2 (mostly visible) → multiplier=0.84
  occlusion=0.5 (ambiguous) → multiplier=0.6
  occlusion=0.8 (mostly hidden) → multiplier=0.36
  occlusion=1.0 (hidden) → multiplier=0.2
```

**Even smoother transitions!**

---

## Implementation in Occlusion Analyzer

### Return Continuous Scores

```dart
class OcclusionAnalyzer {
  
  /// Returns continuous occlusion scores [0.0 to 1.0]
  /// 0.0 = clearly visible (center of visible segment)
  /// 0.5 = ambiguous (segment boundary)
  /// 1.0 = clearly hidden (center of hidden segment)
  static Map<int, Map<int, double>> analyzePerCamera({
    required Map<int, List<LEDObservation>> observationsByCamera,
    required int totalLEDs,
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
      final smoothed = _movingAverage(sequence, window: 5);
      
      // Normalize to [0, 1] where 0=hidden, 1=visible
      final maxConf = smoothed.reduce(max);
      final normalized = smoothed.map((s) => s / max(maxConf, 0.01)).toList();
      
      // Invert: 0=visible, 1=hidden
      occlusion[cameraIndex] = {};
      for (int led = 0; led < totalLEDs; led++) {
        occlusion[cameraIndex]![led] = 1.0 - normalized[led];
      }
    }
    
    return occlusion;
  }
}
```

**This gives continuous occlusion scores naturally!**

---

## Complete Pipeline with Weighting

```dart
class TriangulationService {
  
  static List<LED3DPosition> triangulate({
    required List<Map<String, dynamic>> allDetections,
    required List<CameraPosition> cameraPositions,
    // ... other params
  }) {
    
    // Group observations
    final observationsByCamera = <int, List<LEDObservation>>{};
    final observationsByLed = <int, List<LEDObservation>>{};
    // ... populate ...
    
    // STEP 1: Analyze occlusion (continuous scores)
    final occlusion = OcclusionAnalyzer.analyzePerCamera(
      observationsByCamera: observationsByCamera,
      totalLEDs: 200,
    );
    
    // STEP 2: Triangulate with weighted selection
    final positions = <LED3DPosition>[];
    
    for (int ledIndex = 0; ledIndex < 200; ledIndex++) {
      final observations = observationsByLed[ledIndex];
      if (observations == null || observations.isEmpty) continue;
      
      // Pick best with visibility weighting (NO filtering!)
      final triangulated = _triangulateWithRayCone(
        observations,
        cameraPositions,
        cameraGeometry,
        cone,
        occlusion,   // Pass occlusion scores
        ledIndex,    // Pass LED index
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
    Map<int, Map<int, double>> occlusion,
    int ledIndex,
  ) {
    if (observations.isEmpty) return null;
    
    // Pick best with WEIGHTED selection
    final bestObs = observations.reduce((a, b) {
      // Base weights
      final weightA = a.detectionConfidence × a.angularConfidence;
      final weightB = b.detectionConfidence × b.angularConfidence;
      
      // Visibility multipliers (continuous)
      final occlusionA = occlusion[a.cameraIndex]?[ledIndex] ?? 0.5;
      final occlusionB = occlusion[b.cameraIndex]?[ledIndex] ?? 0.5;
      
      final visMultA = 1.0 - (occlusionA × 0.8);  // Maps [0,1] to [1.0,0.2]
      final visMultB = 1.0 - (occlusionB × 0.8);
      
      // Adjusted weights
      final adjWeightA = weightA × visMultA;
      final adjWeightB = weightB × visMultB;
      
      return adjWeightA > adjWeightB ? a : b;
    });
    
    // Triangulate using best observation
    // ... existing code ...
  }
}
```

---

## Benefits of Weighting Approach

✅ **Graceful degradation** - handles edge cases
✅ **Smooth transitions** - no binary cliff edges  
✅ **Flexible** - visible strongly preferred but not absolute
✅ **Robust** - never completely fails (always picks something)
✅ **Continuous** - can use continuous occlusion scores
✅ **Balanced** - visible wins unless much lower quality

---

## Summary

**Hard filtering (what I suggested):**
```dart
// Exclude hidden segments
filtered = observations.where(occlusion < 0.5)
bestObs = filtered.max_by(weight)
```
❌ Binary decision
❌ Fails on edge cases
❌ Cliff-edge transitions

**Soft weighting (what you suggested):**
```dart
// Weight by visibility
adjustedWeight = weight × visibilityMultiplier
bestObs = observations.max_by(adjustedWeight)
```
✅ Smooth degradation
✅ Handles all cases
✅ Flexible preference

**Your approach is much better!** 🎯

**Implementation:**
- Occlusion analyzer returns continuous scores [0.0 to 1.0]
- Triangulation multiplies base weight by visibility weight
- Visible segments strongly preferred (5×) but not absolute
- Edge cases handled gracefully

**This is the right design!**
