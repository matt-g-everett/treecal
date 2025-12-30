# Quick Start Guide - LED Position Mapping

This is a step-by-step guide to map your Christmas tree LEDs.

## What You'll Need

- Christmas tree with individually controllable LEDs
- Phone camera (or any camera)
- Tripod or stable surface for camera
- Dark room

## Step 1: Install Dependencies

```bash
pip install numpy opencv-python matplotlib scipy --break-system-packages
```

## Step 2: Choose Your Capture Method

### Option A: Individual Photos (Recommended)

**Setup:**
1. Position your phone on a tripod at 3-5 locations around the tree
2. Mark each camera position (tape on floor)
3. Set up your LED controller to light one LED at a time

**Capture:**
For each camera position:
- Create a folder: `camera1/`, `camera2/`, etc.
- Light LED 0, take photo → save as `led_000.jpg`
- Light LED 1, take photo → save as `led_001.jpg`
- Continue for all LEDs

**Result:**
```
images/
├── camera1/
│   ├── led_000.jpg
│   ├── led_001.jpg
│   └── ...
├── camera2/
└── camera3/
```

### Option B: Video Recording (Faster)

**Setup:**
1. Position camera at each location
2. Program your LEDs to cycle through all of them (e.g., 0.5s each)

**Capture:**
- Start recording video
- Start LED sequence
- Stop recording after all LEDs have lit

**Extract frames:**
```bash
# First analyze to find timing
python extract_video_frames.py analyze camera1.mp4

# Then extract based on detected timing
python extract_video_frames.py extract camera1.mp4 camera1/ \
    --num-leds 200 \
    --start-frame 30 \
    --frames-per-led 15
```

## Step 3: Process Images

```bash
python process_images.py images/ \
    --num-leds 200 \
    --tree-height 2.0 \
    --output my_led_positions.json
```

This will:
- Detect LEDs in all images
- Triangulate 3D positions
- Fill gaps with sequential prediction
- Save results to JSON
- Show a 3D visualization

## Step 4: Use the Results

Your `led_positions.json` contains:
```json
{
  "leds": {
    "0": {
      "height": 0.025,     // meters from ground
      "angle": 45.3,       // degrees (0-360)
      "radius": 0.48,      // meters from center
      "confidence": 1.0,   // how reliable (0-1)
      "is_observed": true  // or predicted
    }
  }
}
```

Use this data for:
- Spatial LED animations
- 3D effects that follow tree shape
- Audio-reactive displays mapped to position
- Any creative lighting patterns

## Tips for Best Results

### Camera Setup
- Use tripod or stable surface
- Keep camera at same height (middle of tree)
- Space cameras evenly around accessible sides
- Distance: 1.5-2m from tree

### Lighting
- **Dark room** - turn off all other lights
- One LED at a time for photos
- Check that LED is bright enough in images
- Avoid overexposure (LED should be sharp point)

### Processing
- If detection fails, try lower threshold (150 instead of 200)
- Make sure your LED indices match your controller
- The more camera angles, the better accuracy
- Back of tree will have lower confidence (that's OK!)

## Troubleshooting

**"LED not detected in any images"**
- Check images are not too dark/bright
- Try adjusting threshold parameter
- Make sure LED is actually visible from cameras

**"Need at least 2 views for triangulation"**
- LED must be visible from 2+ camera angles
- Add more camera positions
- Or accept lower coverage on back of tree

**"Poor accuracy on back of tree"**
- This is expected! You said you care less about the back
- Sequential prediction still gives reasonable estimates
- Can manually tune if needed

## What's Next?

Once you have positions mapped:

1. **Test the data:**
   ```python
   import json
   with open('led_positions.json') as f:
       data = json.load(f)
   
   # Access LED 42's position
   led42 = data['leds']['42']
   print(f"Height: {led42['height']}m, Angle: {led42['angle']}°")
   ```

2. **Create animations** based on spatial position
3. **Integrate** with your LED controller
4. **Experiment** with 3D effects

Happy mapping! 🎄
