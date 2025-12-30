import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/calibration_service.dart';
import 'dart:math' as math;

class CalibrationScreen extends StatefulWidget {
  final int positionNumber;
  
  const CalibrationScreen({
    super.key,
    required this.positionNumber,
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  late TextEditingController _distanceController;
  late TextEditingController _angleController;
  late TextEditingController _heightController;
  late TextEditingController _notesController;
  
  @override
  void initState() {
    super.initState();
    
    final calibService = Provider.of<CalibrationService>(context, listen: false);
    final existing = calibService.getCalibration(widget.positionNumber);
    
    _distanceController = TextEditingController(
      text: existing?.distanceFromCenter.toString() ?? '1.5'
    );
    _angleController = TextEditingController(
      text: existing?.angleFromFront.toString() ?? '0'
    );
    _heightController = TextEditingController(
      text: existing?.heightFromGround.toString() ?? '1.0'
    );
    _notesController = TextEditingController(
      text: existing?.notes ?? ''
    );
  }
  
  @override
  void dispose() {
    _distanceController.dispose();
    _angleController.dispose();
    _heightController.dispose();
    _notesController.dispose();
    super.dispose();
  }
  
  void _saveCalibration() {
    final calibService = Provider.of<CalibrationService>(context, listen: false);
    
    final calibration = CameraCalibration(
      positionNumber: widget.positionNumber,
      distanceFromCenter: double.tryParse(_distanceController.text) ?? 1.5,
      angleFromFront: double.tryParse(_angleController.text) ?? 0.0,
      heightFromGround: double.tryParse(_heightController.text) ?? 1.0,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );
    
    calibService.setCalibration(widget.positionNumber, calibration);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calibration saved')),
    );
    
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final angle = double.tryParse(_angleController.text) ?? 0.0;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Calibrate Position ${widget.positionNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveCalibration,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Visual Guide
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Camera Position',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: CustomPaint(
                      painter: TreeDiagramPainter(
                        cameraAngle: angle,
                        cameraDistance: double.tryParse(_distanceController.text) ?? 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Measurement Instructions
          Card(
            color: Colors.blue.shade900.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to Measure',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InstructionItem(
                    icon: Icons.straighten,
                    text: 'Distance: Measure from tree center to phone',
                  ),
                  _InstructionItem(
                    icon: Icons.explore,
                    text: 'Angle: 0° = front, 90° = right side, 180° = back',
                  ),
                  _InstructionItem(
                    icon: Icons.height,
                    text: 'Height: Measure camera lens height from ground',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Distance Input
          TextField(
            controller: _distanceController,
            decoration: InputDecoration(
              labelText: 'Distance from Tree Center (meters)',
              hintText: '1.5',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showTip(
                  'Distance Measurement',
                  'Measure from the center of your tree to where your phone is positioned. About 1.5-2 meters works well.',
                ),
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          
          const SizedBox(height: 16),
          
          // Angle Input with Quick Buttons
          TextField(
            controller: _angleController,
            decoration: const InputDecoration(
              labelText: 'Angle from Front (degrees)',
              hintText: '0',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          
          const SizedBox(height: 8),
          
          // Quick angle buttons
          Wrap(
            spacing: 8,
            children: [
              _QuickAngleButton(
                label: 'Front (0°)',
                angle: 0,
                controller: _angleController,
                onChanged: () => setState(() {}),
              ),
              _QuickAngleButton(
                label: 'Right (90°)',
                angle: 90,
                controller: _angleController,
                onChanged: () => setState(() {}),
              ),
              _QuickAngleButton(
                label: 'Back (180°)',
                angle: 180,
                controller: _angleController,
                onChanged: () => setState(() {}),
              ),
              _QuickAngleButton(
                label: 'Left (270°)',
                angle: 270,
                controller: _angleController,
                onChanged: () => setState(() {}),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Height Input
          TextField(
            controller: _heightController,
            decoration: InputDecoration(
              labelText: 'Camera Height from Ground (meters)',
              hintText: '1.0',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showTip(
                  'Height Measurement',
                  'Measure from ground to camera lens. Mid-height of tree (around 1.0m) usually works best.',
                ),
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          
          const SizedBox(height: 16),
          
          // Notes
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g., "Near the window"',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          
          const SizedBox(height: 24),
          
          // Save Button
          ElevatedButton.icon(
            onPressed: _saveCalibration,
            icon: const Icon(Icons.save),
            label: const Text('Save Calibration'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showTip(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _InstructionItem extends StatelessWidget {
  final IconData icon;
  final String text;
  
  const _InstructionItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _QuickAngleButton extends StatelessWidget {
  final String label;
  final double angle;
  final TextEditingController controller;
  final VoidCallback onChanged;
  
  const _QuickAngleButton({
    required this.label,
    required this.angle,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        controller.text = angle.toString();
        onChanged();
      },
    );
  }
}

class TreeDiagramPainter extends CustomPainter {
  final double cameraAngle;
  final double cameraDistance;
  
  TreeDiagramPainter({
    required this.cameraAngle,
    required this.cameraDistance,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 4;
    
    // Draw tree (circle)
    final treePaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 20, treePaint);
    
    // Draw tree outline
    final treeOutlinePaint = Paint()
      ..color = Colors.green.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 20, treeOutlinePaint);
    
    // Draw cardinal directions
    final directionPaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    // Front indicator
    canvas.drawLine(
      center,
      center + Offset(0, -scale),
      directionPaint,
    );
    
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Front (0°)',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      center + Offset(-textPainter.width / 2, -scale - 20),
    );
    
    // Draw camera position
    final angleRad = (cameraAngle - 90) * math.pi / 180;
    final cameraPos = center + Offset(
      math.cos(angleRad) * cameraDistance * scale / 2,
      math.sin(angleRad) * cameraDistance * scale / 2,
    );
    
    // Camera to tree line
    final linePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(center, cameraPos, linePaint);
    
    // Camera icon
    final cameraPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(cameraPos, 12, cameraPaint);
    
    final cameraIconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(cameraPos, 6, cameraIconPaint);
    
    // Distance label
    final distanceText = TextPainter(
      text: TextSpan(
        text: '${cameraDistance.toStringAsFixed(1)}m',
        style: const TextStyle(color: Colors.blue, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    );
    distanceText.layout();
    final labelPos = center + (cameraPos - center) * 0.5;
    distanceText.paint(
      canvas,
      labelPos + const Offset(5, -15),
    );
    
    // Angle arc
    final arcPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    final arcRect = Rect.fromCircle(center: center, radius: 40);
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      angleRad + math.pi / 2,
      false,
      arcPaint,
    );
    
    // Angle label
    final angleText = TextPainter(
      text: TextSpan(
        text: '${cameraAngle.toStringAsFixed(0)}°',
        style: const TextStyle(color: Colors.orange, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    );
    angleText.layout();
    final angleTextPos = center + Offset(45, -5);
    angleText.paint(canvas, angleTextPos);
  }

  @override
  bool shouldRepaint(TreeDiagramPainter oldDelegate) {
    return oldDelegate.cameraAngle != cameraAngle ||
           oldDelegate.cameraDistance != cameraDistance;
  }
}
