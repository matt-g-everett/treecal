import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyBrokerAddress = 'mqtt_broker_address';
  static const String _keyBrokerPort = 'mqtt_broker_port';
  static const String _keyUsername = 'mqtt_username';
  static const String _keyPassword = 'mqtt_password';
  static const String _keyTotalLeds = 'total_leds';
  static const String _keyCameraAdjustmentDelay = 'camera_adjustment_delay';
  static const String _keyConeBaseWidth = 'cone_base_width';
  static const String _keyConeBaseHeight = 'cone_base_height';

  SharedPreferences? _prefs;

  // Default values
  static const String defaultBrokerAddress = '192.168.1.100';
  static const int defaultBrokerPort = 1883;
  static const int defaultTotalLeds = 500;
  static const int defaultCameraAdjustmentDelay = 1000;
  static const double defaultConeBaseWidth = 0.0; // 0 means use screen-relative default
  static const double defaultConeBaseHeight = 0.0;

  // Cached values
  String _brokerAddress = defaultBrokerAddress;
  int _brokerPort = defaultBrokerPort;
  String _username = '';
  String _password = '';
  int _totalLeds = defaultTotalLeds;
  int _cameraAdjustmentDelay = defaultCameraAdjustmentDelay;
  double _coneBaseWidth = defaultConeBaseWidth;
  double _coneBaseHeight = defaultConeBaseHeight;

  // Getters
  String get brokerAddress => _brokerAddress;
  int get brokerPort => _brokerPort;
  String get username => _username;
  String get password => _password;
  int get totalLeds => _totalLeds;
  int get cameraAdjustmentDelay => _cameraAdjustmentDelay;
  double get coneBaseWidth => _coneBaseWidth;
  double get coneBaseHeight => _coneBaseHeight;

  /// Initialize the settings service. Must be called before using.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSettings();
  }

  void _loadSettings() {
    if (_prefs == null) return;

    _brokerAddress = _prefs!.getString(_keyBrokerAddress) ?? defaultBrokerAddress;
    _brokerPort = _prefs!.getInt(_keyBrokerPort) ?? defaultBrokerPort;
    _username = _prefs!.getString(_keyUsername) ?? '';
    _password = _prefs!.getString(_keyPassword) ?? '';
    _totalLeds = _prefs!.getInt(_keyTotalLeds) ?? defaultTotalLeds;
    _cameraAdjustmentDelay = _prefs!.getInt(_keyCameraAdjustmentDelay) ?? defaultCameraAdjustmentDelay;
    _coneBaseWidth = _prefs!.getDouble(_keyConeBaseWidth) ?? defaultConeBaseWidth;
    _coneBaseHeight = _prefs!.getDouble(_keyConeBaseHeight) ?? defaultConeBaseHeight;

    notifyListeners();
  }

  // Setters (auto-save)
  Future<void> setBrokerAddress(String value) async {
    _brokerAddress = value;
    await _prefs?.setString(_keyBrokerAddress, value);
    notifyListeners();
  }

  Future<void> setBrokerPort(int value) async {
    _brokerPort = value;
    await _prefs?.setInt(_keyBrokerPort, value);
    notifyListeners();
  }

  Future<void> setUsername(String value) async {
    _username = value;
    await _prefs?.setString(_keyUsername, value);
    notifyListeners();
  }

  Future<void> setPassword(String value) async {
    _password = value;
    await _prefs?.setString(_keyPassword, value);
    notifyListeners();
  }

  Future<void> setTotalLeds(int value) async {
    _totalLeds = value;
    await _prefs?.setInt(_keyTotalLeds, value);
    notifyListeners();
  }

  Future<void> setCameraAdjustmentDelay(int value) async {
    _cameraAdjustmentDelay = value;
    await _prefs?.setInt(_keyCameraAdjustmentDelay, value);
    notifyListeners();
  }

  Future<void> setConeBaseWidth(double value) async {
    _coneBaseWidth = value;
    await _prefs?.setDouble(_keyConeBaseWidth, value);
    notifyListeners();
  }

  Future<void> setConeBaseHeight(double value) async {
    _coneBaseHeight = value;
    await _prefs?.setDouble(_keyConeBaseHeight, value);
    notifyListeners();
  }

  /// Save cone dimensions together
  Future<void> saveConeSettings(double width, double height) async {
    _coneBaseWidth = width;
    _coneBaseHeight = height;
    await _prefs?.setDouble(_keyConeBaseWidth, width);
    await _prefs?.setDouble(_keyConeBaseHeight, height);
    notifyListeners();
  }

  /// Save all settings at once (useful for settings screen)
  Future<void> saveAll({
    String? brokerAddress,
    int? brokerPort,
    String? username,
    String? password,
    int? totalLeds,
    int? cameraAdjustmentDelay,
  }) async {
    if (brokerAddress != null) {
      _brokerAddress = brokerAddress;
      await _prefs?.setString(_keyBrokerAddress, brokerAddress);
    }
    if (brokerPort != null) {
      _brokerPort = brokerPort;
      await _prefs?.setInt(_keyBrokerPort, brokerPort);
    }
    if (username != null) {
      _username = username;
      await _prefs?.setString(_keyUsername, username);
    }
    if (password != null) {
      _password = password;
      await _prefs?.setString(_keyPassword, password);
    }
    if (totalLeds != null) {
      _totalLeds = totalLeds;
      await _prefs?.setInt(_keyTotalLeds, totalLeds);
    }
    if (cameraAdjustmentDelay != null) {
      _cameraAdjustmentDelay = cameraAdjustmentDelay;
      await _prefs?.setInt(_keyCameraAdjustmentDelay, cameraAdjustmentDelay);
    }
    notifyListeners();
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    await _prefs?.clear();
    _brokerAddress = defaultBrokerAddress;
    _brokerPort = defaultBrokerPort;
    _username = '';
    _password = '';
    _totalLeds = defaultTotalLeds;
    _cameraAdjustmentDelay = defaultCameraAdjustmentDelay;
    _coneBaseWidth = defaultConeBaseWidth;
    _coneBaseHeight = defaultConeBaseHeight;
    notifyListeners();
  }
}
