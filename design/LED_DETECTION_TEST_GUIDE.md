# LED Detection Test Feature

## Overview

The LED Detection Test screen provides real-time feedback on LED detection quality using OpenCV, helping you validate your camera setup before running a full capture.

## Purpose

**Quick validation workflow:**
1. Position camera
2. Align cone overlay to tree
3. Test detection on individual LEDs
4. Get instant feedback on detection quality
5. Adjust setup if needed

## Features

### Cone Calibration Overlay

**Fixed cone height** spanning most of the screen:
- Apex at 10% from top (★ star marker)
- Base at 90% from top (yellow oval)
- User positions themselves to fit tree in cone

**Interactive adjustments:**
- **Swipe ↔**: Adjust base width to match tree
- **Swipe ↕**: Adjust base height for perspective correction
- **Reset button**: Return to default settings

### LED Detection Testing

**Select any LED (0-199):**
- Increment/decrement buttons
- Tests one LED at a time

**Detection process:**
1. Turn off all LEDs
2. Turn on selected test LED
3. Wait for camera adjustment (800ms)
4. Capture single frame
5. Process with OpenCV
6. Display results

### Detection Results

**Visual overlay on camera:**
- Green circle = high confidence (>70%)
- Orange circle = medium confidence (40-70%)
- Red circle = low confidence (<40%)
- Crosshair marks exact detection point
- Percentage shows detection confidence

**Detailed results panel:**
- Position (x, y) in pixels
- Brightness value
- Blob area
- **Detection confidence** - Is this a real LED?
- **Angular confidence** - How accurate is angle measurement?
- Normalized height (0-100%)
- Cone bounds validation

## Confidence Scores Explained

### Detection Confidence

**Question:** "Is this a real LED or reflection/noise?"

**Factors:**
- ✅ Brightness (>200 = excellent, 150-200 = good, <150 = poor)
- ✅ Size (10-50 px² = good, <5 = noise, >50 = bloom)
- ✅ Cone bounds (inside = plausible, outside = likely reflection)

**Does NOT depend on:**
- ❌ Position in frame (edge LEDs are valid)
- ❌ Camera angle

### Angular Confidence

**Question:** "How accurate will the angle measurement be?"

**Factors:**
- ✅ Distance from centerline (center = 100%, edge = 30%)
- ✅ Radial position (accounts for lens distortion)

**Used for:**
- Weighting observations during triangulation
- Not used for detection filtering

### Triangulation Weight

**Combined score** for multi-camera triangulation:
```
weight = detection_confidence × angular_confidence
```

**Example:**
- Edge LED: detection=0.9, angular=0.4 → weight=0.36 (use with low weight)
- Center LED: detection=0.9, angular=1.0 → weight=0.90 (use with high weight)

## Typical Results

### Good Detection
```
Position: (520, 380)
Brightness: 245
Area: 28 px²
Detection confidence: 95%
Angular confidence: 85%
Normalized height: 45%
✓ Inside cone bounds
```

**Interpretation:** Excellent! High confidence, good position.

### Edge Detection
```
Position: (50, 380)
Brightness: 230
Area: 22 px²
Detection confidence: 90%
Angular confidence: 35%
Normalized height: 45%
✓ Inside cone bounds
```

**Interpretation:** Real LED, but edge position. Will be used in triangulation with lower weight.

### Reflection
```
Position: (520, 900)
Brightness: 180
Area: 85 px²
Detection confidence: 25%
Angular confidence: 65%
Normalized height: -15%
✗ Outside cone bounds
```

**Interpretation:** Likely reflection or noise. Below tree bounds, large blob, will be filtered out.

### Weak LED
```
Position: (520, 380)
Brightness: 140
Area: 8 px²
Detection confidence: 35%
Angular confidence: 85%
Normalized height: 45%
✓ Inside cone bounds
```

**Interpretation:** Very dim. May be occluded, needs brighter LEDs or better camera settings.

## Troubleshooting

### No Detections
**Problem:** LED turned on but nothing detected

**Solutions:**
- Increase camera exposure (adjust phone camera settings)
- Check MQTT connection (LED actually turning on?)
- Reduce brightness threshold in code (default 150)
- Room too bright (turn off lights)

### Multiple Detections
**Problem:** One LED lights up, but 3+ spots detected

**Causes:**
- Reflections from ornaments/tinsel
- Bloom/glare from very bright LED
- Neighboring LEDs accidentally on

**Solutions:**
- Most are filtered by low confidence
- Highest confidence usually correct
- Consider dimming LEDs slightly

### Outside Cone Bounds
**Problem:** Detection outside yellow cone overlay

**Solutions:**
- LED actually outside tree (back side visible)
- Adjust cone width (swipe ↔)
- Adjust cone perspective (swipe ↕)
- Camera positioned incorrectly

### Low Brightness
**Problem:** Detection confidence <40% due to brightness

**Solutions:**
- Increase LED brightness
- Adjust camera exposure compensation
- Move closer to tree
- Ensure dark environment

## Integration with Full Capture

**Test screen settings saved:**
- Cone parameters exported to calibration file
- Same detection algorithm used in Python processing
- Confidence thresholds consistent

**Workflow:**
1. Use test screen to validate setup
2. Adjust cone overlay until LEDs fit well
3. Test 3-5 LEDs at different heights
4. Ensure most have >70% detection confidence
5. Export cone calibration
6. Run full capture with confidence

## Technical Details

### OpenCV Processing

**Algorithm:**
1. Convert to grayscale
2. Gaussian blur (5×5 kernel)
3. Binary threshold (default 150)
4. Find contours
5. Filter by area (5-100 px²)
6. Calculate centroids
7. Score confidence

**Performance:**
- Runs in isolate (doesn't block UI)
- Processes 1920×1080 image in ~100-200ms
- Real-time feedback on detection

### Cone Parameters

**Saved format:**
```json
{
  "apex_y_pixels": 108,
  "base_y_pixels": 972,
  "base_width_pixels": 720,
  "base_height_pixels": 180,
  "tree_height_pixels": 864
}
```

**Used for:**
- Normalized height calculation: `h = (base_y - led_y) / tree_height`
- Cone bounds validation: `radius(h) = (width/2) × (1 - h)`
- Informing Python triangulation

## Best Practices

1. **Test in actual capture conditions**
   - Same lighting
   - Same camera position
   - Same LED brightness

2. **Test at multiple heights**
   - Bottom LED (near base oval)
   - Middle LED (center of cone)
   - Top LED (near apex)

3. **Test at different angles**
   - Centerline LED (best angular confidence)
   - Edge LED (lower angular confidence)

4. **Validate cone alignment**
   - All tested LEDs should be inside cone
   - If many outside, adjust cone overlay

5. **Check consistency**
   - Test same LED twice
   - Should get similar results
   - If very different, lighting/camera issue

## Future Enhancements

**Potential additions:**
- Live continuous detection (video stream processing)
- Multi-LED testing (test multiple at once)
- Heatmap visualization (coverage map)
- Auto-brightness adjustment recommendations
- Reflection detection warnings
- Historical results comparison

This feature opens the door for iterative improvements and real-time feedback during setup! 🎯
