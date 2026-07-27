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
  late final AnimationController _controller;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  double _targetTilt = 0;
  double _tilt = 0;
  double _tiltVelocity = 0;
  double _wavePosition = 0;
  double _waveVelocity = 0;
  double _motionEnergy = 0;
  double _lastGyroEnergy = 0;
  bool _sensorActive = false;
  DateTime _lastFeedback = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )
      ..addListener(_updatePhysics)
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
        final energy = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        ).clamp(0.0, 12.0);

        final impulse = (energy - _lastGyroEnergy).abs();
        _lastGyroEnergy = energy;
        _waveVelocity += (event.y * 0.012 + event.z * 0.006).clamp(-0.20, 0.20);
        _motionEnergy = math.max(_motionEnergy, (energy / 7.5).clamp(0.0, 1.0));

        if (widget.drink.ice && impulse > 1.4) {
          _playMotionFeedback();
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _playMotionFeedback() {
    final now = DateTime.now();
    if (now.difference(_lastFeedback).inMilliseconds < 420) return;
    _lastFeedback = now;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void _updatePhysics() {
    if (!mounted || widget.paused) return;

    const dt = 1 / 60;
    final fallbackTilt = math.sin(_controller.value * math.pi * 2) * 0.018;
    final desiredTilt = _sensorActive ? _targetTilt : fallbackTilt;

    // Ressort amorti : le verre suit l’inclinaison sans paraître collé au capteur.
    final tiltAcceleration = (desiredTilt - _tilt) * 34 - _tiltVelocity * 8.5;
    _tiltVelocity += tiltAcceleration * dt;
    _tilt += _tiltVelocity * dt;

    // Masse liquide secondaire : elle dépasse la position cible et revient avec inertie.
    final waveTarget = _tilt * 0.82;
    final waveAcceleration = (waveTarget - _wavePosition) * 19 - _waveVelocity * 3.2;
    _waveVelocity += waveAcceleration * dt;
    _wavePosition += _waveVelocity * dt;

    _motionEnergy *= 0.978;
    if (_motionEnergy < 0.002) _motionEnergy = 0;

    setState(() {});
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _controller
      ..removeListener(_updatePhysics)
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
          tilt: _tilt,
          wavePosition: _wavePosition,
          waveVelocity: _waveVelocity,
          motionEnergy: _motionEnergy,
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
    required this.tilt,
    required this.wavePosition,
    required this.waveVelocity,
    required this.motionEnergy,
    required this.fillLevel,
    required this.bubbles,
    required this.condensation,
  });

  final Drink drink;
  final double progress;
  final double tilt;
  final double wavePosition;
  final double waveVelocity;
  final double motionEnergy;
  final double fillLevel;
  final bool bubbles;
  final bool condensation;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyRect = Rect.fromLTWH(24, 12, size.width - 48, size.height - 34);
    final glassRect = RRect.fromRectAndRadius(bodyRect, const Radius.circular(50));
    final innerRect = glassRect.deflate(9);

    _drawShadow(canvas, glassRect);
    _drawBackGlass(canvas, glassRect);

    canvas.save();
    canvas.clipRRect(innerRect);
    _drawLiquid(canvas, size, innerRect);
    if (drink.ice) _drawIce(canvas, size, innerRect);
    if (bubbles) _drawBubbles(canvas, size, innerRect);
    if (drink.foam) _drawFoam(canvas, size, innerRect);
    _drawInnerReflections(canvas, size);
    if (condensation) _drawCondensation(canvas, size, innerRect);
    canvas.restore();

    _drawGlassEdges(canvas, glassRect, bodyRect);
    _drawBase(canvas, size);
  }

  double _liquidTop(Size size) {
    final usableHeight = size.height - 86;
    return 42 + usableHeight * (1 - fillLevel.clamp(0.30, 0.96));
  }

  double _surfaceY(double x, Size size) {
    final top = _liquidTop(size);
    final halfWidth = (size.width - 70) / 2;
    final normalizedX = (x - size.width / 2) / halfWidth;
    final slope = normalizedX * wavePosition * 72;
    final energy = motionEnergy.clamp(0.0, 1.0);
    final velocityEnergy = waveVelocity.abs().clamp(0.0, 0.35);
    final waveA = math.sin(normalizedX * math.pi * 1.35 + progress * math.pi * 2.2) *
        (2.0 + energy * 10 + velocityEnergy * 16);
    final waveB = math.sin(normalizedX * math.pi * 3.1 - progress * math.pi * 3.4) *
        (0.9 + energy * 4.5);
    final edgeLift = math.pow(normalizedX.abs(), 3) * (2.2 + energy * 3.5);
    return top + slope + waveA + waveB + edgeLift;
  }

  void _drawShadow(Canvas canvas, RRect glassRect) {
    canvas.drawRRect(
      glassRect.shift(const Offset(0, 14)),
      Paint()
        ..color = drink.color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(glassRect.center.dx, glassRect.bottom + 12),
        width: glassRect.width * 0.78,
        height: 30,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.62)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }

  void _drawBackGlass(Canvas canvas, RRect glassRect) {
    canvas.drawRRect(
      glassRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, 0.18, 0.52, 0.82, 1],
          colors: [
            Color(0x66FFFFFF),
            Color(0x18000000),
            Color(0x08000000),
            Color(0x26000000),
            Color(0x55FFFFFF),
          ],
        ).createShader(glassRect.outerRect),
    );
  }

  void _drawLiquid(Canvas canvas, Size size, RRect innerRect) {
    final path = Path();
    const segments = 64;
    for (var i = 0; i <= segments; i++) {
      final x = innerRect.left + innerRect.width * i / segments;
      final y = _surfaceY(x, size);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path
      ..lineTo(innerRect.right, innerRect.bottom)
      ..lineTo(innerRect.left, innerRect.bottom)
      ..close();

    final top = _liquidTop(size);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.18, 0.55, 0.82, 1],
          colors: [
            Color.lerp(drink.color, Colors.white, 0.28)!,
            Color.lerp(drink.color, Colors.white, 0.08)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.26)!,
            Color.lerp(drink.color, Colors.black, 0.52)!,
          ],
        ).createShader(Rect.fromLTWH(innerRect.left, top - 45, innerRect.width, innerRect.bottom - top + 45)),
    );

    final surfacePath = Path();
    for (var i = 0; i <= segments; i++) {
      final x = innerRect.left + innerRect.width * i / segments;
      final y = _surfaceY(x, size);
      if (i == 0) {
        surfacePath.moveTo(x, y);
      } else {
        surfacePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      surfacePath,
      Paint()
        ..color = Color.lerp(drink.color, Colors.white, 0.48)!.withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  void _drawFoam(Canvas canvas, Size size, RRect innerRect) {
    final foamPaint = Paint()..color = const Color(0xFFF8E8C8).withValues(alpha: 0.95);
    final shadowPaint = Paint()..color = const Color(0xFFC89D62).withValues(alpha: 0.28);
    final count = 27 + (motionEnergy * 12).round();
    for (var i = 0; i < count; i++) {
      final ratio = (i + 0.5) / count;
      final x = innerRect.left + 4 + ratio * (innerRect.width - 8);
      final y = _surfaceY(x, size) - 2 - (i % 3) * 1.2;
      final radius = 3.6 + (i * 17 % 5) * 0.9 + motionEnergy * 1.5;
      canvas.drawCircle(Offset(x + 1, y + 2), radius, shadowPaint);
      canvas.drawCircle(Offset(x, y), radius, foamPaint);
      if (i % 4 == 0) {
        canvas.drawCircle(
          Offset(x - radius * 0.25, y - radius * 0.25),
          radius * 0.22,
          Paint()..color = Colors.white.withValues(alpha: 0.8),
        );
      }
    }
  }

  void _drawIce(Canvas canvas, Size size, RRect innerRect) {
    for (var i = 0; i < 5; i++) {
      final ratio = (i + 1) / 6;
      final x = innerRect.left + innerRect.width * ratio + wavePosition * (i - 2) * 13;
      final surface = _surfaceY(x, size);
      final y = surface + 24 + (i % 2) * 22 + motionEnergy * (i % 3) * 4;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((i - 2) * 0.16 + wavePosition * 0.55 + waveVelocity * 0.22);
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
            colors: [Color(0xAAFFFFFF), Color(0x28FFFFFF), Color(0x66000000)],
          ).createShader(cube.outerRect),
      );
      canvas.drawRRect(
        cube.deflate(2),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      canvas.restore();
    }
  }

  void _drawBubbles(Canvas canvas, Size size, RRect innerRect) {
    final top = _liquidTop(size);
    final count = 22 + (motionEnergy * 16).round();
    for (var i = 0; i < count; i++) {
      final phase = (progress * (0.65 + (i % 5) * 0.12) + i * 0.071) % 1;
      final xBase = innerRect.left + 15 + ((i * 47) % (innerRect.width - 30)).toDouble();
      final x = xBase + math.sin(progress * math.pi * 2 + i) * (2 + motionEnergy * 5);
      final surface = _surfaceY(x, size);
      final y = innerRect.bottom - 10 - phase * (innerRect.bottom - surface - 10);
      if (y < surface + 3 || y < top - 30) continue;
      final radius = 1.2 + (i % 4) * 0.75;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.56)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
      canvas.drawCircle(
        Offset(x - radius * 0.25, y - radius * 0.25),
        radius * 0.24,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  void _drawInnerReflections(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(51, 42, 13, size.height - 112),
        const Radius.circular(8),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x88FFFFFF), Color(0x24FFFFFF), Color(0x55FFFFFF)],
        ).createShader(Rect.fromLTWH(51, 42, 13, size.height - 112)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 66, 66, 5, size.height - 170),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );
  }

  void _drawCondensation(Canvas canvas, Size size, RRect innerRect) {
    for (var i = 0; i < 26; i++) {
      final x = innerRect.left + 10 + ((i * 73) % (innerRect.width - 20)).toDouble();
      final y = innerRect.top + 18 + ((i * 109) % (innerRect.height - 36)).toDouble();
      final radius = 1.3 + (i % 4) * 0.65;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = Colors.white.withValues(alpha: 0.20),
      );
      canvas.drawCircle(
        Offset(x - radius * 0.25, y - radius * 0.35),
        radius * 0.28,
        Paint()..color = Colors.white.withValues(alpha: 0.62),
      );
    }
  }

  void _drawGlassEdges(Canvas canvas, RRect glassRect, Rect bodyRect) {
    canvas.drawRRect(
      glassRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xAAFFFFFF), Color(0x22FFFFFF), Color(0x12FFFFFF), Color(0xAAFFFFFF)],
        ).createShader(bodyRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );
    canvas.drawRRect(
      glassRect.deflate(5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  void _drawBase(Canvas canvas, Size size) {
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(55, size.height - 37, size.width - 110, 18),
      const Radius.circular(9),
    );
    canvas.drawRRect(
      baseRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x88FFFFFF), Color(0x22000000), Color(0x66FFFFFF)],
        ).createShader(baseRect.outerRect),
    );
  }

  @override
  bool shouldRepaint(covariant DrinkGlassPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.drink != drink ||
        oldDelegate.tilt != tilt ||
        oldDelegate.wavePosition != wavePosition ||
        oldDelegate.waveVelocity != waveVelocity ||
        oldDelegate.motionEnergy != motionEnergy ||
        oldDelegate.fillLevel != fillLevel ||
        oldDelegate.bubbles != bubbles ||
        oldDelegate.condensation != condensation;
  }
}
