import 'dart:math' as math;

import 'drink_motion_profile.dart';

class FluidSolver {
  FluidSolver({this.columns = 64})
      : height = List<double>.filled(columns, 0),
        _velocity = List<double>.filled(columns, 0),
        _next = List<double>.filled(columns, 0),
        _nextVelocity = List<double>.filled(columns, 0);

  final int columns;
  final List<double> height;
  final List<double> _velocity;
  final List<double> _next;
  final List<double> _nextVelocity;

  double slope = 0;
  double slopeVelocity = 0;
  double rotationImpulse = 0;
  double motionEnergy = 0;
  double foam = 0.085;

  // Lissage des impulsions gyroscope : évite qu'un event capteur se traduise
  // en à-coup instantané, la cible est approchée progressivement à la place.
  double _pendingPush = 0;

  // Surplus de mousse juste après un service, qui retombe lentement (~30s)
  // vers le niveau de base au lieu d'y converger quasi instantanément.
  double _foamBoost = 0;

  // Facteurs d'échelle par boisson (voir applyMotionProfile) : 1.0 tant
  // qu'aucun profil n'a été appliqué, donc le comportement par défaut est
  // inchangé pour tout code qui n'utilise pas cette fonctionnalité.
  double _forceScale = 1;
  double _propagationScale = 1;
  double _dampingScale = 1;
  double _tiltScale = 1;
  double _foamScale = 1;

  // Le tuning V7.3 (vagues) et la décroissance de mousse ont été validés en
  // prenant le profil "Bières" comme référence. Les facteurs d'échelle sont
  // donc des ratios par rapport à ces valeurs — pour la bière ils valent
  // exactement 1.0, donc son comportement ne change jamais.
  static const _beerWaveStrength = 0.72;
  static const _beerWaveSpeed = 0.78;
  static const _beerDamping = 0.90;
  static const _beerTiltResponse = 0.82;
  static const _beerFoamPersistence = 0.96;

  /// Applique les paramètres physiques d'une boisson sans recréer
  /// l'instance (le [height] existant reste la même liste, ce qui compte
  /// pour DrinkVessel qui en garde une vue non-copiante).
  void applyMotionProfile(DrinkMotionProfile profile) {
    _forceScale = profile.waveStrength / _beerWaveStrength;
    _propagationScale = profile.waveSpeed / _beerWaveSpeed;
    _dampingScale = profile.damping / _beerDamping;
    _tiltScale = profile.tiltResponse / _beerTiltResponse;
    _foamScale = profile.foamPersistence / _beerFoamPersistence;
  }

  void reset() {
    slope = 0;
    slopeVelocity = 0;
    rotationImpulse = 0;
    motionEnergy = 0;
    foam = 0.085;
    _pendingPush = 0;
    _foamBoost = 0;
    for (var i = 0; i < columns; i++) {
      height[i] = 0;
      _velocity[i] = 0;
      _next[i] = 0;
      _nextVelocity[i] = 0;
    }
  }

  void applyGyroscope(double x, double y, double z) {
    final targetImpulse = (z * 0.88 + y * 0.12).clamp(-14.0, 14.0).toDouble();
    rotationImpulse += (targetImpulse - rotationImpulse) * 0.4;

    final energy = math.sqrt(x * x + y * y + z * z);
    motionEnergy = math.max(
      motionEnergy,
      (energy / 7.0).clamp(0.0, 1.0).toDouble(),
    );

    final center = x >= 0 ? columns * 3 ~/ 4 : columns ~/ 4;
    final targetPush = (y * 0.72 + z * 0.28).clamp(-9.0, 9.0);
    _pendingPush += (targetPush - _pendingPush) * 0.4;
    final spread = math.max(columns * 0.035, 1.0);
    for (var i = 0; i < columns; i++) {
      final distance = (i - center) / spread;
      _velocity[i] +=
          _pendingPush * math.exp(-(distance * distance) * 0.5) * 0.032;
    }
  }

  void addPourEnergy(double flow) {
    motionEnergy = math.max(motionEnergy, 0.24 + flow * 0.56);
    _foamBoost = math.max(_foamBoost, 0.6);
  }

  void step({
    required double dt,
    required double targetSlope,
    required double flow,
    required double progress,
  }) {
    final acceleration = ((targetSlope - slope) * 19.5 -
            slopeVelocity * 4.6 +
            rotationImpulse * 0.17) *
        _tiltScale;
    slopeVelocity += acceleration * dt;
    slope += slopeVelocity * dt;
    slope = slope.clamp(-1.45, 1.45).toDouble();

    const substeps = 7;
    final step = dt / substeps;
    for (var s = 0; s < substeps; s++) {
      for (var i = 0; i < columns; i++) {
        final x = i / (columns - 1) * 2 - 1;
        final leftIndex = i == 0 ? 1 : i - 1;
        final rightIndex = i == columns - 1 ? columns - 2 : i + 1;
        final left = height[leftIndex];
        final right = height[rightIndex];
        final laplacian = left + right - 2 * height[i];
        final velocityLaplacian =
            _velocity[leftIndex] + _velocity[rightIndex] - 2 * _velocity[i];

        final equilibrium = x * slope * 0.42;
        final primaryWave =
            math.sin(i * 0.24 - progress * math.pi * 4.2) * motionEnergy * 0.0045;
        final secondaryWave =
            math.sin(i * 0.51 + progress * math.pi * 2.7) * motionEnergy * 0.0018;
        final edgeWeight = x.abs() * x.abs();
        final wallPressure = -slopeVelocity * x * edgeWeight * 0.050;
        final restoring = (equilibrium - height[i]) * 21;
        // Damping adaptatif : une petite vague (vitesse et énergie faibles)
        // s'éteint lentement, une grosse vague perd davantage d'énergie.
        final speed = _velocity[i].abs();
        final damping = _velocity[i] *
            (1.6 + motionEnergy * 4.4 + speed * 0.9) *
            _dampingScale;

        final force = laplacian * 112 * _forceScale +
            velocityLaplacian * 4.8 * _propagationScale +
            restoring * _forceScale -
            damping +
            (primaryWave + secondaryWave) * _forceScale +
            wallPressure * _forceScale;

        _nextVelocity[i] = _velocity[i] + force * step;
        _next[i] = height[i] + _nextVelocity[i] * step;
      }

      double sum = 0;
      for (var i = 0; i < columns; i++) {
        sum += _next[i];
      }
      final mean = sum / columns;

      // Le clamp ci-dessous peut saturer certaines colonnes et faire dériver
      // le volume total ; la seconde passe redistribue l'écart résiduel pour
      // que le volume du liquide reste exactement constant.
      double clampedSum = 0;
      for (var i = 0; i < columns; i++) {
        _velocity[i] = _nextVelocity[i];
        final h = (_next[i] - mean).clamp(-0.58, 0.58).toDouble();
        height[i] = h;
        clampedSum += h;
      }
      final volumeError = clampedSum / columns;
      if (volumeError != 0) {
        for (var i = 0; i < columns; i++) {
          height[i] -= volumeError;
        }
      }

      // Légère perte d'énergie aux parois seulement : la vague rebondit au
      // lieu d'être absorbée (la condition de bord du Laplacien assure déjà
      // la réflexion, cette ligne ne fait que dissiper un peu d'énergie).
      const wallEnergyRetention = 0.985;
      _velocity.first *= wallEnergyRetention;
      _velocity.last *= wallEnergyRetention;

      // A light capillary pass removes the digital saw-tooth effect while
      // preserving the larger inertial wave.
      for (var i = 1; i < columns - 1; i++) {
        _next[i] = height[i] * 0.82 +
            (height[i - 1] + height[i + 1]) * 0.09;
      }
      for (var i = 1; i < columns - 1; i++) {
        height[i] = _next[i];
      }
    }

    final foamTarget =
        0.082 + motionEnergy * 0.12 + flow * 0.055 + _foamBoost * 0.30;
    foam += (foamTarget - foam) * dt * (motionEnergy > 0.16 ? 2.6 : 0.28);
    foam = foam.clamp(0.06, 0.22).toDouble();
    motionEnergy *= math.pow(0.038, dt).toDouble();
    rotationImpulse *= math.pow(0.060, dt).toDouble();
    // Demi-vie ≈ 30s pour la bière (référence) : la tête de mousse retombe
    // progressivement après un service au lieu de se stabiliser en moins
    // d'une seconde. _foamScale étire/compresse cette durée par boisson.
    _foamBoost *= math.pow(0.977, dt / _foamScale).toDouble();
  }
}
