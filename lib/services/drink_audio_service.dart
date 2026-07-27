import 'package:flutter/services.dart';

/// Façade audio temporaire, sans plugin natif externe.
///
/// Cette version garantit la compilation Android avec la configuration Gradle
/// actuelle. Les méthodes restent stables afin de pouvoir brancher ensuite un
/// moteur audio natif dédié sans modifier le moteur de simulation.
class DrinkAudioService {
  DrinkAudioService._();

  static final DrinkAudioService instance = DrinkAudioService._();

  bool _muted = false;
  bool _pouring = false;

  bool get muted => _muted;

  Future<void> initialize() async {}

  Future<void> setMuted(bool value) async {
    _muted = value;
    if (_muted) {
      await stopAll();
    }
  }

  Future<void> startFizz({double intensity = 0.45}) async {
    if (_muted) return;
  }

  Future<void> stopFizz() async {}

  Future<void> startPour({double intensity = 0.5}) async {
    if (_muted || _pouring) return;
    _pouring = true;
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.selectionClick();
  }

  Future<void> updatePourIntensity(double intensity) async {}

  Future<void> stopPour() async {
    _pouring = false;
  }

  Future<void> playIceClink({double strength = 0.6}) async {
    if (_muted) return;
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.lightImpact();
  }

  Future<void> playRefill() async {
    if (_muted) return;
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.mediumImpact();
  }

  Future<void> playEmptyGlass() async {
    if (_muted) return;
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.mediumImpact();
  }

  Future<void> stopAll() async {
    _pouring = false;
  }

  Future<void> dispose() async {
    _pouring = false;
  }
}
