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
  final double sourceWidth;    // Width of coordinate system these values are in
  final double sourceHeight;   // Height of coordinate system these values are in

  ConeParameters({
    required this.apexY,
    required this.baseY,
    required this.baseWidth,
    required this.baseHeight,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
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

  /// Scale cone parameters to a different image size.
  /// Used to convert from preview coordinates to camera image coordinates.
  ConeParameters scaledTo(double targetWidth, double targetHeight) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      // No source dimensions - can't scale, return as-is
      return this;
    }

    final scaleX = targetWidth / sourceWidth;
    final scaleY = targetHeight / sourceHeight;

    return ConeParameters(
      apexY: apexY * scaleY,
      baseY: baseY * scaleY,
      baseWidth: baseWidth * scaleX,
      baseHeight: baseHeight * scaleY,
      sourceWidth: targetWidth,
      sourceHeight: targetHeight,
    );
  }

  /// Scale and rotate cone parameters for camera image coordinates.
  /// Handles the rotation between portrait preview and landscape camera sensor.
  ///
  /// [sensorOrientation]: Camera sensor rotation in degrees (0, 90, 180, 270)
  /// [targetWidth], [targetHeight]: Camera image dimensions (pre-rotation)
  ConeParameters scaledToWithRotation(
    double targetWidth,
    double targetHeight,
    int sensorOrientation,
  ) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return this;
    }

    // For 90° rotation: preview Y → camera X, preview X → camera (height - Y)
    // The cone apex (top of preview) maps to the right side of the landscape image
    // The cone base (bottom of preview) maps to the left side
    //
    // Preview coordinate system (portrait):
    //   - Origin at top-left
    //   - Y increases downward (apex at small Y, base at large Y)
    //   - X increases rightward
    //
    // Camera coordinate system (landscape, 90° sensor):
    //   - Origin at top-left of landscape image
    //   - What appears at top of preview is at RIGHT of camera image
    //   - Camera X = preview Y scaled
    //   - Camera Y = (sourceWidth - preview X) scaled

    switch (sensorOrientation) {
      case 90:
        // Preview is portrait, camera is landscape rotated 90° clockwise
        // Preview Y (vertical) → Camera X (horizontal)
        // Preview X (horizontal) → Camera Y (vertical, inverted)
        //
        // When phone is portrait and sensor is 90°:
        // - Top of preview = right edge of raw camera image
        // - Bottom of preview = left edge of raw camera image
        //
        // So: preview Y=0 (top) → camera X = targetWidth (right edge)
        //     preview Y=sourceHeight (bottom) → camera X = 0 (left edge)
        //
        // Camera X = targetWidth - (preview_Y / sourceHeight * targetWidth)
        //          = targetWidth * (1 - preview_Y / sourceHeight)

        final apexX = targetWidth - (apexY / sourceHeight * targetWidth);
        final baseX = targetWidth - (baseY / sourceHeight * targetWidth);

        // Tree height in camera coordinates (horizontal span)
        final treeWidthInCamera = (baseX - apexX).abs();

        // Base width in preview (horizontal) becomes base height in camera (vertical)
        final baseHeightInCamera = baseWidth / sourceWidth * targetHeight;

        return ConeParameters(
          apexY: apexX,  // Note: naming is confusing but we're reusing the structure
          baseY: baseX,  // apexY now means "apex X in camera coords"
          baseWidth: treeWidthInCamera,  // The "width" of tree in camera = horizontal span
          baseHeight: baseHeightInCamera,
          sourceWidth: targetWidth,
          sourceHeight: targetHeight,
        );

      case 270:
        // Opposite rotation
        final apexX270 = apexY / sourceHeight * targetWidth;
        final baseX270 = baseY / sourceHeight * targetWidth;
        final treeWidthInCamera270 = (baseX270 - apexX270).abs();
        final baseHeightInCamera270 = baseWidth / sourceWidth * targetHeight;

        return ConeParameters(
          apexY: apexX270,
          baseY: baseX270,
          baseWidth: treeWidthInCamera270,
          baseHeight: baseHeightInCamera270,
          sourceWidth: targetWidth,
          sourceHeight: targetHeight,
        );

      case 180:
        // Upside down - just invert Y
        final scaleX = targetWidth / sourceWidth;
        final scaleY = targetHeight / sourceHeight;
        return ConeParameters(
          apexY: targetHeight - (apexY * scaleY),
          baseY: targetHeight - (baseY * scaleY),
          baseWidth: baseWidth * scaleX,
          baseHeight: baseHeight * scaleY,
          sourceWidth: targetWidth,
          sourceHeight: targetHeight,
        );

      default:
        // 0° - no rotation, just scale
        return scaledTo(targetWidth, targetHeight);
    }
  }

  Map<String, dynamic> toJson() => {
    'apex_y_pixels': apexY,
    'base_y_pixels': baseY,
    'base_width_pixels': baseWidth,
    'base_height_pixels': baseHeight,
    'tree_height_pixels': treeHeightPixels,
    'perspective_ratio': baseHeight / baseWidth,
    'source_width': sourceWidth,
    'source_height': sourceHeight,
  };
}

class _ConeCalibrationOverlayState extends State<ConeCalibrationOverlay> {
  // Fixed positions - user moves phone to align tree with these
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
    _baseY = screenHeight * 0.85;   // 85% from top (leaves margin at bottom)

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

    // Defer initial callback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyChange();
    });
  }
  
  void _notifyChange() {
    widget.onParametersChanged(ConeParameters(
      apexY: _apexY,
      baseY: _baseY,
      baseWidth: _baseWidth,
      baseHeight: _baseHeight,
      sourceWidth: widget.previewSize.width,
      sourceHeight: widget.previewSize.height,
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
