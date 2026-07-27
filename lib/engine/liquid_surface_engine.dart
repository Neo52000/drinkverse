import 'dart:math' as math;

import 'drink_physics_profile.dart';

/// Moteur déterministe de surface liquide à ressorts couplés.
///
/// Il ne dépend ni de Flutter, ni des capteurs, ni du moteur de rendu. Les
/// entrées sont normalisées et la sortie est une liste d'offsets verticaux que
/// n'importe quel renderer peut exploiter.
class LiquidSurfaceEngine {
  LiquidSurfaceEngine({
    this.pointCount = 35,
    this.maxAmplitude = 92,
    DrinkPhysicsProfile profile = DrinkPhysicsProfile.water,
  })  : assert(pointCount >= 5),
        assert(maxAmplitude > 0),
        _profile = profile,
        _surface = List<double>.filled(pointCount, 0),
        _velocity = List<double>.filled(pointCount, 0),
        _nextSurface = List<double>.filled(pointCount, 0);

  final int pointCount;
  final double maxAmplitude;

  DrinkPhysicsProfile _profile;
  final List<double> _surface;
  final List<double> _velocity;
  final List<double> _nextSurface;

  double _tilt = 0;
  double _tiltVelocity = 0;
  double _motionEnergy = 0;

  DrinkPhysicsProfile get profile => _profile;
  List<double> get surface => List<double>.unmodifiable(_surface);
  double get tilt => _tilt;
  double get motionEnergy => _motionEnergy;

  void setProfile(DrinkPhysicsProfile value, {bool preserveMotion = true}) {
    _profile = value;
    if (!preserveMotion) reset();
  }

  /// Injecte une impulsion locale créée par un mouvement brusque ou un choc.
  void injectImpulse({
    required double strength,
    double position = 0.5,
    double radius = 0.18,
  }) {
    final safePosition = position.clamp(0.0, 1.0);
    final safeRadius = radius.clamp(0.03, 1.0);
    final center = safePosition * (pointCount - 1);
    final radiusInPoints = math.max(1.0, safeRadius * pointCount);

    for (var index = 0; index < pointCount; index++) {
      final distance = (index - center) / radiusInPoints;
      final influence = math.exp(-distance * distance * 2.4);
      _velocity[index] += strength * influence * _profile.turbulence;
    }

    _motionEnergy = math.max(
      _motionEnergy,
      (strength.abs() / 8).clamp(0.0, 1.0),
    );
  }

  /// Avance la simulation.
  ///
  /// [targetTilt] est normalisé entre -1 et 1. [deltaSeconds] est plafonné pour
  /// éviter une explosion numérique lors d'une reprise après mise en veille.
  void step({
    required double deltaSeconds,
    required double targetTilt,
    double externalEnergy = 0,
  }) {
    final dt = deltaSeconds.clamp(1 / 240, 1 / 24);
    final desiredTilt = targetTilt.clamp(-1.0, 1.0);

    final tiltAcceleration =
        (desiredTilt - _tilt) * 30 - _tiltVelocity * (7 + _profile.viscosity * 2.5);
    _tiltVelocity += tiltAcceleration * dt;
    _tilt += _tiltVelocity * dt;

    final densityFactor = 1 / math.max(_profile.density, 0.1);
    final damping = _profile.damping + _profile.viscosity * 1.8;

    for (var index = 0; index < pointCount; index++) {
      final normalizedX = index / (pointCount - 1) * 2 - 1;
      final equilibrium = normalizedX * _tilt * _profile.tiltResponse;
      final left = index == 0 ? _surface[index] : _surface[index - 1];
      final right = index == pointCount - 1 ? _surface[index] : _surface[index + 1];
      final neighborForce =
          (left + right - 2 * _surface[index]) * _profile.waveSpread;
      final springForce =
          (equilibrium - _surface[index]) * _profile.waveStiffness;
      final dampingForce = -_velocity[index] * damping;
      final acceleration =
          (neighborForce + springForce + dampingForce) * densityFactor;

      _velocity[index] += acceleration * dt;
      _nextSurface[index] =
          (_surface[index] + _velocity[index] * dt).clamp(-maxAmplitude, maxAmplitude);
    }

    for (var index = 0; index < pointCount; index++) {
      _surface[index] = _nextSurface[index];
    }

    _motionEnergy = math.max(_motionEnergy, externalEnergy.clamp(0.0, 1.0));
    _motionEnergy *= math.pow(0.972, dt * 60).toDouble();
    if (_motionEnergy < 0.0005) _motionEnergy = 0;
  }

  void reset() {
    for (var index = 0; index < pointCount; index++) {
      _surface[index] = 0;
      _velocity[index] = 0;
      _nextSurface[index] = 0;
    }
    _tilt = 0;
    _tiltVelocity = 0;
    _motionEnergy = 0;
  }
}