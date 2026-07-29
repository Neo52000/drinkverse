import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Façade audio du verre.
///
/// Les sons servis (`assets/audio/*.wav`) sont synthétiques (générés par
/// `tool/generate_audio_assets.py`), pas des enregistrements réels — ils
/// peuvent être remplacés à tout moment en déposant un fichier du même nom
/// dans `assets/audio/`, sans toucher à cette classe ni au moteur de
/// simulation.
class DrinkAudioService {
  DrinkAudioService._();

  static final DrinkAudioService instance = DrinkAudioService._();

  static const _pourAsset = 'audio/pour_loop.wav';
  static const _fizzAsset = 'audio/fizz_loop.wav';
  static const _refillAsset = 'audio/refill_clink.wav';
  static const _emptyAsset = 'audio/empty_glass.wav';

  final AudioPlayer _pourPlayer = AudioPlayer(playerId: 'drinkverse-pour');
  final AudioPlayer _fizzPlayer = AudioPlayer(playerId: 'drinkverse-fizz');
  final AudioPlayer _oneShotPlayer =
      AudioPlayer(playerId: 'drinkverse-oneshot');

  bool _muted = false;
  bool _pouring = false;
  bool _fizzing = false;

  // Mémorise le Future d'init plutôt qu'un simple booléen : les boucles ne
  // sont utilisables qu'une fois leur setSource() natif terminé, donc
  // startPour/startFizz attendent ce même Future avant de jouer quoi que ce
  // soit — sans ça, un premier appel arrivant avant la fin de l'init (ex.
  // juste après initState) échouait silencieusement.
  Future<void>? _initFuture;

  bool get muted => _muted;

  Future<void> initialize() {
    return _initFuture ??= _safe(() async {
      await _pourPlayer.setReleaseMode(ReleaseMode.loop);
      await _fizzPlayer.setReleaseMode(ReleaseMode.loop);
      await _pourPlayer.setSource(AssetSource(_pourAsset));
      await _fizzPlayer.setSource(AssetSource(_fizzAsset));
    });
  }

  Future<void> setMuted(bool value) async {
    _muted = value;
    if (_muted) {
      await stopAll();
    }
  }

  Future<void> startFizz({double intensity = 0.45}) async {
    if (_muted || _fizzing) return;
    _fizzing = true;
    await initialize();
    await _safe(() async {
      await _fizzPlayer.setVolume(intensity.clamp(0.0, 1.0));
      await _fizzPlayer.resume();
    });
  }

  Future<void> stopFizz() async {
    if (!_fizzing) return;
    _fizzing = false;
    await _safe(() => _fizzPlayer.pause());
  }

  Future<void> startPour({double intensity = 0.5}) async {
    if (_muted || _pouring) return;
    _pouring = true;
    await HapticFeedback.selectionClick();
    await initialize();
    await _safe(() async {
      await _pourPlayer.setVolume(intensity.clamp(0.0, 1.0));
      await _pourPlayer.resume();
    });
  }

  Future<void> updatePourIntensity(double intensity) async {
    if (!_pouring || _muted) return;
    await _safe(() => _pourPlayer.setVolume(intensity.clamp(0.0, 1.0)));
  }

  Future<void> stopPour() async {
    if (!_pouring) return;
    _pouring = false;
    await _safe(() => _pourPlayer.pause());
  }

  Future<void> playIceClink({double strength = 0.6}) async {
    if (_muted) return;
    await HapticFeedback.lightImpact();
    await _safe(
      () => _oneShotPlayer.play(
        AssetSource(_refillAsset),
        volume: strength.clamp(0.0, 1.0),
      ),
    );
  }

  Future<void> playRefill() async {
    if (_muted) return;
    await HapticFeedback.mediumImpact();
    await _safe(() => _oneShotPlayer.play(AssetSource(_refillAsset)));
  }

  Future<void> playEmptyGlass() async {
    if (_muted) return;
    await HapticFeedback.mediumImpact();
    await _safe(() => _oneShotPlayer.play(AssetSource(_emptyAsset)));
  }

  Future<void> stopAll() async {
    _pouring = false;
    _fizzing = false;
    await _safe(() => _pourPlayer.pause());
    await _safe(() => _fizzPlayer.pause());
  }

  Future<void> dispose() async {
    await stopAll();
    await _safe(() => _pourPlayer.dispose());
    await _safe(() => _fizzPlayer.dispose());
    await _safe(() => _oneShotPlayer.dispose());
  }

  /// N'interrompt jamais l'UI pour une erreur audio (le son est un bonus,
  /// pas une dépendance critique), mais journalise en mode debug — un échec
  /// totalement silencieux est invérifiable sur device.
  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('DrinkAudioService: $e');
    }
  }
}
