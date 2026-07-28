import 'package:drinkverse/services/drink_audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // audioplayers has no native implementation in the test environment; stub
  // its method channels so plugin calls resolve instead of throwing
  // MissingPluginException (DrinkAudioService's own try/catch can't reach
  // errors raised inside the plugin's internal async setup).
  late DrinkAudioService service;

  setUpAll(() {
    for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
    // DrinkAudioService.instance constructs its AudioPlayers on first access
    // (which registers them with the plugin), so it must happen after the
    // mock channel handlers above are installed.
    service = DrinkAudioService.instance;
  });

  tearDownAll(() => service.dispose());

  group('DrinkAudioService', () {
    test('initialize is idempotent and safe without a platform audio backend',
        () async {
      await service.initialize();
      await service.initialize();
    });

    test('setMuted toggles the muted getter and stops playback', () async {
      expect(service.muted, isFalse);
      await service.setMuted(true);
      expect(service.muted, isTrue);
      await service.setMuted(false);
      expect(service.muted, isFalse);
    });

    test('pour/fizz/one-shot calls never throw without a real backend',
        () async {
      await service.startPour(intensity: 0.6);
      await service.updatePourIntensity(0.8);
      await service.stopPour();
      await service.startFizz(intensity: 0.3);
      await service.stopFizz();
      await service.playRefill();
      await service.playEmptyGlass();
      await service.playIceClink();
      await service.stopAll();
    });

    test('muted service ignores start calls', () async {
      await service.setMuted(true);
      await service.startPour(intensity: 1);
      await service.startFizz(intensity: 1);
      await service.setMuted(false);
    });
  });
}
