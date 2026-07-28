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
  static const int _pointCount = 55;
  static const double _gravity = 9.81;

  late final AnimationController _controller;
  late final List<double> _surface;
  late final List<double> _velocity;
  late final List<double> _nextSurface;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  double _accelerometerTilt = 0;
  double _fusedTilt = 0;
  double _liquidTilt = 0;
  double _liquidTiltVelocity = 0;
  double _gyroRollRate = 0;
  double _gyroMagnitude = 0;
  double _lastGyroMagnitude = 0;
  double _drinkAngle = 0;
  double _motionEnergy = 0;
  double _foamEnergy = 0;
  double _displayFill = 0.72;
  double _initialFill = 0.72;
  double _residue = 0;

  bool _sensorActive = false;
  bool _immersive = false;
  bool _pouring = false;
  bool _wasPouring = false;
  DateTime _lastFeedback = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _displayFill = widget.fillLevel;
    _initialFill = widget.fillLevel;
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

  @override
  void didUpdateWidget(covariant DrinkGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fillLevel != widget.fillLevel && !_immersive) {
      _displayFill = widget.fillLevel;
      _initialFill = widget.fillLevel;
    }
  }

  void _startSensors() {
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _sensorActive = true;
        final horizontal = (event.x / _gravity).clamp(-1.0, 1.0).toDouble();
        _accelerometerTilt = horizontal.abs() < 0.018 ? 0 : horizontal;

        final vertical = (event.y.abs() / _gravity).clamp(0.0, 1.0).toDouble();
        _drinkAngle = (1 - vertical).clamp(0.0, 1.0).toDouble();
      },
      onError: (_) => _sensorActive = false,
      cancelOnError: false,
    );

    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _gyroRollRate = (event.z * 0.88 + event.y * 0.12)
            .clamp(-10.0, 10.0)
            .toDouble();
        final magnitude = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        ).clamp(0.0, 18.0).toDouble();
        final impulse = (magnitude - _lastGyroMagnitude).abs();
        _lastGyroMagnitude = magnitude;
        _gyroMagnitude = magnitude;

        final normalized = (magnitude / 7.0).clamp(0.0, 1.0).toDouble();
        _motionEnergy = math.max(_motionEnergy, normalized);
        _foamEnergy = math.max(
          _foamEnergy,
          (normalized * 1.18).clamp(0.0, 1.0).toDouble(),
        );

        final lateral = (event.y * 0.72 + event.z * 0.48)
            .clamp(-8.0, 8.0)
            .toDouble();
        _injectImpulse(lateral * 0.34, event.x);

        if ((widget.drink.ice && impulse > 1.15) ||
            (widget.drink.foam && impulse > 1.95)) {
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
      final influence = math.exp(-distance * distance / 46);
      _velocity[i] += strength * influence;
    }
  }

  void _playMotionFeedback() {
    final now = DateTime.now();
    if (now.difference(_lastFeedback).inMilliseconds < 340) return;
    _lastFeedback = now;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void _stepPhysics() {
    if (!mounted || widget.paused) return;
    const dt = 1 / 60;

    final fallback = math.sin(_controller.value * math.pi * 2) * 0.009;
    if (_sensorActive) {
      final predicted = _fusedTilt + _gyroRollRate * dt * 0.31;
      _fusedTilt = (predicted * 0.92 + _accelerometerTilt * 0.08)
          .clamp(-1.15, 1.15)
          .toDouble();
    } else {
      _fusedTilt = fallback;
    }

    final stiffness = 37.0 + _gyroMagnitude.clamp(0.0, 6.0) * 1.5;
    const damping = 7.2;
    final acceleration =
        (_fusedTilt - _liquidTilt) * stiffness - _liquidTiltVelocity * damping;
    _liquidTiltVelocity += acceleration * dt;
    _liquidTilt += _liquidTiltVelocity * dt;

    final activity = (_motionEnergy * 0.75 + _gyroMagnitude / 18)
        .clamp(0.0, 1.0)
        .toDouble();
    final neighborStrength = 31.0 + activity * 13.0;
    final springStrength = 15.5 + activity * 4.5;
    final surfaceDamping = 3.65 + (1 - activity) * 0.85;

    for (var i = 0; i < _pointCount; i++) {
      final normalizedX = i / (_pointCount - 1) * 2 - 1;
      final equilibrium = normalizedX * _liquidTilt * 62;
      final left = i == 0 ? _surface[1] : _surface[i - 1];
      final right = i == _pointCount - 1 ? _surface[_pointCount - 2] : _surface[i + 1];
      final neighborForce =
          (left + right - 2 * _surface[i]) * neighborStrength;
      final springForce = (equilibrium - _surface[i]) * springStrength;
      final dampingForce = -_velocity[i] * surfaceDamping;
      _velocity[i] += (neighborForce + springForce + dampingForce) * dt;
      _nextSurface[i] = (_surface[i] + _velocity[i] * dt)
          .clamp(-110.0, 110.0)
          .toDouble();
    }

    for (var i = 0; i < _pointCount; i++) {
      _surface[i] = _nextSurface[i];
    }

    _updatePouring(dt);

    _motionEnergy *= 0.974;
    _foamEnergy *= 0.988;
    _gyroMagnitude *= 0.93;
    _gyroRollRate *= 0.91;
    if (_motionEnergy < 0.001) _motionEnergy = 0;
    if (_foamEnergy < 0.001) _foamEnergy = 0;

    setState(() {});
  }

  void _updatePouring(double dt) {
    _pouring = false;
    if (!_immersive || _displayFill <= 0) return;

    final pourFactor = ((_drinkAngle - 0.50) / 0.50)
        .clamp(0.0, 1.0)
        .toDouble();
    _pouring = pourFactor > 0.025;

    if (_pouring) {
      final flowRate = 0.038 + math.pow(pourFactor, 1.38) * 0.34;
      _displayFill = (_displayFill - flowRate * dt)
          .clamp(0.0, 0.98)
          .toDouble();
      _motionEnergy = math.max(_motionEnergy, 0.28 + pourFactor * 0.62);
      _foamEnergy = math.max(_foamEnergy, 0.20 + pourFactor * 0.44);
      _residue = math.max(
        _residue,
        ((_initialFill - _displayFill) / math.max(_initialFill, 0.01))
            .clamp(0.0, 1.0)
            .toDouble(),
      );

      final edge = _liquidTilt >= 0 ? _pointCount - 1 : 0;
      _velocity[edge] += (_liquidTilt >= 0 ? 1 : -1) * pourFactor * 0.62;
    }

    if (_pouring && !_wasPouring) HapticFeedback.selectionClick();
    if (!_pouring && _wasPouring && _displayFill <= 0.01) {
      HapticFeedback.mediumImpact();
    }
    _wasPouring = _pouring;
  }

  void _refill() {
    if (!_immersive || _displayFill > 0.03) return;
    setState(() {
      _displayFill = widget.fillLevel.clamp(0.55, 0.94).toDouble();
      _initialFill = _displayFill;
      _residue = 0;
      _foamEnergy = widget.drink.foam ? 0.9 : 0.25;
      _motionEnergy = 0.65;
      for (var i = 0; i < _pointCount; i++) {
        _velocity[i] += math.sin(i / (_pointCount - 1) * math.pi) * 5.2;
      }
    });
    HapticFeedback.mediumImpact();
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 286.0;
        final maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 410.0;
        _immersive = maxHeight >= 500 && maxWidth >= 260;
        final size = _immersive
            ? Size(maxWidth, maxHeight)
            : Size(math.min(maxWidth, 286), math.min(maxHeight, 410));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _refill,
          child: SizedBox.expand(
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: DrinkGlassPainter(
                  drink: widget.drink,
                  progress: _controller.value,
                  surface: List<double>.unmodifiable(_surface),
                  motionEnergy: _motionEnergy,
                  foamEnergy: _foamEnergy,
                  fillLevel: _displayFill,
                  bubbles: widget.bubbles,
                  condensation: widget.condensation,
                  immersive: _immersive,
                  drinkAngle: _drinkAngle,
                  tilt: _liquidTilt,
                  pouring: _pouring,
                  residue: _residue,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class DrinkGlassPainter extends CustomPainter {
  const DrinkGlassPainter({
    required this.drink,
    required this.progress,
    required this.surface,
    required this.motionEnergy,
    required this.foamEnergy,
    required this.fillLevel,
    required this.bubbles,
    required this.condensation,
    required this.immersive,
    required this.drinkAngle,
    required this.tilt,
    required this.pouring,
    required this.residue,
  });

  final Drink drink;
  final double progress;
  final List<double> surface;
  final double motionEnergy;
  final double foamEnergy;
  final double fillLevel;
  final bool bubbles;
  final bool condensation;
  final bool immersive;
  final double drinkAngle;
  final double tilt;
  final bool pouring;
  final double residue;

  @override
  void paint(Canvas canvas, Size size) {
    final margin = immersive ? 0.0 : 12.0;
    final body = Rect.fromLTWH(
      margin,
      immersive ? 0 : 8,
      size.width - margin * 2,
      size.height - (immersive ? 0 : 18),
    );
    final glass = RRect.fromRectAndRadius(
      body,
      immersive ? Radius.zero : const Radius.circular(44),
    );
    final inner = immersive ? glass : glass.deflate(5);

    _drawRearGlass(canvas, glass);
    canvas.save();
    canvas.clipRRect(inner);
    _drawLiquid(canvas, size, inner);
    if (drink.ice) _drawIce(canvas, size, inner);
    if (bubbles) _drawBubbles(canvas, size, inner);
    if (drink.foam && fillLevel > 0.015) _drawFoam(canvas, size, inner);
    if (immersive && drink.foam && residue > 0.02) {
      _drawFoamResidue(canvas, size, inner);
    }
    _drawLiquidLight(canvas, size, inner);
    if (condensation) _drawCondensation(canvas, inner);
    canvas.restore();

    if (immersive) {
      _drawFullscreenEdges(canvas, size);
      if (pouring && fillLevel > 0.01) _drawPourLip(canvas, size);
      if (fillLevel <= 0.015) _drawEmptyMessage(canvas, size);
    } else {
      _drawFrontGlass(canvas, glass, body);
    }
  }

  double _baseTop(Size size) {
    if (immersive) {
      final minTop = -size.height * 0.015;
      final maxTop = size.height * 1.015;
      return maxTop - (maxTop - minTop) * fillLevel.clamp(0.0, 1.0);
    }
    final usable = size.height - 46;
    return 24 + usable * (1 - fillLevel.clamp(0.0, 0.96));
  }

  double _surfaceAt(double x, RRect inner, Size size) {
    final ratio = ((x - inner.left) / inner.width).clamp(0.0, 1.0).toDouble();
    final scaled = ratio * (surface.length - 1);
    final low = scaled.floor().clamp(0, surface.length - 1);
    final high = math.min(low + 1, surface.length - 1);
    final t = scaled - low;
    final displacement = surface[low] * (1 - t) + surface[high] * t;
    final scale = immersive ? (size.width / 286).clamp(0.85, 1.75) : 1.0;
    final microWave =
        math.sin(ratio * math.pi * 8 + progress * math.pi * 2.7) *
            (0.45 + motionEnergy * 2.6) *
            scale;
    final secondary =
        math.sin(ratio * math.pi * 3.4 - progress * math.pi * 1.7) *
            motionEnergy *
            1.8 *
            scale;
    return _baseTop(size) + displacement * scale + microWave + secondary;
  }

  Path _liquidPath(Size size, RRect inner) {
    final path = Path();
    const segments = 120;
    for (var i = 0; i <= segments; i++) {
      final x = inner.left + inner.width * i / segments;
      final y = _surfaceAt(x, inner, size);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path
      ..lineTo(inner.right, inner.bottom + 2)
      ..lineTo(inner.left, inner.bottom + 2)
      ..close();
  }

  void _drawRearGlass(Canvas canvas, RRect glass) {
    canvas.drawRRect(
      glass,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x42FFFFFF), Color(0x08000000), Color(0x1FFFFFFF)],
        ).createShader(glass.outerRect),
    );
  }

  void _drawLiquid(Canvas canvas, Size size, RRect inner) {
    if (fillLevel <= 0.001) return;
    final path = _liquidPath(size, inner);
    final top = _baseTop(size);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.18, 0.52, 0.82, 1],
          colors: [
            Color.lerp(drink.color, Colors.white, 0.36)!,
            Color.lerp(drink.color, Colors.white, 0.10)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.24)!,
            Color.lerp(drink.color, Colors.black, 0.48)!,
          ],
        ).createShader(
          Rect.fromLTWH(inner.left, top - 80, inner.width, inner.bottom - top + 100),
        ),
    );

    final surfacePath = Path();
    const segments = 120;
    for (var i = 0; i <= segments; i++) {
      final x = inner.left + inner.width * i / segments;
      final y = _surfaceAt(x, inner, size);
      i == 0 ? surfacePath.moveTo(x, y) : surfacePath.lineTo(x, y);
    }
    canvas.drawPath(
      surfacePath,
      Paint()
        ..color = Color.lerp(drink.color, Colors.white, 0.65)!
            .withValues(alpha: 0.90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = immersive ? 3.0 : 2.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  void _drawFoam(Canvas canvas, Size size, RRect inner) {
    final layers = 2 + (foamEnergy * 4).round();
    final baseRadius = immersive ? 6.5 : 4.0;
    for (var layer = 0; layer < layers; layer++) {
      final count = immersive ? 46 : 26;
      for (var i = 0; i < count; i++) {
        final ratio = (i + 0.5) / count;
        final x = inner.left + ratio * inner.width;
        final y = _surfaceAt(x, inner, size) - layer * baseRadius * 0.72;
        final radius = baseRadius + ((i * 13 + layer * 7) % 5) * 0.65;
        canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()..color = const Color(0xFFF8E8C8).withValues(alpha: 0.94),
        );
      }
    }
  }

  void _drawFoamResidue(Canvas canvas, Size size, RRect inner) {
    final currentTop = _baseTop(size);
    final available = math.max(0.0, currentTop - inner.top - 20);
    final rings = (2 + residue * 7).round();
    final paint = Paint()
      ..color = const Color(0xFFF4E1BC).withValues(alpha: 0.20 + residue * 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = immersive ? 2.8 : 1.7;
    for (var i = 0; i < rings; i++) {
      final y = inner.top + 22 + available * (i + 1) / (rings + 1);
      final path = Path()..moveTo(inner.left + 6, y);
      for (var s = 1; s <= 36; s++) {
        final x = inner.left + 6 + (inner.width - 12) * s / 36;
        path.lineTo(x, y + math.sin(s * 0.68 + i * 1.7) * (1.1 + residue * 2.2));
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawBubbles(Canvas canvas, Size size, RRect inner) {
    if (fillLevel <= 0.015) return;
    final count = (immersive ? 86 : 30) + (motionEnergy * 30).round();
    final top = _baseTop(size);
    for (var i = 0; i < count; i++) {
      final seed = i * 47 + 19;
      final x = inner.left + 8 + (seed % 997) / 997 * (inner.width - 16);
      final speed = 0.35 + (i % 7) * 0.08;
      final cycle = (progress * speed + i * 0.071) % 1;
      final y = inner.bottom - 10 - cycle * math.max(0, inner.bottom - top - 16);
      if (y < _surfaceAt(x, inner, size) + 4) continue;
      final radius = (immersive ? 2.1 : 1.4) + (i % 5) * 0.68;
      canvas.drawCircle(
        Offset(x + math.sin(progress * math.pi * 2 + i) * 2.2, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.50)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.05,
      );
    }
  }

  void _drawIce(Canvas canvas, Size size, RRect inner) {
    if (fillLevel <= 0.04) return;
    for (var i = 0; i < 5; i++) {
      final ratio = (i + 1) / 6;
      final x = inner.left + inner.width * ratio;
      final y = _surfaceAt(x, inner, size) + (immersive ? 30 : 22) + (i % 2) * 20;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((i - 2) * 0.12 + tilt * 0.16 + motionEnergy * 0.14);
      final cubeSize = immersive ? 33.0 : 26.0;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: cubeSize, height: cubeSize),
        Radius.circular(cubeSize * 0.2),
      );
      canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.14));
      canvas.drawRRect(
        rect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.35,
      );
      canvas.restore();
    }
  }

  void _drawLiquidLight(Canvas canvas, Size size, RRect inner) {
    if (fillLevel <= 0.015) return;
    final top = _baseTop(size);
    canvas.drawRect(
      Rect.fromLTWH(inner.left, top, inner.width, math.max(0, inner.bottom - top)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.13),
          ],
        ).createShader(inner.outerRect),
    );
  }

  void _drawCondensation(Canvas canvas, RRect inner) {
    final count = immersive ? 52 : 18;
    for (var i = 0; i < count; i++) {
      final x = inner.left + 7 + ((i * 67) % 1000) / 1000 * (inner.width - 14);
      final y = inner.top + 12 + ((i * 89) % 1000) / 1000 * (inner.height - 24);
      final radius = 1.3 + (i % 4) * 0.62;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
    }
  }

  void _drawFrontGlass(Canvas canvas, RRect glass, Rect body) {
    canvas.drawRRect(
      glass,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawLine(
      Offset(body.left + 28, body.top + 38),
      Offset(body.left + 28, body.bottom - 55),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.27)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawFullscreenEdges(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x72FFFFFF), Color(0x06FFFFFF), Color(0x58FFFFFF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Rect.fromLTWH(0, 0, 5, size.height), edgePaint);
    canvas.drawRect(Rect.fromLTWH(size.width - 5, 0, 5, size.height), edgePaint);
  }

  void _drawPourLip(Canvas canvas, Size size) {
    final rightSide = tilt >= 0;
    final x = rightSide ? size.width - 14 : 14.0;
    final intensity = ((drinkAngle - 0.50) / 0.50).clamp(0.0, 1.0).toDouble();
    final width = 10 + intensity * 20;
    final path = Path()
      ..moveTo(x - width / 2, 0)
      ..quadraticBezierTo(x, 12 + intensity * 20, x + width / 2, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(drink.color, Colors.white, 0.2)!
            .withValues(alpha: 0.70 + intensity * 0.2),
    );
  }

  void _drawEmptyMessage(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'Verre vide\nTouchez pour resservir',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 18,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 40);
    painter.paint(
      canvas,
      Offset((size.width - painter.width) / 2, size.height * 0.43),
    );
  }

  @override
  bool shouldRepaint(covariant DrinkGlassPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.surface != surface ||
        oldDelegate.motionEnergy != motionEnergy ||
        oldDelegate.foamEnergy != foamEnergy ||
        oldDelegate.fillLevel != fillLevel ||
        oldDelegate.immersive != immersive ||
        oldDelegate.drinkAngle != drinkAngle ||
        oldDelegate.tilt != tilt ||
        oldDelegate.pouring != pouring ||
        oldDelegate.residue != residue ||
        oldDelegate.drink != drink;
  }
}
