# Python Visualization Tools

## Overview

**The Flutter app does ALL the processing!** These Python scripts are OPTIONAL and only provide visualization of the results.

## What You Need Python For

✅ **3D Visualization** - View your LED positions in 3D
✅ **Statistics** - Summary of mapping quality
✅ **Export Plots** - Save visualizations as PNG

That's it! Everything else is in Flutter.

## Setup

### Install Dependencies

```bash
pip install -r requirements_visualize.txt
```

This installs only:
- numpy (for calculations)
- matplotlib (for plotting)

**No OpenCV, no scipy, no other heavy dependencies needed!**

## Usage

### Basic Visualization

```bash
python visualize.py led_positions.json
```

Shows interactive 3D plot with:
- Blue dots = Observed LEDs (triangulated from cameras)
- Red dots = Predicted LEDs (interpolated/extrapolated)
- Cone outline for reference

### Color by Confidence

```bash
python visualize.py led_positions.json --confidence
```

Colors LEDs by confidence score (green = high, purple = low)

### Save to File

```bash
python visualize.py led_positions.json --save tree_3d.png
```

Saves high-resolution (300 DPI) PNG instead of showing interactive plot

### 2D Projections

```bash
python visualize.py led_positions.json --projections
```

Shows top, side, and front views

### Statistics Only

```bash
python visualize.py led_positions.json --stats
```

Prints statistics without showing plot:
- Number of LEDs (observed vs predicted)
- Confidence distribution
- Spatial extents
- Angular coverage

## Examples

### Example 1: Quick Look
```bash
python visualize.py led_positions.json
```
Interactive 3D plot opens

### Example 2: Save High-Quality Plot
```bash
python visualize.py led_positions.json --confidence --save final_tree.png
```
Saves confidence-colored plot at 300 DPI

### Example 3: Check Mapping Quality
```bash
python visualize.py led_positions.json --stats
```
```
============================================================
LED POSITION STATISTICS
============================================================

Total LEDs: 200
Tree Height: 2.00m
Number of Cameras: 5

Observed (triangulated): 142 (71.0%)
Predicted (interpolated): 58 (29.0%)

Confidence (observed LEDs):
  Mean: 0.847
  Min:  0.523
  Max:  0.982
  High confidence (>0.8): 98 (69.0%)

Spatial Distribution:
  X range: [-0.487, 0.491]m
  Y range: [-0.493, 0.485]m
  Z range: [0.012, 1.987]m
  Height range: [0.006, 0.994] (normalized)
  Angle range: [0.2°, 359.8°]
============================================================
```

## What About the Other Python Files?

### ❌ Files You DON'T Need Anymore

All processing is now in Flutter, so these are obsolete:

- `process_advanced.py` - ❌ Flutter does this
- `process_images.py` - ❌ Flutter does this
- `process_with_calibration.py` - ❌ Flutter does this
- `advanced_led_detection.py` - ❌ Flutter has OpenCV
- `cone_constrained_triangulation.py` - ❌ Flutter does ray-cone
- `cone_detection.py` - ❌ Flutter has manual overlay
- `cone_outline_detection.py` - ❌ Flutter has manual overlay
- `led_position_mapper.py` - ❌ Flutter does triangulation
- `angular_confidence.py` - ❌ Flutter has cosine model

### ✅ Files You Might Keep

- `visualize.py` - ✅ For 3D plots
- `example_animation.py` - ✅ Shows how to use positions
- `led_controller.py` - ✅ If you want Python animations

### 🗑️ Safe to Delete

You can safely delete all the processing scripts if you want:

```bash
# Delete all obsolete Python processing
rm process_*.py
rm advanced_led_detection.py
rm cone_*.py
rm led_position_mapper.py
rm angular_confidence.py
rm requirements.txt  # (old heavy requirements)
```

Keep only:
- `visualize.py`
- `requirements_visualize.txt`
- `example_animation.py` (if you want Python animations)
- `led_controller.py` (if you want Python animations)

## Workflow

### Complete Workflow (Flutter + Python visualization)

```
[Flutter App - 12 minutes]
1. Capture from 5 positions → detections
2. Filter reflections
3. Triangulate with ray-cone
4. Fill gaps
5. Export led_positions.json (24KB)

[Python - 10 seconds]
6. python visualize.py led_positions.json --confidence
7. Verify mapping looks good
8. Done!
```

### If You Don't Want Python At All

Just skip step 6! The led_positions.json is all you need for animations.

You can visualize in other tools:
- Blender (import JSON as mesh)
- Online 3D viewers
- Your own visualization code

## Dependencies Comparison

### Old (All Processing)
```
opencv-python  # 200MB
scipy          # 150MB
numpy
matplotlib
pillow
```
**Total: ~500MB**

### New (Visualization Only)
```
numpy
matplotlib
```
**Total: ~50MB**

**10× smaller!**

## FAQ

**Q: Do I need Python at all?**
A: No! It's purely optional for visualization. The Flutter app produces everything you need.

**Q: Can I use the old Python processing scripts?**
A: Yes, but why? Flutter does it better (real-time, no storage, same accuracy).

**Q: What if I don't have Python?**
A: No problem! Use led_positions.json directly for animations.

**Q: Can I visualize without Python?**
A: Yes - import JSON into Blender, Unity, or any 3D tool that reads JSON.

**Q: Why keep Python at all?**
A: Just for quick matplotlib plots. If you don't need them, delete everything!

## Summary

**Python is now OPTIONAL** for:
- ✅ Quick 3D visualization
- ✅ Statistics reporting
- ✅ Saving plot images

**Flutter does EVERYTHING else:**
- ✅ Capture + detection
- ✅ Reflection filtering
- ✅ Triangulation
- ✅ Gap filling
- ✅ Export

**Recommendation:** Keep `visualize.py` for quick verification, delete the rest!
