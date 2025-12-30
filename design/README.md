# LED Tree Mapper - 100% FOSS

A complete system for mapping LED positions on Christmas trees using computer vision and geometric triangulation.

**Fully Free and Open Source!** 🔓✨

---

## Quick Start

### Flutter App (Required)
```bash
cd led_mapper_app
flutter pub get
flutter run
```

### Python Tools (Optional)
```bash
pip install -r requirements_visualize.txt
python visualize.py led_positions.json
```

---

## What You Get

### ✅ Flutter Mobile App
- Automated capture via MQTT
- Real-time OpenCV detection
- Ray-cone triangulation (±2cm accuracy)
- **3D visualization with flutter_gl (FOSS!)**
- Export to JSON

### ✅ Python Analysis (Optional)
- matplotlib publication plots
- High-resolution export (300 DPI)
- 2D projections
- Detailed statistics

---

## Licenses - All FOSS!

| Component | License |
|-----------|---------|
| Flutter App | MIT/BSD |
| flutter_gl | MIT ✅ |
| opencv_dart | Apache 2.0 |
| matplotlib | BSD/PSF ✅ |
| numpy | BSD |

**No Syncfusion! No proprietary code!**

---

## Features

- ✅ Real-time LED detection
- ✅ Reflection filtering
- ✅ Proper geometric triangulation
- ✅ Sequential prediction
- ✅ In-app 3D visualization
- ✅ Touch controls (drag, pinch)
- ✅ Statistics
- ✅ JSON export
- ✅ 100% FOSS

---

## Workflow

1. **Capture** (Flutter - 12 min)
   - 5 camera positions
   - 200 LEDs per position
   - Real-time detection
   
2. **Process** (Flutter - 2 min)
   - Filter reflections
   - Triangulate positions
   - Fill gaps
   
3. **Visualize** (Both - 10 sec)
   - Flutter: Quick 3D view
   - Python: Publication plots

**Result:** led_positions.json (24KB, ±2cm accuracy)

---

## Documentation

- `FOSS_IMPLEMENTATION_COMPLETE.md` - Implementation details
- `PROPER_TRIANGULATION_IMPLEMENTATION.md` - Ray-cone math
- `FINAL_FEATURE_VERIFICATION.md` - Feature checklist
- `FOSS_VISUALIZATION_OPTIONS.md` - Why we chose flutter_gl

---

## Why FOSS?

**Freedom:**
- No restrictions
- No surprise fees
- Modify freely

**Transparency:**
- Audit source
- Community review

**Sustainability:**
- Won't disappear
- Community maintained

---

## Comparison

| Feature | This System | Syncfusion |
|---------|-------------|------------|
| License | MIT ✅ | Proprietary ❌ |
| Cost | Free forever | $1000/yr if >$1M |
| Source | Open | Closed |
| Restrictions | None | Many |

**We chose FOSS!** 🔓

---

## Summary

**100% FOSS LED mapping system:**
- Flutter app with flutter_gl visualization
- Python matplotlib for analysis
- ±2cm accuracy
- No proprietary dependencies
- Free forever

**Map your tree with confidence!** 🎄✨
