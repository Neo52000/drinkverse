import 'package:drinkverse/engine/drink_physics_profile.dart';
import 'package:drinkverse/engine/liquid_surface_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiquidSurfaceEngine', () {
    test('starts at rest', () {
      final engine = LiquidSurfaceEngine();

      expect(engine.surface, everyElement(0));
      expect(engine.tilt, 0);
      expect(engine.motionEnergy, 0);
    });

    test('responds to tilt without exceeding amplitude', () {
      final engine = LiquidSurfaceEngine(maxAmplitude: 60);

      for (var frame = 0; frame < 240; frame++) {
        engine.step(deltaSeconds: 1 / 60, targetTilt: 0.8);
      }

      expect(engine.surface.first, lessThan(0));
      expect(engine.surface.last, greaterThan(0));
      expect(engine.surface, everyElement(inInclusiveRange(-60, 60)));
    });

    test('localized impulse creates motion energy', () {
      final engine = LiquidSurfaceEngine();

      engine.injectImpulse(strength: 5, position: 0.25);
      engine.step(deltaSeconds: 1 / 60, targetTilt: 0);

      expect(engine.motionEnergy, greaterThan(0));
      expect(engine.surface.any((value) => value.abs() > 0), isTrue);
    });

    test('viscous profile settles faster than spirit profile', () {
      final spirit = LiquidSurfaceEngine(profile: DrinkPhysicsProfile.spirit);
      final smoothie = LiquidSurfaceEngine(profile: DrinkPhysicsProfile.smoothie);

      spirit.injectImpulse(strength: 7);
      smoothie.injectImpulse(strength: 7);

      for (var frame = 0; frame < 180; frame++) {
        spirit.step(deltaSeconds: 1 / 60, targetTilt: 0);
        smoothie.step(deltaSeconds: 1 / 60, targetTilt: 0);
      }

      final spiritAmplitude =
          spirit.surface.map((value) => value.abs()).reduce((a, b) => a + b);
      final smoothieAmplitude =
          smoothie.surface.map((value) => value.abs()).reduce((a, b) => a + b);

      expect(smoothieAmplitude, lessThan(spiritAmplitude));
    });

    test('reset clears all simulation state', () {
      final engine = LiquidSurfaceEngine();
      engine.injectImpulse(strength: 8);
      engine.step(deltaSeconds: 1 / 60, targetTilt: -0.7);

      engine.reset();

      expect(engine.surface, everyElement(0));
      expect(engine.tilt, 0);
      expect(engine.motionEnergy, 0);
    });
  });
}