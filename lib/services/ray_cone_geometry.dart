import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// 3D vector utilities
class Vector3 {
  final double x, y, z;
  
  const Vector3(this.x, this.y, this.z);
  
  Vector3 operator +(Vector3 other) => Vector3(x + other.x, y + other.y, z + other.z);
  Vector3 operator -(Vector3 other) => Vector3(x - other.x, y - other.y, z - other.z);
  Vector3 operator *(double scalar) => Vector3(x * scalar, y * scalar, z * scalar);
  Vector3 operator /(double scalar) => Vector3(x / scalar, y / scalar, z / scalar);
  
  double dot(Vector3 other) => x * other.x + y * other.y + z * other.z;
  
  Vector3 cross(Vector3 other) => Vector3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );
  
  double get length => math.sqrt(x * x + y * y + z * z);
  
  Vector3 get normalized {
    final len = length;
    return len > 0 ? this / len : this;
  }
  
  @override
  String toString() => '($x, $y, $z)';
}

/// Camera intrinsics and geometry
class CameraGeometry {
  final double imageWidth;
  final double imageHeight;
  final double fovHorizontalDegrees;
  
  CameraGeometry({
    required this.imageWidth,
    required this.imageHeight,
    this.fovHorizontalDegrees = 60.0,
  });
  
  /// Get principal point (image center)
  Vector3 get principalPoint => Vector3(imageWidth / 2, imageHeight / 2, 0);
  
  /// Calculate focal length from FOV
  double get focalLength {
    // f = (width / 2) / tan(FOV / 2)
    final fovRad = fovHorizontalDegrees * math.pi / 180.0;
    return (imageWidth / 2.0) / math.tan(fovRad / 2.0);
  }
  
  /// Convert pixel coordinates to normalized image coordinates
  /// Origin at image center, Z=1 plane
  Vector3 pixelToNormalizedImageCoords(double pixelX, double pixelY) {
    final cx = imageWidth / 2.0;
    final cy = imageHeight / 2.0;
    final f = focalLength;
    
    // Normalized coordinates on Z=1 plane
    final x = (pixelX - cx) / f;
    final y = (pixelY - cy) / f;
    
    return Vector3(x, y, 1.0);
  }
  
  /// Get ray direction from camera through pixel
  /// Camera at origin, looking along +Z
  Vector3 pixelToRayDirection(double pixelX, double pixelY) {
    final normalized = pixelToNormalizedImageCoords(pixelX, pixelY);
    return normalized.normalized;
  }
}

/// Cone surface parameters
class ConeModel {
  final double baseRadius;    // Radius at bottom (z=0)
  final double topRadius;     // Radius at top (z=height)
  final double height;        // Tree height
  final Vector3 center;       // Center position (usually origin)
  
  ConeModel({
    required this.baseRadius,
    required this.topRadius,
    required this.height,
    Vector3? center,
  }) : center = center ?? const Vector3(0, 0, 0);
  
  /// Get radius at a given height
  double radiusAtHeight(double z) {
    if (height == 0) return baseRadius;
    
    // Linear taper: r(z) = baseRadius - (baseRadius - topRadius) * (z / height)
    final t = z / height;
    return baseRadius * (1 - t) + topRadius * t;
  }
  
  /// Get normalized height (0-1)
  double normalizeHeight(double z) {
    return (z / height).clamp(0.0, 1.0);
  }
  
  /// Convert cone coordinates (height, angle) to 3D position
  Vector3 coneToCartesian(double normalizedHeight, double angleDegrees) {
    final z = normalizedHeight * height;
    final radius = radiusAtHeight(z);
    final angleRad = angleDegrees * math.pi / 180.0;
    
    final x = center.x + radius * math.cos(angleRad);
    final y = center.y + radius * math.sin(angleRad);
    
    return Vector3(x, y, z + center.z);
  }
  
  /// Create from manual cone overlay parameters
  factory ConeModel.fromConeParameters({
    required double treeHeight,
    required double baseWidthPixels,
    double taperRatio = 0.0,  // 0 = point top, 1 = cylinder
  }) {
    // Estimate physical radius from pixel width
    // Assume cone fills ~60% of frame at typical distance
    final estimatedBaseRadius = treeHeight * 0.3; // Rough estimate
    final topRadius = estimatedBaseRadius * taperRatio;
    
    return ConeModel(
      baseRadius: estimatedBaseRadius,
      topRadius: topRadius,
      height: treeHeight,
    );
  }
}

/// Ray-cone intersection result (single surface)
class RayConeIntersection {
  final double normalizedHeight;  // 0-1
  final double angleDegrees;      // 0-360
  final Vector3 position3D;
  final double distance;          // Distance from camera
  
  RayConeIntersection({
    required this.normalizedHeight,
    required this.angleDegrees,
    required this.position3D,
    required this.distance,
  });
  
  @override
  String toString() => 
    'h=$normalizedHeight, θ=$angleDegrees°, pos=$position3D, dist=$distance';
}

/// Dual ray-cone intersection (front AND back surfaces)
class DualRayConeIntersection {
  final RayConeIntersection front;  // Near intersection (closer to camera)
  final RayConeIntersection? back;  // Far intersection (farther from camera)
  
  DualRayConeIntersection({
    required this.front,
    this.back,
  });
  
  bool get hasBothSurfaces => back != null;
  
  @override
  String toString() => 
    'Front: $front${back != null ? '\nBack: $back' : ' (no back intersection)'}';
}

/// Ray-cone intersection calculator
class RayConeIntersector {
  
  /// Find intersection of ray with cone surface
  /// 
  /// Ray: P(t) = origin + t * direction
  /// Cone: (x² + y²) = r(z)² where r(z) = baseR * (1 - z/h)
  /// 
  /// Returns intersection in cone coordinates (height, angle)
  static RayConeIntersection? intersect({
    required Vector3 rayOrigin,
    required Vector3 rayDirection,
    required ConeModel cone,
  }) {
    // Transform to cone-centered coordinates
    final origin = rayOrigin - cone.center;
    final dir = rayDirection.normalized;
    
    // Cone equation: x² + y² = r(z)²
    // where r(z) = baseR - (baseR - topR) * z / height
    // 
    // Let: a = (baseR - topR) / height  (taper rate)
    //      b = baseR
    // Then: r(z) = b - a*z
    //
    // Substituting ray P(t) = O + t*D:
    // (Ox + t*Dx)² + (Oy + t*Dy)² = (b - a*(Oz + t*Dz))²
    //
    // This is a quadratic in t
    
    final a = (cone.baseRadius - cone.topRadius) / cone.height;
    final b = cone.baseRadius;
    
    // Expand to At² + Bt + C = 0
    final A = dir.x * dir.x + dir.y * dir.y - a * a * dir.z * dir.z;
    final B = 2 * (origin.x * dir.x + origin.y * dir.y) 
            - 2 * a * a * origin.z * dir.z 
            + 2 * a * b * dir.z;
    final C = origin.x * origin.x + origin.y * origin.y 
            - b * b 
            + 2 * a * b * origin.z 
            - a * a * origin.z * origin.z;
    
    // Solve quadratic
    final discriminant = B * B - 4 * A * C;
    
    if (discriminant < 0) {
      return null; // No intersection
    }
    
    // Two solutions - we want the nearest positive one
    final sqrtDisc = math.sqrt(discriminant);
    final t1 = (-B - sqrtDisc) / (2 * A);
    final t2 = (-B + sqrtDisc) / (2 * A);
    
    // Pick nearest valid intersection
    double? t;
    if (t1 > 0 && t2 > 0) {
      t = math.min(t1, t2);
    } else if (t1 > 0) {
      t = t1;
    } else if (t2 > 0) {
      t = t2;
    } else {
      return null; // Both behind camera
    }
    
    // Intersection point
    final point = origin + dir * t;
    
    // Check if within cone height bounds
    if (point.z < 0 || point.z > cone.height) {
      return null;
    }
    
    // Convert to cone coordinates
    final normalizedHeight = cone.normalizeHeight(point.z);
    final angleDegrees = (math.atan2(point.y, point.x) * 180 / math.pi + 360) % 360;
    
    // Convert back to world coordinates
    final position3D = point + cone.center;
    
    return RayConeIntersection(
      normalizedHeight: normalizedHeight,
      angleDegrees: angleDegrees,
      position3D: position3D,
      distance: t,
    );
  }
  
  /// Simplified intersection for common case (cone at origin, camera looking at it)
  static RayConeIntersection? intersectSimple({
    required Vector3 cameraPosition,
    required Vector3 rayDirectionWorld,
    required ConeModel cone,
  }) {
    return intersect(
      rayOrigin: cameraPosition,
      rayDirection: rayDirectionWorld,
      cone: cone,
    );
  }
  
  /// Find BOTH intersections of ray with cone surface (front AND back)
  /// 
  /// Returns both the near (front) and far (back) intersections.
  /// Useful for determining which side of tree an LED is on.
  static DualRayConeIntersection? intersectDual({
    required Vector3 rayOrigin,
    required Vector3 rayDirection,
    required ConeModel cone,
  }) {
    // Transform to cone-centered coordinates
    final origin = rayOrigin - cone.center;
    final dir = rayDirection.normalized;
    
    final a = (cone.baseRadius - cone.topRadius) / cone.height;
    final b = cone.baseRadius;
    
    // Expand to At² + Bt + C = 0
    final A = dir.x * dir.x + dir.y * dir.y - a * a * dir.z * dir.z;
    final B = 2 * (origin.x * dir.x + origin.y * dir.y) 
            - 2 * a * a * origin.z * dir.z 
            + 2 * a * b * dir.z;
    final C = origin.x * origin.x + origin.y * origin.y 
            - b * b 
            + 2 * a * b * origin.z 
            - a * a * origin.z * origin.z;
    
    // Solve quadratic
    final discriminant = B * B - 4 * A * C;
    
    if (discriminant < 0) {
      return null; // No intersection
    }
    
    // Two solutions
    final sqrtDisc = math.sqrt(discriminant);
    final t1 = (-B - sqrtDisc) / (2 * A);
    final t2 = (-B + sqrtDisc) / (2 * A);
    
    // Helper to create intersection from t value
    RayConeIntersection? makeIntersection(double t) {
      if (t <= 0) return null; // Behind camera
      
      final point = origin + dir * t;
      
      // Check if within cone height bounds
      if (point.z < 0 || point.z > cone.height) {
        return null;
      }
      
      // Convert to cone coordinates
      final normalizedHeight = cone.normalizeHeight(point.z);
      final angleDegrees = (math.atan2(point.y, point.x) * 180 / math.pi + 360) % 360;
      
      // Convert back to world coordinates
      final position3D = point + cone.center;
      
      return RayConeIntersection(
        normalizedHeight: normalizedHeight,
        angleDegrees: angleDegrees,
        position3D: position3D,
        distance: t,
      );
    }
    
    // Get both intersections (t1 is always <= t2)
    final near = makeIntersection(math.min(t1, t2));
    final far = makeIntersection(math.max(t1, t2));
    
    if (near == null && far == null) {
      return null; // No valid intersections
    }
    
    // Return front (required) and back (optional)
    return DualRayConeIntersection(
      front: near ?? far!,  // If only one intersection, use it as front
      back: near != null ? far : null,  // Back only exists if we have both
    );
  }
}

/// Transform ray from camera coordinate system to world coordinate system
class CameraTransform {
  final Vector3 position;      // Camera position in world
  final double yawDegrees;     // Rotation around Z axis (looking at tree)
  
  CameraTransform({
    required this.position,
    required this.yawDegrees,
  });
  
  /// Transform ray direction from camera space to world space
  /// Camera space: +Z is forward, +X is right, +Y is down
  /// World space: Z is up, camera looks toward tree center
  Vector3 rayToWorld(Vector3 rayCamera) {
    // Rotate ray by camera yaw
    final yawRad = yawDegrees * math.pi / 180.0;
    final cosYaw = math.cos(yawRad);
    final sinYaw = math.sin(yawRad);
    
    // Camera looks at tree center (origin)
    // Camera +Z points toward tree
    // Rotate ray by yaw around Z axis
    
    final x = rayCamera.x * cosYaw - rayCamera.y * sinYaw;
    final y = rayCamera.x * sinYaw + rayCamera.y * cosYaw;
    final z = rayCamera.z;
    
    return Vector3(x, y, z);
  }
}

/// Example usage and testing
void testRayConeIntersection() {
  debugPrint('=== Testing Ray-Cone Intersection ===\n');
  
  // Create cone (2m tall Christmas tree)
  final cone = ConeModel(
    baseRadius: 0.5,   // 0.5m radius at base
    topRadius: 0.05,   // Nearly point at top
    height: 2.0,       // 2m tall
  );
  
  // Camera setup
  final camera = CameraGeometry(
    imageWidth: 1920,
    imageHeight: 1080,
    fovHorizontalDegrees: 60,
  );
  
  // Camera position (1.5m from tree, 1m high, at 0° angle)
  final cameraPos = Vector3(1.5, 0.0, 1.0);
  
  // Test pixel at center of image (should hit middle of tree)
  final rayDir = camera.pixelToRayDirection(960, 540);
  
  debugPrint('Camera: pos=$cameraPos, FOV=${camera.fovHorizontalDegrees}°');
  debugPrint('Cone: base_r=${cone.baseRadius}m, top_r=${cone.topRadius}m, h=${cone.height}m');
  debugPrint('Test pixel: (960, 540) - center of image');
  debugPrint('Ray direction (camera space): $rayDir');
  
  // Transform ray to world space (camera looking at -X toward origin)
  final rayWorld = Vector3(-rayDir.z, rayDir.x, rayDir.y);
  
  debugPrint('Ray direction (world space): $rayWorld\n');
  
  // Find intersection
  final intersection = RayConeIntersector.intersect(
    rayOrigin: cameraPos,
    rayDirection: rayWorld,
    cone: cone,
  );
  
  if (intersection != null) {
    debugPrint('✓ Intersection found!');
    debugPrint('  Height: ${(intersection.normalizedHeight * 100).toStringAsFixed(1)}%');
    debugPrint('  Angle: ${intersection.angleDegrees.toStringAsFixed(1)}°');
    debugPrint('  3D Position: ${intersection.position3D}');
    debugPrint('  Distance from camera: ${intersection.distance.toStringAsFixed(3)}m');
    
    final radius = cone.radiusAtHeight(intersection.normalizedHeight * cone.height);
    debugPrint('  Cone radius at this height: ${radius.toStringAsFixed(3)}m');
  } else {
    debugPrint('✗ No intersection found');
  }
  
  debugPrint('\n=== Test Complete ===');
}
