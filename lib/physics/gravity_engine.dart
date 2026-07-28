import 'dart:math' as math;

class GravitySample {
  const GravitySample({
    required this.x,
    required this.y,
    required this.slope,
    required this.pour,
  });

  final double x;
  final double y;
  final double slope;
  final double pour;
}

class GravityEngine {
  const GravityEngine();

  GravitySample fromAccelerometer(double x, double y, double z) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    if (magnitude <= 0.1) {
      return const GravitySample(x: 0, y: 1, slope: 0, pour: 0);
    }

    final gravityX = (x / magnitude).clamp(-1.0, 1.0).toDouble();
    final gravityY = (y / magnitude).clamp(-1.0, 1.0).toDouble();
    final slope = (gravityX / math.max(gravityY.abs(), 0.22))
        .clamp(-1.35, 1.35)
        .toDouble();
    final pour = (1 - gravityY.abs()).clamp(0.0, 1.0).toDouble();

    return GravitySample(
      x: gravityX,
      y: gravityY,
      slope: slope,
      pour: pour,
    );
  }
}