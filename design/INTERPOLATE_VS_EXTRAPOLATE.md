# Gap Filling: Interpolate vs Extrapolate

## When Each Is Used

### Decision Logic

```dart
for each missing LED at index i:
  Find nearest known LED before (searching backwards)
  Find nearest known LED after (searching forwards)
  
  if (before exists AND after exists):
    → INTERPOLATE between them
  
  else if (before exists but NOT after):
    → EXTRAPOLATE FORWARD from before
  
  else if (after exists but NOT before):
    → EXTRAPOLATE BACKWARD from after
  
  else:
    → Can't fill (no known LEDs at all - shouldn't happen)
```

---

## Interpolate: Between Two Known Points

### When Used

**Required:** Known LED BEFORE **and** AFTER the missing LED

**Example 1: Small gap in middle**
```
LED 50: detected ✓
LED 51: MISSING
LED 52: MISSING  
LED 53: detected ✓

Gap: LEDs 51-52 (2 missing)

For LED 51:
  before = 50 ✓
  after = 53 ✓
  → INTERPOLATE between 50 and 53

For LED 52:
  before = 50 ✓
  after = 53 ✓
  → INTERPOLATE between 50 and 53
```

**Example 2: Larger gap**
```
LED 100: detected ✓
LED 101-109: MISSING (9 LEDs)
LED 110: detected ✓

For LED 105:
  before = 100 ✓
  after = 110 ✓
  → INTERPOLATE between 100 and 110
  
Position at t = (105-100)/(110-100) = 0.5 (midpoint)
```

**Characteristics:**
- Most accurate (bounded by two known points)
- Position is weighted average based on distance
- Used for most gaps in middle of detected sequence

---

## Extrapolate Forward: Extending Beyond Last Known

### When Used

**Required:** Known LED BEFORE, but NO known LED after

**Example 1: Missing LEDs at end**
```
LED 195: detected ✓
LED 196: detected ✓
LED 197: MISSING
LED 198: MISSING
LED 199: MISSING

For LED 197:
  before = 196 ✓
  after = null ✗ (no detected LED after 197)
  → EXTRAPOLATE FORWARD from 196
  
Step calculated from 195→196
LED 197 = LED 196 + 1×step
```

**Example 2: Gap at end of detection range**
```
LED 180: detected ✓
LED 181: detected ✓
LED 182-199: ALL MISSING

For LED 185:
  before = 181 ✓
  after = null ✗
  → EXTRAPOLATE FORWARD from 181
  
Step from 180→181
LED 185 = LED 181 + 4×step
```

**Characteristics:**
- Less accurate than interpolation (no endpoint to constrain)
- Uses step calculated from previous two LEDs (if available)
- Otherwise uses default step
- Gets progressively less reliable with distance

---

## Extrapolate Backward: Extending Before First Known

### When Used

**Required:** Known LED AFTER, but NO known LED before

**Example 1: Missing LEDs at start**
```
LED 0: MISSING
LED 1: MISSING
LED 2: MISSING
LED 3: detected ✓
LED 4: detected ✓

For LED 1:
  before = null ✗ (no detected LED before 1)
  after = 3 ✓
  → EXTRAPOLATE BACKWARD from 3
  
Step calculated from 3→4
LED 1 = LED 3 + (1-3)×step = LED 3 - 2×step
```

**Example 2: Gap at beginning**
```
LED 0-15: ALL MISSING
LED 16: detected ✓
LED 17: detected ✓

For LED 10:
  before = null ✗
  after = 16 ✓
  → EXTRAPOLATE BACKWARD from 16
  
Step from 16→17
LED 10 = LED 16 + (10-16)×step = LED 16 - 6×step
```

**Characteristics:**
- Less accurate than interpolation
- Uses step calculated from next two LEDs (if available)
- Otherwise uses default step
- Gets progressively less reliable with distance

---

## Visual Examples

### Scenario 1: Typical Gaps (Interpolation)

```
Detected: ✓    Missing: ○    
Position: 0    10   20   30   40   50

LED positions:
✓----○○○○----✓----○○----✓----✓----✓
0    1234    10   1112  20   30   40

LEDs 1-4:   before=0, after=10  → INTERPOLATE
LEDs 11-12: before=10, after=20 → INTERPOLATE
```

### Scenario 2: Gap at End (Extrapolate Forward)

```
LED positions:
✓----✓----✓----✓----○○○○○
180  185  190  195  196-199

LEDs 196-199: before=195, after=null → EXTRAPOLATE FORWARD
Uses step from 190→195 (or 195→196 if calculated)
```

### Scenario 3: Gap at Start (Extrapolate Backward)

```
LED positions:
○○○○○----✓----✓----✓----✓
0-4      5    10   15   20

LEDs 0-4: before=null, after=5 → EXTRAPOLATE BACKWARD
Uses step from 5→10
```

### Scenario 4: Complex Mixed Pattern

```
LED positions:
○○----✓----○○○----✓----✓----○○○○
01    5    678    15   20   2124-25

LED 0-1:   before=null, after=5  → EXTRAPOLATE BACKWARD
LED 6-8:   before=5, after=15    → INTERPOLATE
LED 21:    before=20, after=null → EXTRAPOLATE FORWARD (wait, check if any after...)

Actually LED 21:
  Searches forward: j=22, 23, 24, 25... none found until end
  before=20 ✓, after=null
  → EXTRAPOLATE FORWARD

LED 24-25: Same (before=20, after=null) → EXTRAPOLATE FORWARD
```

---

## Step Calculation

### For Interpolation

**No step needed!** Position calculated directly:
```dart
t = (target - before) / (after - before)
position = before_pos + (after_pos - before_pos) × t
```

### For Extrapolation

**Step calculation priority:**

**1. From neighboring detected LEDs (preferred):**
```dart
// Forward extrapolation:
if (LED before-1 exists):
  step = calculateStep(LED[before-1], LED[before])
else:
  step = defaultStep

// Backward extrapolation:
if (LED after+1 exists):
  step = calculateStep(LED[after], LED[after+1])
else:
  step = defaultStep
```

**2. Default step (fallback):**
```dart
defaultStep = {
  'x': 0.01,      // 1cm
  'y': 0.01,      // 1cm
  'z': 0.01,      // 1cm
  'height': 0.005, // 0.5%
}
```

---

## Example Execution

### Scenario: Sparse Detection

```
Detected LEDs: 0, 5, 10, 15, 195, 199
Missing: 1-4, 6-9, 11-14, 16-194, 196-198

Processing order (i = 0 to 199):

i=0: detected ✓ (skip)

i=1:
  before = 0 ✓
  after = 5 ✓
  → INTERPOLATE(0, 5, 1)
  
i=2:
  before = 0 ✓
  after = 5 ✓
  → INTERPOLATE(0, 5, 2)
  
i=3, 4: Same (INTERPOLATE between 0 and 5)

i=5: detected ✓ (skip)

i=6:
  before = 5 ✓
  after = 10 ✓
  → INTERPOLATE(5, 10, 6)
  
i=7-9: Same (INTERPOLATE between 5 and 10)

i=10: detected ✓ (skip)

i=11-14: INTERPOLATE(10, 15)

i=15: detected ✓ (skip)

i=16:
  before = 15 ✓
  after = 195 ✓ (very far!)
  → INTERPOLATE(15, 195, 16)
  
i=17-194: INTERPOLATE(15, 195)
  All positions spread evenly from 15 to 195
  Large gap, but still interpolated!

i=195: detected ✓ (skip)

i=196:
  before = 195 ✓
  after = 199 ✓
  → INTERPOLATE(195, 199, 196)
  
i=197-198: INTERPOLATE(195, 199)

i=199: detected ✓ (skip)
```

**Result:**
- LEDs 1-4: interpolated
- LEDs 6-9: interpolated
- LEDs 11-14: interpolated
- LEDs 16-194: interpolated (179 LEDs!)
- LEDs 196-198: interpolated

**All used interpolation!** (No extrapolation needed in this case)

---

## When Extrapolation Actually Happens

### Case 1: All LEDs at End Missing

```
Detected: 0-190
Missing: 191-199

i=191:
  before = 190 ✓
  after = null (search finds nothing)
  → EXTRAPOLATE FORWARD from 190
  
Step from 189→190
LED 191 = LED 190 + 1×step
LED 192 = LED 190 + 2×step
...
LED 199 = LED 190 + 9×step
```

### Case 2: All LEDs at Start Missing

```
Missing: 0-9
Detected: 10-199

i=0:
  before = null (search backwards finds nothing)
  after = 10 ✓
  → EXTRAPOLATE BACKWARD from 10
  
Step from 10→11
LED 0 = LED 10 - 10×step
LED 1 = LED 10 - 9×step
...
LED 9 = LED 10 - 1×step
```

### Case 3: Only First and Last Detected

```
Detected: 0, 199
Missing: 1-198

i=1:
  before = 0 ✓
  after = 199 ✓
  → INTERPOLATE(0, 199, 1)
  
All LEDs 1-198 interpolated between 0 and 199!
No extrapolation needed.
```

---

## Accuracy Comparison

### Interpolation
```
Accuracy: ±5cm (good)
Reason: Bounded by two known points
Confidence: High (constrained)
```

### Extrapolation (1-5 LEDs away)
```
Accuracy: ±5-10cm (decent)
Reason: Short distance from known point
Confidence: Medium (step is reliable)
```

### Extrapolation (>5 LEDs away)
```
Accuracy: ±10-30cm (poor)
Reason: Errors accumulate
Confidence: Low (no constraint)
```

### Long-range Interpolation (>50 LEDs gap)
```
Accuracy: ±10-20cm (better than long extrapolation)
Reason: Still constrained by endpoints
Confidence: Medium (large gap but bounded)
```

**Key insight:** Interpolation is ALWAYS better than extrapolation, even for large gaps!

---

## Summary

### Interpolate (Between Two Known Points)
**When:** Known LED before AND after
**Accuracy:** Best (±5cm)
**Used for:** Most gaps in detected sequence

### Extrapolate Forward (Extending Past Last Known)
**When:** Known LED before, NO LED after
**Accuracy:** Medium to poor (±5-30cm depending on distance)
**Used for:** Missing LEDs at end of string

### Extrapolate Backward (Extending Before First Known)
**When:** NO LED before, known LED after
**Accuracy:** Medium to poor (±5-30cm depending on distance)
**Used for:** Missing LEDs at start of string

**Priority:** Always tries to interpolate first!
- Searches in both directions
- Only extrapolates if can't find boundary on one side
- Extrapolation is fallback for edge cases

**Your question highlights the key difference:** 
- Interpolation: bounded by data (reliable)
- Extrapolation: extending beyond data (speculation)

The algorithm smartly prefers interpolation whenever possible! 🎯
