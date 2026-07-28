import '../models/drink.dart';

/// Paramètres visuels de l'effervescence, séparés du moteur de mouvement afin
/// de faire évoluer les bulles sans modifier le gyroscope, le vidage ou la
/// simulation mass-spring historique.
class DrinkBubbleProfile {
  const DrinkBubbleProfile({
    required this.enabled,
    required this.baseCount,
    required this.motionBoost,
    required this.minSpeed,
    required this.speedSpread,
    required this.minRadius,
    required this.radiusSpread,
    required this.horizontalDrift,
    required this.opacity,
  });

  final bool enabled;
  final int baseCount;
  final int motionBoost;
  final double minSpeed;
  final double speedSpread;
  final double minRadius;
  final double radiusSpread;
  final double horizontalDrift;
  final double opacity;

  static DrinkBubbleProfile forDrink(Drink drink) {
    switch (drink.category) {
      case 'Bières':
        return const DrinkBubbleProfile(
          enabled: true,
          baseCount: 56,
          motionBoost: 18,
          minSpeed: 0.20,
          speedSpread: 0.30,
          minRadius: 0.8,
          radiusSpread: 1.7,
          horizontalDrift: 1.4,
          opacity: 0.42,
        );
      case 'Sodas':
        return const DrinkBubbleProfile(
          enabled: true,
          baseCount: 92,
          motionBoost: 34,
          minSpeed: 0.34,
          speedSpread: 0.48,
          minRadius: 0.7,
          radiusSpread: 1.9,
          horizontalDrift: 2.5,
          opacity: 0.56,
        );
      case 'Cocktails':
        return DrinkBubbleProfile(
          enabled: drink.bubbles,
          baseCount: drink.bubbles ? 28 : 0,
          motionBoost: 12,
          minSpeed: 0.18,
          speedSpread: 0.25,
          minRadius: 0.9,
          radiusSpread: 1.5,
          horizontalDrift: 1.8,
          opacity: 0.38,
        );
      case 'Boissons chaudes':
        return const DrinkBubbleProfile(
          enabled: false,
          baseCount: 0,
          motionBoost: 0,
          minSpeed: 0,
          speedSpread: 0,
          minRadius: 0,
          radiusSpread: 0,
          horizontalDrift: 0,
          opacity: 0,
        );
      default:
        return DrinkBubbleProfile(
          enabled: drink.bubbles,
          baseCount: drink.bubbles ? 36 : 0,
          motionBoost: 14,
          minSpeed: 0.22,
          speedSpread: 0.30,
          minRadius: 0.8,
          radiusSpread: 1.6,
          horizontalDrift: 1.8,
          opacity: 0.42,
        );
    }
  }
}
