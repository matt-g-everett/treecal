import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../services/mqtt_service.dart';
import '../services/camera_service.dart';
import '../services/capture_service.dart';
import '../services/calibration_service.dart';
import '../services/settings_service.dart';
import '../main.dart';
import 'settings_screen.dart';
import 'capture_screen.dart';
import 'export_screen.dart';
import 'led_detection_test_screen.dart';
import 'led_visualization_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LED Position Mapper'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: const HomeContent(),
    );
  }
}

class HomeContent extends StatelessWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final mqtt = Provider.of<MqttService>(context);
    final camera = Provider.of<CameraService>(context);
    final capture = Provider.of<CaptureService>(context);

    // Configure services with settings
    mqtt.configure(settings);
    capture.configure(settings);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
          // Status Cards
          _StatusCard(
            title: 'MQTT Connection',
            icon: mqtt.isConnected ? Icons.wifi : Icons.wifi_off,
            status: mqtt.statusMessage,
            color: mqtt.isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 12),
          
          _StatusCard(
            title: 'Camera',
            icon: camera.isInitialized ? Icons.camera_alt : Icons.camera_alt_outlined,
            status: camera.statusMessage,
            color: camera.isInitialized ? Colors.green : Colors.orange,
          ),
          const SizedBox(height: 24),
          
          // Connection Buttons
          if (!mqtt.isConnected)
            ElevatedButton.icon(
              onPressed: () async {
                await mqtt.connect();
              },
              icon: const Icon(Icons.wifi),
              label: const Text('Connect to MQTT'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          
          if (mqtt.isConnected && !camera.isInitialized && cameras.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () async {
                // Use back camera by default
                final backCamera = cameras.firstWhere(
                  (camera) => camera.lensDirection == CameraLensDirection.back,
                  orElse: () => cameras.first,
                );
                await camera.initialize(backCamera);
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Initialize Camera'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          
          const SizedBox(height: 24),
          
          // Capture Info
          if (mqtt.isConnected && camera.isInitialized) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to Capture',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total LEDs: ${capture.totalLEDs}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<List<String>>(
                      future: capture.getCapturedPositions(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Text(
                            'Captured positions: ${snapshot.data!.length}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Start Capture Button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CaptureScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.photo_camera),
              label: const Text('Start New Capture'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(20),
                backgroundColor: Colors.green,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // LED Detection Test Button
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LEDDetectionTestScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.search),
              label: const Text('Test LED Detection'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                side: const BorderSide(color: Colors.blue),
                foregroundColor: Colors.blue,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Process All Button (if detections available)
            if (capture.numDetections > 0) ...[
              ElevatedButton.icon(
                onPressed: capture.state == CaptureState.processing 
                  ? null
                  : () async {
                      // Get tree height from user
                      final height = await showDialog<double>(
                        context: context,
                        builder: (context) => _TreeHeightDialog(),
                      );
                      
                      if (height != null && context.mounted) {
                        await capture.processAllDetections(
                          calibration: Provider.of<CalibrationService>(context, listen: false),
                          treeHeight: height,
                        );
                      }
                    },
                icon: capture.state == CaptureState.processing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_fix_high),
                label: Text(capture.state == CaptureState.processing
                  ? 'Processing...'
                  : 'Process All Positions (${capture.numDetections} detections)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: Colors.purple,
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Results display (if processing complete)
            if (capture.finalPositions != null) ...[
              Card(
                color: Colors.green.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        '✓ ${capture.finalPositions!.length} LED positions ready!',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saved to led_positions.json',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // 3D Visualization Button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LEDVisualizationScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.scatter_plot),
                label: const Text('View 3D Visualization'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.purple,
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // View/Export Button
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ExportScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('View & Export Captures'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
          
          const SizedBox(height: 24),

          // Instructions
          Card(
            color: Colors.blue.shade900.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Start:',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('1. Configure MQTT settings'),
                  const Text('2. Connect to MQTT broker'),
                  const Text('3. Initialize camera'),
                  const Text('4. Position phone at first angle'),
                  const Text('5. Start capture'),
                  const Text('6. Repeat at 3-5 positions'),
                  const Text('7. Export and process'),
                ],
              ),
            ),
          ),
        ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String status;
  final Color color;

  const _StatusCard({
    required this.title,
    required this.icon,
    required this.status,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(title),
        subtitle: Text(status),
      ),
    );
  }
}

class _TreeHeightDialog extends StatefulWidget {
  @override
  State<_TreeHeightDialog> createState() => _TreeHeightDialogState();
}

class _TreeHeightDialogState extends State<_TreeHeightDialog> {
  final _controller = TextEditingController(text: '2.0');
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tree Height'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter the height of your tree in meters:'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Height (meters)',
              hintText: '2.0',
              suffixText: 'm',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Process'),
        ),
      ],
    );
  }
  
  void _submit() {
    final height = double.tryParse(_controller.text);
    if (height != null && height > 0) {
      Navigator.pop(context, height);
    }
  }
}
