# Quick Setup Guide - LED Mapper Flutter App

## What You'll Need

1. **Android Phone** with camera
2. **MQTT Broker** for LED control (your existing setup)
3. **Flutter SDK** installed on computer
4. **Your LED MQTT message format** (I'll help configure this)

## Installation (5 minutes)

### 1. Install Flutter

**Windows:**
```bash
# Download from https://flutter.dev/docs/get-started/install/windows
# Extract and add to PATH
```

**Mac/Linux:**
```bash
# Download from https://flutter.dev/docs/get-started/install
# Or use: brew install flutter (Mac)
```

Verify:
```bash
flutter doctor
```

### 2. Setup App

```bash
cd led_mapper_app
flutter pub get
```

### 3. Connect Phone

- Enable Developer Mode on Android
- Enable USB Debugging
- Connect via USB
- Verify: `flutter devices`

### 4. Run App

```bash
flutter run
```

## Configuration (2 minutes)

### MQTT Settings

When you provide your MQTT message format, I'll help you configure:

**What I need from you:**
1. MQTT broker address (IP or hostname)
2. Port (usually 1883)
3. Topic format for controlling LEDs
4. Message payload format

**Example formats:**

**Format 1: Simple topics**
```
To turn on LED 42:
  Topic: led/42/set
  Message: ON
```

**Format 2: JSON payloads**
```
To turn on LED 42:
  Topic: lights/tree/42
  Message: {"state": "on"}
```

**Format 3: Home Assistant**
```
To turn on LED 42:
  Topic: homeassistant/light/led_42/set
  Message: ON
```

Once you tell me your format, configure in app:
1. Open app
2. Tap Settings (⚙️)
3. Enter your MQTT details
4. Save

## First Capture (10 minutes)

### Quick Test

1. **Connect MQTT**: Tap "Connect to MQTT"
2. **Init Camera**: Tap "Initialize Camera"
3. **Test**: In settings, try turning on one LED manually to verify

### Full Capture

1. Position phone on tripod at front of tree
2. Tap "Start New Capture"
3. Position 1
4. Tap "START CAPTURE"
5. Wait 5-10 minutes (for 200 LEDs)
6. Move to position 2, repeat
7. Do 3-5 positions total

### Export

1. Tap "View & Export Captures"
2. Tap "Export All as ZIP"
3. Share to your computer

## Processing (5 minutes)

On your computer:

```bash
# Unzip captures
unzip led_captures.zip

# Process
python process_images.py . --num-leds 200 --tree-height 2.0

# View results
cat led_positions.json
```

## Common Issues

**"Can't connect to MQTT"**
- Check broker IP address
- Verify you're on same network
- Try a public broker first: `broker.hivemq.com`

**"Camera permission denied"**
- Go to Android Settings > Apps > LED Mapper > Permissions
- Enable Camera

**"LEDs not turning on"**
- Your MQTT format might be different
- Test with MQTT Explorer first
- Share your format and I'll help configure

## Next: Provide Your MQTT Format

Please share:
1. Your MQTT broker address
2. How you currently turn on LED #42 (topic + message)
3. How you turn off an LED
4. How you turn off all LEDs (if you have this)

I'll give you the exact configuration for the app! 🎄
