# LED Mapper - Flutter App

Automated LED position capture app for Christmas tree LED mapping. Controls LEDs via MQTT and captures photos automatically.

## Features

- 📱 **Automated Capture**: Cycles through all LEDs automatically, taking photos
- 🔌 **MQTT Integration**: Full MQTT support for LED control
- 📷 **Camera Control**: Built-in camera integration
- 🗂️ **Multi-Position Support**: Capture from multiple camera angles
- 📤 **Export**: ZIP and share captured images
- ⚙️ **Configurable**: Customize MQTT topics, delays, and LED count

## Setup

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android device with camera
- MQTT broker for LED control

### Installation

1. **Clone/download the app files**

2. **Install dependencies:**
   ```bash
   cd led_mapper_app
   flutter pub get
   ```

3. **Connect your Android device** (or start emulator)

4. **Run the app:**
   ```bash
   flutter run
   ```

## Configuration

### MQTT Settings

Before starting, configure your MQTT connection:

1. Open the app
2. Tap **Settings** (gear icon)
3. Configure:
   - **Broker Address**: Your MQTT broker (e.g., `192.168.1.100`)
   - **Port**: Usually `1883`
   - **Username/Password**: If required
   - **Topic Template**: Pattern for LED topics (e.g., `led/{{index}}/set`)
   - **ON/OFF Payload**: Messages to turn LED on/off
   - **All Off Topic**: Topic to turn all LEDs off

### Example MQTT Configurations

**Simple numbered topics:**
```
Topic Template: led/{{index}}/set
ON Payload: ON
OFF Payload: OFF
All Off Topic: led/all/set
```

**JSON payloads:**
```
Topic Template: lights/strip1/{{index}}
ON Payload: {"state":"on"}
OFF Payload: {"state":"off"}
All Off Topic: lights/strip1/all
```

**Home Assistant:**
```
Topic Template: homeassistant/light/tree_led_{{index}}/set
ON Payload: ON
OFF Payload: OFF
All Off Topic: homeassistant/light/tree_all/set
```

### Capture Settings

- **Total LEDs**: Number of LEDs in your strand
- **Delay Before Capture**: Wait time (ms) after LED turns on before taking photo
- **Delay After Capture**: Wait time (ms) before moving to next LED

## Usage

### Step 1: Connect to MQTT

1. Configure settings (see above)
2. Tap **"Connect to MQTT"** on home screen
3. Wait for "Connected" status

### Step 2: Initialize Camera

1. Tap **"Initialize Camera"**
2. Grant camera permissions if prompted
3. Wait for "Camera ready" status

### Step 3: Capture First Position

1. Position your phone at the first angle (e.g., front of tree)
2. Use a tripod or stable surface
3. Tap **"Start New Capture"**
4. Select position number (1)
5. Tap **"START CAPTURE"**
6. Wait while app cycles through all LEDs (takes ~5-10 minutes for 200 LEDs)

### Step 4: Capture Additional Positions

1. When complete, tap **"Next Position"**
2. Move phone to next angle (e.g., side of tree)
3. Repeat capture (position 2)
4. Continue for 3-5 positions around tree

### Step 5: Export

1. Tap **"View & Export Captures"**
2. Review captured positions
3. Tap **"Export All as ZIP"**
4. Share/save the ZIP file
5. Transfer to computer for processing

## Processing Captured Images

After capturing, use the Python processing scripts:

1. **Extract ZIP** on your computer
2. **Run processing:**
   ```bash
   python process_images.py led_captures/ \
       --num-leds 200 \
       --tree-height 2.0 \
       --output led_positions.json
   ```

This generates a JSON file with height/angle/radius for each LED.

## Tips for Best Results

### Camera Positioning
- Use a tripod or stable mount
- Keep camera at same height (middle of tree)
- Distance: 1.5-2 meters from tree
- Aim for 3-5 positions evenly spaced

### Lighting
- **Dark room** - turn off all other lights
- Only the single LED should be visible
- Check first few captures to ensure LED is bright enough

### Timing
- Default 300ms delay usually works
- Increase if LEDs are slow to respond
- Decrease for faster capture (but check quality)

### Coverage
- Don't worry about 100% coverage
- 60-70% visible LEDs is great
- Back of tree (against wall) will be predicted

## Troubleshooting

### MQTT Connection Fails
- Check broker address and port
- Verify network connection (same WiFi as broker)
- Try public broker first: `broker.hivemq.com:1883`

### Camera Not Working
- Grant camera permissions in Android settings
- Try restarting the app
- Check if another app is using camera

### LED Not Turning On
- Verify MQTT topic format matches your setup
- Check payload format (ON vs on vs 1 vs true)
- Test with MQTT client (e.g., MQTT Explorer) first

### Images Too Dark/Bright
- Adjust room lighting
- Move camera closer/farther
- LED might be too dim - check LED brightness settings

### Capture is Slow
- Reduce delays in settings (try 200ms before, 50ms after)
- Normal: ~200 LEDs takes 5-10 minutes
- Can't be much faster due to MQTT/camera lag

## MQTT Message Format

You'll need to configure the app to match your LED controller's MQTT format. Here's what happens:

**For each LED index (0 to N-1):**
1. App substitutes `{{index}}` in topic template
2. Sends configured ON payload to that topic
3. Waits (delay before capture)
4. Takes photo
5. Sends OFF payload
6. Waits (delay after capture)
7. Moves to next LED

**Example for LED 42:**
```
Topic: led/42/set
Payload: ON

[wait 300ms]
[take photo]

Topic: led/42/set
Payload: OFF

[wait 100ms]
[next LED]
```

## App Structure

```
lib/
├── main.dart                 # App entry point
├── services/
│   ├── mqtt_service.dart    # MQTT connection & LED control
│   ├── camera_service.dart  # Camera management
│   └── capture_service.dart # Orchestrates capture process
└── screens/
    ├── home_screen.dart     # Main screen
    ├── capture_screen.dart  # Live capture interface
    ├── settings_screen.dart # Configuration
    └── export_screen.dart   # View & export images
```

## Advanced

### Customizing LED Control Logic

Edit `lib/services/mqtt_service.dart` to:
- Change message format
- Add authentication
- Support different protocols

### Batch Processing

To process multiple captures at once:
```bash
# Process all camera folders
for dir in camera*/; do
    python process_images.py "$dir" --num-leds 200 --output "${dir}_positions.json"
done
```

## Development

### Building APK

```bash
flutter build apk --release
```

APK will be in: `build/app/outputs/flutter-apk/app-release.apk`

### Adding Features

The app is modular - easy to extend:
- Add new MQTT authentication methods
- Support different message formats
- Add image filtering/processing
- Implement on-device triangulation

## License

MIT License - Feel free to modify and use for your projects!

## Next Steps

After capturing and processing:
1. Use LED positions for animations
2. Create spatial audio visualizations
3. Build 3D effects
4. Integrate with home automation

Happy mapping! 🎄✨
