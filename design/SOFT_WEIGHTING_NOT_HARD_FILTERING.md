# Soft Weighting vs Hard Filtering for Occlusion

## The User's Correction

**I said:** "Filter observations - keep only visible segment cameras"
**User corrected:** "We should PREFER visible segments, not exclude hidden ones"

**Absolutely right!**

---

## Why Hard Filtering is Wrong

### Problem: Edge Cases

**LED on exact side of tree:**
```
LED at θ=90° (between Camera 1 at 0° and Camera 3 at 180°)

Camera 1 occlusion: 0.6 (marginal - in transition zone)
Camera 2 occlusion: 0.4 (marginal - in transition zone)
Camera 3 occlusion: 0.7 (marginal - in transition zone)
Camera 4 occlusion: 0.5 (exactly on boundary)
Camera 5 occlusion: 0.6 (marginal)

Hard filter (threshold 0.5):
  filtered = []  ← All cameras excluded!
  
Result: Can't triangulate this LED at all!
```

**This is too strict!**

### Problem: Ambiguous Cases

**LED partially visible from multiple angles:**
```
LED wrapping around tree curve:

Camera 1: occlusion=0.3 (mostly visible)
Camera 2: occlusion=0.6 (slightly hidden)
Camera 3: occlusion=0.8 (mostly hidden)

Hard filter:
  Keep: Camera 1 only
  Throw away: Cameras 2 & 3 completely
  
But Camera 2 might still have useful info!
```

---

## Better Approach: Soft Weighting

### Weighted Preference

**Instead of filtering, apply weight penalty:**

```dart
For each observation:
  base_weight = detectionConfidence × angularConfidence
  
  occlusion_penalty = occlusion score from sequence analysis
  
  final_weight = base_weight × (1.0 - occlusion_penalty)
```

**Example:**
```
Camera 1:
  base_weight = 0.8 (good detection and centering)
  occlusion = 0.1 (visible segment)
  final_weight = 0.8 × (1.0 - 0.1) = 0.72 ✓

Camera 3:
  base_weight = 0.9 (excellent detection and centering!)
  occlusion = 0.9 (hidden segment)
  final_weight = 0.9 × (1.0 - 0.9) = 0.09 ✗

Picks: Camera 1 (0.72 > 0.09) ✓
```

**Camera 1 wins despite Camera 3 having better raw measurements!**

---

## Implementation

### Updated Triangulation Logic

```dart
static LED3DPosition? _triangulateWithRayCone(
  List<LEDObservation> observations,
  List<CameraPosition> cameraPositions,
  CameraGeometry cameraGeometry,
  ConeModel cone,
  Map<int, Map<int, double>> occlusion,  // NEW parameter!
  int ledIndex,  // NEW parameter!
) {
  if (observations.isEmpty) return null;
  
  // Calculate final weight for each observation
  final weightsWithOcclusion = observations.map((obs) {
    final baseWeight = obs.weight;  // detection × angular
    
    // Get occlusion score for this camera/LED
    final occlusionScore = occlusion[obs.cameraIndex]?[ledIndex] ?? 0.5;
    
    // Apply penalty: visible (0.0) = no penalty, hidden (1.0) = strong penalty
    final finalWeight = baseWeight * (1.0 - occlusionScore);
    
    return MapEntry(obs, finalWeight);
  }).toList();
  
  // Pick observation with highest final weight
  final best = weightsWithOcclusion.reduce((a, b) => 
    a.value > b.value ? a : b
  );
  
  final bestObs = best.key;
  final bestWeight = best.value;
  
  // Continue with triangulation using best observation...
  // (rest of existing code)
}
```

---

## Comparison: Hard Filter vs Soft Weight

### Scenario 1: Clear Visible Camera

```
LED 42:

Camera 1: base=0.8, occlusion=0.1
Camera 3: base=0.9, occlusion=0.9

Hard filter:
  Keep: [Camera 1] (occlusion < 0.5)
  Pick: Camera 1 ✓

Soft weight:
  Camera 1: 0.8 × 0.9 = 0.72
  Camera 3: 0.9 × 0.1 = 0.09
  Pick: Camera 1 ✓

Result: Same ✓
```

### Scenario 2: All Cameras Marginal (Edge Case)

```
LED at side of tree:

Camera 1: base=0.7, occlusion=0.6
Camera 2: base=0.8, occlusion=0.5
Camera 3: base=0.6, occlusion=0.7

Hard filter (threshold 0.5):
  Keep: [Camera 2] (exactly on threshold)
  Pick: Camera 2

Soft weight:
  Camera 1: 0.7 × 0.4 = 0.28
  Camera 2: 0.8 × 0.5 = 0.40 ✓ Best!
  Camera 3: 0.6 × 0.3 = 0.18
  Pick: Camera 2 ✓

Result: Same, but more graceful ✓
```

### Scenario 3: All Hidden (Extreme Edge)

```
LED somehow hidden from all cameras:
(Shouldn't happen, but possible in weird geometry)

Camera 1: base=0.3, occlusion=0.8
Camera 2: base=0.4, occlusion=0.9
Camera 3: base=0.5, occlusion=0.85

Hard filter:
  Keep: [] (all > 0.5)
  Result: Can't triangulate! ✗

Soft weight:
  Camera 1: 0.3 × 0.2 = 0.06
  Camera 2: 0.4 × 0.1 = 0.04
  Camera 3: 0.5 × 0.15 = 0.075 ✓ Best of bad options
  Pick: Camera 3
  Result: Still triangulates (with low confidence) ✓

Result: Soft weight handles edge case ✓
```

---

## Benefits of Soft Weighting

### 1. Graceful Degradation

**Hard filter:**
- Binary: include or exclude
- Can fail completely (no observations pass filter)
- All-or-nothing

**Soft weight:**
- Continuous: strong preference but not absolute
- Always picks something (even if all are suboptimal)
- Graceful handling of edge cases

### 2. Better Use of Information

**Hard filter:**
```
Camera 2: occlusion=0.51
→ Excluded completely (just over threshold)

Camera 3: occlusion=0.49
→ Included (just under threshold)

Tiny difference (0.02) causes dramatic difference in treatment!
```

**Soft weight:**
```
Camera 2: occlusion=0.51
→ weight × 0.49 (slight penalty)

Camera 3: occlusion=0.49
→ weight × 0.51 (slight bonus)

Proportional difference reflects actual confidence!
```

### 3. Natural Behavior

**What we want:**
- Visible segment observations strongly preferred ✓
- Hidden segment observations strongly penalized ✓
- But not completely thrown away ✓
- Smooth gradient from good to bad ✓

**Soft weighting achieves all of this!**

---

## Weight Penalty Function Options

### Option 1: Linear (Recommended)

```dart
final_weight = base_weight × (1.0 - occlusion_score)

occlusion=0.0 (visible) → penalty=0% → full weight
occlusion=0.5 (marginal) → penalty=50% → half weight
occlusion=1.0 (hidden) → penalty=100% → zero weight
```

**Simple and intuitive!**

### Option 2: Exponential (Stronger Preference)

```dart
final_weight = base_weight × exp(-3 × occlusion_score)

occlusion=0.0 → penalty=0% → weight × 1.0
occlusion=0.5 → penalty=78% → weight × 0.22
occlusion=1.0 → penalty=95% → weight × 0.05
```

**More aggressive preference for visible!**

### Option 3: Step Function (Softer Filter)

```dart
if (occlusion_score < 0.3):
  penalty = 0%           // Clearly visible
else if (occlusion_score < 0.7):
  penalty = 50%          // Ambiguous
else:
  penalty = 90%          // Clearly hidden

final_weight = base_weight × (1.0 - penalty)
```

**More interpretable thresholds!**

---

## Recommended Implementation

### Simple Linear Penalty

```dart
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
    final baseWeight = obs.weight;  // detection × angular
    final occlusionScore = occlusion[obs.cameraIndex]?[ledIndex] ?? 0.5;
    
    // Linear penalty: visible (0.0) = no penalty, hidden (1.0) = full penalty
    final finalWeight = baseWeight * (1.0 - occlusionScore);
    
    if (finalWeight > bestWeight) {
      bestWeight = finalWeight;
      bestObs = obs;
    }
  }
  
  // Triangulate using best observation
  // (existing ray-cone intersection code)
  // ...
  
  return LED3DPosition(
    // ...
    confidence: bestWeight,  // Use final weight as confidence
    // ...
  );
}
```

**Clean and simple!**

---

## Example: Complete Flow

### LED 42 with Occlusion Scores

**Observations:**
```
Camera 1: det=0.92, ang=0.87, base_weight=0.80
Camera 2: det=0.88, ang=0.76, base_weight=0.67
Camera 3: det=0.92, ang=1.00, base_weight=0.92  ← Best raw!
Camera 4: det=0.85, ang=0.71, base_weight=0.60
Camera 5: det=0.89, ang=0.85, base_weight=0.76
```

**Occlusion from sequence analysis:**
```
Camera 1: occlusion=0.05 (clearly visible)
Camera 2: occlusion=0.10 (clearly visible)
Camera 3: occlusion=0.92 (clearly hidden!)
Camera 4: occlusion=0.08 (clearly visible)
Camera 5: occlusion=0.12 (clearly visible)
```

**Final weights with penalty:**
```
Camera 1: 0.80 × (1.0 - 0.05) = 0.76
Camera 2: 0.67 × (1.0 - 0.10) = 0.60
Camera 3: 0.92 × (1.0 - 0.92) = 0.07  ← Massive penalty!
Camera 4: 0.60 × (1.0 - 0.08) = 0.55
Camera 5: 0.76 × (1.0 - 0.12) = 0.67

Best: Camera 1 (final_weight = 0.76)
```

**Result:** 
- Camera 1 selected (good view, clearly visible)
- Camera 3 rejected (best raw measurements, but hidden segment!)
- Correct choice! ✓

---

## Summary

**User's correction:**
> "We should PREFER visible segments, not exclude hidden ones"

**Why you're right:**

❌ **Hard filtering:**
- Can fail on edge cases (no cameras pass)
- Binary decision (all-or-nothing)
- Throws away potentially useful data

✅ **Soft weighting:**
- Always picks something (graceful degradation)
- Proportional preference (smooth gradient)
- Uses all information appropriately
- Visible observations naturally win

**Implementation:**
```dart
final_weight = base_weight × (1.0 - occlusion_score)

Pick: max(final_weight)
```

**Result:** Visible-segment cameras strongly preferred, but hidden-segment cameras still considered if needed.

**This is the right approach!** 🎯✨
