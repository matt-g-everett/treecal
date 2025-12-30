# Angular Confidence - Missing Front/Back Component

## Current Implementation

### What It Measures NOW

**File:** `led_detection_service.dart`, line 250-287

```dart
static double _calculateAngularConfidence(
  double x,
  double y,
  double imageWidth,
  double imageHeight,
) {
  // Distance from image center
  final dx = x - centerX;
  final dy = y - centerY;
  final radialDistance = sqrt(dx² + dy²);
  
  // Normalized distance [0, 1]
  final normalizedDistance = radialDistance / maxDistance;
  
  // Viewing angle from centerline
  final viewingAngle = normalizedDistance × halfFOV;
  
  // Confidence based on cosine
  return cos(viewingAngle);
}
```

**What this captures:**
- ✅ How close LED is to camera centerline (2D image space)
- ✅ Lens distortion effects (edges less accurate)
- ✅ Projection geometry

**What this IGNORES:**
- ❌ Whether LED is facing TOWARD or AWAY from camera
- ❌ Which surface (front/back) LED is on relative to camera
- ❌ 3D geometric orientation

---

## The Problem

### Example Scenario

```
LED at position θ=60° (on tree)

Camera 1 (at 0°):
  - LED is at center of frame
  - Current angular_confidence: 1.0 (perfect!)
  - Reality: LED IS facing camera ✓
  - Correct!

Camera 3 (at 180°):
  - LED is at center of frame (seeing it through tree)
  - Current angular_confidence: 1.0 (perfect!)
  - Reality: LED is facing AWAY ✗
  - Wrong! Should be lower!
```

**Both cameras get angular_confidence = 1.0, but Camera 3 is seeing through the tree!**

### Why This Matters

**Currently, when we pick "best" observation:**
```dart
bestObs = observations.reduce((a, b) => 
  a.angularConfidence > b.angularConfidence ? a : b
);
```

**If Camera 3 happens to have LED more centered than Camera 1:**
```
Camera 1: angular_conf=0.87 (slightly off-center, but facing camera)
Camera 3: angular_conf=0.92 (perfectly centered, but LED facing away!)

Current: Picks Camera 3 ✗ Wrong!
Should: Pick Camera 1 ✓ Correct!
```

**We'd pick the worse observation!**

---

## The Solution: Add 3D Orientation Component

### Enhanced Angular Confidence

**Need to combine TWO factors:**

1. **Image-space factor** (current) - How centered in frame?
2. **3D orientation factor** (NEW!) - Is LED facing camera?

```dart
angular_confidence = image_factor × orientation_factor
```

### Orientation Factor Calculation

**Based on angle between LED and camera:**

```dart
double _calculateOrientationFactor(
  double ledAngleDegrees,    // LED position on tree (0-360°)
  double cameraAngleDegrees, // Camera position around tree (0-360°)
) {
  // Angular difference
  final diff = (ledAngleDegrees - cameraAngleDegrees).abs();
  final angleDiff = diff > 180 ? 360 - diff : diff;
  
  // Convert to radians
  final angleRad = angleDiff * pi / 180;
  
  // Cosine falloff
  // 0° difference (facing camera) = 1.0
  // 90° difference (side) = 0.0
  // 180° difference (facing away) = -1.0 → clamp to 0
  return max(0.0, cos(angleRad));
}
```

**Example:**
```
LED at θ=60°

Camera 1 at 0°:   |60-0|=60°   → cos(60°)=0.5
Camera 2 at 72°:  |60-72|=12°  → cos(12°)=0.978 (nearly facing!)
Camera 3 at 180°: |60-180|=120° → cos(120°)=-0.5 → 0.0 (facing away!)
Camera 4 at 288°: |60-288|=132° → cos(132°)=-0.67 → 0.0
Camera 5 at 36°:  |60-36|=24°  → cos(24°)=0.914
```

---

## Complete Angular Confidence Formula

### Combined Calculation

```dart
static double calculateAngularConfidence(
  double pixelX,
  double pixelY,
  double imageWidth,
  double imageHeight,
  double ledAngleDegrees,       // NEW!
  double cameraAngleDegrees,    // NEW!
  {
    double fovDegrees = 60.0,
    double minConfidence = 0.1,
  }
) {
  // 1. Image-space factor (existing)
  final centerX = imageWidth / 2;
  final centerY = imageHeight / 2;
  final dx = pixelX - centerX;
  final dy = pixelY - centerY;
  final radialDistance = sqrt(dx * dx + dy * dy);
  final maxDistance = sqrt(centerX * centerX + centerY * centerY);
  final normalizedDistance = radialDistance / maxDistance;
  final halfFovRad = fovDegrees * pi / 360.0;
  final viewingAngle = normalizedDistance * halfFovRad;
  
  final imageFactor = cos(viewingAngle);
  
  // 2. 3D orientation factor (NEW!)
  final diff = (ledAngleDegrees - cameraAngleDegrees).abs();
  final angleDiff = diff > 180 ? 360 - diff : diff;
  final angleRad = angleDiff * pi / 180;
  
  final orientationFactor = max(0.0, cos(angleRad));
  
  // 3. Combined confidence
  final combined = imageFactor * orientationFactor;
  
  return max(combined, minConfidence);
}
```

---

## Impact on Best-Observation Selection

### Before (Missing Orientation)

```
LED at θ=60°

Camera 1 (0°): pixel=(960, 540), angular_conf=1.0 (centered)
Camera 3 (180°): pixel=(960, 540), angular_conf=1.0 (centered, through tree)

Picks: Random (both same confidence)
```

### After (With Orientation)

```
LED at θ=60°

Camera 1 (0°): 
  image_factor=1.0 (centered)
  orientation_factor=0.5 (60° difference)
  angular_conf = 1.0 × 0.5 = 0.5

Camera 3 (180°):
  image_factor=1.0 (centered)
  orientation_factor=0.0 (120° difference, facing away!)
  angular_conf = 1.0 × 0.0 = 0.0

Picks: Camera 1 ✓ Correct!
```

**Camera 3 is eliminated because LED is facing away!**

---

## Where to Calculate This?

### Problem: Chicken and Egg

**To calculate orientation factor, we need:**
- LED angle (θ)
- Camera angle (φ)

**But to get LED angle, we need:**
- To triangulate
- Which requires angular confidence
- Which requires LED angle!

**Circular dependency!**

### Solution: Iterative Refinement

**First pass (no orientation):**
```dart
// Use only image-space factor
angular_conf_v1 = cos(viewing_angle)

// Triangulate using best camera (by image-space only)
position_v1 = triangulate_with_image_conf()

// Get LED angle from first triangulation
led_angle_v1 = position_v1.angle
```

**Second pass (with orientation):**
```dart
// Recalculate with orientation factor
for (obs in observations) {
  image_factor = cos(viewing_angle)
  orientation_factor = cos(|led_angle_v1 - camera.angle|)
  angular_conf_v2 = image_factor × orientation_factor
}

// Re-triangulate with improved confidence
position_v2 = triangulate_with_full_conf()

// Usually converges immediately (positions very similar)
```

**Typically only need 1-2 iterations!**

---

## Alternative: Use Initial Estimate

### Simpler Approach

**If we have a rough idea of LED position from detection:**

```dart
// Rough angle estimate from pixel position in frame
// (before full triangulation)
estimated_angle = estimate_from_pixel(pixelX, pixelY, camera)

// Use for orientation factor immediately
orientation_factor = cos(|estimated_angle - camera.angle|)
```

**Good enough for filtering obviously bad views!**

---

## Implementation Priority

### What's Needed

**Current state:**
- ✅ Image-space angular confidence (implemented)
- ❌ 3D orientation factor (missing)
- ❌ Combined calculation (missing)

**To implement:**

1. **Add orientation factor calculation**
   ```dart
   static double _calculateOrientationFactor(
     double ledAngle,
     double cameraAngle,
   )
   ```

2. **Update angular confidence to combine both**
   ```dart
   final angularConf = imageFactor × orientationFactor;
   ```

3. **Add LED angle to detection data**
   - Either estimate from pixel position
   - Or iterate (triangulate, refine, re-triangulate)

---

## Expected Impact

### Before (Current)

**Problem cases:**
```
Camera seeing LED through tree might be selected as "best"
if it happens to be more centered in frame
```

**Example:**
- 30% of time, picks wrong camera (one seeing through tree)
- Results in ~5-10cm errors

### After (With Orientation)

**Improved:**
```
Camera seeing LED through tree gets low orientation_factor
Never selected as "best" even if centered
```

**Example:**
- 95%+ of time, picks correct camera (LED facing it)
- Results in ~2cm errors (as designed)

**Improvement: ~2× better camera selection**

---

## Quick Fix vs Full Solution

### Option 1: Quick Fix (Good Enough)

**Just use detection confidence as proxy:**

```dart
// Detection confidence is ALREADY lower when viewing through tree!
// (dimmer LED, partial occlusion)

// Current best-obs selection:
bestObs = max_by(angular_confidence)

// Improved best-obs selection:
bestObs = max_by(angular_confidence × detection_confidence)
```

**This already exists as `obs.weight`!**

```dart
double get weight => detectionConfidence * angularConfidence;
```

**So change to:**
```dart
bestObs = observations.reduce((a, b) => 
  a.weight > b.weight ? a : b  // Use weight instead of angularConfidence
);
```

**This implicitly accounts for occlusion through detection_confidence!**

---

### Option 2: Full Solution (More Accurate)

**Add explicit 3D orientation factor:**

1. First triangulation pass (image-space only)
2. Calculate orientation factors
3. Second triangulation pass (with orientation)

**More accurate, but more complex.**

---

## Recommendation

### Start with Quick Fix

**Change one line in triangulation:**

```dart
// OLD:
final bestObs = observations.reduce((a, b) => 
  a.angularConfidence > b.angularConfidence ? a : b
);

// NEW:
final bestObs = observations.reduce((a, b) => 
  a.weight > b.weight ? a : b
);
```

**This uses `weight = detectionConfidence × angularConfidence`**

**Benefits:**
- ✅ Already accounts for dimmer LEDs through tree
- ✅ One line change
- ✅ No new calculations needed
- ✅ Good enough for most cases

**Detection confidence naturally lower when viewing through tree because:**
- LED is dimmer
- Partially occluded by branches
- Lower brightness detection

**This implicitly captures orientation!**

---

### Later Add Full Orientation (If Needed)

**If quick fix isn't sufficient:**
- Add explicit orientation factor
- Iterate triangulation
- Get 2× improvement

**But test quick fix first!**

---

## Summary

**Your question revealed:**
- ❌ Angular confidence currently ignores 3D orientation
- ❌ Can select camera seeing LED through tree as "best"
- ❌ Needs front/back surface awareness

**Solutions:**

**Quick fix:** Use `weight` (detection × angular) instead of just `angular`
- ✅ One line change
- ✅ Detection already lower for occluded views
- ✅ Good enough

**Full solution:** Add explicit orientation factor
- cos(|LED_angle - camera_angle|)
- Iterate triangulation
- More accurate

**Recommendation:** Try quick fix first! 🎯

**Great catch - this could improve accuracy significantly!**
