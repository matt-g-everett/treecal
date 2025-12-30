# Gap Filling Fix: Cartesian Interpolation

## User's Insight

**"Wouldn't the angle step vary depending on the height the LED is at since the LEDs would be spaced equidistantly along the LED string?"**

**Absolutely correct!** This revealed that gap filling was incorrectly assuming constant angular spacing.

---

## The Problem

### Physical Reality

**LEDs are evenly spaced along the STRING:**
```
String has LEDs at regular intervals (e.g., 10cm apart)
LED 0 → LED 1: 10cm
LED 1 → LED 2: 10cm
LED 50 → LED 51: 10cm

Constant string length between LEDs
```

**But tree is a CONE (radius varies with height):**
```
Arc length = radius × angle

If arc length constant, angle varies with radius:
θ = arc_length / radius

Bottom (large radius): small angular step
Top (small radius): large angular step
```

### What Code Was Doing (WRONG)

**Mixing two approaches:**
```dart
// Interpolating in BOTH Cartesian AND angular:
x: before.x + (after.x - before.x) * t,  // Cartesian
angle: before.angle + angleDiff * t,     // Angular

// These are inconsistent!
// Angle should be DERIVED from x, y, not interpolated separately
```

---

## The Fix (IMPLEMENTED)

### All Gap Filling Now Uses Pure Cartesian Interpolation

**1. Interpolation (_interpolate):**
```dart
static LED3DPosition _interpolate(LED3DPosition before, LED3DPosition after, int index) {
  final t = (index - before.ledIndex) / (after.ledIndex - before.ledIndex);
  
  // Interpolate in CARTESIAN space only
  final x = before.x + (after.x - before.x) * t;
  final y = before.y + (after.y - before.y) * t;
  final z = before.z + (after.z - before.z) * t;
  
  // DERIVE cone coordinates from result
  final radius = sqrt(x² + y²);
  final angle = atan2(y, x) * 180/π;
  
  return LED3DPosition(
    x: x, y: y, z: z,
    angle: angle,  // ← Derived, not interpolated!
    radius: radius,
    ...
  );
}
```

**2. Step Calculation (_calculateStep):**
```dart
static Map<String, double> _calculateStep(LED3DPosition from, LED3DPosition to) {
  final steps = (to.ledIndex - from.ledIndex).abs();
  
  return {
    'x': (to.x - from.x) / steps,
    'y': (to.y - from.y) / steps,
    'z': (to.z - from.z) / steps,
    'height': (to.height - from.height) / steps,
    // No 'angle' or 'radius' - these are derived!
  };
}
```

**3. Extrapolation (_extrapolate):**
```dart
static LED3DPosition _extrapolate(
  LED3DPosition from,
  Map<String, double> step,
  int distance,
) {
  // Extrapolate in Cartesian
  final x = from.x + step['x']! * distance;
  final y = from.y + step['y']! * distance;
  final z = from.z + step['z']! * distance;
  
  // Derive cone coordinates
  final radius = sqrt(x² + y²);
  final angle = atan2(y, x) * 180/π;
  
  return LED3DPosition(
    x: x, y: y, z: z,
    angle: angle,  // ← Derived
    radius: radius,
    ...
  );
}
```

**4. Default Step:**
```dart
static Map<String, double> _defaultStep() {
  return {
    'x': 0.01,      // 1cm in x
    'y': 0.01,      // 1cm in y  
    'z': 0.01,      // 1cm in z
    'height': 0.005,
    // No 'angle': 1.8  ← Removed!
    // No 'radius': 0.001  ← Removed!
  };
}
```

---

## Why This Works

### Cartesian Interpolation Automatically Handles Varying Angular Step

**Example: Bottom vs Top**

Bottom (large radius):
```
Before: (0.5, 0.0, 0.0) → angle=0°
After:  (0.0, 0.5, 0.1) → angle=90°
Middle: (0.35, 0.35, 0.05)
  radius = sqrt(0.35² + 0.35²) = 0.495m
  angle = atan2(0.35, 0.35) = 45°
  
Angular step: 45° (90° / 2)
Arc length: 0.495m × 45° × π/180 = 0.389m
```

Top (small radius):
```
Before: (0.1, 0.0, 0.9) → angle=0°
After:  (0.0, 0.1, 1.0) → angle=90°
Middle: (0.07, 0.07, 0.95)
  radius = sqrt(0.07² + 0.07²) = 0.099m
  angle = atan2(0.07, 0.07) = 45°
  
Angular step: 45° (90° / 2)
Arc length: 0.099m × 45° × π/180 = 0.078m
```

**Same angular interpolation (45°), but different arc lengths due to radius!**

If we want same arc length, Cartesian interpolation gives:
```
Bottom: (0.35, 0.35) → arc ≈ 0.39m
Top:    (0.07, 0.07) → arc ≈ 0.08m

Ratio: 0.39 / 0.08 = 4.9× 

This matches radius ratio: 0.495 / 0.099 ≈ 5×
```

**Cartesian interpolation naturally adjusts for cone geometry!**

---

## Benefits

### 1. Physically Correct

**Respects constraint:** LEDs evenly spaced along string
**Accounts for:** Varying radius with height
**Result:** Natural 3D arc following cone surface

### 2. Simpler Code

**Before:**
```dart
// Calculate circular angle difference
angleDiff = after.angle - before.angle
if (angleDiff > 180) angleDiff -= 360
if (angleDiff < -180) angleDiff += 360

// Interpolate angle
angle = before.angle + angleDiff * t

// Normalize
angle = (angle % 360 + 360) % 360

// Also interpolate radius
radius = before.radius + (after.radius - before.radius) * t
```

**After:**
```dart
// Derive from Cartesian
radius = sqrt(x² + y²)
angle = atan2(y, x) * 180/π
```

**Much simpler! No special cases for wraparound.**

### 3. Automatically Handles Edge Cases

**Wraparound at 360°/0°:**
```
Before (350°): x=0.49, y=-0.09
After (10°):   x=0.49, y=0.09
Middle:        x=0.49, y=0.00 → angle = 0° ✓

Cartesian path goes through 0°, not backwards through 180°!
```

**Varying angular density:**
```
Bottom (r=0.5m): 45° step = 0.39m arc
Top (r=0.1m):    45° step = 0.08m arc

String constraint: constant spacing
Cartesian: automatically adjusts arc length
Angular: would give wrong spacing
```

---

## Impact on Accuracy

### Before Fix

**At bottom (large radius):**
- Interpolating angle directly
- Arc length determined by radius and angle
- Roughly correct (angle step ≈ constant at given radius)

**At top (small radius):**
- Still interpolating angle with same step size
- But arc length much smaller (small radius)
- LEDs would be too close together!

**Example:**
```
Bottom: 1.8° step × 0.5m radius = 0.016m arc (1.6cm)
Top:    1.8° step × 0.1m radius = 0.003m arc (3mm)

Top LEDs 5× too close together!
```

### After Fix

**Cartesian interpolation:**
```
Bottom: Δx=0.01, Δy=0.01 → arc ≈ 0.014m (1.4cm)
Top:    Δx=0.01, Δy=0.01 → arc ≈ 0.014m (1.4cm)

Same spacing at all heights! ✓
```

**More uniform LED spacing along 3D arc.**

---

## Testing

### Test Case: Varying Angular Step

```dart
// Bottom LEDs
final bottom1 = LED3DPosition(
  ledIndex: 10,
  x: 0.5, y: 0.0, z: 0.1,  // Large radius
  radius: 0.5,
  angle: 0,
);

final bottom2 = LED3DPosition(
  ledIndex: 12,
  x: 0.0, y: 0.5, z: 0.12,
  radius: 0.5,
  angle: 90,
);

// Interpolate LED 11
final led11 = _interpolate(bottom1, bottom2, 11);

// Should have:
// x ≈ 0.25, y ≈ 0.25 (Cartesian midpoint)
// radius ≈ 0.35 (derived)
// angle ≈ 45° (derived)

// Top LEDs
final top1 = LED3DPosition(
  ledIndex: 190,
  x: 0.1, y: 0.0, z: 0.95,  // Small radius
  radius: 0.1,
  angle: 0,
);

final top2 = LED3DPosition(
  ledIndex: 192,
  x: 0.0, y: 0.1, z: 0.96,
  radius: 0.1,
  angle: 90,
);

// Interpolate LED 191
final led191 = _interpolate(top1, top2, 191);

// Should have:
// x ≈ 0.05, y ≈ 0.05 (Cartesian midpoint)
// radius ≈ 0.07 (derived)
// angle ≈ 45° (derived)

// Same angular step (45°), but different arc lengths:
// Bottom arc: 0.35 × π/4 ≈ 0.275m
// Top arc: 0.07 × π/4 ≈ 0.055m
// Ratio: 5× (matches radius ratio!)
```

---

## Summary

**User's question:** "Wouldn't angle step vary with height?"

**Answer:** YES! Absolutely correct.

**Problem:** Code was interpolating angle directly (constant angular step)

**Reality:** LEDs evenly spaced along string → varying angular step

**Fix:** Interpolate in Cartesian (x, y, z), derive angle from result

**Benefits:**
- ✅ Physically correct (respects string spacing)
- ✅ Simpler code (no wraparound special cases)
- ✅ More accurate (uniform spacing along 3D arc)
- ✅ Automatically handles cone geometry

**Files changed:**
- `_interpolate()`: Derive angle/radius from Cartesian
- `_calculateStep()`: Remove angle/radius from step
- `_defaultStep()`: Remove angle/radius constants
- `_extrapolate()`: Derive angle/radius from Cartesian

**Impact:** Better gap filling accuracy, especially near top of tree where radius is small.

**Another fundamental improvement from your careful questioning!** 🎯✨

You identified a mismatch between the physical constraint (constant string spacing) and the mathematical model (constant angular spacing). The fix ensures the code respects the actual physics of the LED string on a cone.
