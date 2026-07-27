import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Moteur audio autonome de DrinkVerse.
///
/// Les premiers sons sont générés en mémoire afin que le projet reste
/// compilable sans fichiers audio externes. Ils seront ensuite remplacés ou
/// complétés par des enregistrements studio libres de droits.
class DrinkAudioService {
  DrinkAudioService._();

  static final DrinkAudioService instance = DrinkAudioService._();

  final AudioPlayer _ambientPlayer = AudioPlayer();
  final AudioPlayer _actionPlayer = AudioPlayer();
  final AudioPlayer _impactPlayer = AudioPlayer();

  bool _initialized = false;
  bool _muted = false;
  bool _pouring = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _ambientPlayer.setReleaseMode(ReleaseMode.loop);
    await _actionPlayer.setReleaseMode(ReleaseMode.stop);
    await _impactPlayer.setReleaseMode(ReleaseMode.stop);
  }

  bool get muted => _muted;

  Future<void> setMuted(bool value) async {
    _muted = value;
    if (_muted) {
      await stopAll();
    }
  }

  Future<void> startFizz({double intensity = 0.45}) async {
    await initialize();
    if (_muted) return;

    final bytes = _buildNoiseWave(
      durationSeconds: 2.2,
      volume: 0.08 + intensity.clamp(0.0, 1.0) * 0.14,
      highPassBias: 0.72,
      pulseRate: 19,
    );

    await _ambientPlayer.stop();
    await _ambientPlayer.setVolume(0.22 + intensity * 0.25);
    await _ambientPlayer.play(BytesSource(bytes));
  }

  Future<void> stopFizz() async {
    await _ambientPlayer.stop();
  }

  Future<void> startPour({double intensity = 0.5}) async {
    await initialize();
    if (_muted || _pouring) return;
    _pouring = true;

    final bytes = _buildNoiseWave(
      durationSeconds: 1.4,
      volume: 0.16 + intensity.clamp(0.0, 1.0) * 0.18,
      highPassBias: 0.38,
      pulseRate: 8,
    );

    await _actionPlayer.setReleaseMode(ReleaseMode.loop);
    await _actionPlayer.setVolume(0.35 + intensity * 0.35);
    await _actionPlayer.play(BytesSource(bytes));
  }

  Future<void> updatePourIntensity(double intensity) async {
    if (!_pouring || _muted) return;
    await _actionPlayer.setVolume(0.28 + intensity.clamp(0.0, 1.0) * 0.55);
  }

  Future<void> stopPour() async {
    if (!_pouring) return;
    _pouring = false;
    await _actionPlayer.stop();
    await _actionPlayer.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> playIceClink({double strength = 0.6}) async {
    await initialize();
    if (_muted) return;

    final bytes = _buildToneWave(
      durationSeconds: 0.18,
      frequency: 1180 + strength.clamp(0.0, 1.0) * 620,
      volume: 0.38,
      decay: 18,
      overtones: const [1.0, 1.71, 2.36],
    );

    await _impactPlayer.stop();
    await _impactPlayer.setVolume(0.28 + strength * 0.42);
    await _impactPlayer.play(BytesSource(bytes));
  }

  Future<void> playRefill() async {
    await initialize();
    if (_muted) return;

    final bytes = _buildNoiseWave(
      durationSeconds: 1.15,
      volume: 0.24,
      highPassBias: 0.24,
      pulseRate: 5,
      fadeIn: true,
    );

    await _actionPlayer.stop();
    await _actionPlayer.setReleaseMode(ReleaseMode.stop);
    await _actionPlayer.setVolume(0.62);
    await _actionPlayer.play(BytesSource(bytes));
  }

  Future<void> playEmptyGlass() async {
    await initialize();
    if (_muted) return;

    final bytes = _buildToneWave(
      durationSeconds: 0.28,
      frequency: 620,
      volume: 0.32,
      decay: 9,
      overtones: const [1.0, 1.5, 2.05],
    );

    await _impactPlayer.stop();
    await _impactPlayer.setVolume(0.48);
    await _impactPlayer.play(BytesSource(bytes));
  }

  Future<void> stopAll() async {
    _pouring = false;
    await Future.wait([
      _ambientPlayer.stop(),
      _actionPlayer.stop(),
      _impactPlayer.stop(),
    ]);
  }

  Future<void> dispose() async {
    await Future.wait([
      _ambientPlayer.dispose(),
      _actionPlayer.dispose(),
      _impactPlayer.dispose(),
    ]);
  }

  Uint8List _buildNoiseWave({
    required double durationSeconds,
    required double volume,
    required double highPassBias,
    required double pulseRate,
    bool fadeIn = false,
  }) {
    const sampleRate = 22050;
    final sampleCount = (sampleRate * durationSeconds).round();
    final random = math.Random(52000 + sampleCount);
    final samples = Int16List(sampleCount);
    var previous = 0.0;

    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final raw = random.nextDouble() * 2 - 1;
      final highPassed = raw - previous * highPassBias;
      previous = raw;

      final pulse = 0.58 + 0.42 * math.sin(t * math.pi * 2 * pulseRate).abs();
      final fadeOut = math.pow(1 - i / sampleCount, 0.22).toDouble();
      final fadeInGain = fadeIn ? math.min(1.0, t / 0.18) : 1.0;
      final sample = highPassed * pulse * fadeOut * fadeInGain * volume;
      samples[i] = (sample.clamp(-1.0, 1.0) * 32767).round();
    }

    return _encodePcm16Wav(samples, sampleRate);
  }

  Uint8List _buildToneWave({
    required double durationSeconds,
    required double frequency,
    required double volume,
    required double decay,
    required List<double> overtones,
  }) {
    const sampleRate = 22050;
    final sampleCount = (sampleRate * durationSeconds).round();
    final samples = Int16List(sampleCount);

    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final envelope = math.exp(-decay * t);
      var value = 0.0;
      for (var harmonic = 0; harmonic < overtones.length; harmonic++) {
        value += math.sin(2 * math.pi * frequency * overtones[harmonic] * t) /
            (harmonic + 1);
      }
      value = value / overtones.length * envelope * volume;
      samples[i] = (value.clamp(-1.0, 1.0) * 32767).round();
    }

    return _encodePcm16Wav(samples, sampleRate);
  }

  Uint8List _encodePcm16Wav(Int16List samples, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final dataLength = samples.length * 2;
    final bytes = ByteData(44 + dataLength);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    bytes.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return bytes.buffer.asUint8List();
  }
}
