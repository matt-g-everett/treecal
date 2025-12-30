# Front/Back Determination - Coordinate System Correction

## The Issue

**Wrong approach (what I showed):**
```json
"candidates": {
  "front": {"x": 0.234, "y": 0.412, "z": 1.056},
  "back": {"x": 0.189, "y": 0.398, "z": 1.032}
}
```

**Problem:** Working in Cartesian (x, y, z) loses the cone structure!

## Why Cone Coordinates?

### 1. Natural Representation

We're working on a **cone surface**, so cone coordinates are natural:

```
(height, angle, radius)
```

Where:
- `height`: 0-1 (normalized vertical position)
- `angle`: 0-360° (around the cone)
- `radius`: meters from center axis (determined by height on cone)

### 2. Better Distance Metric

**Cartesian distance is misleading:**
```python
# Front: (0.234, 0.412, 1.056)
# Back:  (0.189, 0.398, 1.032)
distance = sqrt((0.234-0.189)² + (0.412-0.398)² + (1.056-1.032)²)
        = 0.052m  # Seems close!
```

**But they're on OPPOSITE surfaces!** The angle might be very different.

**Cone distance is more meaningful:**
```python
# Front: (h=0.528, θ=60.2°, r=0.476)
# Back:  (h=0.516, θ=64.8°, r=0.474)

Δh = |0.528 - 0.516| = 0.012  # Very close in height
Δθ = |60.2 - 64.8| = 4.6°     # Small angle difference
Δr = |0.476 - 0.474| = 0.002  # Almost same radius

arc_distance = r × Δθ (in radians) ≈ 0.038m  # Real separation
height_distance = 0.012 × tree_height ≈ 0.024m
```

### 3. Angle Wrapping

**Cartesian doesn't handle wraparound:**
```
LED at θ=2° and LED at θ=358°
Cartesian: Looks far apart
Cone: Actually 4° apart! (wraps around)
```

**This is CRITICAL for string continuity!**

### 4. String Topology

LEDs spiral around the tree:
```
LED 0:   h=0.00, θ=0°
LED 1:   h=0.01, θ=10°
LED 2:   h=0.02, θ=20°
...
LED 36:  h=0.36, θ=0°   ← Back to 0° (wrapped)
LED 37:  h=0.37, θ=10°
```

In cone space: Clear spiral pattern
In Cartesian: Confusing jumps

---

## Correct Representation

### Candidate Structure

```dart
class LEDPositionCandidate {
  final int ledIndex;
  
  // PRIMARY: Cone coordinates (what we work with)
  final double normalizedHeight;  // 0-1
  final double angleDegrees;      // 0-360
  final double radius;            // meters
  
  // DERIVED: Cartesian coordinates (for export/visualization)
  final double x, y, z;
  
  final double confidence;
  final int numObservations;
  final String surface;  // 'front' or 'back'
}
```

### JSON Output (Corrected)

```json
{
  "led_index": 42,
  
  // Final position (chosen candidate)
  "height": 0.528,
  "angle": 60.2,
  "radius": 0.476,
  "x": 0.234,
  "y": 0.412,
  "z": 1.056,
  
  // Surface determination
  "surface": "front",
  "front_confidence": 0.92,
  
  // Both candidates (in cone coordinates!)
  "candidates": {
    "front": {
      "height": 0.528,
      "angle": 60.2,
      "radius": 0.476,
      "x": 0.234,
      "y": 0.412,
      "z": 1.056
    },
    "back": {
      "height": 0.516,
      "angle": 64.8,
      "radius": 0.474,
      "x": 0.189,
      "y": 0.398,
      "z": 1.032
    }
  },
  
  "reason": "Strong continuity in (h,θ) space (score: 1.84)"
}
```

---

## Distance Calculation (Corrected)

### Cone Space Distance

```dart
double coneDistance(LEDPositionCandidate a, LEDPositionCandidate b) {
  // Height component (vertical separation)
  final dh = (a.normalizedHeight - b.normalizedHeight).abs();
  final heightDist = dh * treeHeight;  // meters
  
  // Angular component (horizontal separation)
  // Handle wraparound: min(|Δθ|, 360-|Δθ|)
  final rawDtheta = (a.angleDegrees - b.angleDegrees).abs();
  final dtheta = math.min(rawDtheta, 360 - rawDtheta);
  
  // Arc length at average radius
  final avgRadius = (a.radius + b.radius) / 2;
  final dthetaRad = dtheta * math.pi / 180;
  final arcDist = avgRadius * dthetaRad;  // meters
  
  // Combined distance (2D on unrolled cone surface)
  return math.sqrt(heightDist * heightDist + arcDist * arcDist);
}
```

### Why This Works

**Imagine "unrolling" the cone:**
```
        Height ↑
          ^
          |     LED N+1 (h=0.53, θ=70°)
          |       ↑
          |      0.03m height
          |       ↓
          |     LED N (h=0.50, θ=60°)
          |       ↑
          |      0.04m height  
          |       ↓
          |     LED N-1 (h=0.46, θ=50°)
          |
          +---------------------------→ Angle

Arc distance at each step ≈ 0.08m
Total 3D distance ≈ sqrt(0.03² + 0.08²) ≈ 0.086m
```

This is the **real distance along the string!**

---

## Continuity Scoring (Corrected)

```dart
double scoreContinuity(
  LEDPositionCandidate candidate,
  Map<int, Map<String, LEDPositionCandidate>> allCandidates,
  double maxDistance,
) {
  double score = 0;
  int neighborCount = 0;
  
  // Check LED-1 and LED+1
  for (final offset in [-1, 1]) {
    final neighborIdx = candidate.ledIndex + offset;
    final neighborCandidates = allCandidates[neighborIdx];
    
    if (neighborCandidates == null) continue;
    
    // Check neighbor's same surface
    final neighborSame = neighborCandidates[candidate.surface];
    
    if (neighborSame != null) {
      // Calculate distance in CONE SPACE
      final dist = coneDistance(candidate, neighborSame);
      
      if (dist < maxDistance) {
        // Closer = higher score
        score += (1.0 - dist / maxDistance);
        neighborCount++;
      }
    }
  }
  
  return neighborCount > 0 ? score / neighborCount : 0.5;
}
```

---

## Example: Front vs Back Decision

### LED 42 Candidates

**From cameras:**
- Camera 1: front (h=0.530, θ=59°), back (h=0.514, θ=65°)
- Camera 2: front (h=0.526, θ=61°), back (h=0.518, θ=64°)
- Camera 3: front (h=0.528, θ=60°), back (h=0.516, θ=65°)

**Averaged candidates:**
```
Front: h=0.528, θ=60.0°, r=0.476m
Back:  h=0.516, θ=64.7°, r=0.474m
```

**Neighbors (already determined):**
```
LED 41 (front): h=0.498, θ=50.2°, r=0.484m
LED 43 (front): h=0.558, θ=69.8°, r=0.468m
```

**Score front candidate:**
```
Distance to LED 41:
  Δh = 0.030 → 0.06m vertical
  Δθ = 9.8° → 0.08m arc (at r≈0.48m)
  Total ≈ 0.10m ✓ (< 0.15m threshold)
  Score: 1.0 - 0.10/0.15 = 0.67

Distance to LED 43:
  Δh = 0.030 → 0.06m vertical
  Δθ = 9.8° → 0.08m arc
  Total ≈ 0.10m ✓
  Score: 0.67

Front score: (0.67 + 0.67) / 2 = 0.67
```

**Score back candidate:**
```
Distance to LED 41 (front!):
  Δh = 0.018 → 0.036m vertical
  Δθ = 14.5° → 0.12m arc
  Total ≈ 0.126m ✓ (barely under threshold)
  Score: 1.0 - 0.126/0.15 = 0.16

Distance to LED 43 (front!):
  Δh = 0.042 → 0.084m vertical
  Δθ = 5.1° → 0.042m arc  
  Total ≈ 0.094m ✓
  Score: 1.0 - 0.094/0.15 = 0.37

Back score: (0.16 + 0.37) / 2 = 0.27
```

**Decision:**
```
Front confidence = 0.67 / (0.67 + 0.27) = 0.71

→ Choose FRONT (confidence: 0.71)
```

---

## Why This Matters

### Problem with Cartesian Distance

If we used Cartesian (x,y,z) distance:

```
LED 41 (front): (0.312, 0.372, 0.996)
LED 42 (back):  (0.189, 0.398, 1.032)

Distance = sqrt((0.312-0.189)² + (0.372-0.398)² + (0.996-1.032)²)
        = sqrt(0.015 + 0.0007 + 0.0013)
        = 0.129m

Looks close! ✓ (< 0.15m)
```

**But this is WRONG!** They're on opposite surfaces with a 14° angle difference!

### Correct Cone Distance

```
LED 41 (front): h=0.498, θ=50.2°, r=0.484m
LED 42 (back):  h=0.516, θ=64.7°, r=0.474m

Δh = 0.018 → 0.036m vertical
Δθ = 14.5° → 0.12m arc
Total = sqrt(0.036² + 0.12²) = 0.126m
```

This captures the **true surface distance** accounting for the angle difference!

---

## Implementation Updates Needed

### 1. Update LEDPositionCandidate

```dart
class LEDPositionCandidate {
  // PRIMARY (work in this space)
  final double normalizedHeight;
  final double angleDegrees;  
  final double radius;
  
  // DERIVED (for export)
  final double x, y, z;
  
  // Calculate cone distance to another candidate
  double coneDistanceTo(LEDPositionCandidate other, double treeHeight) {
    final dh = (normalizedHeight - other.normalizedHeight).abs();
    final heightDist = dh * treeHeight;
    
    final rawDtheta = (angleDegrees - other.angleDegrees).abs();
    final dtheta = math.min(rawDtheta, 360 - rawDtheta);
    final avgRadius = (radius + other.radius) / 2;
    final arcDist = avgRadius * (dtheta * math.pi / 180);
    
    return math.sqrt(heightDist * heightDist + arcDist * arcDist);
  }
}
```

### 2. Update Continuity Scoring

```dart
// Use coneDistanceTo() instead of cartesian distanceTo()
final dist = candidate.coneDistanceTo(neighborSame, treeHeight);
```

### 3. Update JSON Export

```dart
// Export both representations
toJson() => {
  // Cone coordinates (primary)
  'height': normalizedHeight,
  'angle': angleDegrees,
  'radius': radius,
  
  // Cartesian (derived)
  'x': x,
  'y': y,
  'z': z,
}
```

---

## Summary

**Your question revealed a fundamental mistake!**

❌ **Wrong:** Working in Cartesian (x, y, z)
- Misleading distances
- Can't handle angle wraparound
- Doesn't respect cone geometry

✅ **Right:** Working in cone coordinates (height, angle, radius)
- Natural distance metric
- Handles wraparound correctly
- Respects surface topology
- Better for string continuity

**The algorithm should work entirely in cone space, only converting to Cartesian for final export/visualization!**

Thanks for catching this! 🎯
