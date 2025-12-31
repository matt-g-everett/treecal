import 'dart:isolate';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math' as math;
import '../screens/cone_calibration_overlay.dart' show ConeParameters;
import 'detection_clamping_service.dart';

/// Detected LED information
class DetectedLED {
  final double x;              // Original detection X
  final double y;              // Original detection Y
  final double clampedX;       // X clamped to cone bounds (for front surface)
  final double clampedY;       // Y clamped to cone bounds (for front surface)
  final double clampedBackX;   // X clamped to cone bounds (for back surface)
  final double clampedBackY;   // Y clamped to cone bounds (for back surface)
  final bool wasClamped;       // Whether clamping was applied
  final double brightness;
  final double area;
  final double detectionConfidence;  // Is this a real LED?
  final double angularConfidence;     // How accurate is the angle?
  final double normalizedHeight;
  final bool inConeBounds;

  DetectedLED({
    required this.x,
    required this.y,
    double? clampedX,
    double? clampedY,
    double? clampedBackX,
    double? clampedBackY,
    this.wasClamped = false,
    required this.brightness,
    required this.area,
    required this.detectionConfidence,
    required this.angularConfidence,
    required this.normalizedHeight,
    required this.inConeBounds,
  }) : clampedX = clampedX ?? x,
       clampedY = clampedY ?? y,
       clampedBackX = clampedBackX ?? x,
       clampedBackY = clampedBackY ?? y;

  /// Overall confidence for display (detection quality)
  double get displayConfidence => detectionConfidence;

  /// Weight for triangulation (combines detection + angular)
  double get triangulationWeight => detectionConfidence * angularConfidence;

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'clamped_x': clampedX,
    'clamped_y': clampedY,
    'clamped_back_x': clampedBackX,
    'clamped_back_y': clampedBackY,
    'was_clamped': wasClamped,
    'brightness': brightness,
    'area': area,
    'detection_confidence': detectionConfidence,
    'angular_confidence': angularConfidence,
    'normalized_height': normalizedHeight,
    'in_cone_bounds': inConeBounds,
  };
}

/// LED detection service using OpenCV
class LEDDetectionService {

  /// Detect LEDs in an image file
  /// Runs in isolate to avoid blocking UI
  static Future<List<DetectedLED>> detectLEDs({
    required String imagePath,
    ConeParameters? coneParams,
    int brightnessThreshold = 150,
    double minArea = 5.0,
    double maxArea = 100.0,
    double cameraFovDegrees = 60.0,      // Horizontal field of view
    double minAngularConfidence = 0.2,   // Confidence floor for edge detections
  }) async {
    final params = {
      'imagePath': imagePath,
      'coneParams': coneParams?.toJson(),
      'brightnessThreshold': brightnessThreshold,
      'minArea': minArea,
      'maxArea': maxArea,
      'cameraFovDegrees': cameraFovDegrees,
      'minAngularConfidence': minAngularConfidence,
    };

    return await Isolate.run(() => _detectLEDsFromFileIsolate(params));
  }

  /// Detect LEDs from BGR image bytes (no file I/O) - runs in isolate
  /// Much faster than detectLEDs() as it skips JPEG encode/decode and disk I/O
  /// If the image is pre-downscaled, pass originalWidth/originalHeight for coordinate scaling
  static Future<List<DetectedLED>> detectLEDsFromBGR({
    required Uint8List bgrBytes,
    required int width,
    required int height,
    int? originalWidth,    // Original pre-downscale width (for coordinate scaling)
    int? originalHeight,   // Original pre-downscale height
    ConeParameters? coneParams,
    int brightnessThreshold = 150,
    double minArea = 5.0,
    double maxArea = 100.0,
    double cameraFovDegrees = 60.0,
    double minAngularConfidence = 0.2,
  }) async {
    // Calculate scale factor if original dimensions provided
    final scaleFactor = (originalWidth != null && originalWidth > width)
        ? originalWidth / width
        : 1.0;

    final params = {
      'bgrBytes': bgrBytes,
      'width': width,
      'height': height,
      'originalWidth': originalWidth ?? width,
      'originalHeight': originalHeight ?? height,
      'appliedDownscale': scaleFactor,
      'coneParams': coneParams?.toJson(),
      'brightnessThreshold': brightnessThreshold,
      'minArea': minArea,
      'maxArea': maxArea,
      'cameraFovDegrees': cameraFovDegrees,
      'minAngularConfidence': minAngularConfidence,
    };

    return await Isolate.run(() => _detectLEDsFromBGRIsolate(params));
  }

  /// Detect LEDs from BGR image bytes SYNCHRONOUSLY (no isolate overhead)
  /// Use this when UI responsiveness is not critical (e.g., during capture with frozen preview)
  static List<DetectedLED> detectLEDsFromBGRSync({
    required Uint8List bgrBytes,
    required int width,
    required int height,
    int? originalWidth,
    int? originalHeight,
    ConeParameters? coneParams,
    int brightnessThreshold = 150,
    double minArea = 5.0,
    double maxArea = 100.0,
    double cameraFovDegrees = 60.0,
    double minAngularConfidence = 0.2,
  }) {
    // Calculate scale factor if original dimensions provided
    final scaleFactor = (originalWidth != null && originalWidth > width)
        ? originalWidth / width
        : 1.0;

    final params = {
      'bgrBytes': bgrBytes,
      'width': width,
      'height': height,
      'originalWidth': originalWidth ?? width,
      'originalHeight': originalHeight ?? height,
      'appliedDownscale': scaleFactor,
      'coneParams': coneParams?.toJson(),
      'brightnessThreshold': brightnessThreshold,
      'minArea': minArea,
      'maxArea': maxArea,
      'cameraFovDegrees': cameraFovDegrees,
      'minAngularConfidence': minAngularConfidence,
    };

    // Run detection directly on main thread
    final img = cv.Mat.fromList(height, width, cv.MatType.CV_8UC3, bgrBytes);
    return _detectLEDsCore(img, params);
  }

  /// Isolate function for file-based LED detection
  static List<DetectedLED> _detectLEDsFromFileIsolate(Map<String, dynamic> params) {
    final imagePath = params['imagePath'] as String;

    // Load image from file
    final img = cv.imread(imagePath);
    if (img.isEmpty) {
      throw Exception('Failed to load image: $imagePath');
    }

    return _detectLEDsCore(img, params);
  }

  /// Isolate function for BGR bytes LED detection
  /// Image is already downscaled by camera service - no need to resize here
  static List<DetectedLED> _detectLEDsFromBGRIsolate(Map<String, dynamic> params) {
    final bgrBytes = params['bgrBytes'] as Uint8List;
    final width = params['width'] as int;
    final height = params['height'] as int;

    // Create Mat from BGR bytes (already downscaled by camera service)
    final img = cv.Mat.fromList(height, width, cv.MatType.CV_8UC3, bgrBytes);

    return _detectLEDsCore(img, params);
  }

  /// Core detection logic (shared by file and bytes paths)
  static List<DetectedLED> _detectLEDsCore(cv.Mat img, Map<String, dynamic> params) {
    final coneParamsJson = params['coneParams'] as Map<String, dynamic>?;
    final brightnessThreshold = params['brightnessThreshold'] as int;
    final minArea = params['minArea'] as double;
    final maxArea = params['maxArea'] as double;
    final cameraFovDegrees = params['cameraFovDegrees'] as double;
    final minAngularConfidence = params['minAngularConfidence'] as double;

    // Get scale factor for coordinate adjustment (default 1.0 = no scaling)
    final scaleFactor = (params['appliedDownscale'] as num?)?.toDouble() ?? 1.0;

    // Use original dimensions for cone bounds and angular confidence calculations
    // Falls back to current image size if no downscaling was applied
    final originalWidth = (params['originalWidth'] as int?)?.toDouble() ?? img.cols.toDouble();
    final originalHeight = (params['originalHeight'] as int?)?.toDouble() ?? img.rows.toDouble();

    // Adjust min/max area for downscaled image
    // Area scales quadratically with linear dimensions
    final areaScale = scaleFactor * scaleFactor;
    final scaledMinArea = minArea / areaScale;
    final scaledMaxArea = maxArea / areaScale;

    // Convert to grayscale
    final gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY);
    
    // Gaussian blur to reduce noise
    final blurred = cv.gaussianBlur(gray, (5, 5), 0);
    
    // Threshold to find bright spots
    final thresh = cv.threshold(
      blurred,
      brightnessThreshold.toDouble(),
      255,
      cv.THRESH_BINARY,
    ).$2;
    
    // Find contours
    final contours = cv.findContours(
      thresh,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    ).$1;
    
    List<DetectedLED> detections = [];
    
    // Parse cone parameters if provided
    ConeParameters? cone;
    if (coneParamsJson != null) {
      cone = ConeParameters(
        apexY: (coneParamsJson['apex_y_pixels'] as num).toDouble(),
        baseY: (coneParamsJson['base_y_pixels'] as num).toDouble(),
        baseWidth: (coneParamsJson['base_width_pixels'] as num).toDouble(),
        baseHeight: (coneParamsJson['base_height_pixels'] as num).toDouble(),
      );
    }
    
    // Analyze each contour
    for (final contour in contours) {
      // Get area first to skip small contours early
      final area = cv.contourArea(contour);

      // Skip if too small or too large (use scaled thresholds)
      if (area < scaledMinArea || area > scaledMaxArea) continue;

      // Get bounding rect to find centroid (in scaled coordinates)
      final rect = cv.boundingRect(contour);
      final scaledCx = rect.x + rect.width / 2.0;
      final scaledCy = rect.y + rect.height / 2.0;

      // Scale coordinates back to original image size
      final cx = scaledCx * scaleFactor;
      final cy = scaledCy * scaleFactor;

      // Scale area back to original size
      final originalArea = area * areaScale;

      // Get brightness at center point (in scaled image)
      final brightness = gray.atPixel(scaledCy.toInt(), scaledCx.toInt())[0].toDouble();

      // Calculate detection confidence (is this a LED?)
      // Use original coordinates and area for consistency
      final detectionConfidence = _calculateDetectionConfidence(
        brightness: brightness,
        area: originalArea,
        inConeBounds: cone != null ? _isInConeBounds(cx, cy, cone, originalWidth) : true,
      );

      // Calculate angular confidence (how accurate is angle measurement?)
      // Use original dimensions for accurate angular calculations
      final angularConfidence = _calculateAngularConfidence(
        cx,
        cy,
        originalWidth,
        originalHeight,
        fovDegrees: cameraFovDegrees,
        minConfidence: minAngularConfidence,
      );

      // Calculate normalized height and clamping
      double normalizedHeight = 0;
      bool inConeBounds = true;
      double clampedX = cx;
      double clampedY = cy;
      double clampedBackX = cx;
      double clampedBackY = cy;
      bool wasClamped = false;

      if (cone != null) {
        // Check if in bounds and clamp if not
        inConeBounds = _isInConeBounds(cx, cy, cone, originalWidth);

        // Apply clamping for both front and back surface candidates
        final (frontClamped, backClamped) = DetectionClampingService.clampForTriangulation(
          x: cx,
          y: cy,
          imageWidth: originalWidth,
          coneParams: cone,
        );

        clampedX = frontClamped.x;
        clampedY = frontClamped.y;
        clampedBackX = backClamped.x;
        clampedBackY = backClamped.y;
        wasClamped = frontClamped.wasClamped || backClamped.wasClamped;

        // Calculate normalized height using clamped Y (front surface)
        normalizedHeight = (cone.baseY - clampedY) / cone.treeHeightPixels;
        normalizedHeight = normalizedHeight.clamp(0.0, 1.0);
      }

      detections.add(DetectedLED(
        x: cx,  // Original-scale coordinates
        y: cy,
        clampedX: clampedX,
        clampedY: clampedY,
        clampedBackX: clampedBackX,
        clampedBackY: clampedBackY,
        wasClamped: wasClamped,
        brightness: brightness,
        area: originalArea,  // Original-scale area
        detectionConfidence: detectionConfidence,
        angularConfidence: angularConfidence,
        normalizedHeight: normalizedHeight,
        inConeBounds: inConeBounds,
      ));
    }
    
    // Clean up
    img.dispose();
    gray.dispose();
    blurred.dispose();
    thresh.dispose();
    
    return detections;
  }
  
  /// Calculate detection confidence (is this a real LED?)
  static double _calculateDetectionConfidence({
    required double brightness,
    required double area,
    required bool inConeBounds,
  }) {
    double confidence = 1.0;
    
    // Brightness confidence
    if (brightness > 200) {
      confidence *= 1.0;
    } else if (brightness > 150) {
      confidence *= 0.7;
    } else {
      confidence *= 0.3;
    }
    
    // Size confidence
    if (area > 10 && area < 50) {
      confidence *= 1.0;  // Good size
    } else if (area < 5) {
      confidence *= 0.3;  // Too small (noise)
    } else {
      confidence *= 0.6;  // Too large (bloom/reflection)
    }
    
    // Cone bounds confidence
    if (!inConeBounds) {
      confidence *= 0.2;  // Outside tree bounds (likely reflection)
    }
    
    return confidence;
  }
  
  /// Calculate angular confidence (how accurate is angle measurement?)
  /// Uses cosine of viewing angle - physically accurate model
  static double _calculateAngularConfidence(
    double x,
    double y,
    double imageWidth,
    double imageHeight, {
    double fovDegrees = 60.0,      // Typical phone camera horizontal FOV
    double minConfidence = 0.2,     // Floor for edge detections
  }) {
    final centerX = imageWidth / 2;
    final centerY = imageHeight / 2;
    
    // Distance from center
    final dx = x - centerX;
    final dy = y - centerY;
    final radialDistance = math.sqrt(dx * dx + dy * dy);
    
    // Max possible distance (corner of image)
    final maxDistance = math.sqrt(centerX * centerX + centerY * centerY);
    
    // Normalized distance from center [0, 1]
    final normalizedDistance = radialDistance / maxDistance;
    
    // Convert to viewing angle
    // At edge of frame = half FOV angle
    final halfFovRad = fovDegrees * math.pi / 360.0;  // Half FOV in radians
    final viewingAngle = normalizedDistance * halfFovRad;
    
    // Angular confidence based on cosine
    // cos(0°) = 1.0 → center of frame (best)
    // cos(30°) = 0.866 → typical edge
    // cos(60°) = 0.5 → far edge
    final baseConfidence = math.cos(viewingAngle);
    
    // Apply minimum floor (edge detections still have some value)
    return math.max(baseConfidence, minConfidence);
  }
  
  /// Check if point is within cone bounds
  static bool _isInConeBounds(
    double x,
    double y,
    ConeParameters cone,
    double imageWidth,
  ) {
    // Check vertical bounds
    if (y < cone.apexY || y > cone.baseY) {
      return false;
    }
    
    // Calculate normalized height
    final normalizedHeight = (cone.baseY - y) / cone.treeHeightPixels;
    
    // Expected radius at this height (linear taper)
    final expectedRadius = (cone.baseWidth / 2) * (1 - normalizedHeight);
    
    // Center X
    final centerX = imageWidth / 2;
    
    // Distance from centerline
    final distFromCenter = (x - centerX).abs();
    
    // Check if within cone bounds (with 20% tolerance)
    return distFromCenter <= expectedRadius * 1.2;
  }
}
