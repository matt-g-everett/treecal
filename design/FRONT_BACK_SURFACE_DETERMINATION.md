# Front/Back Surface Determination - Design Document

## The Problem

### Trees Aren't Solid!

Christmas trees are semi-transparent - you can see through them. This creates an ambiguity:

**When a camera looks at an LED through the tree:**
- The camera ray passes through the cone at TWO points
- **Front surface (near):** Closer to camera
- **Back surface (far):** Farther from camera

**Question:** Which surface is the LED actually on?

### Current Implementation (Naive)

```dart
// Current: Always use nearest intersection
final t = min(t1, t2);  // Pick front surface
```

**Problem:** LEDs on the back surface are placed on the front surface!
- Wrong 3D position
- Wrong for animations (need to know front vs back)
- Accuracy suffers

---

## The Solution

### Key Insight: String Continuity

LEDs are wired in a string: 0 → 1 → 2 → 3 → ... → 199

**Sequential LEDs should be close together!**

If LED N is on the front:
- LED N-1 and N+1 are LIKELY on the front too
- Distance between consecutive LEDs < 15cm typically

If LED N is on the back:
- LED N-1 and N+1 are LIKELY on the back too
- Distance between consecutive LEDs < 15cm typically

**Strategy:**
1. Generate TWO candidates per LED (front and back)
2. Score each candidate by proximity to neighbors
3. Choose sequence that maximizes continuity

---

## Mathematical Formulation

### Ray-Cone Intersection (Dual)

**Quadratic equation:** At² + Bt + C = 0

**Two solutions:**
```
t₁ = (-B - √Δ) / (2A)  // Near intersection (front)
t₂ = (-B + √Δ) / (2A)  // Far intersection (back)
```

**Both give valid positions on cone surface!**

**Position candidates:**
```dart
front_position = rayOrigin + t₁ * rayDirection
back_position = rayOrigin + t₂ * rayDirection
```

### Continuity Scoring

**For each LED N, score each candidate (front/back):**

```
continuity_score(N, surface) = 
  Σ (over neighbors M ∈ {N-1, N+1})
    if distance(LED_N[surface], LED_M[surface]) < max_distance:
      score += 1 - (distance / max_distance)
```

**Higher score = better string continuity**

### Global Optimization

**This is a Hidden Markov Model (HMM)!**

**States:** {front, back}
**Observations:** Camera ray intersections
**Transition:** Prefer staying on same surface (continuity)
**Emission:** Observation likelihood (detection confidence)

**Solution:** Viterbi algorithm finds optimal path through state space

---

## Implementation Strategy

### Phase 1: Dual Intersection (✅ Done)

```dart
class DualRayConeIntersection {
  final RayConeIntersection front;  // Near
  final RayConeIntersection? back;  // Far (optional)
}

static DualRayConeIntersection? intersectDual(...) {
  // Return BOTH t₁ and t₂ intersections
}
```

### Phase 2: Candidate Generation

```dart
// For each LED, generate candidates
Map<int, Candidates> candidates = {};

for (LED in 0..199) {
  candidates[LED] = {
    'front': average(all_cameras.front_intersections),
    'back': average(all_cameras.back_intersections),
  };
}
```

### Phase 3: Continuity Scoring

```dart
// Score each candidate based on neighbors
for (LED in 0..199) {
  for (surface in ['front', 'back']) {
    score = 0;
    
    // Check LED-1
    if (exists(LED-1, surface)) {
      dist = distance(candidates[LED][surface], 
                     candidates[LED-1][surface]);
      if (dist < max_dist) {
        score += (1 - dist/max_dist);
      }
    }
    
    // Check LED+1
    if (exists(LED+1, surface)) {
      dist = distance(candidates[LED][surface], 
                     candidates[LED+1][surface]);
      if (dist < max_dist) {
        score += (1 - dist/max_dist);
      }
    }
    
    scores[LED][surface] = score;
  }
}
```

### Phase 4: Viterbi Algorithm

```dart
// Dynamic programming to find best path
// State: surface ∈ {front, back}
// Score: continuity + observation confidence

for (LED in 0..199) {
  for (surface in ['front', 'back']) {
    // Best path to reach (LED, surface)
    best_score[LED][surface] = max(
      best_score[LED-1]['front'] + transition_cost('front', surface) + continuity_score[LED][surface],
      best_score[LED-1]['back'] + transition_cost('back', surface) + continuity_score[LED][surface]
    );
    
    // Remember best predecessor
    best_prev[LED][surface] = argmax(...);
  }
}

// Backtrack to find optimal path
optimal_path = backtrack(best_score, best_prev);
```

**Transition costs:**
- Same surface → 0 (free)
- Switch surface → penalty (string doesn't usually switch sides)

---

## Example Scenario

### Input: 5 Cameras Observing LED 42

**Camera 1:** Ray intersects at t₁=1.2m (front), t₂=2.1m (back)
**Camera 2:** Ray intersects at t₁=1.3m (front), t₂=2.0m (back)
**Camera 3:** Ray intersects at t₁=1.1m (front), t₂=2.2m (back)
**Camera 4:** Only sees front (back obscured)
**Camera 5:** Only sees front (back obscured)

**Candidates:**
```
LED 42 front: average(1.2, 1.3, 1.1) = 1.2m from cameras
LED 42 back:  average(2.1, 2.0, 2.2) = 2.1m from cameras
```

**Continuity Check:**
```
LED 41 is on front (already determined)
LED 43 is on front (already determined)

Distance(LED42_front, LED41_front) = 0.08m ✓ (< 0.15m)
Distance(LED42_front, LED43_front) = 0.09m ✓ (< 0.15m)
→ Front score: 2.0

Distance(LED42_back, LED41_front) = 0.45m ✗ (> 0.15m)
Distance(LED42_back, LED43_front) = 0.43m ✗ (> 0.15m)
→ Back score: 0.0
```

**Decision:** LED 42 is on FRONT surface (score 2.0 > 0.0)

---

## Confidence Metric

### Front Confidence Score

```
front_confidence = front_score / (front_score + back_score)
```

**Interpretation:**
- 0.9-1.0: Strongly front
- 0.7-0.9: Probably front
- 0.3-0.7: Ambiguous
- 0.1-0.3: Probably back
- 0.0-0.1: Strongly back

**Use cases:**
- Animation: Know which LEDs are visible from which angles
- Quality: Filter ambiguous LEDs
- Visualization: Color by front/back confidence

---

## Edge Cases

### 1. No Back Intersection

Some cameras might not see back surface (blocked by branches).

**Solution:** Only use front candidate, mark as "front (only option)"

### 2. First/Last LEDs

LED 0 and LED 199 have only one neighbor.

**Solution:** Use single neighbor, lower confidence

### 3. String Wraps Around Tree

String might spiral, crossing from front to back.

**Solution:** Allow transitions, but with penalty

### 4. Ambiguous Sections

Some LEDs might be truly ambiguous (e.g., on the side).

**Solution:** Mark with low confidence (0.5), could be either

---

## Benefits

### 1. Accuracy Improvement

**Before:** ±2cm (but on wrong surface sometimes)
**After:** ±2cm on CORRECT surface

### 2. Animation Intelligence

```javascript
// Front LEDs visible from 0-180°
// Back LEDs visible from 180-360°

if (led.surface === 'front') {
  brightness = max(0, cos(viewAngle));
} else {
  brightness = max(0, cos(viewAngle + 180));
}
```

### 3. Quality Filtering

```dart
// Only use high-confidence LEDs
final reliable = leds.where((led) => 
  led.frontConfidence > 0.8 || led.frontConfidence < 0.2
);
```

### 4. Debugging

```
LED 42:
  Front: (0.23, 0.41, 1.05) - confidence: 0.92 ✓
  Back:  (0.19, 0.38, 1.03) - confidence: 0.08
  Decision: FRONT (high confidence)
```

---

## Performance

### Computational Complexity

**Dual Intersection:** O(N × M)
- N = LEDs (200)
- M = cameras (5)
- Same as current: ~1000 intersections

**Continuity Scoring:** O(N)
- Each LED checks 2 neighbors: 200 × 2 = 400 checks

**Viterbi Algorithm:** O(N × S²)
- N = LEDs (200)
- S = states (2: front/back)
- 200 × 4 = 800 operations

**Total:** Still ~2 seconds (same as current)

### Memory

**Before:** 200 positions × 48 bytes = 9.6KB
**After:** 200 positions × 64 bytes = 12.8KB (+3.2KB for confidence)

---

## Implementation Priority

### Phase 1: Foundation (Current PR)
✅ Dual intersection support
✅ DualRayConeIntersection class
✅ Basic candidate generation

### Phase 2: Scoring (Next)
- Continuity score calculation
- Distance-based scoring
- Neighbor checking

### Phase 3: Optimization (Final)
- Viterbi algorithm
- Global path optimization
- Transition cost tuning

### Phase 4: Integration
- Update triangulation service
- Add front/back to JSON export
- Update visualization (color by surface)

---

## Testing Strategy

### Unit Tests

```dart
test('Dual intersection returns front and back', () {
  final dual = RayConeIntersector.intersectDual(...);
  expect(dual.front, isNotNull);
  expect(dual.back, isNotNull);
  expect(dual.front.distance < dual.back.distance, isTrue);
});

test('String continuity prefers same surface', () {
  // LED 0, 1, 2 all on front
  // LED 1 back candidate should score low
  final score = scoreContinuity(led1_back, neighbors_front);
  expect(score < 0.5, isTrue);
});
```

### Integration Tests

```dart
test('Complete pipeline with front/back', () {
  final positions = processCapturesWithSurfaces(...);
  
  // Check that string is continuous
  for (int i = 1; i < 199; i++) {
    final prev = positions[i-1];
    final curr = positions[i];
    final next = positions[i+1];
    
    // Same surface should cluster
    expect(curr.surface == prev.surface || 
           curr.surface == next.surface, isTrue);
  }
});
```

---

## Visualization

### Flutter (3D View)

```dart
// Color by surface
final frontMaterial = PointsMaterial({
  'color': 0x00ff00,  // Green = front
});

final backMaterial = PointsMaterial({
  'color': 0xff0000,  // Red = back
});
```

### Python (matplotlib)

```python
# Separate front/back in plot
front_leds = [p for p in positions if p['front_confidence'] > 0.5]
back_leds = [p for p in positions if p['front_confidence'] < 0.5]

ax.scatter(front_x, front_y, front_z, c='green', label='Front')
ax.scatter(back_x, back_y, back_z, c='red', label='Back')
```

---

## Future Enhancements

### 1. Multi-Surface Trees

Some trees might have LEDs spiraling through interior.

**Solution:** Allow 3+ surfaces with more complex continuity model

### 2. Branch Detection

Detect branches as separate surfaces.

**Solution:** Cluster LEDs by surface connectivity

### 3. Occlusion Modeling

Model which LEDs are visible from which camera angles.

**Solution:** Ray tracing with tree geometry

---

## Summary

**Problem:** LEDs could be on front or back of tree

**Solution:** Use string continuity to disambiguate

**Method:** 
1. Generate both candidates (front/back)
2. Score by continuity with neighbors
3. Optimize with Viterbi algorithm

**Benefits:**
- ✅ Correct surface determination
- ✅ Animation intelligence
- ✅ Quality metric
- ✅ Better accuracy

**Status:** Foundation complete, scoring next!

---

## References

### Algorithms
- Viterbi Algorithm (Hidden Markov Models)
- Dynamic Programming
- Ray-cone intersection (computer graphics)

### Papers
- "String Light Reconstruction" (fictional - similar to structure from motion)
- "Hidden Markov Models for Sequential Data"

**Great insight! This will make the system much more robust!** 🎄✨
