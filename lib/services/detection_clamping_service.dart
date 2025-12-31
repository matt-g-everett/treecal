import 'dart:math' as math;
import '../screens/cone_calibration_overlay.dart' show ConeParameters;

/// Result of clamping a detection to cone bounds
class ClampedDetection {
  final double x;
  final double y;
  final bool wasClamped;
  final String clampReason;

  ClampedDetection({
    required this.x,
    required this.y,
    required this.wasClamped,
    this.clampReason = '',
  });
}

/// Service to clamp out-of-bounds LED detections to the cone surface.
///
/// When the user fits the cone overlay close to the tree lights, some LEDs
/// may be detected slightly outside the cone bounds. Rather than discarding
/// these detections, we clamp them to the nearest valid point on the cone.
///
/// Clamping rules:
/// 1. Horizontal clamping: Rays left/right of cone are pulled to the edges
///    at the appropriate height (accounting for cone taper)
/// 2. Below-base clamping: Front surface rays clamp to bottom of base oval,
///    back surface rays clamp to top of base oval
/// 3. Above-apex clamping: Rays above tree clamp to apex point (centerline)
class DetectionClampingService {
  /// Clamp a detection point to the cone bounds.
  ///
  /// [x], [y]: Detection coordinates in image space
  /// [imageWidth]: Width of the image
  /// [coneParams]: Cone overlay parameters
  /// [isFrontSurface]: Whether this is a front or back surface candidate
  ///                   (affects below-base clamping behavior)
  ///
  /// Returns clamped coordinates and whether clamping occurred.
  static ClampedDetection clampToCone({
    required double x,
    required double y,
    required double imageWidth,
    required ConeParameters coneParams,
    bool isFrontSurface = true,
  }) {
    final centerX = imageWidth / 2;
    double clampedX = x;
    double clampedY = y;
    bool wasClamped = false;
    String reason = '';

    // === VERTICAL CLAMPING FIRST ===

    // Above apex: clamp to apex height and centerline
    if (y < coneParams.apexY) {
      clampedY = coneParams.apexY;
      clampedX = centerX; // Apex is at centerline
      wasClamped = true;
      reason = 'above apex';
    }
    // At or below baseY: clamp vertically to oval arc
    // This handles both "below oval" and "inside oval" cases uniformly
    else if (y >= coneParams.baseY - coneParams.baseHeight / 2) {
      final baseRadiusX = coneParams.baseWidth / 2;   // Horizontal radius (a)
      final baseRadiusY = coneParams.baseHeight / 2;  // Vertical radius (b)
      final distFromCenter = clampedX - centerX;

      // Check if we're outside the oval horizontally (zones 6 and 8)
      if (distFromCenter.abs() > baseRadiusX) {
        // Clamp to leftmost/rightmost point of oval (at baseY, the oval center)
        clampedX = centerX + baseRadiusX * distFromCenter.sign;
        clampedY = coneParams.baseY;
        reason = 'outside oval width';
      } else {
        // Within oval width - clamp vertically to oval arc
        // Find Y on the oval for this X: (x/a)² + (y/b)² = 1
        // y = b * sqrt(1 - (x/a)²)
        final normalizedX = distFromCenter / baseRadiusX;
        final ovalYOffset = baseRadiusY * math.sqrt(1 - normalizedX * normalizedX);

        if (isFrontSurface) {
          // Front surface: clamp to bottom arc of oval
          clampedY = coneParams.baseY + ovalYOffset;
        } else {
          // Back surface: clamp to top arc of oval
          clampedY = coneParams.baseY - ovalYOffset;
        }
        reason = 'oval (${isFrontSurface ? "front" : "back"})';
      }

      wasClamped = true;
    }

    // === HORIZONTAL CLAMPING ===
    // Only if we're within the vertical bounds of the cone

    if (clampedY >= coneParams.apexY && clampedY <= coneParams.baseY) {
      // Calculate expected cone radius at this height
      final expectedRadius = coneParams.radiusAtPixelY(clampedY);
      final distFromCenter = clampedX - centerX;

      // If outside cone bounds horizontally, clamp to edge
      if (distFromCenter.abs() > expectedRadius) {
        clampedX = centerX + expectedRadius * distFromCenter.sign;
        if (!wasClamped) {
          wasClamped = true;
          reason = 'outside cone edge';
        }
      }
    }

    return ClampedDetection(
      x: clampedX,
      y: clampedY,
      wasClamped: wasClamped,
      clampReason: reason,
    );
  }

  /// Clamp detection for triangulation with front/back determination.
  ///
  /// Returns two clamped positions: one for front surface candidate,
  /// one for back surface candidate.
  static (ClampedDetection front, ClampedDetection back) clampForTriangulation({
    required double x,
    required double y,
    required double imageWidth,
    required ConeParameters coneParams,
  }) {
    final front = clampToCone(
      x: x,
      y: y,
      imageWidth: imageWidth,
      coneParams: coneParams,
      isFrontSurface: true,
    );

    final back = clampToCone(
      x: x,
      y: y,
      imageWidth: imageWidth,
      coneParams: coneParams,
      isFrontSurface: false,
    );

    return (front, back);
  }

  /// Check if a point is inside the cone bounds (no clamping needed).
  static bool isInsideCone({
    required double x,
    required double y,
    required double imageWidth,
    required ConeParameters coneParams,
  }) {
    // Check vertical bounds
    if (y < coneParams.apexY || y > coneParams.baseY) {
      return false;
    }

    // Check horizontal bounds at this height
    final centerX = imageWidth / 2;
    final expectedRadius = coneParams.radiusAtPixelY(y);
    final distFromCenter = (x - centerX).abs();

    return distFromCenter <= expectedRadius;
  }

  /// Calculate how far outside the cone a point is (for confidence adjustment).
  /// Returns 0 if inside, positive value representing pixel distance if outside.
  static double distanceOutsideCone({
    required double x,
    required double y,
    required double imageWidth,
    required ConeParameters coneParams,
  }) {
    final centerX = imageWidth / 2;
    double maxDistance = 0;

    // Vertical distance above apex
    if (y < coneParams.apexY) {
      final verticalDist = coneParams.apexY - y;
      final horizontalDist = (x - centerX).abs();
      maxDistance = math.sqrt(verticalDist * verticalDist + horizontalDist * horizontalDist);
    }
    // Vertical distance below base
    else if (y > coneParams.baseY) {
      final verticalDist = y - coneParams.baseY;
      final baseRadius = coneParams.baseWidth / 2;
      final horizontalDist = math.max(0.0, (x - centerX).abs() - baseRadius);
      maxDistance = math.sqrt(verticalDist * verticalDist + horizontalDist * horizontalDist);
    }
    // Within vertical bounds - check horizontal
    else {
      final expectedRadius = coneParams.radiusAtPixelY(y);
      final distFromCenter = (x - centerX).abs();
      if (distFromCenter > expectedRadius) {
        maxDistance = distFromCenter - expectedRadius;
      }
    }

    return maxDistance;
  }
}
