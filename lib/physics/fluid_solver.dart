import 'dart:math' as math;

class FluidSolver {
  FluidSolver({this.columns = 64})
      : height = List<double>.filled(columns, 0),
        _velocity = List<double>.filled(columns, 0),
        _next = List<double>.filled(columns, 0);

  final int columns;
  final List<double> height;
  final List<double> _velocity;
  final List<double> _next;

  double slope = 0;
  double slopeVelocity = 0;
  double rotationImpulse = 0;
  double motionEnergy = 0;
  double foam = 0.085;

  void reset() {
    slope = 0;
    slopeVelocity = 0;
    rotationImpulse = 0;
    motionEnergy = 0;
    foam = 0.085;
    for (var i = 0; i < columns; i++) {
      height[i] = 0;
      _velocity[i] = 0;
      _next[i] = 0;
    }
  }

  void applyGyroscope(double x, double y, double z) {
    rotationImpulse = (z * 0.88 + y * 0.12).clamp(-14.0, 14.0).toDouble();
    final energy = math.sqrt(x * x + y * y + z * z);
    motionEnergy = math.max(
      motionEnergy,
      (energy / 7.0).clamp(0.0, 1.0).toDouble(),
    );

    final center = x >= 0 ? columns * 3 ~/ 4 : columns ~/ 4;
    final impulse = (y * 0.72 + z * 0.28).clamp(-9.0, 9.0);
    for (var i = 0; i < columns; i++) {
      final distance = i - center;
      _velocity[i] += impulse * math.exp(-(distance * distance) / 90) * 0.032;
    }
  }

  void addPourEnergy(double flow) {
    motionEnergy = math.max(motionEnergy, 0.24 + flow * 0.56);
  }

  void step({
    required double dt,
    required double targetSlope,
    required double flow,
    required double progress,
  }) {
    final acceleration = (targetSlope - slope) * 28 -
        slopeVelocity * 6.4 +
        rotationImpulse * 0.16;
    slopeVelocity += acceleration * dt;
    slope += slopeVelocity * dt;
    slope = slope.clamp(-1.45, 1.45).toDouble();

    const substeps = 6;
    final step = dt / substeps;
    for (var s = 0; s < substeps; s++) {
      for (var i = 0; i < columns; i++) {
        final x = i / (columns - 1) * 2 - 1;
        final left = height[i == 0 ? 1 : i - 1];
        final right = height[i == columns - 1 ? columns - 2 : i + 1];
        final laplacian = left + right - 2 * height[i];
        final equilibrium = x * slope * 0.42;
        final travellingWave =
            math.sin(i * 0.34 - progress * math.pi * 4.8) * motionEnergy * 0.006;
        final wallPressure = -slopeVelocity * x * x.abs() * 0.045;
        final force = laplacian * 96 +
            (equilibrium - height[i]) * 34 -
            _velocity[i] * (7.4 - motionEnergy * 1.9) +
            travellingWave +
            wallPressure;
        _velocity[i] += force * step;
        _next[i] = height[i] + _velocity[i] * step;
      }

      final mean = _next.reduce((a, b) => a + b) / columns;
      for (var i = 0; i < columns; i++) {
        height[i] = (_next[i] - mean).clamp(-0.62, 0.62).toDouble();
      }
      _velocity.first *= 0.38;
      _velocity.last *= 0.38;
    }

    final foamTarget = 0.082 + motionEnergy * 0.12 + flow * 0.055;
    foam += (foamTarget - foam) * dt * (motionEnergy > 0.16 ? 2.6 : 0.28);
    foam = foam.clamp(0.06, 0.22).toDouble();
    motionEnergy *= math.pow(0.032, dt).toDouble();
    rotationImpulse *= math.pow(0.055, dt).toDouble();
  }
}