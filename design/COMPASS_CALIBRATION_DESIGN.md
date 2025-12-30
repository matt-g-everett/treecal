# Compass-Based Camera Angle Calibration

## The Problem

**Real-world constraints:**
- Tree in corner of room
- Can only position phone at 3 angles (not evenly spaced)
- Manual angle estimation is error-prone
- Hard to measure precise angles

**Current approach:**
```dart
// User manually enters angle
CameraPosition(
  index: 0,
  angle: 0,    // ← User guesses this!
  distance: 1.5,
  height: 1.0,
);
```

**Problems with manual:**
- ❌ Inaccurate (guessing angles)
- ❌ Time-consuming
- ❌ Hard to visualize
- ❌ No way to verify

---

## The Solution: Use Phone Compass

**Phone sensors available:**
- Magnetometer (compass) - gives bearing 0-360°
- Can read current heading direction
- Available on all phones

**Approach:**
1. User calibrates "zero reference" (e.g., point at tree center)
2. For each camera position:
   - Point phone at tree center
   - Read compass bearing
   - Calculate angle relative to reference
3. Store angle automatically

---

## Implementation

### 1. Add Compass Service

**File:** `lib/services/compass_service.dart`

```dart
import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';

/// Service for reading phone compass/magnetometer
class CompassService {
  static StreamSubscription<CompassEvent>? _subscription;
  static double _currentHeading = 0.0;
  static bool _isListening = false;
  
  /// Start listening to compass
  static Future<void> startListening() async {
    if (_isListening) return;
    
    _subscription = FlutterCompass.events?.listen((CompassEvent event) {
      _currentHeading = event.heading ?? 0.0;
    });
    
    _isListening = true;
  }
  
  /// Stop listening to compass
  static Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }
  
  /// Get current compass heading (0-360°)
  /// 0° = North, 90° = East, 180° = South, 270° = West
  static double getCurrentHeading() {
    return _currentHeading;
  }
  
  /// Get average heading over a period (more stable)
  static Future<double> getAverageHeading({
    Duration duration = const Duration(seconds: 2),
    int samples = 20,
  }) async {
    final headings = <double>[];
    final interval = duration.inMilliseconds ~/ samples;
    
    for (int i = 0; i < samples; i++) {
      headings.add(_currentHeading);
      await Future.delayed(Duration(milliseconds: interval));
    }
    
    // Use circular mean for angles
    double sumSin = 0;
    double sumCos = 0;
    
    for (final heading in headings) {
      final rad = heading * 3.14159 / 180;
      sumSin += sin(rad);
      sumCos += cos(rad);
    }
    
    final avgRad = atan2(sumSin / samples, sumCos / samples);
    final avgHeading = (avgRad * 180 / 3.14159 + 360) % 360;
    
    return avgHeading;
  }
  
  /// Calculate relative angle between two bearings
  /// Returns angle in range [0, 360)
  static double relativeBearing(double bearing1, double bearing2) {
    double diff = (bearing2 - bearing1) % 360;
    if (diff < 0) diff += 360;
    return diff;
  }
}
```

**Dependencies:** Add to `pubspec.yaml`
```yaml
dependencies:
  flutter_compass: ^0.8.0
```

---

### 2. Update Camera Calibration UI

**Add compass-based calibration mode:**

```dart
class CameraCalibrationScreen extends StatefulWidget {
  // ...
}

class _CameraCalibrationScreenState extends State<CameraCalibrationScreen> {
  bool _useCompass = true;
  double? _referenceHeading;  // Zero reference
  double _currentHeading = 0.0;
  
  @override
  void initState() {
    super.initState();
    CompassService.startListening();
    
    // Update UI with current heading
    Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _currentHeading = CompassService.getCurrentHeading();
        });
      }
    });
  }
  
  @override
  void dispose() {
    CompassService.stopListening();
    super.dispose();
  }
  
  Future<void> _setReferenceHeading() async {
    // Average over 2 seconds for stability
    final heading = await CompassService.getAverageHeading();
    
    setState(() {
      _referenceHeading = heading;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reference set: ${heading.toStringAsFixed(1)}°')),
    );
  }
  
  Future<void> _addCameraWithCompass() async {
    if (_referenceHeading == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please set reference heading first')),
      );
      return;
    }
    
    // Get stable heading
    final heading = await CompassService.getAverageHeading();
    
    // Calculate angle relative to reference
    final relativeAngle = CompassService.relativeBearing(
      _referenceHeading!,
      heading,
    );
    
    // Add camera with calculated angle
    final camera = CameraPosition(
      index: _cameras.length,
      angle: relativeAngle,
      distance: 1.5,  // User can still adjust
      height: 1.0,    // User can still adjust
    );
    
    setState(() {
      _cameras.add(camera);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Camera added at ${relativeAngle.toStringAsFixed(1)}° '
          '(${heading.toStringAsFixed(1)}° absolute)'
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Camera Calibration')),
      body: Column(
        children: [
          // Compass indicator
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Current Heading', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text(
                    '${_currentHeading.toStringAsFixed(1)}°',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  if (_referenceHeading != null) ...[
                    SizedBox(height: 8),
                    Text('Reference: ${_referenceHeading!.toStringAsFixed(1)}°'),
                    Text(
                      'Relative: ${CompassService.relativeBearing(_referenceHeading!, _currentHeading).toStringAsFixed(1)}°',
                      style: TextStyle(color: Colors.blue, fontSize: 24),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          // Instructions
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Setup:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('1. Point phone at tree center'),
                  Text('2. Tap "Set Reference"'),
                  Text('3. Move to each camera position'),
                  Text('4. Point at tree center and tap "Add Camera"'),
                ],
              ),
            ),
          ),
          
          // Buttons
          if (_referenceHeading == null)
            ElevatedButton.icon(
              icon: Icon(Icons.explore),
              label: Text('Set Reference (point at tree)'),
              onPressed: _setReferenceHeading,
            )
          else
            Column(
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.add_a_photo),
                  label: Text('Add Camera (point at tree)'),
                  onPressed: _addCameraWithCompass,
                ),
                TextButton(
                  child: Text('Reset Reference'),
                  onPressed: () {
                    setState(() {
                      _referenceHeading = null;
                      _cameras.clear();
                    });
                  },
                ),
              ],
            ),
          
          // Camera list
          Expanded(
            child: ListView.builder(
              itemCount: _cameras.length,
              itemBuilder: (context, index) {
                final camera = _cameras[index];
                return ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text('Camera ${index + 1}'),
                  subtitle: Text(
                    'Angle: ${camera.angle.toStringAsFixed(1)}°, '
                    'Distance: ${camera.distance}m, '
                    'Height: ${camera.height}m'
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.edit),
                    onPressed: () => _editCamera(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

---

### 3. Calibration Workflow

**Step-by-step process:**

```
1. User Setup:
   - Places phone in first position
   - Points phone camera at tree center
   - Taps "Set Reference"
   - App records: reference_heading = 247° (example)

2. First Camera Position:
   - Phone is already at position 1
   - Points at tree center
   - Taps "Add Camera"
   - App reads: current_heading = 247°
   - Calculates: relative_angle = 0° (reference)
   - Stores: Camera 1 at 0°

3. Second Camera Position:
   - User moves to position 2 (wherever possible)
   - Points at tree center
   - Taps "Add Camera"
   - App reads: current_heading = 317°
   - Calculates: relative_angle = (317 - 247) = 70°
   - Stores: Camera 2 at 70°

4. Third Camera Position:
   - User moves to position 3
   - Points at tree center
   - Taps "Add Camera"
   - App reads: current_heading = 167°
   - Calculates: relative_angle = (167 - 247 + 360) = 280°
   - Stores: Camera 3 at 280°

Result: Cameras at 0°, 70°, 280° (automatically determined!)
```

---

### 4. Visual Feedback

**Add real-time compass visualization:**

```dart
class CompassIndicator extends StatelessWidget {
  final double heading;
  final double? referenceHeading;
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(200, 200),
      painter: CompassPainter(
        heading: heading,
        referenceHeading: referenceHeading,
      ),
    );
  }
}

class CompassPainter extends CustomPainter {
  final double heading;
  final double? referenceHeading;
  
  CompassPainter({required this.heading, this.referenceHeading});
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Draw compass circle
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.grey[300]!..style = PaintingStyle.stroke..strokeWidth = 2,
    );
    
    // Draw cardinal directions
    _drawText(canvas, center, radius, 0, 'N');
    _drawText(canvas, center, radius, 90, 'E');
    _drawText(canvas, center, radius, 180, 'S');
    _drawText(canvas, center, radius, 270, 'W');
    
    // Draw current heading arrow
    _drawArrow(canvas, center, radius * 0.8, heading, Colors.blue);
    
    // Draw reference heading if set
    if (referenceHeading != null) {
      _drawArrow(canvas, center, radius * 0.6, referenceHeading!, Colors.red);
    }
  }
  
  void _drawArrow(Canvas canvas, Offset center, double length, double angle, Color color) {
    final rad = (angle - 90) * 3.14159 / 180;  // -90 to point up at 0°
    final end = Offset(
      center.dx + length * cos(rad),
      center.dy + length * sin(rad),
    );
    
    canvas.drawLine(
      center,
      end,
      Paint()..color = color..strokeWidth = 3,
    );
    
    // Arrow head
    final arrowSize = 10.0;
    final arrowAngle1 = rad + 2.8;
    final arrowAngle2 = rad - 2.8;
    
    canvas.drawLine(
      end,
      Offset(end.dx + arrowSize * cos(arrowAngle1), end.dy + arrowSize * sin(arrowAngle1)),
      Paint()..color = color..strokeWidth = 3,
    );
    
    canvas.drawLine(
      end,
      Offset(end.dx + arrowSize * cos(arrowAngle2), end.dy + arrowSize * sin(arrowAngle2)),
      Paint()..color = color..strokeWidth = 3,
    );
  }
  
  void _drawText(Canvas canvas, Offset center, double radius, double angle, String text) {
    final rad = (angle - 90) * 3.14159 / 180;
    final pos = Offset(
      center.dx + radius * 1.15 * cos(rad),
      center.dy + radius * 1.15 * sin(rad),
    );
    
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, pos - Offset(textPainter.width / 2, textPainter.height / 2));
  }
  
  @override
  bool shouldRepaint(CompassPainter oldDelegate) => true;
}
```

---

## Advantages of Compass-Based Calibration

### 1. Accuracy
```
Manual estimation: ±10-20° error
Compass reading: ±2-5° error (much better!)
```

### 2. Speed
```
Manual: 
  - Measure angles with protractor
  - Calculate positions
  - Enter numbers
  Time: ~5 minutes

Compass:
  - Point and tap
  - Point and tap
  - Point and tap
  Time: ~30 seconds
```

### 3. Flexibility
```
Manual: Need to plan camera positions
Compass: Use whatever positions work in your room!

Example with tree in corner:
- Camera 1: 0° (reference)
- Camera 2: 73° (where you can fit)
- Camera 3: 285° (other accessible angle)

No need for evenly-spaced angles!
```

### 4. Verification
```
Compass shows real-time angle
→ Can verify before adding camera
→ Can re-check if needed
→ Visual feedback with compass rose
```

---

## Indoor Compass Accuracy

### Potential Issues

**1. Magnetic Interference:**
```
Metal objects, electronics can affect compass
→ Keep away from metal shelves, radiators
→ Avoid near TV, computer, speakers
→ Use averaging to reduce noise
```

**2. Calibration:**
```
Phone compass needs calibration
→ Most phones prompt automatically
→ "Figure 8" motion to calibrate
→ Do this before starting
```

**3. Noise:**
```
Indoor readings can be noisy
→ Use 2-second averaging
→ Take multiple readings if unsure
→ Still better than manual estimation!
```

### Mitigation

```dart
// Use averaging for stability
final heading = await CompassService.getAverageHeading(
  duration: Duration(seconds: 2),
  samples: 20,
);

// Allow user to re-measure if reading seems off
ElevatedButton(
  child: Text('Re-measure Angle'),
  onPressed: () async {
    final newHeading = await CompassService.getAverageHeading();
    // Update camera angle
  },
);
```

---

## Implementation Plan

### Phase 1: Basic Compass (2-3 hours)
1. Add `flutter_compass` dependency
2. Create `CompassService`
3. Test compass reading on device

### Phase 2: UI Integration (2-3 hours)
1. Update calibration screen
2. Add reference heading button
3. Add camera position button
4. Show current heading

### Phase 3: Visual Feedback (2-3 hours)
1. Create compass rose widget
2. Show current heading arrow
3. Show reference arrow
4. Add relative angle display

### Phase 4: Polish (1-2 hours)
1. Add instructions
2. Add error handling
3. Add re-measurement option
4. Test with real tree setup

**Total: 7-11 hours**

---

## Example Usage

### User Experience

```
[Screen shows compass rose, heading shows 247°]

User: "I'll set this as my reference"
[Taps "Set Reference"]
App: "Reference set: 247°"

[User moves to second position, heading shows 317°]
App: Shows "Relative: 70°" in real-time

User: "Looks good"
[Taps "Add Camera"]
App: "Camera 2 added at 70°"

[User moves to third position, heading shows 167°]
App: Shows "Relative: 280°" in real-time

User: "Perfect"
[Taps "Add Camera"]
App: "Camera 3 added at 280°"

Done! Three cameras at 0°, 70°, 280° automatically calibrated.
```

---

## Alternative: Use Phone Gyroscope

**If compass is too noisy:**

Could use gyroscope for relative rotation:
```dart
// Record rotation from first position
1. Set reference at position 1
2. User rotates phone to position 2
3. Gyroscope tracks rotation angle
4. Add camera at (reference + rotation)
```

**Pros:**
- Not affected by magnetic interference
- Very accurate for rotation

**Cons:**
- Drift over time
- Needs frequent re-calibration
- More complex to implement

**Recommendation:** Start with compass, it's simpler and usually good enough!

---

## Summary

**Problem:** Tree in corner, only 3 imprecise camera positions possible

**Solution:** Use phone compass to auto-detect camera angles

**Benefits:**
- ✅ Much more accurate than manual (±2-5° vs ±10-20°)
- ✅ Much faster (<1 minute vs 5 minutes)
- ✅ Works with any camera positions (not just evenly spaced)
- ✅ Real-time visual feedback
- ✅ Easy to verify and re-measure

**Implementation:** 7-11 hours

**Next steps:**
1. Add `flutter_compass` dependency
2. Create `CompassService`
3. Update calibration UI
4. Test with your corner tree setup!

This will make calibration SO much easier and more accurate! 🎯✨
