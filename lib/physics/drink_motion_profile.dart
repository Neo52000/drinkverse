import '../models/drink.dart';

class DrinkMotionProfile {
  const DrinkMotionProfile({
    required this.waveStrength,
    required this.waveSpeed,
    required this.damping,
    required this.tiltResponse,
    required this.bubbleDensity,
    required this.foamPersistence,
    required this.iceMobility,
  });

  final double waveStrength;
  final double waveSpeed;
  final double damping;
  final double tiltResponse;
  final double bubbleDensity;
  final double foamPersistence;
  final double iceMobility;

  static DrinkMotionProfile forDrink(Drink drink) {
    switch (drink.category) {
      case 'Bières':
        return const DrinkMotionProfile(
          waveStrength: 0.72,
          waveSpeed: 0.78,
          damping: 0.90,
          tiltResponse: 0.82,
          bubbleDensity: 0.92,
          foamPersistence: 0.96,
          iceMobility: 0.0,
        );
      case 'Sodas':
        return const DrinkMotionProfile(
          waveStrength: 1.18,
          waveSpeed: 1.28,
          damping: 0.82,
          tiltResponse: 1.18,
          bubbleDensity: 1.0,
          foamPersistence: 0.20,
          iceMobility: 1.0,
        );
      case 'Cocktails':
        return const DrinkMotionProfile(
          waveStrength: 1.02,
          waveSpeed: 1.05,
          damping: 0.86,
          tiltResponse: 1.0,
          bubbleDensity: 0.50,
          foamPersistence: 0.16,
          iceMobility: 0.82,
        );
      case 'Boissons chaudes':
        return const DrinkMotionProfile(
          waveStrength: 0.42,
          waveSpeed: 0.58,
          damping: 0.95,
          tiltResponse: 0.62,
          bubbleDensity: 0.06,
          foamPersistence: 0.88,
          iceMobility: 0.0,
        );
      default:
        return const DrinkMotionProfile(
          waveStrength: 0.85,
          waveSpeed: 0.9,
          damping: 0.88,
          tiltResponse: 0.9,
          bubbleDensity: 0.45,
          foamPersistence: 0.5,
          iceMobility: 0.5,
        );
    }
  }
}
