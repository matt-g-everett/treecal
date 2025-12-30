import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'settings_service.dart';

class MqttService extends ChangeNotifier {
  MqttServerClient? _client;
  bool _isConnected = false;
  String _statusMessage = 'Disconnected';

  // Reference to settings (injected via configure)
  SettingsService? _settings;

  // Connection config (populated from settings before connect)
  String _brokerAddress = '';
  int _brokerPort = 1883;
  final String _clientId = 'treecal_${DateTime.now().millisecondsSinceEpoch}';
  String _username = '';
  String _password = '';

  // Topics for binary frame protocol
  static const String _streamTopic = 'home/xmastree/stream';
  static const String _ackTopic = 'home/xmastree/ack';

  // Ack handling
  final _ackController = StreamController<int>.broadcast();
  Stream<int> get ackStream => _ackController.stream;

  bool get isConnected => _isConnected;
  String get statusMessage => _statusMessage;

  /// Configure the service with settings. Call before connect().
  void configure(SettingsService settings) {
    _settings = settings;
    _brokerAddress = settings.brokerAddress;
    _brokerPort = settings.brokerPort;
    _username = settings.username;
    _password = settings.password;
  }

  /// Number of LEDs (from settings, or default)
  int get numPixels => _settings?.totalLeds ?? 500;

  Future<bool> connect() async {
    // Refresh from settings if available
    if (_settings != null) {
      _brokerAddress = _settings!.brokerAddress;
      _brokerPort = _settings!.brokerPort;
      _username = _settings!.username;
      _password = _settings!.password;
    }

    if (_brokerAddress.isEmpty) {
      _updateStatus('Error: Broker address not configured');
      return false;
    }

    try {
      _updateStatus('Connecting to $_brokerAddress:$_brokerPort...');

      _client = MqttServerClient.withPort(_brokerAddress, _clientId, _brokerPort);
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 60;
      _client!.connectTimeoutPeriod = 5000;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(_clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      if (_username.isNotEmpty) {
        connMessage.authenticateAs(_username, _password);
      }

      _client!.connectionMessage = connMessage;

      await _client!.connect();

      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        _updateStatus('Connected to $_brokerAddress');

        // Subscribe to ack topic
        _client!.subscribe(_ackTopic, MqttQos.atMostOnce);

        // Listen for ack messages
        _client!.updates!.listen(_onMessage);

        return true;
      } else {
        _isConnected = false;
        _updateStatus('Connection failed: ${_client!.connectionStatus}');
        return false;
      }
    } catch (e) {
      _isConnected = false;
      _updateStatus('Error: $e');
      return false;
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      if (message.topic == _ackTopic) {
        final payload = message.payload as MqttPublishMessage;
        final data = MqttPublishPayload.bytesToStringAsString(
          payload.payload.message,
        );

        // Parse ack JSON: {"type":"ack","ackID":123}
        final match = RegExp(r'"ackID"\s*:\s*(\d+)').firstMatch(data);
        if (match != null) {
          final ackId = int.parse(match.group(1)!);
          _ackController.add(ackId);
        }
      }
    }
  }

  void disconnect() {
    _client?.disconnect();
    _isConnected = false;
    _updateStatus('Disconnected');
  }

  /// Sends a frame of RGB pixel data to the LED strip.
  ///
  /// [pixels] - List of RGB values as (r, g, b) tuples
  /// [ackId] - Optional ack ID (1-255). If non-zero, ESP32 will send an ack
  ///           after displaying the frame. Use 0 for no acknowledgment.
  void sendFrame(List<(int r, int g, int b)> pixels, {int ackId = 0}) {
    if (!_isConnected || _client == null) {
      throw Exception('Not connected to MQTT broker');
    }

    final frame = _buildFrame(pixels, ackId);
    final builder = MqttClientPayloadBuilder();
    for (final byte in frame) {
      builder.addByte(byte);
    }

    _client!.publishMessage(
      _streamTopic,
      MqttQos.atMostOnce,
      builder.payload!,
    );
  }

  /// Sends a frame and waits for acknowledgment from the ESP32.
  ///
  /// Returns a Future that completes when the ack is received.
  /// Throws TimeoutException if ack is not received within [timeout].
  Future<void> sendFrameWithAck(
    List<(int r, int g, int b)> pixels,
    int ackId, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (ackId == 0) {
      throw ArgumentError('ackId must be non-zero for ack-based sending');
    }

    final completer = Completer<void>();
    StreamSubscription<int>? subscription;

    subscription = ackStream.listen((receivedAckId) {
      if (receivedAckId == ackId) {
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    sendFrame(pixels, ackId: ackId);

    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      subscription.cancel();
      rethrow;
    }
  }

  /// Builds a binary frame in the format expected by the ESP32.
  ///
  /// Frame format (packed struct):
  ///   - ackID: 1 byte (uint8)
  ///   - len: 2 bytes (uint16, little-endian)
  ///   - data: len * 3 bytes (RGB triplets)
  Uint8List _buildFrame(List<(int r, int g, int b)> pixels, int ackId) {
    final len = pixels.length;
    final frameSize = 1 + 2 + (len * 3); // ackID + len + RGB data
    final buffer = Uint8List(frameSize);
    final byteData = ByteData.view(buffer.buffer);

    // ackID (1 byte)
    buffer[0] = ackId & 0xFF;

    // len (2 bytes, little-endian)
    byteData.setUint16(1, len, Endian.little);

    // RGB data
    var offset = 3;
    for (final (r, g, b) in pixels) {
      buffer[offset++] = r & 0xFF;
      buffer[offset++] = g & 0xFF;
      buffer[offset++] = b & 0xFF;
    }

    return buffer;
  }

  /// Sets a single LED and waits for acknowledgment.
  Future<void> setLEDWithAck(
    int index,
    int r,
    int g,
    int b,
    int totalPixels,
    int ackId, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final pixels = List.generate(
      totalPixels,
      (i) => i == index ? (r, g, b) : (0, 0, 0),
    );
    await sendFrameWithAck(pixels, ackId, timeout: timeout);
  }

  // ============================================================
  // Convenience methods for simple on/off control
  // These use the binary frame protocol with numPixels from settings
  // ============================================================

  /// Turns off all LEDs (convenience method using numPixels from settings).
  Future<void> turnOffAllLEDs() async {
    final black = List.generate(numPixels, (_) => (0, 0, 0));
    sendFrame(black);
  }

  /// Turns on all LEDs to white (convenience method using numPixels from settings).
  Future<void> turnOnAllLEDs({int r = 255, int g = 255, int b = 255}) async {
    final color = List.generate(numPixels, (_) => (r, g, b));
    sendFrame(color);
  }

  /// Sets a single LED on or off (convenience method).
  ///
  /// When [on] is true, sets the LED to white (255, 255, 255).
  /// When [on] is false, turns off the LED (0, 0, 0).
  Future<void> setLED(int index, bool on, {int r = 255, int g = 255, int b = 255}) async {
    final pixels = List.generate(
      numPixels,
      (i) => i == index && on ? (r, g, b) : (0, 0, 0),
    );
    sendFrame(pixels);
  }

  /// Sets a single LED to a specific RGB color (convenience method).
  Future<void> setLEDColor(int index, int r, int g, int b) async {
    final pixels = List.generate(
      numPixels,
      (i) => i == index ? (r, g, b) : (0, 0, 0),
    );
    sendFrame(pixels);
  }

  void _updateStatus(String status) {
    _statusMessage = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _ackController.close();
    disconnect();
    super.dispose();
  }
}
