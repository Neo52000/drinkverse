import 'package:flutter/foundation.dart';

/// Paramètres physiques indépendants du rendu.
///
/// Une boisson peut ainsi modifier son comportement sans imposer de logique
/// particulière au widget ou au moteur de rendu.
@immutable
class DrinkPhysicsProfile {
  const DrinkPhysicsProfile({
    required this.density,
    required this.viscosity,
    required this.surfaceTension,
    required this.waveStiffness,
    required this.waveSpread,
    required this.damping,
    required this.tiltResponse,
    required this.turbulence,
    required this.foamResponse,
    required this.bubbleActivity,
  })  : assert(density > 0),
        assert(viscosity >= 0),
        assert(surfaceTension >= 0),
        assert(waveStiffness > 0),
        assert(waveSpread >= 0),
        assert(damping >= 0),
        assert(tiltResponse >= 0),
        assert(turbulence >= 0),
        assert(foamResponse >= 0),
        assert(bubbleActivity >= 0);

  final double density;
  final double viscosity;
  final double surfaceTension;
  final double waveStiffness;
  final double waveSpread;
  final double damping;
  final double tiltResponse;
  final double turbulence;
  final double foamResponse;
  final double bubbleActivity;

  static const water = DrinkPhysicsProfile(
    density: 1,
    viscosity: 0.12,
    surfaceTension: 0.72,
    waveStiffness: 18,
    waveSpread: 30,
    damping: 4.1,
    tiltResponse: 56,
    turbulence: 0.68,
    foamResponse: 0.05,
    bubbleActivity: 0.02,
  );

  static const soda = DrinkPhysicsProfile(
    density: 1.04,
    viscosity: 0.18,
    surfaceTension: 0.66,
    waveStiffness: 17,
    waveSpread: 28,
    damping: 4.45,
    tiltResponse: 53,
    turbulence: 0.75,
    foamResponse: 0.42,
    bubbleActivity: 0.95,
  );

  static const beer = DrinkPhysicsProfile(
    density: 1.01,
    viscosity: 0.24,
    surfaceTension: 0.61,
    waveStiffness: 15.5,
    waveSpread: 25,
    damping: 4.9,
    tiltResponse: 49,
    turbulence: 0.62,
    foamResponse: 1,
    bubbleActivity: 0.72,
  );

  static const spirit = DrinkPhysicsProfile(
    density: 0.94,
    viscosity: 0.16,
    surfaceTension: 0.58,
    waveStiffness: 19.5,
    waveSpread: 31,
    damping: 3.8,
    tiltResponse: 59,
    turbulence: 0.82,
    foamResponse: 0,
    bubbleActivity: 0,
  );

  static const smoothie = DrinkPhysicsProfile(
    density: 1.12,
    viscosity: 0.88,
    surfaceTension: 0.83,
    waveStiffness: 11,
    waveSpread: 16,
    damping: 8.7,
    tiltResponse: 31,
    turbulence: 0.22,
    foamResponse: 0.28,
    bubbleActivity: 0,
  );

  DrinkPhysicsProfile copyWith({
    double? density,
    double? viscosity,
    double? surfaceTension,
    double? waveStiffness,
    double? waveSpread,
    double? damping,
    double? tiltResponse,
    double? turbulence,
    double? foamResponse,
    double? bubbleActivity,
  }) {
    return DrinkPhysicsProfile(
      density: density ?? this.density,
      viscosity: viscosity ?? this.viscosity,
      surfaceTension: surfaceTension ?? this.surfaceTension,
      waveStiffness: waveStiffness ?? this.waveStiffness,
      waveSpread: waveSpread ?? this.waveSpread,
      damping: damping ?? this.damping,
      tiltResponse: tiltResponse ?? this.tiltResponse,
      turbulence: turbulence ?? this.turbulence,
      foamResponse: foamResponse ?? this.foamResponse,
      bubbleActivity: bubbleActivity ?? this.bubbleActivity,
    );
  }
}