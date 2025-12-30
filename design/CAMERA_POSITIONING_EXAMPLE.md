# Camera Positioning - Practical Example

Let me walk you through a real example to make this concrete.

## Your Tree Setup

```
           North
             ↑
             |
    Wall ----+---- (Tree against wall)
             |
          [TREE]
             |
           Room
```

## Step-by-Step Example

### Position 1: Front of Tree

**Setup:**
1. Stand in front of tree (facing it)
2. Put phone on tripod ~1.5m from tree center
3. Camera at about chest height (1.0m from floor)

**Measurements:**
```
Distance: 1.5 meters (from tree center to phone)
Angle: 0° (front of tree)
Height: 1.0 meters (from floor to camera)
```

**In the app:**
- Tap "Calibrate Position 1"
- Enter: Distance=1.5, Angle=0, Height=1.0
- See the diagram showing camera at front
- Save

**Capture:**
- Tap "Start Capture"
- App cycles through all 200 LEDs
- Takes ~6 minutes
- Saves to `camera1/` folder

### Position 2: Right Side

**Setup:**
1. Move tripod to right side of tree
2. Same distance from tree (1.5m)
3. Same height (1.0m)

**Measurements:**
```
Distance: 1.5 meters
Angle: 90° (right side)
Height: 1.0 meters
```

**In the app:**
- Position selector shows "2"
- Tap "Calibrate Position 2"
- Enter: Distance=1.5, Angle=90, Height=1.0
- Or use quick button "Right (90°)"
- Save

**Capture:**
- Tap "Start Capture"
- Another 6 minutes
- Saves to `camera2/` folder

### Position 3: Left Side

**Same as Position 2, but:**
```
Distance: 1.5 meters
Angle: 270° (left side)
Height: 1.0 meters
```

### Positions 4 & 5 (Optional but Recommended)

**Position 4: Front-Right**
```
Distance: 1.5 meters
Angle: 45° (between front and right)
Height: 1.0 meters
```

**Position 5: Front-Left**
```
Distance: 1.5 meters
Angle: 315° (between front and left)
Height: 1.0 meters
```

## What You'll Have

```
led_captures/
├── camera1/          (Position 1: Front, 0°)
│   ├── led_000.jpg
│   ├── led_001.jpg
│   └── ... (200 images)
├── camera2/          (Position 2: Right, 90°)
├── camera3/          (Position 3: Left, 270°)
├── camera4/          (Position 4: Front-Right, 45°)
├── camera5/          (Position 5: Front-Left, 315°)
└── camera_calibrations.json
```

## Processing

**Export from app:**
- Tap "View & Export"
- Tap "Export All as ZIP"
- Share to your computer

**On computer:**
```bash
# Extract
unzip led_captures.zip
cd led_captures

# Process with calibration
python process_with_calibration.py . \
    --calibration camera_calibrations.json \
    --num-leds 200 \
    --tree-height 2.0

# Output: led_positions.json
```

## What the Calibration Does

The calibration converts your measurements into 3D camera coordinates:

**Position 1 (Front, 0°):**
```
Distance: 1.5m, Angle: 0°, Height: 1.0m
→ Camera at: (0, -1.5, 1.0)
   x=0 (centered)
   y=-1.5 (in front of tree)
   z=1.0 (height)
```

**Position 2 (Right, 90°):**
```
Distance: 1.5m, Angle: 90°, Height: 1.0m
→ Camera at: (1.5, 0, 1.0)
   x=1.5 (to the right)
   y=0 (level with tree)
   z=1.0 (height)
```

The processing script uses these to triangulate LED positions.

## Visualization

```
        Top View (looking down)
        
            Wall
        -----------
             |
        [  Tree  ]  ← Center at (0,0)
             |
        
        Camera 5      Camera 1      Camera 4
           ↓             ↓             ↓
           *             *             *
          315°           0°           45°
           
           
    Camera 3  *                   * Camera 2
            270°                 90°
            
    (All cameras 1.5m from tree center)
```

## Tips

**Don't stress about perfect measurements:**
- ±10cm error in distance? Fine.
- ±10° error in angle? Fine.
- The algorithm is robust

**But DO be consistent:**
- Same height for all positions
- Roughly same distance
- Tree roughly centered in frame

**Verification:**
- After measuring, look at your phone's camera view
- Tree should be centered and fill ~30-50% of frame
- If tree is way off to one side, adjust position

## Common Mistakes

❌ **Wrong:**
```
Position 1: 1.5m from tree trunk
Position 2: 1.5m from tree trunk
```
Problem: Not measuring from center!

✅ **Right:**
```
Position 1: 1.5m from tree CENTER
Position 2: 1.5m from tree CENTER
```

---

❌ **Wrong:**
```
Position 1: Distance in centimeters (150)
```
Problem: App expects meters!

✅ **Right:**
```
Position 1: Distance in meters (1.5)
```

---

❌ **Wrong:**
```
Angle: 1.57 radians
```
Problem: App expects degrees!

✅ **Right:**
```
Angle: 90 degrees
```

## Quick Checklist

Before each capture:
- [ ] Phone on stable tripod
- [ ] Tree is centered in frame
- [ ] Measured distance from tree center
- [ ] Recorded angle (0-360°)
- [ ] Measured camera height
- [ ] Entered calibration in app
- [ ] Saved calibration
- [ ] Ready to start capture!

After all captures:
- [ ] Export from app includes `camera_calibrations.json`
- [ ] All camera folders present
- [ ] Use `process_with_calibration.py` (not `process_images.py`)
- [ ] Pass `--calibration` flag

## That's It!

The calibration process takes ~3 minutes per position. Much easier than it sounds when you actually do it:

1. Put phone somewhere
2. Measure with tape
3. Type numbers in app
4. Tap capture
5. Wait 6 minutes
6. Repeat

Total time for 5 positions: ~45 minutes (mostly waiting for captures).

The result: Accurate 3D positions for all 200 LEDs! 🎄✨
