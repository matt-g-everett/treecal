# Cone Surface Projection - Physical Constraint Refinement

## The Idea

We KNOW that LEDs are wrapped around a Christmas tree, which is approximately cone-shaped. Therefore, all LEDs should lie on the surface of a cone.

Triangulation gives us approximate 3D positions, but measurement errors mean some LEDs might be:
- **Inside the cone** (too close to center)
- **Outside the cone** (too far from center)  
- **At wrong radius for their height**

**Solution:** Project all triangulated positions onto the estimated cone surface.

## How It Works

### Step 1: Estimate Cone Parameters

From observed (triangulated) LEDs:

```python
# For each observed LED at height h:
#   Calculate radius r from tree center
#   
# Fit linear model: r = r_bottom - (r_bottom - r_top) * (h / H)
#
# Using weighted least squares (weight by confidence)
```

**Example output:**
```
Estimated cone parameters:
  Center: (0.023, -0.015)
  Radius at bottom (h=0): 0.487m
  Radius at top (h=2.0): 0.052m
```

### Step 2: Project Each LED

For each LED at position (x, y, z):

1. **Calculate current radius** from center:
   ```
   r_current = sqrt((x - cx)^2 + (y - cy)^2)
   ```

2. **Calculate expected radius** at height z:
   ```
   r_expected = r_bottom - (r_bottom - r_top) * (z / H)
   ```

3. **Scale to cone surface**, preserving angle:
   ```
   angle = atan2(y - cy, x - cx)
   x_new = cx + r_expected * cos(angle)
   y_new = cy + r_expected * sin(angle)
   z_new = z  (height unchanged)
   ```

**Visual:**
```
         Before              After
       (scattered)       (on surface)
       
          * *                 *
         *   *               * *
        *  *  *             *   *
       *   •   *           *  •  *
        * tree *            * ↓  *
         *   *               * *
          * *                 *
          
     (some LEDs inside/    (all LEDs on
      outside cone)         cone surface)
```

### Step 3: Measure Improvement

Track adjustment distance for each LED:

```
Average adjustment: 2.34cm
Max adjustment: 8.71cm
```

Small adjustments indicate good initial triangulation.
Large adjustments suggest measurement errors that are now corrected.

## Benefits

### 1. **Enforces Physical Plausibility**

LEDs MUST be on the tree surface. Projection guarantees this.

### 2. **Corrects Measurement Errors**

Triangulation errors (camera position, lens distortion, pixel detection) get corrected by snapping to the cone.

### 3. **Improves Predicted LEDs**

Sequential prediction works better when observed LEDs follow a consistent pattern (the cone surface).

### 4. **Better Animations**

Lighting effects that treat the tree as a cone (e.g., "rising effect", "spiral") will look more natural.

## Example Results

**Before cone projection:**
```
LED 42:
  Triangulated: (0.234, -0.567, 0.842)
  Radius: 0.612m (at height 0.842m)
  Expected radius: 0.487m
  Error: 0.125m (12.5cm off!)
```

**After cone projection:**
```
LED 42:
  Projected: (0.187, -0.453, 0.842)
  Radius: 0.487m (at height 0.842m)
  Adjustment: 0.125m
  Now on cone surface ✓
```

## When Cone Projection Helps Most

### ✅ Helps When:
- Tree is actually cone-shaped
- Significant measurement errors in triangulation
- Want physically plausible positions
- Sparse observations (few cameras)

### ⚠️ May Not Help When:
- Tree is irregular shape (very full/sparse sections)
- Perfect triangulation accuracy (adjustments will be tiny)
- Tree has drooping branches (not a perfect cone)

## Usage

**Enable (default):**
```bash
python process_advanced.py images/ \
    --calibration calibrations.json \
    --num-leds 200 \
    --cone-projection
```

**Disable:**
```bash
python process_advanced.py images/ \
    --calibration calibrations.json \
    --num-leds 200 \
    --no-cone-projection
```

## Output

**During processing:**
```
==========================================================
PHASE 5: CONE SURFACE PROJECTION
==========================================================

Estimated cone parameters:
  Center: (0.023, -0.015)
  Radius at bottom (h=0): 0.487m
  Radius at top (h=2.0): 0.052m

Cone surface projection:
  Refined 200 LED positions
  Average adjustment: 2.34cm
  All LEDs now lie on cone surface
```

**Interpretation:**
- **Small average adjustment** (< 3cm): Good triangulation, cone is refining small errors
- **Medium adjustment** (3-8cm): Moderate errors being corrected
- **Large adjustment** (> 8cm): Either poor triangulation or tree isn't very cone-shaped

## Advanced: Custom Cone Shape

If your tree isn't a simple cone, you could extend this to:

### Parabolic Profile
```python
r = r_bottom * (1 - (h/H)^2)^0.5
```
Fuller at bottom, tapers faster at top.

### Multi-Segment Cone
```python
if h < H/2:
    r = r_bottom - slope1 * h
else:
    r = r_mid - slope2 * (h - H/2)
```
Different taper rates for top vs bottom.

### Measured Profile
Manually measure tree radius at multiple heights, interpolate.

## Mathematical Details

### Weighted Least Squares Cone Fitting

Given observed LEDs with positions and confidence scores:

```
Minimize: Σ w_i * (r_i - (a + b*h_i))^2

Where:
  r_i = radius of LED i
  h_i = height of LED i
  w_i = confidence of LED i
  a, b = parameters to solve for
  
Solution:
  [a] = (A^T W A)^-1 A^T W r
  [b]
  
  Where A = [1  h_0]
            [1  h_1]
            [⋮  ⋮  ]
            [1  h_n]
            
  W = diag([w_0, w_1, ..., w_n])
```

Then:
```
r_bottom = a
r_top = a + b * H
```

### Projection Geometry

For LED at (x, y, z):

```
Current angle: θ = atan2(y - cy, x - cx)
Expected radius: r = r_bottom - (r_bottom - r_top) * z/H

Projected position:
  x' = cx + r * cos(θ)
  y' = cy + r * sin(θ)
  z' = z
```

This is a **radial projection** - moves LED toward/away from center axis while preserving:
- Height (z)
- Angle around tree (θ)

## Comparison to Alternatives

### Alternative 1: Helical Model Projection

**Idea:** Project onto helical path instead of just cone surface

**Pros:**
- Even tighter constraint
- Enforces spiral wrapping pattern

**Cons:**
- Assumes perfect helical wrapping
- Real LED strands have irregularities
- Over-constrains the problem

**When to use:** If you KNOW the wrapping is very regular

### Alternative 2: No Projection

**Idea:** Trust triangulation completely

**Pros:**
- No assumptions about tree shape
- Preserves all triangulation data

**Cons:**
- Doesn't fix measurement errors
- LEDs might not be physically plausible

**When to use:** When triangulation is very accurate (low errors)

### Cone Projection (Current)

**Sweet spot:**
- Physical plausibility ✓
- Corrects errors ✓
- Doesn't over-constrain ✓
- Works for irregular strands ✓

## Validation

**How to check if cone projection is helping:**

1. **Run with and without:**
   ```bash
   # With projection
   python process_advanced.py ... --cone-projection
   
   # Without projection  
   python process_advanced.py ... --no-cone-projection
   ```

2. **Compare results:**
   - Visualize both in 3D
   - Check if "with" looks more uniform
   - See if animations look better with projected positions

3. **Check adjustment distances:**
   - Average < 3cm: Projection is refining
   - Average > 8cm: Either bad triangulation or irregular tree

4. **Validate on known LEDs:**
   - If you manually measured some LED positions
   - Compare projected vs unprojected
   - Which is closer to ground truth?

## Summary

Cone surface projection:
- ✅ Enforces physical constraint (LEDs on tree)
- ✅ Corrects triangulation errors
- ✅ Improves downstream predictions
- ✅ Takes ~1 second (negligible overhead)
- ✅ Can be disabled if not wanted

**Recommendation:** Keep it enabled (default) unless you have a good reason not to.

The typical ~2-3cm adjustments show it's working correctly - small refinements that improve overall consistency without dramatically changing the positions.
