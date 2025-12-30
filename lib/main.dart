import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'screens/home_screen.dart';
import 'services/mqtt_service.dart';
import 'services/camera_service.dart';
import 'services/capture_service.dart';
import 'services/calibration_service.dart';
import 'services/settings_service.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize settings
  final settings = SettingsService();
  await settings.init();

  // Get available cameras
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error initializing cameras: $e');
  }

  runApp(TreeCalApp(settings: settings));
}

class TreeCalApp extends StatelessWidget {
  final SettingsService settings;

  const TreeCalApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => MqttService()),
        ChangeNotifierProvider(create: (_) => CameraService()),
        ChangeNotifierProvider(create: (_) => CaptureService()),
        ChangeNotifierProvider(create: (_) => CalibrationService()),
      ],
      child: MaterialApp(
        title: 'TreeCal',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
