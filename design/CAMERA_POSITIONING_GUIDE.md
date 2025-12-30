# Camera Positioning Guide

A critical part of LED mapping is knowing where your camera is relative to the tree. Here are your options, from simplest to most accurate.

## Option 1: Simple Manual Measurement ⭐ **Recommended for Most Users**

### What You Need
- Measuring tape
- Marker or tape for floor
- Compass app on phone (optional)

### Steps

**1. Mark Tree Center**
- Put tape on floor directly below tree center
- This is your reference point (0, 0)

**2. For Each Camera Position, Measure:**

**Distance:**
- Measure from tree center mark to phone
- Aim for 1.5-2.0 meters

**Angle:**
- Use compass app OR just estimate
- 0° = Front of tree (facing wall)
- 90° = Right side
- 180° = Back (against wall)
- 270° = Left side

**Height:**
- Measure from floor to camera lens
- Aim for middle of tree (~1.0m)

**3. Record in App:**
- Before each capture, tap "Calibrate Position"
- Enter your measurements
- App saves them automatically

### Example Setup

```
Position 1: Distance=1.5m, Angle=0°,   Height=1.0m (front)
Position 2: Distance=1.5m, Angle=60°,  Height=1.0m (front-right)
Position 3: Distance=1.5m, Angle=120°, Height=1.0m (side-right)
Position 4: Distance=1.5m, Angle=240°, Height=1.0m (side-left)
Position 5: Distance=1.5m, Angle=300°, Height=1.0m (front-left)
```

**Tip:** Keep distance and height the same for all positions, only change the angle. This makes triangulation more reliable.

---

## Option 2: Use the Flutter App's Calibration UI ⭐⭐ **Best Experience**

### Features
- Visual diagram showing camera position
- Quick angle presets (0°, 90°, 180°, 270°)
- Saves calibration with each capture
- Exports calibration.json automatically

### Usage

1. **Before Each Capture:**
   - Position phone on tripod
   - Tap "Calibrate Position" in capture screen
   - Measure and enter values (see Option 1)
   - See visual preview of setup
   - Save calibration

2. **Export:**
   - When you export ZIP, calibration data is included
   - File: `camera_calibrations.json`

3. **Process:**
   ```bash
   python process_with_calibration.py led_captures/ \
       --calibration camera_calibrations.json \
       --num-leds 200 \
       --tree-height 2.0
   ```

---

## Option 3: Self-Calibration (Advanced) 🎓

### Concept
Use the LEDs themselves to solve for camera positions. Since you know LEDs should follow a helical pattern, you can optimize both LED positions AND camera positions simultaneously.

### When to Use
- You can't easily measure camera positions
- You want maximum accuracy
- You're comfortable with advanced processing

### Implementation

This uses **bundle adjustment** - an algorithm that jointly optimizes camera and LED positions.

```python
from scipy.optimize import least_squares

def bundle_adjustment(initial_camera_params, initial_led_params, observations):
    """
    Jointly optimize camera positions and LED positions
    
    Args:
        initial_camera_params: Initial guesses for camera positions
        initial_led_params: Initial guesses for LED positions (from helix model)
        observations: Dict of {(camera_idx, led_idx): pixel_position}
    """
    
    def reprojection_error(params):
        # Split params into camera and LED portions
        n_cameras = len(initial_camera_params)
        camera_params = params[:n_cameras * 6]  # 6 params per camera (pos + rotation)
        led_params = params[n_cameras * 6:]     # 3 params per LED (x, y, z)
        
        errors = []
        for (cam_idx, led_idx), pixel_obs in observations.items():
            # Project LED through camera
            pixel_pred = project_point(
                led_position=led_params[led_idx*3:(led_idx+1)*3],
                camera_params=camera_params[cam_idx*6:(cam_idx+1)*6]
            )
            
            # Reprojection error
            errors.extend([
                pixel_obs[0] - pixel_pred[0],
                pixel_obs[1] - pixel_pred[1]
            ])
        
        return errors
    
    # Optimize
    result = least_squares(
        reprojection_error,
        x0=np.concatenate([camera_params.flatten(), led_params.flatten()]),
        verbose=2
    )
    
    return result.x
```

**Note:** This is advanced and requires good initial guesses. Start with Option 1 or 2, then refine with this if needed.

---

## Comparison

| Method | Accuracy | Ease of Use | Time Required |
|--------|----------|-------------|---------------|
| Manual Measurement | Good (±5cm) | Easy | 5 min |
| App Calibration | Good (±5cm) | Very Easy | 3 min |
| Self-Calibration | Excellent (±1-2cm) | Hard | 15-30 min |

---

## Tips for Accurate Positioning

### 1. Consistency
- Keep camera height the same for all positions
- Keep distance the same if possible
- Only vary the angle around the tree

### 2. Coverage
- Aim for evenly spaced angles
- Don't need to measure perfectly - approximate is fine
- 3-5 positions is plenty

### 3. Stability
- Use tripod or stable surface
- Phone shouldn't move during capture
- Mark position on floor so you can verify

### 4. Verification
- After measuring, take a test photo
- Check that tree is roughly centered in frame
- Distance looks right (tree not too big/small in frame)

---

## Troubleshooting

### "Poor triangulation results"

**Problem:** LED positions look wrong or scattered

**Solution:**
1. Check your measurements are in meters (not cm!)
2. Verify angle is 0-360° (not radians)
3. Make sure you're measuring from tree CENTER (not edge)
4. Try more camera positions
5. Ensure cameras have good overlap (all see some same LEDs)

### "Some LEDs are way off"

**Problem:** Most LEDs look good but some are completely wrong

**Solution:**
- These LEDs might only be visible from 1 camera
- Add another camera position to see them
- Or accept lower confidence for these LEDs
- Sequential prediction will fill them in reasonably

### "Don't have a measuring tape"

**Solution:**
- Use your phone! Most are ~15cm tall
- Or measure your foot/shoe length
- Or use any object of known size
- Accuracy of ±20cm is usually fine

---

## What the Processing Script Needs

The `process_with_calibration.py` script expects:

```json
{
  "calibrations": [
    {
      "position_number": 1,
      "distance_from_center": 1.5,
      "angle_from_front": 0.0,
      "height_from_ground": 1.0,
      "notes": "Front of tree"
    },
    {
      "position_number": 2,
      "distance_from_center": 1.5,
      "angle_from_front": 90.0,
      "height_from_ground": 1.0,
      "notes": "Right side"
    }
  ]
}
```

The app generates this automatically!

---

## Quick Start

**Absolute Minimum:**
1. Position phone ~1.5m from tree at front → Record: 1.5m, 0°, 1.0m
2. Move phone to right side → Record: 1.5m, 90°, 1.0m
3. Move phone to left side → Record: 1.5m, 270°, 1.0m
4. Enter these in app's calibration screen
5. Done! Process will work.

**Recommended:**
Add 2 more positions (45° and 315°) for better coverage.

**For perfectionists:**
Use 7+ positions every 45° around the tree, use bundle adjustment refinement.

---

## Remember

- You DON'T need millimeter precision
- Approximate measurements work fine
- The sequential prediction compensates for gaps
- You care less about the back anyway!

The goal is to get camera positions roughly right so triangulation can work. Even with ±10cm errors in your measurements, you'll still get good LED positions (±5cm), which is plenty accurate for lighting effects.
