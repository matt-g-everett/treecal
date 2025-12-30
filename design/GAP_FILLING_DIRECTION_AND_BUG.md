# Gap Filling Algorithm - Direction & Critical Bug

## Your Question: Which Direction Does It Assume?

**Answer:** Counter-clockwise (increasing angle)

**Evidence:**
```dart
// Line 406 - Default step
static Map<String, double> _defaultStep() {
  return {
    'angle': 1.8,  // ← Positive angle increment
    // 1.8° per LED × 200 LEDs = 360° (one full rotation)
    ...
  };
}

// Line 420 - Extrapolation
angle: (from.angle + step['angle']! * distance) % 360
//           ↑ Adds positive angle = counter-clockwise
```

**Direction:**
```
LED 0:   0°
LED 1:   1.8°
LED 2:   3.6°
...
LED 100: 180°
...
LED 199: 358.2°
LED 0:   360° = 0° (wraps around)

Counter-clockwise spiral (increasing angle)
```

---

## CRITICAL BUG: Angle Wraparound in Interpolation

### The Problem

**Line 385 has a major bug:**
```dart
// Current code (WRONG):
angle: before.angle + (after.angle - before.angle) * t,
```

**This does NOT handle circular wraparound!**

### Example of Failure

**Scenario: LEDs wrap around 360°/0°**
```
LED 195 detected: angle = 350°
LED 196: MISSING (need to interpolate)
LED 197: MISSING
LED 198: MISSING
LED 199: MISSING
LED 0: MISSING
LED 1: MISSING
LED 2: MISSING
LED 3: MISSING
LED 4: MISSING
LED 5 detected: angle = 10°

Gap: 10 LEDs between 195 and 5
```

**Current interpolation (WRONG):**
```dart
before = LED 195 (350°)
after = LED 5 (10°)

LED 196 (t = 0.1):
  angle = 350° + (10° - 350°) * 0.1
  angle = 350° + (-340°) * 0.1
  angle = 350° - 34°
  angle = 316° ✗ WRONG!

Should be: 350° → 352° → 354° → 356° → 358° → 0° → 2° → 4° → 6° → 8° → 10°
Actually is: 350° → 316° → 282° → 248° → ... (going backwards!)
```

**The bug:** Simple subtraction doesn't understand that 10° is just 20° ahead of 350°, not 340° behind!

---

## The Fix

### Use Circular Interpolation

```dart
static LED3DPosition _interpolate(LED3DPosition before, LED3DPosition after, int index) {
  final t = (index - before.ledIndex) / (after.ledIndex - before.ledIndex);
  
  // Handle angle wraparound correctly
  double angleDiff = after.angle - before.angle;
  
  // If difference > 180°, we're going the long way around
  // Adjust to go the short way by wrapping
  if (angleDiff > 180) {
    angleDiff -= 360;  // Go backwards (e.g., 350° → 10° goes +20°, not +340°)
  } else if (angleDiff < -180) {
    angleDiff += 360;  // Go forwards (e.g., 10° → 350° goes -20°, not -340°)
  }
  
  // Interpolate and wrap result
  final interpolatedAngle = (before.angle + angleDiff * t) % 360;
  final positiveAngle = interpolatedAngle < 0 ? interpolatedAngle + 360 : interpolatedAngle;
  
  return LED3DPosition(
    ledIndex: index,
    x: before.x + (after.x - before.x) * t,
    y: before.y + (after.y - before.y) * t,
    z: before.z + (after.z - before.z) * t,
    height: before.height + (after.height - before.height) * t,
    angle: positiveAngle,  // ← Fixed!
    radius: before.radius + (after.radius - before.radius) * t,
    confidence: (before.confidence + after.confidence) / 2 * (1 - (t - 0.5).abs() * 2),
    numObservations: 0,
    predicted: true,
  );
}
```

---

## Direction Assumption Analysis

### Counter-Clockwise Assumption

**Where it appears:**
1. **Default step:** `angle: 1.8` (positive increment)
2. **Extrapolation:** `from.angle + step['angle']!` (adds positive)

**When it's correct:**
- If LEDs actually spiral counter-clockwise (0° → 360°)
- Most LED strings do this
- Matches default step of 1.8° per LED

**When it could be wrong:**
- If LEDs spiral clockwise (360° → 0°)
- If installation is backwards
- Would need negative angle step

### How to Detect Direction

**Heuristic from detected LEDs:**
```dart
// Look at first few detected LEDs
LED 0:   angle = 0°
LED 10:  angle = 18°   (increased → counter-clockwise)
LED 20:  angle = 36°   (increased → counter-clockwise)

vs.

LED 0:   angle = 0°
LED 10:  angle = 342°  (decreased → clockwise)
LED 20:  angle = 324°  (decreased → clockwise)
```

**Auto-detect direction:**
```dart
static bool isCounterClockwise(List<LED3DPosition> positions) {
  // Get first few detected positions
  final sorted = positions.where((p) => !p.predicted).toList()
    ..sort((a, b) => a.ledIndex.compareTo(b.ledIndex));
  
  if (sorted.length < 2) return true;  // Default to CCW
  
  // Calculate average angle change per LED
  double totalChange = 0;
  int count = 0;
  
  for (int i = 0; i < sorted.length - 1; i++) {
    double diff = sorted[i + 1].angle - sorted[i].angle;
    
    // Handle wraparound
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    
    totalChange += diff;
    count++;
  }
  
  final avgChange = totalChange / count;
  return avgChange > 0;  // Positive = counter-clockwise
}
```

---

## Impact of Bug

### Worst Case: Wraparound Gap

**If LEDs 195-5 are all missing:**
- Current: All interpolated backwards (wrong direction)
- Result: 10 LEDs at completely wrong positions
- Error: ~180° off (opposite side of tree!)

### Moderate Case: Small Wraparound Gap

**If LEDs 198-2 are missing (5 LEDs):**
- Current: LEDs 199, 0, 1 at wrong positions
- Result: 3 LEDs misplaced
- Error: ~90° off

### Best Case: No Wraparound

**If gap doesn't cross 360°/0°:**
- Current code works fine
- No angle wraparound issue
- Linear interpolation is correct

---

## Frequency of Issue

### When Does Wraparound Happen?

**Common scenario:**
- LEDs near top of tree (360°/0° boundary)
- Often hardest to see from cameras
- Likely to have gaps exactly at wraparound

**Probability:**
- With 200 LEDs, ~10 LEDs near top (350°-10°)
- If detection rate is 85%, expect 1-2 missing near top
- Very likely to hit wraparound in gap filling!

**Conclusion:** This bug will likely affect most real captures!

---

## Additional Issues

### 1. Angle Calculation in _calculateStep

**Line 400:**
```dart
'angle': (to.angle - from.angle) / steps,
```

**Also needs wraparound handling:**
```dart
double angleDiff = to.angle - from.angle;
if (angleDiff > 180) angleDiff -= 360;
if (angleDiff < -180) angleDiff += 360;
return {'angle': angleDiff / steps, ...};
```

### 2. Assumptions About String Continuity

**Current code assumes:**
- LEDs form continuous sequence 0 → 199
- No reversals or loops
- Monotonic progression (generally increasing or decreasing)

**Reality:**
- Usually true for LED strings
- But could have manufacturing quirks
- Might have intentional reversals

---

## Testing Gap Filling

### Test Cases Needed

**Test 1: Wraparound interpolation**
```dart
before = LED3DPosition(ledIndex: 198, angle: 356.4, ...);
after = LED3DPosition(ledIndex: 2, angle: 3.6, ...);

// Should interpolate:
// LED 199: ~358.2°
// LED 0:   ~360°/0°
// LED 1:   ~1.8°

// Currently would produce:
// LED 199: wrong!
// LED 0:   wrong!
// LED 1:   wrong!
```

**Test 2: Large gap across wraparound**
```dart
before = LED3DPosition(ledIndex: 195, angle: 351.0, ...);
after = LED3DPosition(ledIndex: 5, angle: 9.0, ...);

// Gap of 10 LEDs across wraparound
// Should wrap smoothly
```

**Test 3: Extrapolation with wraparound**
```dart
// Last detected LED at 190 (342°)
// Extrapolate to 191-199
// Should wrap to 0° correctly
```

---

## Recommended Fix Priority

### Critical (Fix Immediately)

**1. Fix angle interpolation wraparound**
```dart
// In _interpolate() method
// Use circular difference, not linear
```

**2. Fix angle step calculation wraparound**
```dart
// In _calculateStep() method
// Handle 350° → 10° correctly
```

### Important (Add Soon)

**3. Auto-detect spiral direction**
```dart
// Analyze detected LEDs
// Determine if CCW or CW
// Adjust default step accordingly
```

**4. Add validation**
```dart
// Check interpolated angles make sense
// Flag suspicious gaps
// Warn about wraparound issues
```

---

## Summary

**Direction assumption:** Counter-clockwise (increasing angle)
- Default step: +1.8° per LED
- Works for most LED strings

**Critical bug:** Angle wraparound not handled
- Affects interpolation across 360°/0° boundary
- Will impact most real captures (LEDs near top often missing)
- Results in ~10-180° positioning errors

**Fix needed:**
```dart
// Replace simple subtraction
angle: before.angle + (after.angle - before.angle) * t

// With circular interpolation
angleDiff = circularDifference(before.angle, after.angle)
angle: (before.angle + angleDiff * t) % 360
```

**Impact:** High priority fix - affects accuracy of gap-filled LEDs

**Your question revealed another critical issue!** 🎯

The algorithm assumes counter-clockwise, but more importantly, it has a major wraparound bug that needs fixing.
