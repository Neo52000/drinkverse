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
  double _drinkAngle = 0;
  double _displayFill = 0.72;
  bool _sensorActive = false;
  bool _immersive = false;
  bool _wasPouring = false;
  DateTime _lastFeedback = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _displayFill = widget.fillLevel;
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
    }
  }

  void _startSensors() {
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _sensorActive = true;

        // Axe horizontal corrigé pour un téléphone tenu en portrait.
        _targetTilt = (event.x / 9.81).clamp(-1.0, 1.0);

        // Téléphone vertical : y proche de 9,81. En levant le bas du téléphone
        // vers la bouche, y diminue progressivement vers zéro.
        final verticalComponent = (event.y.abs() / 9.81).clamp(0.0, 1.0);
        _drinkAngle = (1.0 - verticalComponent).clamp(0.0, 1.0);
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
        _foamEnergy = math.max(_foamEnergy, (normalized * 1.2).clamp(0.0, 1.0));

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

    final tiltAcceleration = (desiredTilt - _smoothedTilt) * 30 - _tiltVelocity * 8;
    _tiltVelocity += tiltAcceleration * dt;
    _smoothedTilt += _tiltVelocity * dt;

    for (var i = 0; i < _pointCount; i++) {
      final normalizedX = i / (_pointCount - 1) * 2 - 1;
      final equilibrium = normalizedX * _smoothedTilt * 52;
      final left = i == 0 ? _surface[i] : _surface[i - 1];
      final right = i == _pointCount - 1 ? _surface[i] : _surface[i + 1];
      final neighborForce = (left + right - 2 * _surface[i]) * 27;
      final springForce = (equilibrium - _surface[i]) * 17;
      final dampingForce = -_velocity[i] * 4.4;
      _velocity[i] += (neighborForce + springForce + dampingForce) * dt;
      _nextSurface[i] = _surface[i] + _velocity[i] * dt;
    }

    for (var i = 0; i < _pointCount; i++) {
      _surface[i] = _nextSurface[i];
    }

    if (_immersive && _displayFill > 0) {
      // Le verre commence à se vider une fois le téléphone incliné au-delà
      // d'environ 55 degrés. Plus l'angle est prononcé, plus le débit augmente.
      final pourFactor = ((_drinkAngle - 0.58) / 0.42).clamp(0.0, 1.0);
      final pouring = pourFactor > 0.02;
      if (pouring) {
        final flowRate = 0.055 + pourFactor * 0.23;
        _displayFill = (_displayFill - flowRate * dt).clamp(0.0, 0.96);
        _motionEnergy = math.max(_motionEnergy, 0.28 + pourFactor * 0.55);
        _foamEnergy = math.max(_foamEnergy, 0.2 + pourFactor * 0.35);
      }
      if (pouring && !_wasPouring) {
        HapticFeedback.selectionClick();
      }
      if (!pouring && _wasPouring && _displayFill <= 0.01) {
        HapticFeedback.mediumImpact();
      }
      _wasPouring = pouring;
    }

    _motionEnergy *= 0.972;
    _foamEnergy *= 0.988;
    if (_motionEnergy < 0.001) _motionEnergy = 0;
    if (_foamEnergy < 0.001) _foamEnergy = 0;

    setState(() {});
  }

  void _refill() {
    if (!_immersive || _displayFill > 0.03) return;
    setState(() {
      _displayFill = widget.fillLevel.clamp(0.55, 0.92);
      _foamEnergy = widget.drink.foam ? 0.8 : 0.2;
      _motionEnergy = 0.55;
      for (var i = 0; i < _pointCount; i++) {
        _velocity[i] += math.sin(i / (_pointCount - 1) * math.pi) * 4;
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
        _immersive = maxHeight >= 520 && maxWidth >= 280;

        final size = _immersive
            ? Size(maxWidth, maxHeight)
            : Size(math.min(maxWidth, 286), math.min(maxHeight, 410));

        return GestureDetector(
          onTap: _refill,
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
              ),
            ),
          ),
        );
      },
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
    required this.immersive,
    required this.drinkAngle,
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

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalMargin = immersive ? 0.0 : 22.0;
    final verticalMargin = immersive ? 0.0 : 10.0;
    final body = Rect.fromLTWH(
      horizontalMargin,
      verticalMargin,
      size.width - horizontalMargin * 2,
      size.height - (immersive ? 0 : 30),
    );
    final radius = immersive ? Radius.zero : const Radius.circular(52);
    final glass = RRect.fromRectAndRadius(body, radius);
    final inner = immersive ? glass : glass.deflate(9);

    if (!immersive) _drawAmbientShadow(canvas, glass);
    _drawRearGlass(canvas, glass);

    canvas.save();
    canvas.clipRRect(inner);
    _drawLiquid(canvas, size, inner);
    if (drink.ice) _drawIce(canvas, size, inner);
    if (bubbles) _drawBubbles(canvas, size, inner);
    if (drink.foam && fillLevel > 0.015) _drawFoam(canvas, size, inner);
    _drawLiquidLight(canvas, size, inner);
    if (condensation) _drawCondensation(canvas, inner);
    canvas.restore();

    if (!immersive) {
      _drawFrontGlass(canvas, glass, body);
      _drawBase(canvas, size);
    } else {
      _drawFullscreenEdges(canvas, size);
      if (fillLevel <= 0.015) _drawEmptyMessage(canvas, size);
    }
  }

  double _baseTop(Size size) {
    if (immersive) {
      final minimumTop = size.height * 0.08;
      final maximumTop = size.height * 0.96;
      return maximumTop - (maximumTop - minimumTop) * fillLevel.clamp(0.0, 0.96);
    }
    final usable = size.height - 88;
    return 42 + usable * (1 - fillLevel.clamp(0.0, 0.96));
  }

  double _surfaceAt(double x, RRect inner, Size size) {
    final ratio = ((x - inner.left) / inner.width).clamp(0.0, 1.0);
    final scaled = ratio * (surface.length - 1);
    final low = scaled.floor().clamp(0, surface.length - 1);
    final high = math.min(low + 1, surface.length - 1);
    final t = scaled - low;
    final displacement = surface[low] * (1 - t) + surface[high] * t;
    final scale = immersive ? size.width / 286 : 1.0;
    final microWave = math.sin(ratio * math.pi * 6 + progress * math.pi * 2.4) *
        (0.7 + motionEnergy * 2.8) * scale.clamp(0.8, 1.7);
    return _baseTop(size) + displacement * scale.clamp(0.8, 1.8) + microWave;
  }

  Path _liquidPath(Size size, RRect inner) {
    final path = Path();
    const segments = 96;
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
  }

  void _drawRearGlass(Canvas canvas, RRect glass) {
    canvas.drawRRect(
      glass,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x52FFFFFF),
            Color(0x10000000),
            Color(0x04000000),
            Color(0x22FFFFFF),
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
          stops: const [0, 0.16, 0.48, 0.78, 1],
          colors: [
            Color.lerp(drink.color, Colors.white, 0.38)!,
            Color.lerp(drink.color, Colors.white, 0.12)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.22)!,
            Color.lerp(drink.color, Colors.black, 0.50)!,
          ],
        ).createShader(
          Rect.fromLTWH(inner.left, top - 60, inner.width, inner.bottom - top + 60),
        ),
    );

    final surfacePath = Path();
    const segments = 96;
    for (var i = 0; i <= segments; i++) {
      final x = inner.left + inner.width * i / segments;
      final y = _surfaceAt(x, inner, size);
      i == 0 ? surfacePath.moveTo(x, y) : surfacePath.lineTo(x, y);
    }
    canvas.drawPath(
      surfacePath,
      Paint()
        ..color = Color.lerp(drink.color, Colors.white, 0.62)!
            .withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = immersive ? 3.2 : 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  void _drawFoam(Canvas canvas, Size size, RRect inner) {
    final layers = 2 + (foamEnergy * 4).round();
    final baseRadius = immersive ? 7.0 : 4.4;
    for (var layer = 0; layer < layers; layer++) {
      final count = immersive ? 44 : 28;
      for (var i = 0; i < count; i++) {
        final ratio = (i + 0.5) / count;
        final x = inner.left + ratio * inner.width;
        final y = _surfaceAt(x, inner, size) - layer * baseRadius * 0.75;
        final radius = baseRadius + ((i * 13 + layer * 7) % 5) * 0.75;
        canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()..color = const Color(0xFFF8E8C8).withValues(alpha: 0.94),
        );
        if ((i + layer) % 5 == 0) {
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
    if (fillLevel <= 0.015) return;
    final count = (immersive ? 75 : 30) + (motionEnergy * 24).round();
    final top = _baseTop(size);
    for (var i = 0; i < count; i++) {
      final seed = i * 47 + 19;
      final x = inner.left + 12 + (seed % 997) / 997 * (inner.width - 24);
      final speed = 0.35 + (i % 7) * 0.08;
      final cycle = (progress * speed + i * 0.071) % 1;
      final y = inner.bottom - 14 - cycle * math.max(0, inner.bottom - top - 22);
      if (y < _surfaceAt(x, inner, size) + 5) continue;
      final radius = (immersive ? 2.2 : 1.5) + (i % 5) * 0.75;
      canvas.drawCircle(
        Offset(x + math.sin(progress * math.pi * 2 + i) * 2.4, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.52)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }
  }

  void _drawIce(Canvas canvas, Size size, RRect inner) {
    if (fillLevel <= 0.04) return;
    for (var i = 0; i < 5; i++) {
      final ratio = (i + 1) / 6;
      final x = inner.left + inner.width * ratio;
      final y = _surfaceAt(x, inner, size) + (immersive ? 34 : 24) + (i % 2) * 22;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((i - 2) * 0.12 + motionEnergy * 0.18);
      final cubeSize = immersive ? 34.0 : 27.0;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: cubeSize, height: cubeSize),
        Radius.circular(cubeSize * 0.2),
      );
      canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.15));
      canvas.drawRRect(
        rect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.restore();
    }
  }

  void _drawLiquidLight(Canvas canvas, Size size, RRect inner) {
    if (fillLevel <= 0.015) return;
    final top = _baseTop(size);
    canvas.drawRect(
      Rect.fromLTWH(inner.left, top, inner.width, inner.bottom - top),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.14),
          ],
        ).createShader(inner.outerRect),
    );
  }

  void _drawCondensation(Canvas canvas, RRect inner) {
    final count = immersive ? 42 : 18;
    for (var i = 0; i < count; i++) {
      final x = inner.left + 10 + ((i * 67) % 1000) / 1000 * (inner.width - 20);
      final y = inner.top + 18 + ((i * 89) % 1000) / 1000 * (inner.height - 36);
      final radius = 1.4 + (i % 4) * 0.65;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = Colors.white.withValues(alpha: 0.15),
      );
    }
  }

  void _drawFrontGlass(Canvas canvas, RRect glass, Rect body) {
    canvas.drawRRect(
      glass,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawLine(
      Offset(body.left + 35, body.top + 42),
      Offset(body.left + 35, body.bottom - 72),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBase(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(55, size.height - 43, size.width - 110, 14),
        const Radius.circular(8),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.17),
    );
  }

  void _drawFullscreenEdges(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x88FFFFFF), Color(0x08FFFFFF), Color(0x66FFFFFF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, 7, size.height), edgePaint);
    canvas.drawRect(Rect.fromLTWH(size.width - 7, 0, 7, size.height), edgePaint);
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
        oldDelegate.drink != drink;
  }
}
