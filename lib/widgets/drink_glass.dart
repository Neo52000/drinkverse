import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/drink.dart';

class DrinkGlass extends StatefulWidget {
  const DrinkGlass({super.key, required this.drink});

  final Drink drink;

  @override
  State<DrinkGlass> createState() => _DrinkGlassState();
}

class _DrinkGlassState extends State<DrinkGlass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  double _tilt = 0;
  double _targetTilt = 0;
  double _motionEnergy = 0;
  bool _sensorActive = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
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
        _targetTilt = (event.x / 9.81).clamp(-1.0, 1.0);
      },
      onError: (_) {
        _sensorActive = false;
      },
      cancelOnError: false,
    );

    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        final angularVelocity =
            (event.x.abs() + event.y.abs() + event.z.abs()).clamp(0.0, 8.0);
        _motionEnergy = math.max(_motionEnergy, angularVelocity / 8.0);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _updatePhysics() {
    if (!mounted) return;

    final fallbackTilt = math.sin(_controller.value * math.pi * 2) * 0.04;
    final desiredTilt = _sensorActive ? _targetTilt : fallbackTilt;

    _tilt += (desiredTilt - _tilt) * 0.09;
    _motionEnergy *= 0.965;
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
    return CustomPaint(
      size: const Size(270, 390),
      painter: DrinkGlassPainter(
        drink: widget.drink,
        progress: _controller.value,
        tilt: _tilt,
        motionEnergy: _motionEnergy,
      ),
    );
  }
}

class DrinkGlassPainter extends CustomPainter {
  DrinkGlassPainter({
    required this.drink,
    required this.progress,
    required this.tilt,
    required this.motionEnergy,
  });

  final Drink drink;
  final double progress;
  final double tilt;
  final double motionEnergy;

  @override
  void paint(Canvas canvas, Size size) {
    final glassRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(24, 10, size.width - 48, size.height - 28),
      const Radius.circular(48),
    );

    canvas.drawRRect(
      glassRect.shift(const Offset(0, 12)),
      Paint()
        ..color = drink.color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34),
    );

    canvas.drawRRect(
      glassRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x55FFFFFF), Color(0x10000000), Color(0x35FFFFFF)],
        ).createShader(glassRect.outerRect),
    );

    canvas.save();
    canvas.clipRRect(glassRect.deflate(8));

    final liquidTop = size.height * 0.29;
    final halfWidth = (size.width - 60) / 2;
    final slopePixels = tilt * 44;
    final waveStrength = 5.5 + motionEnergy * 17;
    final liquidPath = Path();
    const segments = 48;

    for (var i = 0; i <= segments; i++) {
      final ratio = i / segments;
      final x = 30 + (size.width - 60) * ratio;
      final slope = ((x - size.width / 2) / halfWidth) * slopePixels;
      final primary =
          math.sin(ratio * math.pi * 2 + progress * math.pi * 2) * waveStrength;
      final secondary =
          math.sin(ratio * math.pi * 4 - progress * math.pi * 3) *
              (2.2 + motionEnergy * 6);
      final y = liquidTop + slope + primary + secondary;
      if (i == 0) {
        liquidPath.moveTo(x, y);
      } else {
        liquidPath.lineTo(x, y);
      }
    }

    liquidPath
      ..lineTo(size.width - 30, size.height - 34)
      ..lineTo(30, size.height - 34)
      ..close();

    canvas.drawPath(
      liquidPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(drink.color, Colors.white, 0.08)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.38)!,
          ],
        ).createShader(
          Rect.fromLTWH(30, liquidTop - 50, size.width - 60, size.height - liquidTop + 50),
        ),
    );

    if (drink.foam) {
      final foamPaint = Paint()
        ..color = const Color(0xFFF5E2BE).withValues(alpha: 0.92);
      for (var i = 0; i < 20; i++) {
        final x = 36 + (i * 12.4) % (size.width - 72);
        final normalizedX = (x - size.width / 2) / halfWidth;
        final foamSlope = normalizedX * slopePixels;
        final foamWave =
            math.sin(i * 1.7 + progress * math.pi * 2) * (3 + motionEnergy * 4);
        final y = liquidTop - 2 + foamSlope + foamWave;
        canvas.drawCircle(Offset(x, y), 5 + i % 3, foamPaint);
      }
    }

    if (drink.ice) {
      final icePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < 4; i++) {
        final x = 58 + i * 37.0 + tilt * (i - 1.5) * 10;
        final y = liquidTop + 42 + (i % 2) * 34.0 + motionEnergy * 6;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate((i - 1.5) * 0.13 + tilt * 0.35);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-14, -14, 28, 28),
            const Radius.circular(6),
          ),
          icePaint,
        );
        canvas.restore();
      }
    }

    final bubblePaint = Paint()..color = Colors.white.withValues(alpha: 0.58);
    final bubbleCount = 18 + (motionEnergy * 10).round();
    for (var i = 0; i < bubbleCount; i++) {
      final x = 46 + ((i * 41) % 168).toDouble() + tilt * 8;
      final cycle = (progress * (1 + motionEnergy) + i * 0.057) % 1;
      final y = size.height - 46 - cycle * (size.height - liquidTop - 62);
      canvas.drawCircle(Offset(x, y), 1.8 + i % 4, bubblePaint);
    }

    canvas.drawLine(
      const Offset(58, 46),
      Offset(58, size.height - 88),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < 16; i++) {
      final dx = 45 + ((i * 31) % 175).toDouble();
      final dy = 38 + ((i * 53) % 250).toDouble();
      canvas.drawCircle(
        Offset(dx, dy),
        1.8 + (i % 3),
        Paint()..color = Colors.white.withValues(alpha: 0.16),
      );
    }

    canvas.restore();

    canvas.drawRRect(
      glassRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant DrinkGlassPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.drink != drink ||
        oldDelegate.tilt != tilt ||
        oldDelegate.motionEnergy != motionEnergy;
  }
}
