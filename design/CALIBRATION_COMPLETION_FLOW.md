# Camera Calibration - Completion Flow

## Missing Step: After Adding Cameras

After user adds 3 cameras, they need a way to:
1. Review the camera positions
2. Save the calibration
3. Proceed to capture

---

## Updated UI - Add Completion Button

**File:** `lib/screens/calibration_screen.dart`

Add to the bottom of the screen:

```dart
@override
Widget build(BuildContext context) {
  final cameras = CalibrationService.getCameraPositions();
  final hasEnoughCameras = cameras.length >= 3;
  
  return Scaffold(
    appBar: AppBar(
      title: Text('Camera Calibration'),
      actions: [
        IconButton(
          icon: Icon(_compassMode ? Icons.explore : Icons.edit),
          tooltip: _compassMode ? 'Compass Mode' : 'Manual Mode',
          onPressed: () {
            setState(() {
              _compassMode = !_compassMode;
            });
          },
        ),
      ],
    ),
    body: Column(
      children: [
        // ... compass display ...
        // ... instructions ...
        // ... add camera button ...
        
        // Camera list
        Expanded(
          child: _buildCameraList(),
        ),
        
        // NEW: Completion section
        if (hasEnoughCameras)
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border(top: BorderSide(color: Colors.green[200]!)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      '${cameras.length} cameras configured',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.save, size: 24),
                    label: Text(
                      'Save Calibration & Continue',
                      style: TextStyle(fontSize: 16),
                    ),
                    onPressed: _completeCalibration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
    
    // NEW: Floating action button for quick completion
    floatingActionButton: hasEnoughCameras
      ? FloatingActionButton.extended(
          icon: Icon(Icons.check),
          label: Text('Done'),
          onPressed: _completeCalibration,
          backgroundColor: Colors.green,
        )
      : null,
  );
}

Future<void> _completeCalibration() async {
  final cameras = CalibrationService.getCameraPositions();
  
  // Show confirmation dialog with summary
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Calibration Complete'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Camera Configuration:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          ...cameras.map((camera) => Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  child: Text('${camera.index + 1}', style: TextStyle(fontSize: 10)),
                  backgroundColor: Colors.blue,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${camera.angle.toStringAsFixed(1)}° • '
                    '${camera.distance.toStringAsFixed(2)}m • '
                    '${camera.height.toStringAsFixed(2)}m',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          )),
          SizedBox(height: 12),
          Divider(),
          SizedBox(height: 8),
          Text(
            'Ready to start capturing LEDs?',
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
      actions: [
        TextButton(
          child: Text('Back to Edit'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ElevatedButton.icon(
          icon: Icon(Icons.check),
          label: Text('Confirm & Continue'),
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
  
  if (confirmed == true) {
    // Save calibration (already saved per camera, but ensure persisted)
    await CalibrationService.saveCalibration();
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calibration saved successfully!'),
        backgroundColor: Colors.green,
      ),
    );
    
    // Navigate to capture screen or home
    Navigator.of(context).pushReplacementNamed('/capture');
    // Or: Navigator.of(context).pop();  // Return to home
  }
}
```

---

## Complete User Flow

### Step-by-Step with Completion

```
1. User opens Calibration Screen
   → Sees compass display and instructions
   
2. User points phone at tree center
   → Taps "Set Reference"
   → App: "Reference set: 247°" ✓
   
3. User taps "Add Camera"
   → Enters distance/height
   → App: "Camera 1 added at 0°" ✓
   → Camera list shows: Camera 1
   
4. User moves to position 2, points at tree
   → Taps "Add Camera"
   → Enters distance/height
   → App: "Camera 2 added at 73°" ✓
   → Camera list shows: Camera 1, Camera 2
   
5. User moves to position 3, points at tree
   → Taps "Add Camera"
   → Enters distance/height
   → App: "Camera 3 added at 285°" ✓
   → Camera list shows: Camera 1, Camera 2, Camera 3
   
6. Green bar appears at bottom:
   "✓ 3 cameras configured"
   [Save Calibration & Continue] button appears ← NEW!
   
7. User taps "Save Calibration & Continue"
   → Dialog shows summary:
     "Camera 1: 0° • 1.5m • 1.0m
      Camera 2: 73° • 1.8m • 1.2m
      Camera 3: 285° • 1.6m • 0.9m
      Ready to start capturing LEDs?"
   
8. User taps "Confirm & Continue"
   → Navigates to Capture Screen
   → Ready to start capturing LEDs!
```

---

## Alternative: Navigation Options

### Option 1: Go to Capture Screen (Recommended)
```dart
// After confirmation
Navigator.of(context).pushReplacementNamed('/capture');
```
**Why:** User just finished calibration, likely wants to capture next
**Flow:** Calibration → Capture → Results

### Option 2: Return to Home
```dart
// After confirmation
Navigator.of(context).pop();
```
**Why:** Let user decide what to do next
**Flow:** Calibration → Home → (user chooses next step)

### Option 3: Show Summary Screen
```dart
// After confirmation
Navigator.of(context).pushReplacement(
  MaterialPageRoute(
    builder: (context) => CalibrationSummaryScreen(),
  ),
);
```
**Why:** Show detailed calibration info, offer test options
**Flow:** Calibration → Summary → (user chooses next step)

---

## Visual Feedback During Process

### Progress Indicator

Add at top of screen:

```dart
Widget _buildProgressIndicator() {
  final cameras = CalibrationService.getCameraPositions();
  final hasReference = _referenceHeading != null;
  
  return Card(
    margin: EdgeInsets.all(16),
    color: Colors.blue[50],
    child: Padding(
      padding: EdgeInsets.all(12),
      child: Row(
        children: [
          _buildProgressStep(
            number: 1,
            label: 'Set Reference',
            completed: hasReference,
          ),
          Expanded(child: Divider(thickness: 2)),
          _buildProgressStep(
            number: 2,
            label: 'Add ${cameras.length}/3 Cameras',
            completed: cameras.length >= 3,
          ),
          Expanded(child: Divider(thickness: 2)),
          _buildProgressStep(
            number: 3,
            label: 'Save',
            completed: false,
          ),
        ],
      ),
    ),
  );
}

Widget _buildProgressStep({
  required int number,
  required String label,
  required bool completed,
}) {
  return Column(
    children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: completed ? Colors.green : Colors.grey[300],
        child: completed
          ? Icon(Icons.check, size: 16, color: Colors.white)
          : Text('$number'),
      ),
      SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: completed ? FontWeight.bold : FontWeight.normal,
          color: completed ? Colors.green : Colors.grey[600],
        ),
      ),
    ],
  );
}
```

**Shows:**
```
[✓] Set Reference ━━━ [✓] Add 3/3 Cameras ━━━ [3] Save
```

---

## Minimum Camera Requirement

### Validation

```dart
// Require at least 3 cameras
Widget _buildCompletionButton() {
  final cameras = CalibrationService.getCameraPositions();
  
  if (cameras.length < 3) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Need at least 3 cameras',
            style: TextStyle(color: Colors.orange[900]),
          ),
          Text(
            '${cameras.length}/3 added',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
  
  // Show completion button if enough cameras
  return Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.green[50],
      border: Border(top: BorderSide(color: Colors.green[200]!)),
    ),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(Icons.save),
        label: Text('Save Calibration & Continue'),
        onPressed: _completeCalibration,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: EdgeInsets.all(16),
        ),
      ),
    ),
  );
}
```

---

## Error Handling

### Before Completion

Check for issues:

```dart
Future<void> _completeCalibration() async {
  final cameras = CalibrationService.getCameraPositions();
  
  // Validation checks
  if (cameras.length < 3) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Need at least 3 cameras to continue'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }
  
  // Check if cameras are too close together
  final angles = cameras.map((c) => c.angle).toList()..sort();
  for (int i = 0; i < angles.length - 1; i++) {
    final diff = angles[i + 1] - angles[i];
    if (diff < 30) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Warning'),
          content: Text(
            'Some cameras are very close together (${diff.toStringAsFixed(0)}° apart). '
            'This may reduce accuracy. Continue anyway?'
          ),
          actions: [
            TextButton(
              child: Text('Back to Edit'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: Text('Continue Anyway'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      
      if (proceed != true) return;
    }
  }
  
  // Proceed with completion...
  _showCompletionDialog();
}
```

---

## Quick Reference

### Complete Button Options

**Option A: Bottom Bar (Recommended)**
```dart
// Shows when cameras.length >= 3
// Fixed at bottom of screen
// Always visible
```

**Option B: Floating Action Button**
```dart
// Shows when cameras.length >= 3
// Floats in bottom-right corner
// Less obtrusive
```

**Option C: Both**
```dart
// Bottom bar + FAB
// Maximum visibility
// User can't miss it
```

**Recommendation:** Use both (bottom bar + FAB) for maximum clarity

---

## Summary

**After adding 3 cameras, user:**

1. **Sees green completion bar** at bottom:
   ```
   ✓ 3 cameras configured
   [Save Calibration & Continue]
   ```

2. **Taps "Save Calibration & Continue"**

3. **Reviews summary dialog:**
   ```
   Camera 1: 0° • 1.5m • 1.0m
   Camera 2: 73° • 1.8m • 1.2m
   Camera 3: 285° • 1.6m • 0.9m
   
   Ready to start capturing LEDs?
   [Back to Edit] [Confirm & Continue]
   ```

4. **Taps "Confirm & Continue"**

5. **Navigates to Capture Screen** → Ready to capture LEDs!

---

## Implementation

**Add to calibration screen:**
```dart
1. Progress indicator (optional, nice UX)
2. Completion button (shows when cameras.length >= 3)
3. _completeCalibration() method
4. Confirmation dialog
5. Navigation to capture screen
```

**Estimated:** 1-2 hours to add completion flow

**The missing piece is now complete!** 🎯✨
