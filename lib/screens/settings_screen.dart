import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _brokerController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _totalLedsController;
  late TextEditingController _cameraAdjustController;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsService>(context, listen: false);

    _brokerController = TextEditingController(text: settings.brokerAddress);
    _portController = TextEditingController(text: settings.brokerPort.toString());
    _usernameController = TextEditingController(text: settings.username);
    _passwordController = TextEditingController(text: settings.password);
    _totalLedsController = TextEditingController(text: settings.totalLeds.toString());
    _cameraAdjustController = TextEditingController(text: settings.cameraAdjustmentDelay.toString());
  }

  @override
  void dispose() {
    _brokerController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _totalLedsController.dispose();
    _cameraAdjustController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final settings = Provider.of<SettingsService>(context, listen: false);

      await settings.saveAll(
        brokerAddress: _brokerController.text,
        brokerPort: int.parse(_portController.text),
        username: _usernameController.text,
        password: _passwordController.text,
        totalLeds: int.parse(_totalLedsController.text),
        cameraAdjustmentDelay: int.parse(_cameraAdjustController.text),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // MQTT Settings
            Text(
              'MQTT Configuration',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _brokerController,
              decoration: const InputDecoration(
                labelText: 'Broker Address',
                hintText: '192.168.5.210',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value!.isEmpty ? 'Please enter broker address' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '1883',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) =>
                  value!.isEmpty ? 'Please enter port' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password (optional)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),

            const SizedBox(height: 24),
            Text(
              'Capture Settings',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _totalLedsController,
              decoration: const InputDecoration(
                labelText: 'Total LEDs',
                hintText: '500',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value!.isEmpty) return 'Please enter total LEDs';
                final num = int.tryParse(value);
                if (num == null || num <= 0) {
                  return 'Please enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _cameraAdjustController,
              decoration: const InputDecoration(
                labelText: 'Camera Exposure Delay (ms)',
                hintText: '1000',
                helperText: 'Time for camera to adjust when lighting changes',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value!.isEmpty) return 'Please enter delay';
                final num = int.tryParse(value);
                if (num == null || num < 0) {
                  return 'Please enter a valid number';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}
