# Complete LED Mapping Pipeline - Final Design

## Overview

After iterative refinement through user insights, here's the complete, correct pipeline.

---

## Pipeline Stages

### Stage 1: Capture & Detection

**What happens:**
```
For each LED position (0-199):
  1. Turn on LED via MQTT
  2. Capture images from all 5 cameras
  3. Detect LED in each image (OpenCV)
  4. Calculate detection confidence (brightness, size)
  5. Calculate angular confidence (distance from frame center)
  6. Filter reflections (spatial clustering)
  7. Store observation (pixel position, confidences)
```

**Output:** 
- List of observations per LED per camera
- Each observation: `(ledIndex, cameraIndex, pixelX, pixelY, detectionConf, angularConf)`

---

### Stage 2: Per-Camera Occlusion Analysis ⭐ KEY INSIGHT

**What happens:**
```
For each camera:
  1. Build confidence sequence: [LED 0 conf, LED 1 conf, ..., LED 199 conf]
  2. Smooth with moving average (window=5) to reduce noise
  3. Segment into visible/hidden regions (threshold=0.5)
  4. Mark each LED as visible or hidden from this camera
```

**Example:**
```
Camera 1 sequence:
LEDs 0-35:   High confidence → Visible segment
LEDs 36-45:  Low/missing     → Hidden segment (facing away)
LEDs 46-80:  High confidence → Visible segment
LEDs 81-95:  Low/missing     → Hidden segment
LEDs 96-199: High confidence → Visible segment
```

**Output:**
- `occlusion[cameraIndex][ledIndex]` = 0.0 (visible) or 1.0 (hidden)

**Why this matters:**
- Uses sequence patterns (not single values)
- Captures string continuity
- Robust to noise
- Direct measurement of which LEDs each camera can see

---

### Stage 3: Occlusion-Weighted Triangulation ⭐ SIMPLIFIED

**What happens:**
```
For each LED:
  1. Get all observations from all cameras
  
  2. Apply occlusion-based weight adjustment:
     For each observation:
       base_weight = detectionConfidence × angularConfidence
       occlusion_score = occlusion[cameraIndex][ledIndex]
       final_weight = base_weight × (1.0 - occlusion_score)
     
     // Visible segment (occlusion=0.0) → no penalty
     // Hidden segment (occlusion=1.0) → zero weight
     // Marginal (occlusion=0.5) → 50% penalty
  
  3. Pick observation with highest final_weight
     bestObs = observations.max_by(final_weight)
  
  4. Triangulate using ONLY best camera's ray-cone intersection
     position = intersect(bestObs.ray, cone)
```

**Output:**
- One position per observed LED
- `LED3DPosition(x, y, z, height, angle, radius, confidence, numObservations)`

**Key points:**
- ✅ No averaging! Just best camera.
- ✅ Soft weighting (not hard filtering) - prefers visible but doesn't exclude hidden
- ✅ Graceful handling of edge cases (LEDs on tree sides)
- ✅ Uses camera with best adjusted view
- ✅ Simple and accurate

---

### Stage 4: Gap Filling

**What happens:**
```
For LEDs not observed:
  1. Find nearest observed LEDs before and after
  2. Interpolate in cone space (height, angle)
  3. Mark as predicted=true
  4. Lower confidence
```

**Example:**
```
LED 42: Observed (h=0.52, θ=60°, conf=0.89)
LED 43: Missing
LED 44: Missing  
LED 45: Observed (h=0.55, θ=68°, conf=0.87)

Interpolate LED 43:
  h = 0.52 + (0.55-0.52) × 1/3 = 0.53
  θ = 60° + (68°-60°) × 1/3 = 62.67°
  conf = 0.5 (predicted)

Interpolate LED 44:
  h = 0.52 + (0.55-0.52) × 2/3 = 0.54
  θ = 60° + (68°-60°) × 2/3 = 65.33°
  conf = 0.5 (predicted)
```

**Output:**
- Complete set of 200 LED positions
- Predicted positions marked with `predicted=true`

---

### Stage 5: Validation (Optional)

**What happens:**
```
For each LED:
  1. Check string continuity (cone distance to neighbors)
  2. Check if position is physically reasonable
  3. Flag suspicious positions
  4. Suggest re-capture for low-confidence LEDs
```

**Quality metrics:**
- Detection rate (% LEDs observed)
- Average confidence
- Max cone distance between neighbors
- Number of predicted LEDs

---

### Stage 6: Export

**What happens:**
```
Export to JSON:
{
  "leds": [
    {
      "led_index": 42,
      "x": 0.234,
      "y": 0.412,
      "z": 1.056,
      "height": 0.528,
      "angle": 60.2,
      "radius": 0.476,
      "confidence": 0.847,
      "num_observations": 5,
      "predicted": false
    },
    ...
  ],
  "metadata": {
    "tree_height": 2.0,
    "capture_date": "2025-12-29",
    "num_leds": 200,
    "num_observed": 178,
    "num_predicted": 22
  }
}
```

---

## Key Simplifications from User Insights

### Insight 1: Don't Average Observations
**Old thinking:** "Average all cameras using weighted circular mean"
**User insight:** "Just pick the best camera!"
**Result:** Much simpler, avoids mixing perspectives

### Insight 2: Use Occlusion Analysis to Filter
**Old thinking:** "Use detection confidence as proxy for orientation"
**User insight:** "We already analyze sequences and neighbors - use that directly!"
**Result:** More robust, uses sequence patterns

### Insight 3: No "Front/Back Candidates"
**Old thinking:** "Track both front and back position candidates, pick between them"
**User insight:** "Best camera already sees the correct surface!"
**Result:** One position per LED, much simpler

### Insight 4: Cone Space Distance
**Old thinking:** "Work in Cartesian (x,y,z) coordinates"
**User insight:** "Why not use cone (height, angle) coordinates directly?"
**Result:** Proper distance metric with angle wraparound

### Insight 5: No Viterbi Needed
**Old thinking:** "Use dynamic programming for global optimization"
**User insight:** "String continuity is local - do we need this?"
**Result:** Simple greedy is sufficient

---

## Data Flow Diagram

```
Capture
  ↓ (observations per LED per camera)
Occlusion Analysis
  ↓ (visible/hidden per camera per LED)
Filter Observations
  ↓ (keep only visible-segment observations)
Pick Best
  ↓ (single best observation per LED)
Triangulate
  ↓ (one position per observed LED)
Gap Fill
  ↓ (interpolate missing LEDs)
Validate
  ↓ (quality checks)
Export
  ↓ (JSON with positions)
```

---

## Implementation Status

| Stage | Status | Notes |
|-------|--------|-------|
| Capture & Detection | ✅ Done | OpenCV, reflection filtering |
| Occlusion Analysis | ❌ TODO | Sequence segmentation |
| Filtered Triangulation | ⚠️ Partial | Best-obs done, needs filtering |
| Gap Filling | ✅ Done | Interpolation/extrapolation |
| Validation | ⚠️ Basic | Needs enhancement |
| Export | ✅ Done | JSON format |

---

## Critical Path to Completion

### 1. Implement Occlusion Analyzer (Priority 1)

```dart
class OcclusionAnalyzer {
  static Map<int, Map<int, double>> analyzePerCamera({
    required Map<int, List<LEDObservation>> observationsByCamera,
    required int totalLEDs,
  }) {
    // For each camera:
    // 1. Build confidence sequence
    // 2. Smooth with moving average
    // 3. Segment into visible/hidden
    // 4. Return occlusion scores
  }
}
```

**Estimated work:** 1 day

### 2. Integrate with Triangulation (Priority 2)

```dart
// In triangulation service:
final occlusion = OcclusionAnalyzer.analyzePerCamera(...);

for (led in leds) {
  final observations = getAllObservations(led);
  
  // Apply soft weighting based on occlusion
  var bestObs = observations.first;
  var bestWeight = 0.0;
  
  for (obs in observations) {
    final baseWeight = obs.weight;  // detection × angular
    final occlusionScore = occlusion[obs.cameraIndex][led];
    final finalWeight = baseWeight × (1.0 - occlusionScore);
    
    if (finalWeight > bestWeight) {
      bestWeight = finalWeight;
      bestObs = obs;
    }
  }
  
  position = triangulate(bestObs);
}
```

**Estimated work:** 0.5 days

### 3. Testing (Priority 3)

- Unit tests for occlusion analyzer
- Integration test for complete pipeline
- Validation with real data

**Estimated work:** 1-2 days

---

## Performance Expectations

**Timing:**
- Capture: ~10 minutes (200 LEDs × 3 seconds each)
- Detection: ~2 seconds (200 LEDs × 5 cameras = 1000 images)
- Occlusion analysis: ~0.5 seconds (5 cameras × 200 LEDs)
- Triangulation: ~1 second (200 LEDs)
- Gap filling: ~0.1 seconds
- Total processing: ~4 seconds

**Accuracy:**
- Observed LEDs: ±2cm (with proper calibration)
- Predicted LEDs: ±5cm (interpolated)
- Overall: 90%+ within ±3cm

**Detection rate:**
- Expected: 85-95% LEDs observed
- Gap filling: Remaining 5-15% predicted

---

## Summary

**Complete pipeline:**
1. ✅ Capture & detect (done)
2. ⏭️ Occlusion analysis (TODO - sequence segmentation)
3. ⚠️ Triangulation (done, needs occlusion filtering)
4. ✅ Gap filling (done)
5. ⚠️ Validation (basic, can enhance)
6. ✅ Export (done)

**Key principles:**
- Pick best observation (don't average)
- Filter by occlusion analysis (use sequences)
- Work in cone space (proper distance metric)
- Keep it simple (no overengineering)

**Remaining work:** ~2-3 days to implement occlusion analyzer and integrate

**The design is now solid thanks to iterative refinement through user questions!** 🎯
