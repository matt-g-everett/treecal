# LED Position Mapper - Design Document

## Overview

This system maps the 3D positions of LEDs wrapped around a Christmas tree using automated photo capture and computer vision. The design combines MQTT-controlled LED sequencing, multi-angle photography, confidence-weighted triangulation, and physical constraints to achieve ±2-3cm accuracy.

## System Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    CAPTURE PHASE                            │
│  (Flutter Mobile App - 5-7 minutes total)                   │
└─────────────────────────────────────────────────────────────┘
                              ↓
        For each camera position (3-5 positions):
                              ↓
        ┌──────────────────────────────────────┐
        │  1. All LEDs ON → Photo              │
        │     (cone outline estimation)        │
        │                                      │
        │  2. LED 0 ON → Photo                 │
        │  3. LED 1 ON → Photo                 │
        │  ...                                 │
        │  N. LED 199 ON → Photo               │
        └──────────────────────────────────────┘
                              ↓
        Export: Images + Camera Calibrations
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   PROCESSING PHASE                          │
│  (Python - 2-5 minutes)                                     │
└─────────────────────────────────────────────────────────────┘
                              ↓
        Phase 0: Cone Estimation (all-on photos)
        Phase 1: LED Detection (individual photos)
        Phase 2: Reflection Analysis
        Phase 3: Triangulation (with confidence weighting)
        Phase 4: Gap Filling (sequential prediction)
        Phase 5: Cone Projection (surface constraint)
                              ↓
        Output: led_positions.json
                (height, angle, radius for each LED)
```

## Mathematical Foundations

### 1. Coordinate Systems

**World Coordinates (XYZ):**
- Origin: Tree center at ground level
- Z-axis: Vertical (height)
- X-Y plane: Ground level
- Units: Meters

**Cylindrical Coordinates (h, θ, r):**
- h: Height above ground [0, H]
- θ: Angle around tree [0°, 360°)
- r: Radius from center axis
- Conversion: x = r·cos(θ), y = r·sin(θ), z = h

**Camera Coordinates:**
- Each camera at position (x_c, y_c, z_c)
- Orientation: angle θ_c around tree
- Distance: d from tree center

### 2. Cone Model

The tree is modeled as a truncated cone:

```
r(h) = r_bottom - (r_bottom - r_top) × (h / H)

Where:
  r_bottom = radius at ground (h=0)
  r_top = radius at top (h=H)
  H = total tree height
```

**Key insight:** This reduces LED position to 2 degrees of freedom (h, θ) instead of 3 (x, y, z).

### 3. Camera Projection

**Simplified pinhole model:**

```
For LED at world position (x, y, z):
For camera at (x_c, y_c, z_c) with angle θ_c:

1. Transform to camera coordinates:
   Δx = x - x_c
   Δy = y - y_c
   Δz = z - z_c
   
2. Rotate by camera angle:
   x_cam = cos(θ_c)·Δx + sin(θ_c)·Δy
   y_cam = -sin(θ_c)·Δx + cos(θ_c)·Δy
   z_cam = Δz

3. Project to image plane:
   px = image_center_x + f × (x_cam / distance)
   py = image_center_y - f × (z_cam / distance)
   
Where:
  f = focal length (pixels)
  distance ≈ √(x_cam² + y_cam²)
```

**Note:** This is a simplified projection. Full implementation would use proper camera calibration matrices, but this approximation works well for our use case (camera far from tree, minimal distortion).

## Core Algorithms

### Algorithm 1: Cone Outline Detection

**Input:** All-LEDs-on photograph
**Output:** Cone parameters (r_bottom, r_top, center)

**Steps:**

1. **Thresholding:**
   ```
   binary = threshold(grayscale, T=150)
   → pixels > 150 become white (LED region)
   → pixels ≤ 150 become black (background)
   ```

2. **Morphological cleanup:**
   ```
   kernel = 5×5 ones matrix
   binary = close(binary, kernel)  ← Fill gaps
   binary = open(binary, kernel)   ← Remove noise
   ```

3. **Contour extraction:**
   ```
   contours = find_contours(binary)
   outline = largest_contour(contours)
   edge_points = outline.points  ← Nx2 array
   ```

4. **Width profile calculation:**
   ```
   For k heights h₁, h₂, ..., hₖ:
     width(hᵢ) = max_x(points at hᵢ) - min_x(points at hᵢ)
   ```

5. **Linear regression:**
   ```
   Fit: width(h) = a + b·h
   
   r_bottom = a / 2
   r_top = (a + b·H) / 2
   ```

**Mathematical basis:** The cone width in image space is approximately linear with height (for distant camera), so linear regression recovers the taper.

### Algorithm 2: Reflection Clustering

**Problem:** Reflections create false detections at same pixel location across multiple LED captures.

**Algorithm:**

1. **Collect all detections:**
   ```
   D = {(led_idx, camera_idx, pixel_x, pixel_y, brightness)}
   ```

2. **Spatial clustering:**
   ```
   For each camera c:
     clusters[c] = []
     
     For each detection d₁ in D where camera=c:
       cluster = [d₁]
       
       For each other detection d₂:
         if distance(d₁.pixel, d₂.pixel) < threshold:
            if d₁.led_idx ≠ d₂.led_idx:
               cluster.append(d₂)
       
       if len(cluster) > 1:
          clusters[c].append(cluster)
   ```

3. **Reflection scoring:**
   ```
   For detection d:
     if d in any cluster C:
       reflection_score = min(1, (|C| - 1) / 10)
       
       # Adjust for brightness variance
       σ² = var([brightness for det in C])
       if σ² > threshold:
          reflection_score *= 0.5  ← Likely overlapping LEDs
     else:
       reflection_score = 0
   ```

**Key insight:** Real LEDs don't appear at the same pixel for different LED indices. If 5+ different LEDs all light up pixel (520, 380), it's almost certainly a reflection.

### Algorithm 3: Confidence Modeling

Each detection receives a composite confidence score:

**Components:**

1. **Reflection confidence:**
   ```
   C_led = 1 - reflection_score
   ```

2. **Angular confidence (corrected):**
   ```
   radial_offset = √((px - center_x)² + (py - center_y)²) / image_diagonal
   C_angular = 1 - 0.7 × radial_offset
   
   → Center of image: C_angular = 1.0 (best)
   → Edge of image: C_angular = 0.3 (worst)
   ```
   
   **Rationale:** Center has direct line of sight, minimal lens distortion. Edge has oblique viewing, distortion, vignetting.

3. **Brightness confidence:**
   ```
   C_brightness = clip((brightness - 150) / 100, 0, 1)
   
   → Very bright (250+): confidence = 1.0
   → Dim (150): confidence = 0.0
   ```

4. **Size confidence:**
   ```
   if area < 5 pixels:    C_size = 0.5  ← Too small (noise)
   elif area > 100 pixels: C_size = 0.6  ← Too large (reflection)
   else:                   C_size = 1.0  ← Appropriate size
   ```

5. **Composite score:**
   ```
   C_overall = 0.40 × C_led + 
               0.25 × C_angular + 
               0.15 × C_brightness +
               0.10 × C_radial +
               0.10 × C_size
   ```

**Weights rationale:** Reflection filtering most important (40%), then angular accuracy (25%), then brightness and size as secondary factors.

### Algorithm 4: Weighted Triangulation

**Standard triangulation:** Minimize reprojection error equally across all observations.

**Problem:** Some observations are more reliable than others.

**Solution:** Weighted least squares.

**Given:**
- Pixel observations: p₁, p₂, ..., pₙ
- Confidence scores: w₁, w₂, ..., wₙ  
- Camera positions: C₁, C₂, ..., Cₙ

**Objective:**
```
Minimize: Σᵢ wᵢ × ||project(Cᵢ, LED) - pᵢ||²
```

**Implementation:**
```
Build system: A·x = b where x = [x_led, y_led, z_led]ᵀ

For each camera i:
  Ray from camera through pixel pᵢ
  Add constraint: LED lies on this ray
  Weight constraint by wᵢ

Solve: (AᵀWA)x = AᵀWb
where W = diag(w₁, w₂, ..., wₙ)
```

**Result:** High-confidence observations (center of frame, not reflection, bright) have more influence on final position.

### Algorithm 5: Cone-Constrained Triangulation

**Motivation:** We KNOW the LED is on the cone surface. Standard triangulation ignores this constraint.

**Better approach:** Solve directly in (h, θ) space.

**Parametrization:**
```
LED position as function of (h, θ):
  r = r_bottom - (r_bottom - r_top) × (h / H)
  x = center_x + r × cos(θ)
  y = center_y + r × sin(θ)
  z = h

Only 2 unknowns instead of 3!
```

**Optimization:**
```
Given pixel observations: p₁, p₂, ..., pₙ

Minimize: Σᵢ wᵢ × ||project(Cᵢ, cone(h,θ)) - pᵢ||²

Subject to: 0 ≤ h ≤ H
           0 ≤ θ < 2π
```

**Advantages:**
- Fewer unknowns → more robust with limited data
- Guaranteed on-surface solution
- Better with noise (constraint acts as regularization)

**Two-stage approach:**
```
Stage 1: Standard XYZ triangulation
         → Get rough positions for ~140 LEDs

Stage 2: Estimate cone from Stage 1 positions
         → Fit (r_bottom, r_top, center)

Stage 3: Re-triangulate with cone constraint
         → Get refined positions, guaranteed on surface
```

### Algorithm 6: Sequential Prediction

**Problem:** Not all LEDs visible from all cameras. Need to fill gaps.

**Key insight:** Errors only accumulate within gaps, reset at known LEDs.

**Algorithm:**

For gaps between known LEDs:
```
Given: LED i at position pᵢ (known)
       LED j at position pⱼ (known)
       Gap size: n = j - i

For each LED k where i < k < j:
  α = (k - i) / (j - i)  ← Interpolation parameter
  
  p_k = (1-α) × pᵢ + α × pⱼ  ← Linear interpolation
  
  confidence_k = 1 - |α - 0.5| × 2  ← Highest at gap center
```

For LEDs before first known or after last known:
```
Estimate average step Δp from nearby known LEDs:
  Δp = avg(pᵢ₊₁ - pᵢ for recent known LEDs)

Extrapolate:
  p_k = p_last_known + (k - last_idx) × Δp
  
confidence_k = max(0.2, 1 - 0.1×|k - last_idx|)
```

**Confidence decay:** The farther from known LEDs, the less certain the prediction.

### Algorithm 7: Cone Surface Projection

**Purpose:** Enforce physical constraint that all LEDs lie on cone surface.

**Algorithm:**

1. **Estimate cone parameters** (if not already known):
   ```
   For each observed LED at (x, y, z):
     r = √((x-cx)² + (y-cy)²)
     h = z
   
   Fit: r = a + b×h  (weighted least squares)
   
   r_bottom = a
   r_top = a + b×H
   ```

2. **Project each LED:**
   ```
   For LED at position (x, y, z):
     # Expected radius at this height
     r_expected = r_bottom - (r_bottom - r_top) × (z / H)
     
     # Current angle
     θ = atan2(y - cy, x - cx)
     
     # Project onto surface
     x_new = cx + r_expected × cos(θ)
     y_new = cy + r_expected × sin(θ)
     z_new = z  (unchanged)
   ```

**Effect:** Radial displacement to cone surface, preserving height and angle.

**Mathematical guarantee:** All LEDs now satisfy r(h) = cone_radius(h).

## Error Analysis

### Sources of Error

1. **Camera positioning:** ±5-10cm
   - Measuring distance/angle from tree
   - Camera not perfectly level
   - Tripod stability

2. **LED detection:** ±2-3 pixels
   - Brightness threshold selection
   - Centroid calculation
   - Camera focus

3. **Camera model:** ±1-2cm
   - Simplified projection (no lens distortion)
   - Focal length estimation
   - Principal point assumption

4. **Cone approximation:** ±1-2cm
   - Tree not perfectly conical
   - Branches/ornaments create irregularities
   - LEDs not exactly on surface

### Error Mitigation Strategies

| Error Source | Mitigation |
|--------------|------------|
| Camera position | Multiple cameras (redundancy), weighted triangulation |
| LED detection | Reflection filtering, confidence scoring |
| Camera model | Cone constraint acts as regularization |
| Cone approximation | Direct estimation from all-on photos |

### Expected Accuracy

**With good setup (5 cameras, clean tree, careful calibration):**
- Observed LEDs (triangulated): ±1.5-2cm
- Predicted LEDs (interpolated): ±2-3cm
- Back of tree (extrapolated): ±3-5cm

**With minimal setup (3 cameras, some reflections, quick calibration):**
- Observed LEDs: ±3-4cm
- Predicted LEDs: ±4-6cm
- Back of tree: ±5-8cm

## Design Decisions & Tradeoffs

### 1. Sequential vs. Color-Coded Capture

**Choice:** Sequential (one LED at a time)

**Rationale:**
- ✅ Simple, reliable
- ✅ Works with any LED type (white or RGB)
- ✅ Excellent reflection filtering (temporal signature)
- ✅ Easy debugging
- ❌ Slower (80 sec vs 5 sec hypothetically)

**Tradeoff:** Accept 6-7 minutes total capture time for much higher reliability.

### 2. Post-Projection vs. Constrained Triangulation

**Choice:** Offer both (user selectable)

**Rationale:**
- Post-projection: Simpler, works with any geometry
- Constrained: Better accuracy, fewer unknowns
- Cone estimation: Can use all-on photos OR sparse points

**Tradeoff:** Slightly more complex code, but users get best of both worlds.

### 3. Camera Calibration Method

**Choice:** Manual measurement (distance, angle, height)

**Rationale:**
- ❌ Could use chessboard calibration (more accurate)
- ✅ Manual faster (~2 min vs 20 min)
- ✅ Accurate enough for our needs (±5cm acceptable)
- ✅ Users understand measurements

**Tradeoff:** Accept slightly lower precision for much better user experience.

### 4. Reflection Detection Approach

**Choice:** Spatial clustering across LED indices

**Alternatives considered:**
- Brightness thresholding only → Misses dim reflections
- Temporal analysis only → Requires multiple captures
- Machine learning → Overkill, needs training data

**Rationale:**
- ✅ Exploits unique reflection signature (same pixel, different LEDs)
- ✅ No training needed
- ✅ Works with varied tree decorations

### 5. Confidence Weighting Strategy

**Choice:** Multi-factor composite score

**Alternatives:**
- Binary (good/bad) → Loses information
- Single factor (e.g., only brightness) → Misses other issues
- Complex ML model → Hard to interpret, tune

**Rationale:**
- ✅ Combines multiple signals
- ✅ Tunable weights
- ✅ Interpretable
- ✅ Degrades gracefully

## Performance Characteristics

### Computational Complexity

**Capture phase:** O(N) where N = number of LEDs
- Dominated by camera/LED hardware delays

**Detection phase:** O(N × C) where C = number of cameras
- Per-LED: Threshold, contour finding, centroid
- Parallelizable across LEDs

**Reflection clustering:** O(N² × C) worst case
- Per camera: Compare all detection pairs
- In practice: O(N × K) where K = avg cluster size (~5-10)

**Triangulation:** O(N × C²)
- Per LED: Solve least squares with C observations
- Dominant computation

**Sequential prediction:** O(N)
- Linear scan through gaps

**Cone projection:** O(N)
- Simple calculation per LED

### Scalability

**Current:** 200 LEDs, 5 cameras
- Capture: 7 minutes
- Processing: 3 minutes
- Total: 10 minutes

**Scaled to 1000 LEDs, 5 cameras:**
- Capture: 35 minutes (linear scaling)
- Processing: 10 minutes (triangulation is bottleneck)
- Total: 45 minutes

**Scaled to 200 LEDs, 10 cameras:**
- Capture: 14 minutes (2x camera positions)
- Processing: 8 minutes (more triangulation work)
- Better accuracy (more redundancy)

## System Robustness

### Failure Modes & Recovery

1. **MQTT connection lost during capture:**
   - Detection: LED doesn't light up
   - Recovery: Pause, reconnect, resume from last LED

2. **Camera crash:**
   - Detection: Photo save fails
   - Recovery: Re-initialize camera, retry last LED

3. **LED not detected in any camera:**
   - Detection: Zero observations after all cameras
   - Recovery: Flag for manual inspection, use prediction

4. **Excessive reflections:**
   - Detection: >50% of detections flagged as reflections
   - Recovery: Increase confidence threshold, warn user

5. **Poor cone fit:**
   - Detection: High residuals in cone estimation
   - Recovery: Skip cone projection, use XYZ only, warn user

6. **Inconsistent camera calibrations:**
   - Detection: Triangulation residuals >20 pixels
   - Recovery: Flag suspicious cameras, ask user to re-measure

## Extension Points

### Current Design Supports:

1. **Different tree shapes:**
   - Change cone to cylinder: r(h) = r_const
   - Change to parabola: r(h) = r₀√(1 - h/H)
   - Use multiple segments for non-uniform taper

2. **Additional constraints:**
   - Helical wrapping: θ(h) = θ₀ + k×h
   - Minimum spacing: ||LED_i - LED_{i+1}|| > d_min
   - Smoothness: ∇²position small

3. **Alternative capture methods:**
   - Video instead of photos
   - Stereo cameras
   - Structured light
   - Time-of-flight depth camera

4. **Machine learning:**
   - Train CNN for LED detection
   - Learn tree shape from many examples
   - Predict positions with uncertainty

5. **Real-time processing:**
   - Stream images during capture
   - Progressive triangulation
   - Live preview of mapping

## Summary

This system combines several techniques to achieve robust LED position mapping:

1. **Physical constraints** (cone model) reduce problem dimensionality
2. **Multi-view geometry** (triangulation) provides 3D information
3. **Confidence modeling** handles imperfect data
4. **Sequential prediction** fills gaps intelligently
5. **Reflection filtering** deals with real-world complications

The result: ±2-3cm accuracy with minimal user effort (10 minutes total), suitable for LED animation applications where sub-centimeter precision isn't required.

**Key innovations:**
- All-on photo for direct cone estimation
- Reflection clustering by spatial-temporal signature
- Corrected angular confidence (center of frame is best)
- Cone-constrained triangulation in (h, θ) space
- Adaptive sequential prediction with confidence decay

**Mathematical foundation:** Standard computer vision (triangulation, least squares) enhanced with domain-specific constraints (cone geometry, reflection physics, spatial coherence).
