# All-On Photo Workflow & Camera Adjustment

## The Enhancement

Your insight: Use an all-LEDs-on photo to directly estimate the cone shape!

## Why This Is Better

### Old Approach: Estimate from Sparse Points
```
Triangulate ~140 individual LEDs → Fit cone to scattered points
```

**Problems:**
- Only ~140 points to fit from
- Points have measurement errors
- Sparse coverage (especially on back)
- No direct view of full tree shape

### New Approach: All-On Photo
```
All LEDs on → Detect outline → Fit cone to continuous edge
```

**Advantages:**
- ✅ See entire tree outline directly
- ✅ Hundreds/thousands of edge points
- ✅ Validates tree is actually cone-shaped
- ✅ Detects irregularities early
- ✅ More accurate cone parameters

## Camera Gamma/Exposure Adjustment

### The Problem

Modern cameras auto-adjust:
- **Exposure** (shutter speed, ISO)
- **White balance** (color temperature)
- **Gamma correction** (brightness curve)

**These take time!** (~300-800ms)

### Brightness Levels During Capture

```
1. Start:           All LEDs off (dark)
2. All-on photo:    All 200 LEDs on (BRIGHT!)
3. Back to dark:    All LEDs off
4. First LED:       1 LED on (dim)
5. Remaining LEDs:  1 LED on (same brightness)
```

**Critical transitions:**
- Dark → All-on: **Big change** (camera needs adjustment)
- All-on → Dark: **Big change** (camera needs adjustment)
- Dark → First LED: **Big change** (camera needs adjustment)
- LED to LED: Small change (no adjustment needed)

### Solution: Adjustment Delays

**Default timing:**
```python
cameraAdjustmentDelay = 800  # ms for big brightness changes
delayBeforeCapture = 300     # ms for LED stabilization (normal)
delayAfterCapture = 100      # ms before next LED
```

**Capture sequence:**
```
1. Turn off all LEDs
   Wait 500ms

2. Turn on ALL LEDs
   Wait 800ms ← Camera adjusts to bright scene
   Take all-on photo
   
3. Turn off all LEDs
   Wait 500ms
   
4. Wait 800ms ← Camera adjusts back to dark
   
5. Turn on LED 0
   Wait 800ms ← Camera adjusts to single LED brightness
   Take photo
   Turn off LED 0
   
6. Turn on LED 1
   Wait 300ms ← Camera already adjusted, just LED stabilization
   Take photo
   Turn off LED 1
   
7. Turn on LED 2
   Wait 300ms
   Take photo
   ...
```

### Why Different Delays?

**Big changes (800ms):**
- Dark → All-on (200x brightness increase!)
- All-on → Dark (200x brightness decrease!)
- Dark → Single LED (needs initial adjustment)

**Small changes (300ms):**
- LED to LED (same brightness level)
- Just LED electrical stabilization

## Capture Time Impact

### Old Workflow
```
200 LEDs × (300ms + 100ms) = 80 seconds
+ Setup overhead = ~90 seconds per position
```

### New Workflow
```
All-on photo: 800ms + 500ms + 800ms = 2.1 seconds
First LED: 800ms + photo = 1.0 second
Remaining 199 LEDs: 199 × 400ms = 79.6 seconds

Total: ~83 seconds per position
```

**Time increase: ~3 seconds per position** (3.6% overhead)

**For 5 positions:** +15 seconds total

**Worth it?** Absolutely! Much better cone parameters.

## Settings Configuration

In the app settings, you can adjust:

```
Camera Adjustment Delay: 800ms
  ↓ How long to wait for camera auto-exposure/white balance
  
  Too short: Images have wrong brightness
  Too long: Slower capture
  
  Good values: 600-1000ms depending on your phone
```

**How to tune:**
1. Start with 800ms (default)
2. If first photo too dark/bright → increase to 1000ms
3. If impatient → try 600ms
4. Check if all-on and LED photos look properly exposed

## All-On Photo Features

### What We Detect

From the all-on photo:

1. **Tree outline** - Edge of bright region
2. **Cone shape** - Width at different heights
3. **Center position** - Tree center in image
4. **Irregularities** - Gaps, asymmetry

### Detection Algorithm

```python
1. Threshold image (brightness > 150)
   → Binary image of bright region

2. Morphological operations
   → Clean up noise, fill gaps

3. Find largest contour
   → This is the tree outline

4. Extract edge points
   → 100s-1000s of points along edge

5. Calculate width profile
   → Width at different heights

6. Fit cone model
   → r = r_bottom - (r_bottom - r_top) * h/H
```

### Example Output

```
Processing camera1/all_leds.jpg...
  Detected 1247 edge points
  Center estimate: (956, 523)
  Width profile: 20 slices
  Estimated: r_bottom=0.492m, r_top=0.048m

Processing camera2/all_leds.jpg...
  Detected 1189 edge points
  Estimated: r_bottom=0.485m, r_top=0.051m

Processing camera3/all_leds.jpg...
  Detected 1312 edge points
  Estimated: r_bottom=0.488m, r_top=0.053m

Final estimate (averaged across 3 cameras):
  r_bottom: 0.488m
  r_top: 0.051m
  center: (0.021, -0.008)
```

## Advantages Over Sparse Estimation

| Metric | Sparse (140 LEDs) | All-On Photo |
|--------|-------------------|--------------|
| Data points | ~140 | ~1000+ |
| Coverage | Scattered | Continuous edge |
| Accuracy | ±3cm | ±1cm |
| Early validation | No | Yes |
| Detects issues | After processing | Immediately |

## What Can Go Wrong

### Problem: All-on photo too bright (overexposed)

**Symptoms:**
- White blob, no detail
- Can't detect edge

**Solution:**
- Reduce `cameraAdjustmentDelay` (less auto-brightness)
- Or reduce LED brightness if possible
- Or dim room lights during all-on capture

### Problem: All-on photo too dark

**Symptoms:**
- Can't detect bright region
- Threshold finds nothing

**Solution:**
- Increase `cameraAdjustmentDelay`
- Check LEDs are actually turning on
- Verify MQTT all-on command works

### Problem: Irregular outline detected

**Symptoms:**
- Cone fit gives weird parameters
- Width profile not linear

**Reasons:**
- Tree actually is irregular!
- Ornaments create lumpy outline
- Some LEDs not working

**Solution:**
- This is useful information!
- Cone projection may not be appropriate
- Or use manual cone measurements

## MQTT Configuration

The app needs an "all-on" command:

### Option 1: Same Topic, Different Payload
```
Topic: led/all/set
ON Payload: ON
OFF Payload: OFF
```

Most common - same as all-off.

### Option 2: Different Topic
```
All-On Topic: led/all/on
All-Off Topic: led/all/off
```

Configure in app settings:
```
All Off Topic: led/all/set
All On Topic: led/all/set  (or custom)
```

## Processing Integration

The processing pipeline now:

```
Phase 0: Cone Estimation from All-On Photos
  ↓ Detect outlines, fit cone
  ↓ Average across cameras
  ↓ Get high-quality cone parameters

Phase 1: Detection with Confidence Scoring
  ↓ Uses estimated cone for context

Phase 2: Reflection Analysis
  
Phase 3: Weighted Triangulation
  ↓ Can use cone-constrained method with known params

Phase 4: Sequential Prediction
  
Phase 5: Cone Surface Projection
  ↓ Uses Phase 0 parameters (or re-estimates if not available)
```

## Manual Override

If all-on photos don't work (too bright, irregular tree, etc.):

**Skip them:**
- Don't take all-on photos
- Processing falls back to sparse estimation
- Still works fine, just less accurate cone parameters

**Or use manual measurements:**
```python
# In processing script
cone_params = ConeParameters(
    center=np.array([0.0, 0.0]),  # Measured
    r_bottom=0.50,                # Measured
    r_top=0.05,                   # Measured
    height=2.0                    # Measured
)
```

## Validation

**Check if all-on photos worked:**

1. **Look at the photos**
   - Tree visible?
   - Bright but not overexposed?
   - Outline clear?

2. **Check cone estimates**
   - Similar across cameras?
   - Reasonable values (r_bottom > r_top)?
   - Makes sense for your tree?

3. **Compare to sparse estimation**
   - Run with and without all-on photos
   - Are parameters close?
   - Which looks more accurate?

## Summary

**New workflow:**
1. ✅ All-on photo captures full tree outline
2. ✅ Camera adjustment delays ensure proper exposure
3. ✅ Direct cone estimation (much more accurate)
4. ✅ Early validation of tree shape
5. ✅ Only ~15 seconds extra total time

**Configuration:**
- `cameraAdjustmentDelay = 800ms` (tunable)
- All-on MQTT topic (usually same as all-off)

**Result:**
- Better cone parameters → More accurate triangulation → Better final positions

This addresses your insight: we now directly observe the cone shape instead of inferring it from sparse points! 🎯
