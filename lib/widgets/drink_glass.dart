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
  static const int _pointCount = 29;

  late final AnimationController _controller;
  late final List<double> _surface;
  late final List<double> _velocity;
  late final List<double> _nextSurface;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  double _targetTilt = 0;
  double _smoothedTilt = 0;
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
      duration: const Duration(seconds: 8),
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
        _targetTilt = (-event.x / 9.81).clamp(-1.0, 1.0);
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
        ).clamp(0.0, 15.0);
        final impulse = (magnitude - _lastGyroMagnitude).abs();
        _lastGyroMagnitude = magnitude;

        final normalized = (magnitude / 8).clamp(0.0, 1.0);
        _motionEnergy = math.max(_motionEnergy, normalized);
        _foamEnergy = math.max(_foamEnergy, (normalized * 1.18).clamp(0.0, 1.0));

        final direction = (event.y * 0.8 + event.z * 0.35).clamp(-7.0, 7.0);
        _injectImpulse(direction * 0.42, event.x);

        if ((widget.drink.ice && impulse > 1.25) ||
            (widget.drink.foam && impulse > 2.1)) {
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
      final distance = (i - center).abs();
      final influence = math.exp(-distance * distance / 28);
      _velocity[i] += strength * influence;
    }
  }

  void _playMotionFeedback() {
    final now = DateTime.now();
    if (now.difference(_lastFeedback).inMilliseconds < 360) return;
    _lastFeedback = now;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void _stepPhysics() {
    if (!mounted || widget.paused) return;

    const dt = 1 / 60;
    final fallback = math.sin(_controller.value * math.pi * 2) * 0.012;
    final desiredTilt = _sensorActive ? _targetTilt : fallback;
    _smoothedTilt += (desiredTilt - _smoothedTilt) * 0.10;

    // Surface discrétisée : chaque point est relié à ses voisins et à une
    // position d'équilibre inclinée. Ce modèle produit des rebonds locaux,
    // une propagation des vagues et une inertie plus crédible.
    for (var i = 0; i < _pointCount; i++) {
      final normalizedX = i / (_pointCount - 1) * 2 - 1;
      final equilibrium = normalizedX * _smoothedTilt * 48;
      final left = i == 0 ? _surface[i] : _surface[i - 1];
      final right = i == _pointCount - 1 ? _surface[i] : _surface[i + 1];
      final neighborForce = (left + right - 2 * _surface[i]) * 25;
      final springForce = (equilibrium - _surface[i]) * 18;
      final dampingForce = -_velocity[i] * 4.6;
      final acceleration = neighborForce + springForce + dampingForce;
      _velocity[i] += acceleration * dt;
      _nextSurface[i] = _surface[i] + _velocity[i] * dt;
    }

    for (var i = 0; i < _pointCount; i++) {
      _surface[i] = _nextSurface[i];
    }

    _motionEnergy *= 0.972;
    _foamEnergy *= 0.988;
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

    _drawAmbientShadow(canvas, glass);
    _drawRearGlass(canvas, glass);

    canvas.save();
    canvas.clipRRect(inner);
    _drawLiquid(canvas, size, inner);
    if (drink.ice) _drawIce(canvas, size, inner);
    if (bubbles) _drawBubbles(canvas, size, inner);
    if (drink.foam) _drawFoam(canvas, size, inner);
    _drawLiquidCaustics(canvas, size, inner);
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
    final t = scaled - low;
    final displacement = surface[low] * (1 - t) + surface[high] * t;
    final microWave = math.sin(ratio * math.pi * 6 + progress * math.pi * 2.4) *
        (0.6 + motionEnergy * 2.5);
    return _baseTop(size) + displacement + microWave;
  }

  Path _liquidPath(Size size, RRect inner) {
    final path = Path();
    const segments = 84;
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

  void _drawAmbientShadow(Canvas canvas, RRect glass) {
    canvas.drawRRect(
      glass.shift(const Offset(0, 13)),
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
          stops: const [0, 0.13, 0.42, 0.72, 1],
          colors: [
            Color.lerp(drink.color, Colors.white, 0.35)!,
            Color.lerp(drink.color, Colors.white, 0.12)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.22)!,
            Color.lerp(drink.color, Colors.black, 0.50)!,
          ],
        ).createShader(
          Rect.fromLTWH(inner.left, top - 45, inner.width, inner.bottom - top + 45),
        ),
    );

    final surfacePath = Path();
    const segments = 84;
    for (var i = 0; i <= segments; i++) {
      final x = inner.left + inner.width * i / segments;
      final y = _surfaceAt(x, inner, size);
      i == 0 ? surfacePath.moveTo(x, y) : surfacePath.lineTo(x, y);
    }
    canvas.drawPath(
      surfacePath,
      Paint()
        ..color = Color.lerp(drink.color, Colors.white, 0.58)!
            .withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
    );
  }

  void _drawFoam(Canvas canvas, Size size, RRect inner) {
    final layers = 2 + (foamEnergy * 3).round();
    final foamBase = Paint()
      ..color = const Color(0xFFF9EACB).withValues(alpha: 0.97);
    final foamShade = Paint()
      ..color = const Color(0xFFC59A5F).withValues(alpha: 0.30);

    for (var layer = 0; layer < layers; layer++) {
      final count = 25 + layer * 5;
      for (var i = 0; i < count; i++) {
        final ratio = (i + 0.5) / count;
        final x = inner.left + 4 + ratio * (inner.width - 8);
        final surfaceY = _surfaceAt(x, inner, size);
        final randomWave = math.sin(i * 2.17 + layer * 1.9 + progress * 4) * 2;
        final y = surfaceY - 3 - layer * 7 + randomWave;
        final radius = 3.2 + ((i * 13 + layer * 7) % 6) * 0.72 + foamEnergy;
        canvas.drawCircle(Offset(x + 1, y + 2), radius, foamShade);
        canvas.drawCircle(Offset(x, y), radius, foamBase);
        if ((i + layer) % 5 == 0) {
          canvas.drawCircle(
            Offset(x - radius * 0.27, y - radius * 0.3),
            radius * 0.23,
            Paint()..color = Colors.white.withValues(alpha: 0.85),
          );
        }
      }
    }
  }

  void _drawBubbles(Canvas canvas, Size size, RRect inner) {
    final count = 42 + (motionEnergy * 30).round();
    for (var i = 0; i < count; i++) {
      final seedX = ((i * 47) % 997) / 997;
      final speed = 0.28 + (i % 7) * 0.075;
      final cycle = (progress * speed * 8 + i * 0.071) % 1;
      final x = inner.left + 10 + seedX * (inner.width - 20) +
          math.sin(cycle * math.pi * 2 + i) * (2 + motionEnergy * 5);
      final surfaceY = _surfaceAt(x, inner, size);
      final y = inner.bottom - 12 - cycle * (inner.bottom - surfaceY - 14);
      final radius = 1.2 + (i % 6) * 0.65;
      final alpha = 0.30 + (i % 4) * 0.12;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
      if (radius > 3.1) {
        canvas.drawCircle(
          Offset(x - radius * 0.25, y - radius * 0.3),
          radius * 0.24,
          Paint()..color = Colors.white.withValues(alpha: 0.72),
        );
      }
    }
  }

  void _drawIce(Canvas canvas, Size size, RRect inner) {
    for (var i = 0; i < 5; i++) {
      final ratio = (i + 1) / 6;
      final x = inner.left + inner.width * ratio + surface[i * 5] * 0.35;
      final y = _surfaceAt(x, inner, size) + 25 + (i % 2) * 22;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((i - 2) * 0.16 + surface[i * 5] * 0.008);
      final cube = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-15, -15, 30, 30),
        const Radius.circular(7),
      );
      canvas.drawRRect(
        cube,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x99FFFFFF), Color(0x22FFFFFF), Color(0x66BDE8FF)],
          ).createShader(cube.outerRect),
      );
      canvas.drawRRect(
        cube,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      canvas.restore();
    }
  }

  void _drawLiquidCaustics(Canvas canvas, Size size, RRect inner) {
    for (var i = 0; i < 7; i++) {
      final x = inner.left + 20 + i * (inner.width - 40) / 6;
      final top = _surfaceAt(x, inner, size) + 15;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x + math.sin(progress * 6 + i) * 8, top + 80 + i * 24),
          width: 30 + i % 3 * 12,
          height: 7,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.055)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  void _drawCondensation(Canvas canvas, RRect inner) {
    for (var i = 0; i < 30; i++) {
      final x = inner.left + 9 + ((i * 59) % 941) / 941 * (inner.width - 18);
      final y = inner.top + 18 + ((i * 83) % 887) / 887 * (inner.height - 36);
      final radius = 1.2 + (i % 5) * 0.7;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = Colors.white.withValues(alpha: 0.14 + (i % 3) * 0.05),
      );
      if (i % 8 == 0) {
        canvas.drawLine(
          Offset(x, y + radius),
          Offset(x, y + radius + 8 + i % 4 * 3),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.10)
            ..strokeWidth = radius,
        );
      }
    }
  }

  void _drawFrontGlass(Canvas canvas, RRect glass, Rect body) {
    canvas.drawRRect(
      glass,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3,
    );
    canvas.drawRRect(
      glass.deflate(5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawLine(
      Offset(body.left + 32, body.top + 36),
      Offset(body.left + 32, body.bottom - 54),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(body.right - 20, body.top + 58),
      Offset(body.right - 20, body.bottom - 82),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.13)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBase(Canvas canvas, Size size) {
    final base = RRect.fromRectAndRadius(
      Rect.fromLTWH(49, size.height - 48, size.width - 98, 20),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      base,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x44FFFFFF), Color(0x10000000), Color(0x66FFFFFF)],
        ).createShader(base.outerRect),
    );
  }

  @override
  bool shouldRepaint(covariant DrinkGlassPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.drink != drink ||
        oldDelegate.motionEnergy != motionEnergy ||
        oldDelegate.foamEnergy != foamEnergy ||
        oldDelegate.fillLevel != fillLevel ||
        oldDelegate.bubbles != bubbles ||
        oldDelegate.condensation != condensation ||
        oldDelegate.surface != surface;
  }
}
