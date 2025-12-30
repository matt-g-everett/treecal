// Basic smoke test for TreeCal app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:treecal/services/settings_service.dart';
import 'package:treecal/services/mqtt_service.dart';
import 'package:treecal/services/camera_service.dart';
import 'package:treecal/services/capture_service.dart';
import 'package:treecal/services/calibration_service.dart';
import 'package:treecal/screens/home_screen.dart';

void main() {
  testWidgets('App loads home screen', (WidgetTester tester) async {
    // Create a test settings service (doesn't need SharedPreferences init for test)
    final settings = SettingsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(create: (_) => MqttService()),
          ChangeNotifierProvider(create: (_) => CameraService()),
          ChangeNotifierProvider(create: (_) => CaptureService()),
          ChangeNotifierProvider(create: (_) => CalibrationService()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Verify the app title is shown
    expect(find.text('LED Position Mapper'), findsOneWidget);

    // Verify MQTT status card is shown
    expect(find.text('MQTT Connection'), findsOneWidget);

    // Verify Camera status card is shown
    expect(find.text('Camera'), findsOneWidget);
  });
}
