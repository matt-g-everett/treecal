import 'package:flutter/material.dart';
import 'package:ditredi/ditredi.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// LED position data point for 3D plotting
class LEDPoint {
  final int index;
  final double x;
  final double y;
  final double z;
  final bool predicted;
  final double confidence;

  LEDPoint({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.predicted,
    required this.confidence,
  });
}

/// 3D Visualization Screen using ditredi (MIT License)
class LEDVisualizationScreen extends StatefulWidget {
  final String? jsonPath;

  const LEDVisualizationScreen({super.key, this.jsonPath});

  @override
  State<LEDVisualizationScreen> createState() => _LEDVisualizationScreenState();
}

class _LEDVisualizationScreenState extends State<LEDVisualizationScreen> {
  List<LEDPoint> _observed = [];
  List<LEDPoint> _predicted = [];
  Map<String, dynamic>? _metadata;
  bool _loading = true;
  String? _error;

  late DiTreDiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DiTreDiController();
    _loadData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      String jsonPath = widget.jsonPath ?? await _getDefaultJsonPath();

      final file = File(jsonPath);
      if (!await file.exists()) {
        throw Exception('LED positions file not found at: $jsonPath');
      }

      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString);

      final positions = data['positions'] as List;

      final observed = <LEDPoint>[];
      final predicted = <LEDPoint>[];

      for (final pos in positions) {
        final point = LEDPoint(
          index: pos['led_index'] as int,
          x: (pos['x'] as num).toDouble(),
          y: (pos['y'] as num).toDouble(),
          z: (pos['z'] as num).toDouble(),
          predicted: pos['predicted'] as bool? ?? false,
          confidence: (pos['confidence'] as num).toDouble(),
        );

        if (point.predicted) {
          predicted.add(point);
        } else {
          observed.add(point);
        }
      }

      setState(() {
        _observed = observed;
        _predicted = predicted;
        _metadata = {
          'total_leds': data['total_leds'],
          'tree_height': data['tree_height'],
          'num_observed': data['num_observed'],
          'num_predicted': data['num_predicted'],
        };
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<String> _getDefaultJsonPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, 'led_captures', 'led_positions.json');
  }

  List<Model3D<Model3D<dynamic>>> _buildScene() {
    final figures = <Model3D<Model3D<dynamic>>>[];

    // Add observed LED points (blue)
    for (final point in _observed) {
      figures.add(
        Point3D(
          vm.Vector3(point.x, point.z, point.y), // Y and Z swapped for display
          color: Colors.blue,
          width: 4.0,
        ),
      );
    }

    // Add predicted LED points (red)
    for (final point in _predicted) {
      figures.add(
        Point3D(
          vm.Vector3(point.x, point.z, point.y), // Y and Z swapped for display
          color: Colors.red.shade300,
          width: 3.0,
        ),
      );
    }

    // Add axes for reference
    // X axis (red)
    figures.add(Line3D(
      vm.Vector3(0, 0, 0),
      vm.Vector3(0.5, 0, 0),
      color: Colors.red,
      width: 2.0,
    ));
    // Y axis (green) - mapped to Z in our coordinate system
    figures.add(Line3D(
      vm.Vector3(0, 0, 0),
      vm.Vector3(0, 0, 0.5),
      color: Colors.green,
      width: 2.0,
    ));
    // Z axis (cyan) - mapped to Y (height)
    figures.add(Line3D(
      vm.Vector3(0, 0, 0),
      vm.Vector3(0, 0.5, 0),
      color: Colors.cyan,
      width: 2.0,
    ));

    // Add ground plane grid
    const gridSize = 1.0;
    const gridStep = 0.25;
    for (double i = -gridSize; i <= gridSize; i += gridStep) {
      // Lines parallel to X
      figures.add(Line3D(
        vm.Vector3(i, 0, -gridSize),
        vm.Vector3(i, 0, gridSize),
        color: Colors.white.withValues(alpha: 0.2),
        width: 1.0,
      ));
      // Lines parallel to Z (Y in world)
      figures.add(Line3D(
        vm.Vector3(-gridSize, 0, i),
        vm.Vector3(gridSize, 0, i),
        color: Colors.white.withValues(alpha: 0.2),
        width: 1.0,
      ));
    }

    return figures;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D LED Visualization'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset View',
            onPressed: () {
              _controller.update(rotationX: -30, rotationY: 30, userScale: 1.0);
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Statistics',
            onPressed: _metadata != null ? _showStatistics : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading visualization...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading visualization',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Info banner
                    if (_metadata != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.blue.shade900,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildInfoChip(
                              'Total',
                              '${_metadata!['total_leds']}',
                              Icons.scatter_plot,
                            ),
                            _buildInfoChip(
                              'Observed',
                              '${_metadata!['num_observed']}',
                              Icons.check_circle,
                              color: Colors.blue,
                            ),
                            _buildInfoChip(
                              'Predicted',
                              '${_metadata!['num_predicted']}',
                              Icons.auto_fix_high,
                              color: Colors.red,
                            ),
                          ],
                        ),
                      ),

                    // 3D Viewport with gesture support
                    Expanded(
                      child: Container(
                        color: Colors.black,
                        child: DiTreDiDraggable(
                          controller: _controller,
                          child: DiTreDi(
                            figures: _buildScene(),
                            controller: _controller,
                            config: const DiTreDiConfig(
                              defaultPointWidth: 4.0,
                              defaultLineWidth: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Controls hint & Legend
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.grey.shade900,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildLegendItem('Observed', Colors.blue),
                              const SizedBox(width: 24),
                              _buildLegendItem('Predicted', Colors.red.shade300),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Drag to rotate • Pinch to zoom',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildInfoChip(String label, String value, IconData icon,
      {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color ?? Colors.white),
        const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }

  void _showStatistics() {
    if (_metadata == null) return;

    final allPoints = [..._observed, ..._predicted];
    final confidences = _observed.map((p) => p.confidence).toList();

    final avgConfidence = confidences.isEmpty
        ? 0.0
        : confidences.reduce((a, b) => a + b) / confidences.length;

    final highConf = confidences.where((c) => c > 0.8).length;

    final minX = allPoints.map((p) => p.x).reduce((a, b) => a < b ? a : b);
    final maxX = allPoints.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final minY = allPoints.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxY = allPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final minZ = allPoints.map((p) => p.z).reduce((a, b) => a < b ? a : b);
    final maxZ = allPoints.map((p) => p.z).reduce((a, b) => a > b ? a : b);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('LED Position Statistics'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total LEDs: ${_metadata!['total_leds']}'),
              Text(
                  'Tree Height: ${(_metadata!['tree_height'] as num).toStringAsFixed(2)}m'),
              const Divider(),
              Text('Observed: ${_metadata!['num_observed']} '
                  '(${(100 * (_metadata!['num_observed'] as num) / (_metadata!['total_leds'] as num)).toStringAsFixed(1)}%)'),
              Text('Predicted: ${_metadata!['num_predicted']} '
                  '(${(100 * (_metadata!['num_predicted'] as num) / (_metadata!['total_leds'] as num)).toStringAsFixed(1)}%)'),
              const Divider(),
              const Text(
                'Confidence (observed):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('  Mean: ${avgConfidence.toStringAsFixed(3)}'),
              if (confidences.isNotEmpty) ...[
                Text(
                    '  Min: ${confidences.reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}'),
                Text(
                    '  Max: ${confidences.reduce((a, b) => a > b ? a : b).toStringAsFixed(3)}'),
                Text('  High (>0.8): $highConf '
                    '(${(100 * highConf / confidences.length).toStringAsFixed(1)}%)'),
              ],
              const Divider(),
              const Text(
                'Spatial Distribution:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                  '  X: [${minX.toStringAsFixed(3)}, ${maxX.toStringAsFixed(3)}]m'),
              Text(
                  '  Y: [${minY.toStringAsFixed(3)}, ${maxY.toStringAsFixed(3)}]m'),
              Text(
                  '  Z: [${minZ.toStringAsFixed(3)}, ${maxZ.toStringAsFixed(3)}]m'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
