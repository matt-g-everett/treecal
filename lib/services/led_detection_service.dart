import 'dart:isolate';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math' as math;
import '../screens/cone_calibration_overlay.dart' show ConeParameters;
import 'detection_clamping_service.dart';

/// Contour polygon from OpenCV for debug visualization
class ContourPolygon {
  final List<Point> points;  // Points in original image coordinates
  final double area;
  final double cx;  // Centroid X
  final double cy;  // Centroid Y

  ContourPolygon({
    required this.points,
    required this.area,
    required this.cx,
    required this.cy,
  });
}

/// Simple 2D point
class Point {
  final double x;
  final double y;
  Point(this.x, this.y);
}

/// Detection result including both LED detections and raw contours for debug
class LEDDetectionResult {
  final List<DetectedLED> detections;
  final List<ContourPolygon> allContours;  // All contours (including filtered ones)
  final List<ContourPolygon> passedContours;  // Only contours that passed filters

  LEDDetectionResult({
    required this.detections,
    required this.allContours,
    required this.passedContours,
  });
}

/// Brightness profile around a centroid for LED detection
class _BrightnessProfile {
  final double peak;           // Maximum brightness in region
  final double weightedAvg;    // Gaussian-weighted average (emphasizes center)
  final double unweightedAvg;  // Simple average
  final double concentration;  // Ratio of weighted/unweighted (>1 = bright center)

  _BrightnessProfile({
    required this.peak,
    required this.weightedAvg,
    required this.unweightedAvg,
    required this.concentration,
  });
}

/// Detected LED information
class DetectedLED {
  final double x;              // Original detection X
  final double y;              // Original detection Y
  final double clampedX;       // X clamped to cone bounds (for front surface)
  final double clampedY;       // Y clamped to cone bounds (for front surface)
  final double clampedBackX;   // X clamped to cone bounds (for back surface)
  final double clampedBackY;   // Y clamped to cone bounds (for back surface)
  final bool wasClamped;       // Whether clamping was applied
  final double brightness;     // Peak brightness
  final double weightedAvg;    // Center-weighted average brightness
  final double unweightedAvg;  // Uniform average brightness
  final double concentration;  // Brightness concentration (weightedAvg/unweightedAvg)
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
    this.weightedAvg = 0,
    this.unweightedAvg = 0,
    this.concentration = 1.0,
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
    return _detectLEDsCore(img, params).detections;
  }

  /// Detect LEDs from BGR bytes with full debug info including contour polygons
  /// Returns LEDDetectionResult with both detections and raw contours for visualization
  ///
  /// If [expectedLedIndex] and [totalLeds] are provided, detections are scored
  /// based on how close their vertical position is to the expected spiral position.
  ///
  /// [sensorOrientation]: Camera sensor rotation (0, 90, 180, 270 degrees).
  /// Used to transform detection coordinates to preview space for cone bounds checking.
  static LEDDetectionResult detectLEDsFromBGRSyncWithContours({
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
    int? expectedLedIndex,
    int? totalLeds,
    int sensorOrientation = 0,
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
      'expectedLedIndex': expectedLedIndex,
      'totalLeds': totalLeds,
      'sensorOrientation': sensorOrientation,
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

    return _detectLEDsCore(img, params).detections;
  }

  /// Isolate function for BGR bytes LED detection
  /// Image is already downscaled by camera service - no need to resize here
  static List<DetectedLED> _detectLEDsFromBGRIsolate(Map<String, dynamic> params) {
    final bgrBytes = params['bgrBytes'] as Uint8List;
    final width = params['width'] as int;
    final height = params['height'] as int;

    // Create Mat from BGR bytes (already downscaled by camera service)
    final img = cv.Mat.fromList(height, width, cv.MatType.CV_8UC3, bgrBytes);

    return _detectLEDsCore(img, params).detections;
  }

  /// Core detection logic (shared by file and bytes paths)
  /// Returns LEDDetectionResult with detections and contour polygons for debug visualization
  static LEDDetectionResult _detectLEDsCore(cv.Mat img, Map<String, dynamic> params) {
    final coneParamsJson = params['coneParams'] as Map<String, dynamic>?;
    final brightnessThreshold = params['brightnessThreshold'] as int;
    final minArea = params['minArea'] as double;
    final maxArea = params['maxArea'] as double;
    final cameraFovDegrees = params['cameraFovDegrees'] as double;
    final minAngularConfidence = params['minAngularConfidence'] as double;

    // Expected LED position for spiral-based filtering (optional)
    final expectedLedIndex = params['expectedLedIndex'] as int?;
    final totalLeds = params['totalLeds'] as int?;

    // Calculate expected normalized height if we know which LED we're looking for
    // LEDs spiral from bottom (index 0) to top (index totalLeds-1)
    double? expectedNormalizedHeight;
    if (expectedLedIndex != null && totalLeds != null && totalLeds > 1) {
      expectedNormalizedHeight = expectedLedIndex / (totalLeds - 1);
    }

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

    // Debug: log contour count and threshold info
    print('[DETECT] Threshold=$brightnessThreshold, contours found: ${contours.length}');
    print('[DETECT] Image size: ${img.cols}x${img.rows}, scaleFactor=$scaleFactor');
    print('[DETECT] Area filter: scaled min=$scaledMinArea, max=$scaledMaxArea (original min=$minArea, max=$maxArea)');

    List<DetectedLED> detections = [];
    List<ContourPolygon> allContours = [];
    List<ContourPolygon> passedContours = [];

    // Sensor orientation for coordinate transformation
    final sensorOrientation = (params['sensorOrientation'] as int?) ?? 0;

    // Parse cone parameters if provided
    ConeParameters? cone;
    if (coneParamsJson != null) {
      cone = ConeParameters(
        apexY: (coneParamsJson['apex_y_pixels'] as num).toDouble(),
        baseY: (coneParamsJson['base_y_pixels'] as num).toDouble(),
        baseWidth: (coneParamsJson['base_width_pixels'] as num).toDouble(),
        baseHeight: (coneParamsJson['base_height_pixels'] as num).toDouble(),
        sourceWidth: (coneParamsJson['source_width'] as num?)?.toDouble() ?? 0,
        sourceHeight: (coneParamsJson['source_height'] as num?)?.toDouble() ?? 0,
      );
    }

    // Analyze each contour
    int skippedSmall = 0;
    int skippedLarge = 0;
    for (final contour in contours) {
      // Get area first to skip small contours early
      final area = cv.contourArea(contour);

      // Get bounding rect for centroid (needed for all contours)
      final rect = cv.boundingRect(contour);
      final scaledCx = rect.x + rect.width / 2.0;
      final scaledCy = rect.y + rect.height / 2.0;
      final cx = scaledCx * scaleFactor;
      final cy = scaledCy * scaleFactor;
      final originalArea = area * areaScale;

      // Extract contour polygon points (scaled to original coordinates)
      final points = <Point>[];
      for (int i = 0; i < contour.length; i++) {
        final pt = contour.elementAt(i);
        points.add(Point(pt.x * scaleFactor, pt.y * scaleFactor));
      }

      final contourPolygon = ContourPolygon(
        points: points,
        area: originalArea,
        cx: cx,
        cy: cy,
      );
      allContours.add(contourPolygon);

      // Skip if too small or too large (use scaled thresholds)
      if (area < scaledMinArea) {
        skippedSmall++;
        continue;
      }
      if (area > scaledMaxArea) {
        // ignore: avoid_print
        print('[DETECT] Skipped LARGE contour: area=${originalArea.toInt()} at ($cx, $cy)');
        skippedLarge++;
        continue;
      }

      // This contour passed the filters
      passedContours.add(contourPolygon);

      // Calculate normalized height and clamping first (needed for confidence)
      double normalizedHeight = 0;
      double coneDistanceRatio = 0;  // 0 = inside cone, >0 = how far outside
      double clampedX = cx;
      double clampedY = cy;
      double clampedBackX = cx;
      double clampedBackY = cy;
      bool wasClamped = false;

      if (cone != null) {
        // Calculate distance from cone bounds (0 = inside, >0 = outside)
        coneDistanceRatio = _coneDistanceRatio(
          cx, cy, cone, originalWidth, originalHeight, sensorOrientation);

        // Calculate normalized height (transforms to preview space internally)
        normalizedHeight = _calculateNormalizedHeight(
          cx, cy, cone, originalWidth, originalHeight, sensorOrientation);

        // Apply clamping for both front and back surface candidates
        // Note: clamping still uses camera coordinates for now
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
      }

      // Analyze brightness profile around centroid
      // Use a tight sampling radius to capture LED core vs bloom
      // At 2x downscale, radius 4 = 9px diameter = ~18px at original resolution
      const int sampleRadius = 4;
      final brightnessProfile = _analyzeBrightnessProfile(
        gray,
        scaledCx.toInt(),
        scaledCy.toInt(),
        sampleRadius,
      );

      // Calculate detection confidence based on brightness profile and vertical position
      final detectionConfidence = _calculateDetectionConfidence(
        peakBrightness: brightnessProfile.peak,
        concentration: brightnessProfile.concentration,
        coneDistanceRatio: coneDistanceRatio,
        detectedNormalizedHeight: normalizedHeight,
        expectedNormalizedHeight: expectedNormalizedHeight,
      );

      // Debug: compact confidence factors
      final expHStr = expectedNormalizedHeight != null
          ? '${(expectedNormalizedHeight * 100).toInt()}%'
          : '?';
      final inCone = coneDistanceRatio == 0;
      print('[LED] peak=${brightnessProfile.peak.toInt()} '
          'wAvg=${brightnessProfile.weightedAvg.toInt()} '
          'uAvg=${brightnessProfile.unweightedAvg.toInt()} '
          'conc=${brightnessProfile.concentration.toStringAsFixed(2)} '
          'h=${(normalizedHeight * 100).toInt()}%/$expHStr '
          'cone=${inCone ? "Y" : "N"}(${coneDistanceRatio.toStringAsFixed(2)}) '
          '-> conf=${(detectionConfidence * 100).toInt()}%');

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

      detections.add(DetectedLED(
        x: cx,  // Original-scale coordinates
        y: cy,
        clampedX: clampedX,
        clampedY: clampedY,
        clampedBackX: clampedBackX,
        clampedBackY: clampedBackY,
        wasClamped: wasClamped,
        brightness: brightnessProfile.peak,
        weightedAvg: brightnessProfile.weightedAvg,
        unweightedAvg: brightnessProfile.unweightedAvg,
        concentration: brightnessProfile.concentration,
        area: originalArea,  // Original-scale area
        detectionConfidence: detectionConfidence,
        angularConfidence: angularConfidence,
        normalizedHeight: normalizedHeight,
        inConeBounds: inCone,
      ));
    }
    
    // ignore: avoid_print
    print('[DETECT] Summary: ${detections.length} passed, $skippedSmall too small, $skippedLarge too large');
    print('[DETECT] Contours: ${allContours.length} total, ${passedContours.length} passed filters');

    // Clean up
    img.dispose();
    gray.dispose();
    blurred.dispose();
    thresh.dispose();

    return LEDDetectionResult(
      detections: detections,
      allContours: allContours,
      passedContours: passedContours,
    );
  }
  
  /// Brightness profile analysis result
  static _BrightnessProfile _analyzeBrightnessProfile(
    cv.Mat gray,
    int cx,
    int cy,
    int radius,
  ) {
    final width = gray.cols;
    final height = gray.rows;

    double peak = 0;
    double weightedSum = 0;
    double weightSum = 0;
    double unweightedSum = 0;
    int pixelCount = 0;

    // Gaussian sigma - controls how quickly weight falls off from center
    // Smaller sigma = tighter focus on center
    final sigma = radius / 2.0;
    final twoSigmaSquared = 2.0 * sigma * sigma;

    // Sample pixels in a square region around the centroid
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final px = cx + dx;
        final py = cy + dy;

        // Bounds check
        if (px < 0 || px >= width || py < 0 || py >= height) continue;

        // Distance from center
        final distSquared = (dx * dx + dy * dy).toDouble();

        // Skip pixels outside circular region
        if (distSquared > radius * radius) continue;

        final brightness = gray.atPixel(py, px)[0].toDouble();

        // Track peak brightness
        if (brightness > peak) {
          peak = brightness;
        }

        // Gaussian weight: higher near center, falls off with distance
        final weight = math.exp(-distSquared / twoSigmaSquared);

        weightedSum += brightness * weight;
        weightSum += weight;
        unweightedSum += brightness;
        pixelCount++;
      }
    }

    // Calculate averages
    final weightedAvg = weightSum > 0 ? weightedSum / weightSum : 0.0;
    final unweightedAvg = pixelCount > 0 ? unweightedSum / pixelCount : 0.0;

    // Concentration: ratio of weighted to unweighted average
    // LED with bright core: concentration > 1.0 (center is brighter than edges)
    // Uniform patch: concentration ≈ 1.0
    final concentration = unweightedAvg > 0 ? weightedAvg / unweightedAvg : 1.0;

    return _BrightnessProfile(
      peak: peak,
      weightedAvg: weightedAvg,
      unweightedAvg: unweightedAvg,
      concentration: concentration,
    );
  }

  /// Calculate detection confidence (is this a real LED?)
  /// Uses peak brightness, concentration, and vertical position to identify LEDs vs reflections
  ///
  /// If [expectedNormalizedHeight] is provided, detections far from the expected
  /// vertical position are penalized. This uses the spiral pattern where LEDs
  /// progress from bottom (height=0) to top (height=1) as index increases.
  ///
  /// [coneDistanceRatio] indicates how far outside the cone bounds the detection is:
  /// - 0.0 = inside cone bounds
  /// - 0.5 = 50% outside the expected radius
  /// - 1.0+ = far outside bounds
  static double _calculateDetectionConfidence({
    required double peakBrightness,
    required double concentration,
    required double coneDistanceRatio,
    double? detectedNormalizedHeight,
    double? expectedNormalizedHeight,
  }) {
    double confidence = 1.0;

    // Peak brightness confidence
    // Real LEDs saturate near 255, reflections are dimmer
    if (peakBrightness >= 250) {
      confidence *= 1.0;   // Saturated = definitely bright source
    } else if (peakBrightness >= 230) {
      confidence *= 0.95;
    } else if (peakBrightness >= 200) {
      confidence *= 0.8;
    } else if (peakBrightness >= 170) {
      confidence *= 0.5;
    } else {
      confidence *= 0.2;   // Too dim to be the active LED
    }

    // Concentration confidence
    // LEDs have bright cores with falloff; reflections are more uniform
    // concentration > 1.0 means center is brighter than average (good)
    // concentration ≈ 1.0 means uniform brightness (likely reflection)
    if (concentration >= 1.10) {
      confidence *= 1.0;   // Strong central peak
    } else if (concentration >= 1.05) {
      confidence *= 0.9;   // Moderate peak
    } else if (concentration >= 1.00) {
      confidence *= 0.7;   // Slight peak
    } else {
      confidence *= 0.4;   // Uniform or inverted (not an LED)
    }

    // Vertical position confidence (if we know which LED to expect)
    // Horizontal position varies with rotation, but vertical position along
    // the spiral changes slowly and predictably
    if (expectedNormalizedHeight != null && detectedNormalizedHeight != null) {
      final heightError = (detectedNormalizedHeight - expectedNormalizedHeight).abs();

      // Allow reasonable tolerance for spiral spacing and detection error
      // ~5% of tree height is close, ~15% is acceptable, beyond that penalize
      if (heightError <= 0.05) {
        confidence *= 1.0;   // Very close to expected height
      } else if (heightError <= 0.10) {
        confidence *= 0.9;   // Reasonable deviation
      } else if (heightError <= 0.15) {
        confidence *= 0.7;   // Getting far
      } else if (heightError <= 0.25) {
        confidence *= 0.4;   // Unlikely to be the right LED
      } else {
        confidence *= 0.1;   // Way off - probably a reflection or wrong LED
      }
    }

    // Cone bounds penalty - gradual falloff based on distance from boundary
    // coneDistanceRatio: 0 = inside, 0.5 = 50% outside expected radius, etc.
    if (coneDistanceRatio > 0) {
      // Softer falloff: allow detections moderately outside bounds
      // At 0% outside = 1.0x, 50% outside = 0.85x, 100% outside = 0.7x, 200% outside = 0.4x
      final boundsPenalty = (1.0 - coneDistanceRatio * 0.3).clamp(0.3, 1.0);
      confidence *= boundsPenalty;
    }

    return confidence.clamp(0.0, 1.0);
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
  
  /// Calculate how far outside cone bounds a point is.
  /// Returns 0.0 if inside bounds, positive value indicating distance ratio if outside.
  /// A ratio of 0.5 means the point is 50% of the expected radius outside the cone.
  ///
  /// Coordinates are in camera image space; cone is in preview space.
  /// [sensorOrientation] is used to transform the point to preview space.
  ///
  /// This accounts for:
  /// 1. Sensor rotation (camera landscape → preview portrait)
  /// 2. Cover/fill scaling (preview may crop parts of the camera image)
  static double _coneDistanceRatio(
    double x,
    double y,
    ConeParameters cone,
    double imageWidth,
    double imageHeight,
    int sensorOrientation,
  ) {
    // After rotation, get effective image dimensions as they appear in preview
    final bool isRotated90or270 = sensorOrientation == 90 || sensorOrientation == 270;
    final double rotatedImageW = isRotated90or270 ? imageHeight : imageWidth;
    final double rotatedImageH = isRotated90or270 ? imageWidth : imageHeight;

    // Transform camera point to rotated image space
    double rotatedX, rotatedY;
    switch (sensorOrientation) {
      case 90:
        // Camera (x, y) → Rotated (height - y, x)
        rotatedX = imageHeight - y;
        rotatedY = x;
        break;
      case 270:
        rotatedX = y;
        rotatedY = imageWidth - x;
        break;
      case 180:
        rotatedX = imageWidth - x;
        rotatedY = imageHeight - y;
        break;
      default:
        rotatedX = x;
        rotatedY = y;
    }

    // Calculate cover/fill scaling (matching _ImagePainter logic)
    final imageAspect = rotatedImageW / rotatedImageH;
    final previewAspect = cone.sourceWidth / cone.sourceHeight;

    double scale;
    double offsetX, offsetY;

    if (imageAspect > previewAspect) {
      // Image is wider - fit height, crop width (X gets offset)
      scale = cone.sourceHeight / rotatedImageH;
      final scaledImageW = rotatedImageW * scale;
      offsetX = (scaledImageW - cone.sourceWidth) / 2;
      offsetY = 0;
    } else {
      // Image is taller - fit width, crop height (Y gets offset)
      scale = cone.sourceWidth / rotatedImageW;
      offsetX = 0;
      final scaledImageH = rotatedImageH * scale;
      offsetY = (scaledImageH - cone.sourceHeight) / 2;
    }

    // Transform rotated coordinates to preview coordinates (accounting for scale and crop)
    final previewX = rotatedX * scale - offsetX;
    final previewY = rotatedY * scale - offsetY;

    // Now check bounds in preview/cone coordinate system
    // Check vertical bounds - return high ratio if outside vertical bounds
    if (previewY < cone.apexY) {
      final verticalDistance = cone.apexY - previewY;
      return verticalDistance / cone.treeHeightPixels;  // Ratio of tree height
    }
    if (previewY > cone.baseY) {
      final verticalDistance = previewY - cone.baseY;
      return verticalDistance / cone.treeHeightPixels;  // Ratio of tree height
    }

    // Calculate normalized height
    final normalizedHeight = (cone.baseY - previewY) / cone.treeHeightPixels;

    // Expected radius at this height (linear taper)
    // Use a minimum radius of 5% of base width to handle apex region
    final baseRadius = cone.baseWidth / 2;
    final minRadius = baseRadius * 0.05;  // Minimum ~5% of base width
    final expectedRadius = (baseRadius * (1 - normalizedHeight)).clamp(minRadius, baseRadius);

    // Center X in preview coordinates
    final centerX = cone.sourceWidth / 2;

    // Distance from centerline
    final distFromCenter = (previewX - centerX).abs();

    // Calculate how far outside the expected radius we are
    // 0.0 = inside bounds, positive = outside
    if (distFromCenter <= expectedRadius) {
      return 0.0;  // Inside cone bounds
    } else {
      // Use a tolerance zone for the ratio calculation
      // This prevents tiny expected radii (near apex) from causing huge ratios
      // Tolerance = 10% of base radius + 10 pixels absolute
      final toleranceZone = baseRadius * 0.1 + 10.0;
      final excessDistance = distFromCenter - expectedRadius;
      return excessDistance / toleranceZone;
    }
  }

  /// Calculate normalized height in preview coordinate space.
  /// Returns value between 0 (base) and 1 (apex).
  ///
  /// This accounts for:
  /// 1. Sensor rotation (camera landscape → preview portrait)
  /// 2. Cover/fill scaling (preview may crop parts of the camera image)
  static double _calculateNormalizedHeight(
    double x,
    double y,
    ConeParameters cone,
    double imageWidth,
    double imageHeight,
    int sensorOrientation,
  ) {
    // After rotation, get effective image dimensions as they appear in preview
    final bool isRotated90or270 = sensorOrientation == 90 || sensorOrientation == 270;
    final double rotatedImageW = isRotated90or270 ? imageHeight : imageWidth;
    final double rotatedImageH = isRotated90or270 ? imageWidth : imageHeight;

    // Transform camera point to rotated image space
    double rotatedY;
    switch (sensorOrientation) {
      case 90:
        // Camera (x, y) → Rotated (height - y, x)
        rotatedY = x;  // The camera X becomes the vertical position after rotation
        break;
      case 270:
        rotatedY = imageWidth - x;
        break;
      case 180:
        rotatedY = imageHeight - y;
        break;
      default:
        rotatedY = y;
    }

    // Calculate cover/fill scaling (matching _ImagePainter logic)
    final imageAspect = rotatedImageW / rotatedImageH;
    final previewAspect = cone.sourceWidth / cone.sourceHeight;

    double scale;
    double offsetY;

    if (imageAspect > previewAspect) {
      // Image is wider - fit height, crop width (no Y offset)
      scale = cone.sourceHeight / rotatedImageH;
      offsetY = 0;
    } else {
      // Image is taller - fit width, crop height (Y gets offset)
      scale = cone.sourceWidth / rotatedImageW;
      final scaledImageH = rotatedImageH * scale;
      offsetY = (scaledImageH - cone.sourceHeight) / 2;  // Cropped from top/bottom
    }

    // Transform rotated Y to preview Y (accounting for scale and crop offset)
    final previewY = rotatedY * scale - offsetY;

    // Calculate normalized height
    final normalizedHeight = (cone.baseY - previewY) / cone.treeHeightPixels;
    return normalizedHeight.clamp(0.0, 1.0);
  }
}
