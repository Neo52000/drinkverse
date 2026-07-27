import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/drink.dart';

class DrinkGlass extends StatefulWidget {
  const DrinkGlass({
    super.key,
    required this.drink,
    this.fillLevel = 0.72,
    this.bubbles = true,
    this.condensation = true,
    this.paused = false,
  });

  final Drink drink;
  final double fillLevel;
  final bool bubbles;
  final bool condensation;
  final bool paused;

  @override
  State<DrinkGlass> createState() => _DrinkGlassState();
}

class _DrinkGlassState extends State<DrinkGlass>
    with SingleTickerProviderStateMixin {
  static const int _pointCount = 33;
  static const double _dt = 1 / 60;

  late final AnimationController _controller;
  late final List<double> _surface;
  late final List<double> _velocity;
  late final List<double> _nextSurface;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  double _targetTilt = 0;
  double _smoothedTilt = 0;
  double _tiltVelocity = 0;
  double _motionEnergy = 0;
  double _foamEnergy = 0;
  double _lastGyroMagnitude = 0;
  bool _sensorActive = false;
  DateTime _lastFeedback = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _surface = List<double>.filled(_pointCount, 0);
    _velocity = List<double>.filled(_pointCount, 0);
    _nextSurface = List<double>.filled(_pointCount, 0);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )
      ..addListener(_stepPhysics)
      ..repeat();

    _startSensors();
  }

  void _startSensors() {
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _sensorActive = true;

        // Sur Android en mode portrait, event.x augmente quand le côté gauche
        // du téléphone descend. La surface du liquide doit monter de ce côté.
        // Le signe positif corrige l'inversion observée sur le Samsung testé.
        _targetTilt = (event.x / 9.81).clamp(-1.0, 1.0);
      },
      onError: (_) => _sensorActive = false,
      cancelOnError: false,
    );

    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        final magnitude = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        ).clamp(0.0, 16.0);

        final impulse = (magnitude - _lastGyroMagnitude).abs();
        _lastGyroMagnitude = magnitude;

        final normalized = (magnitude / 7.5).clamp(0.0, 1.0);
        _motionEnergy = math.max(_motionEnergy, normalized);
        _foamEnergy = math.max(
          _foamEnergy,
          (normalized * 1.25).clamp(0.0, 1.0),
        );

        final direction = (event.y * 0.85 + event.z * 0.35).clamp(-8.0, 8.0);
        _injectImpulse(direction * 0.48, event.x);

        if ((widget.drink.ice && impulse > 1.2) ||
            (widget.drink.foam && impulse > 2.0)) {
          _playMotionFeedback();
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _injectImpulse(double strength, double lateralAxis) {
    final center = lateralAxis >= 0 ? _pointCount * 2 ~/ 3 : _pointCount ~/ 3;
    for (var i = 0; i < _pointCount; i++) {
      final distance = (i - center).toDouble();
      final influence = math.exp(-(distance * distance) / 34);
      _velocity[i] += strength * influence;
    }
  }

  void _playMotionFeedback() {
    final now = DateTime.now();
    if (now.difference(_lastFeedback).inMilliseconds < 380) return;
    _lastFeedback = now;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void _stepPhysics() {
    if (!mounted || widget.paused) return;

    final fallback = math.sin(_controller.value * math.pi * 2) * 0.008;
    final desiredTilt = _sensorActive ? _targetTilt : fallback;

    // Filtre ressort pour éviter l'effet "capteur collé".
    final tiltAcceleration = (desiredTilt - _smoothedTilt) * 30 -
        _tiltVelocity * 8.2;
    _tiltVelocity += tiltAcceleration * _dt;
    _smoothedTilt += _tiltVelocity * _dt;

    // Surface discrétisée : ressort vertical + couplage entre voisins.
    for (var i = 0; i < _pointCount; i++) {
      final normalizedX = i / (_pointCount - 1) * 2 - 1;
      final equilibrium = normalizedX * _smoothedTilt * 54;
      final left = i == 0 ? _surface[i] : _surface[i - 1];
      final right = i == _pointCount - 1 ? _surface[i] : _surface[i + 1];

      final neighborForce = (left + right - 2 * _surface[i]) * 29;
      final springForce = (equilibrium - _surface[i]) * 17;
      final dampingForce = -_velocity[i] * 4.25;
      final acceleration = neighborForce + springForce + dampingForce;

      _velocity[i] += acceleration * _dt;
      _nextSurface[i] = _surface[i] + _velocity[i] * _dt;
    }

    for (var i = 0; i < _pointCount; i++) {
      _surface[i] = _nextSurface[i];
    }

    _motionEnergy *= 0.974;
    _foamEnergy *= 0.989;
    if (_motionEnergy < 0.001) _motionEnergy = 0;
    if (_foamEnergy < 0.001) _foamEnergy = 0;

    setState(() {});
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _controller
      ..removeListener(_stepPhysics)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(286, 410),
        painter: DrinkGlassPainter(
          drink: widget.drink,
          progress: _controller.value,
          surface: List<double>.unmodifiable(_surface),
          motionEnergy: _motionEnergy,
          foamEnergy: _foamEnergy,
          fillLevel: widget.fillLevel,
          bubbles: widget.bubbles,
          condensation: widget.condensation,
        ),
      ),
    );
  }
}

class DrinkGlassPainter extends CustomPainter {
  DrinkGlassPainter({
    required this.drink,
    required this.progress,
    required this.surface,
    required this.motionEnergy,
    required this.foamEnergy,
    required this.fillLevel,
    required this.bubbles,
    required this.condensation,
  });

  final Drink drink;
  final double progress;
  final List<double> surface;
  final double motionEnergy;
  final double foamEnergy;
  final double fillLevel;
  final bool bubbles;
  final bool condensation;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTWH(22, 10, size.width - 44, size.height - 30);
    final glass = RRect.fromRectAndRadius(body, const Radius.circular(52));
    final inner = glass.deflate(9);

    _drawShadow(canvas, glass);
    _drawRearGlass(canvas, glass);

    canvas.save();
    canvas.clipRRect(inner);
    _drawLiquid(canvas, size, inner);
    if (drink.ice) _drawIce(canvas, size, inner);
    if (bubbles) _drawBubbles(canvas, size, inner);
    if (drink.foam) _drawFoam(canvas, size, inner);
    _drawLightRays(canvas, size, inner);
    if (condensation) _drawCondensation(canvas, inner);
    canvas.restore();

    _drawFrontGlass(canvas, glass, body);
    _drawBase(canvas, size);
  }

  double _baseTop(Size size) {
    final usable = size.height - 88;
    return 42 + usable * (1 - fillLevel.clamp(0.30, 0.96));
  }

  double _surfaceAt(double x, RRect inner, Size size) {
    final ratio = ((x - inner.left) / inner.width).clamp(0.0, 1.0);
    final scaled = ratio * (surface.length - 1);
    final low = scaled.floor().clamp(0, surface.length - 1);
    final high = math.min(low + 1, surface.length - 1);
    final interpolation = scaled - low;
    final displacement =
        surface[low] * (1 - interpolation) + surface[high] * interpolation;
    final microWave = math.sin(
          ratio * math.pi * 7 + progress * math.pi * 2.2,
        ) *
        (0.45 + motionEnergy * 2.2);
    return _baseTop(size) + displacement + microWave;
  }

  Path _liquidPath(Size size, RRect inner) {
    final path = Path();
    const segments = 90;
    for (var i = 0; i <= segments; i++) {
      final x = inner.left + inner.width * i / segments;
      final y = _surfaceAt(x, inner, size);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path
      ..lineTo(inner.right, inner.bottom)
      ..lineTo(inner.left, inner.bottom)
      ..close();
  }

  void _drawShadow(Canvas canvas, RRect glass) {
    canvas.drawRRect(
      glass.shift(const Offset(0, 14)),
      Paint()
        ..color = drink.color.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(glass.center.dx, glass.bottom + 13),
        width: glass.width * 0.76,
        height: 28,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );
  }

  void _drawRearGlass(Canvas canvas, RRect glass) {
    canvas.drawRRect(
      glass,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, 0.14, 0.48, 0.82, 1],
          colors: [
            Color(0x70FFFFFF),
            Color(0x16000000),
            Color(0x05000000),
            Color(0x24000000),
            Color(0x58FFFFFF),
          ],
        ).createShader(glass.outerRect),
    );
  }

  void _drawLiquid(Canvas canvas, Size size, RRect inner) {
    final path = _liquidPath(size, inner);
    final top = _baseTop(size);

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.12, 0.40, 0.72, 1],
          colors: [
            Color.lerp(drink.color, Colors.white, 0.38)!,
            Color.lerp(drink.color, Colors.white, 0.13)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.22)!,
            Color.lerp(drink.color, Colors.black, 0.50)!,
          ],
        ).createShader(
          Rect.fromLTWH(
            inner.left,
            top - 45,
            inner.width,
            inner.bottom - top + 45,
          ),
        ),
    );

    final surfacePath = Path();
    const segments = 90;
    for (var i = 0; i <= segments; i++) {
      final x = inner.left + inner.width * i / segments;
      final y = _surfaceAt(x, inner, size);
      i == 0 ? surfacePath.moveTo(x, y) : surfacePath.lineTo(x, y);
    }

    canvas.drawPath(
      surfacePath,
      Paint()
        ..color = Color.lerp(drink.color, Colors.white, 0.60)!
            .withValues(alpha: 0.94)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
    );
  }

  void _drawFoam(Canvas canvas, Size size, RRect inner) {
    final layers = 2 + (foamEnergy * 4).round();
    for (var layer = 0; layer < layers; layer++) {
      final count = 25 + layer * 4;
      for (var i = 0; i < count; i++) {
        final ratio = (i + 0.5) / count;
        final x = inner.left + ratio * inner.width;
        final y = _surfaceAt(x, inner, size) - 2 - layer * 5.1;
        final radius = 3.2 + ((i * 19 + layer * 7) % 5) * 0.75;
        canvas.drawCircle(
          Offset(x + 1, y + 2),
          radius,
          Paint()..color = const Color(0xFFC49457).withValues(alpha: 0.25),
        );
        canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()..color = const Color(0xFFF9EBCF).withValues(alpha: 0.96),
        );
        if ((i + layer) % 4 == 0) {
          canvas.drawCircle(
            Offset(x - radius * 0.25, y - radius * 0.3),
            radius * 0.22,
            Paint()..color = Colors.white.withValues(alpha: 0.82),
          );
        }
      }
    }
  }

  void _drawBubbles(Canvas canvas, Size size, RRect inner) {
    final top = _baseTop(size);
    final count = 34 + (motionEnergy * 18).round();
    for (var i = 0; i < count; i++) {
      final seed = i * 97;
      final xRatio = ((seed % 101) / 101.0);
      final speed = 0.32 + (i % 7) * 0.07;
      final cycle = (progress * speed * 10 + i * 0.071) % 1;
      final x = inner.left + 8 + xRatio * (inner.width - 16) +
          math.sin(progress * math.pi * 2 + i) * 2.5;
      final y = inner.bottom - 12 - cycle * (inner.bottom - top - 18);
      final radius = 1.2 + (i % 6) * 0.58;

      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.44)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
      canvas.drawCircle(
        Offset(x - radius * 0.25, y - radius * 0.25),
        math.max(0.45, radius * 0.22),
        Paint()..color = Colors.white.withValues(alpha: 0.60),
      );
    }
  }

  void _drawIce(Canvas canvas, Size size, RRect inner) {
    for (var i = 0; i < 5; i++) {
      final ratio = (i + 1) / 6;
      final x = inner.left + inner.width * ratio;
      final surfaceY = _surfaceAt(x, inner, size);
      final y = surfaceY + 25 + (i % 2) * 24 + motionEnergy * (i - 2) * 4;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((i - 2) * 0.15 + surface[i * 5] * 0.004);
      final cube = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-16, -16, 32, 32),
        const Radius.circular(7),
      );
      canvas.drawRRect(
        cube,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x88FFFFFF), Color(0x18FFFFFF), Color(0x55BDEBFF)],
          ).createShader(cube.outerRect),
      );
      canvas.drawRRect(
        cube,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      canvas.restore();
    }
  }

  void _drawLightRays(Canvas canvas, Size size, RRect inner) {
    final top = _baseTop(size);
    for (var i = 0; i < 5; i++) {
      final x = inner.left + 26 + i * 38.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top + 14, 9, inner.bottom - top - 36),
          const Radius.circular(5),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.035 + (i % 2) * 0.018)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  void _drawCondensation(Canvas canvas, RRect inner) {
    for (var i = 0; i < 28; i++) {
      final x = inner.left + 12 + ((i * 47) % 205).toDouble();
      final y = inner.top + 25 + ((i * 73) % 310).toDouble();
      final radius = 1.2 + (i % 4) * 0.72;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
      if (i % 6 == 0) {
        canvas.drawLine(
          Offset(x, y + radius),
          Offset(x, y + radius + 6 + i % 10),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.08)
            ..strokeWidth = radius,
        );
      }
    }
  }

  void _drawFrontGlass(Canvas canvas, RRect glass, Rect body) {
    canvas.drawRRect(
      glass,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.33)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawRRect(
      glass.deflate(5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.09)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawLine(
      Offset(body.left + 35, body.top + 39),
      Offset(body.left + 35, body.bottom - 66),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBase(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(51, size.height - 43, size.width - 102, 15),
        const Radius.circular(8),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x66FFFFFF), Color(0x10000000), Color(0x55FFFFFF)],
        ).createShader(Rect.fromLTWH(51, size.height - 43, size.width - 102, 15)),
    );
  }

  @override
  bool shouldRepaint(covariant DrinkGlassPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.drink != drink ||
        oldDelegate.surface != surface ||
        oldDelegate.motionEnergy != motionEnergy ||
        oldDelegate.foamEnergy != foamEnergy ||
        oldDelegate.fillLevel != fillLevel ||
        oldDelegate.bubbles != bubbles ||
        oldDelegate.condensation != condensation;
  }
}
