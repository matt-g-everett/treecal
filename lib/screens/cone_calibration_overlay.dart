import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../services/settings_service.dart';

class ConeCalibrationOverlay extends StatefulWidget {
  final Size previewSize;
  final Function(ConeParameters) onParametersChanged;
  final SettingsService settings;
  final bool showControls;

  const ConeCalibrationOverlay({
    super.key,
    required this.previewSize,
    required this.onParametersChanged,
    required this.settings,
    this.showControls = true,
  });

  @override
  State<ConeCalibrationOverlay> createState() => _ConeCalibrationOverlayState();
}

class ConeParameters {
  final double apexY;          // Y position of apex (fixed)
  final double baseY;          // Y position of base (fixed)
  final double baseWidth;      // Width of base oval
  final double baseHeight;     // Height of base oval (perspective)
  
  ConeParameters({
    required this.apexY,
    required this.baseY,
    required this.baseWidth,
    required this.baseHeight,
  });
  
  double get treeHeightPixels => baseY - apexY;
  
  /// Convert pixel Y coordinate to normalized height (0-1)
  /// where 0 = base, 1 = apex
  double pixelYToNormalizedHeight(double pixelY) {
    if (treeHeightPixels == 0) return 0;
    return (baseY - pixelY) / treeHeightPixels;
  }
  
  /// Get expected radius at a given pixel Y position
  double radiusAtPixelY(double pixelY) {
    final h = pixelYToNormalizedHeight(pixelY);
    // Linear taper: r(h) = r_base * (1 - h)
    return (baseWidth / 2) * (1 - h);
  }
  
  Map<String, dynamic> toJson() => {
    'apex_y_pixels': apexY,
    'base_y_pixels': baseY,
    'base_width_pixels': baseWidth,
    'base_height_pixels': baseHeight,
    'tree_height_pixels': treeHeightPixels,
    'perspective_ratio': baseHeight / baseWidth,
  };
}

class _ConeCalibrationOverlayState extends State<ConeCalibrationOverlay> {
  // Fixed positions
  late double _apexY;
  late double _baseY;
  
  // Adjustable dimensions
  late double _baseWidth;   // Horizontal swipe
  late double _baseHeight;  // Vertical swipe (perspective correction)
  
  @override
  void initState() {
    super.initState();

    final screenHeight = widget.previewSize.height;
    final screenWidth = widget.previewSize.width;

    // Fixed cone height (fills most of screen)
    _apexY = screenHeight * 0.10;   // 10% from top
    _baseY = screenHeight * 0.90;   // 90% from top

    // Load saved dimensions or use defaults
    final savedWidth = widget.settings.coneBaseWidth;
    final savedHeight = widget.settings.coneBaseHeight;

    if (savedWidth > 0 && savedHeight > 0) {
      // Use saved dimensions
      _baseWidth = savedWidth.clamp(100.0, screenWidth * 0.95);
      _baseHeight = savedHeight.clamp(_baseWidth * 0.1, _baseWidth * 0.5);
    } else {
      // Initial oval dimensions (screen-relative defaults)
      _baseWidth = screenWidth * 0.6;          // 60% of screen width
      _baseHeight = _baseWidth * 0.25;         // 25% of width (typical perspective)
    }

    _notifyChange();
  }
  
  void _notifyChange() {
    widget.onParametersChanged(ConeParameters(
      apexY: _apexY,
      baseY: _baseY,
      baseWidth: _baseWidth,
      baseHeight: _baseHeight,
    ));
  }
  
  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      final delta = details.delta;

      // Vertical swipe: Adjust base oval HEIGHT (perspective)
      if (delta.dy.abs() > delta.dx.abs()) {
        _baseHeight = (_baseHeight + delta.dy).clamp(
          _baseWidth * 0.1,   // Min 10% of width (very flat)
          _baseWidth * 0.5,   // Max 50% of width (very round)
        );
      }
      // Horizontal swipe: Adjust base oval WIDTH
      else {
        _baseWidth = (_baseWidth + delta.dx * 2).clamp(
          100.0,  // Minimum width
          widget.previewSize.width * 0.95,  // Max 95% of screen
        );

        // Keep height proportional if it would exceed limits
        if (_baseHeight > _baseWidth * 0.5) {
          _baseHeight = _baseWidth * 0.5;
        } else if (_baseHeight < _baseWidth * 0.1) {
          _baseHeight = _baseWidth * 0.1;
        }
      }

      _notifyChange();
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    // Save dimensions when user finishes adjusting
    widget.settings.saveConeSettings(_baseWidth, _baseHeight);
  }
  
  void _reset() {
    setState(() {
      final screenWidth = widget.previewSize.width;
      _baseWidth = screenWidth * 0.6;
      _baseHeight = _baseWidth * 0.25;
      _notifyChange();
    });
    // Save reset dimensions
    widget.settings.saveConeSettings(_baseWidth, _baseHeight);
  }

  @override
  Widget build(BuildContext context) {
    final perspectiveRatio = _baseHeight / _baseWidth;

    // When not showing controls, just show the cone outline
    if (!widget.showControls) {
      return CustomPaint(
        size: widget.previewSize,
        painter: ConeOverlayPainter(
          apexY: _apexY,
          baseY: _baseY,
          baseWidth: _baseWidth,
          baseHeight: _baseHeight,
        ),
      );
    }

    return GestureDetector(
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: CustomPaint(
        size: widget.previewSize,
        painter: ConeOverlayPainter(
          apexY: _apexY,
          baseY: _baseY,
          baseWidth: _baseWidth,
          baseHeight: _baseHeight,
        ),
        child: Stack(
          children: [
            // Instructions overlay
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Align the cone to your tree',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 12),
                    Text(
                      '1. Move closer/farther to fit tree in cone',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.width_normal, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Swipe ↔ to match tree width',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.height, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Swipe ↕ to adjust perspective',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Reset button
            Positioned(
              top: 20,
              right: 20,
              child: FloatingActionButton(
                mini: true,
                onPressed: _reset,
                backgroundColor: Colors.white.withValues(alpha: 0.9),
                child: const Icon(Icons.refresh, color: Colors.black87),
              ),
            ),
            
            // Measurement display
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Cone Calibration',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Width: ${_baseWidth.toInt()}px',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'Height: ${_baseHeight.toInt()}px',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'Perspective: ${(perspectiveRatio * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConeOverlayPainter extends CustomPainter {
  final double apexY;
  final double baseY;
  final double baseWidth;
  final double baseHeight;
  
  ConeOverlayPainter({
    required this.apexY,
    required this.baseY,
    required this.baseWidth,
    required this.baseHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    
    // Semi-transparent fill
    final fillPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    
    // Bright outline
    final outlinePaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    // Apex marker
    final apexPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
    
    final apexOutlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    // Draw cone fill
    final path = Path();
    path.moveTo(centerX, apexY);  // Start at apex
    
    // Left edge
    path.lineTo(centerX - baseWidth / 2, baseY);
    
    // Base oval (bottom arc)
    path.addArc(
      Rect.fromCenter(
        center: Offset(centerX, baseY),
        width: baseWidth,
        height: baseHeight,
      ),
      math.pi,     // Start at left (180°)
      math.pi,     // Sweep to right (180°)
    );
    
    // Right edge back to apex
    path.lineTo(centerX, apexY);
    
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, outlinePaint);
    
    // Draw full base oval for clarity
    final ovalRect = Rect.fromCenter(
      center: Offset(centerX, baseY),
      width: baseWidth,
      height: baseHeight,
    );
    canvas.drawOval(ovalRect, outlinePaint);
    
    // Draw apex star
    _drawStar(canvas, Offset(centerX, apexY), 8.0, apexPaint, apexOutlinePaint);
    
    // Draw center vertical line (for symmetry reference)
    final centerLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    
    canvas.drawLine(
      Offset(centerX, apexY),
      Offset(centerX, baseY),
      centerLinePaint,
    );
    
    // Draw guide text on apex
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '★ APEX',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(centerX + 15, apexY - 6),
    );
    
    // Draw guide text on base
    final baseTextPainter = TextPainter(
      text: const TextSpan(
        text: 'BASE',
        style: TextStyle(
          color: Colors.green,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    baseTextPainter.layout();
    baseTextPainter.paint(
      canvas,
      Offset(centerX - baseTextPainter.width / 2, baseY + baseHeight / 2 + 5),
    );
  }
  
  void _drawStar(Canvas canvas, Offset center, double radius, Paint fillPaint, Paint outlinePaint) {
    final path = Path();
    const numPoints = 5;
    final outerRadius = radius;
    final innerRadius = radius * 0.4;
    
    for (int i = 0; i < numPoints * 2; i++) {
      final angle = (i * math.pi / numPoints) - math.pi / 2;
      final r = i.isEven ? outerRadius : innerRadius;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(ConeOverlayPainter oldDelegate) {
    return oldDelegate.apexY != apexY ||
           oldDelegate.baseY != baseY ||
           oldDelegate.baseWidth != baseWidth ||
           oldDelegate.baseHeight != baseHeight;
  }
}
