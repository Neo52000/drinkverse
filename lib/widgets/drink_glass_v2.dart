import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/drink.dart';
import '../physics/drink_motion_profile.dart';

class DrinkGlassV2 extends StatefulWidget {
  const DrinkGlassV2({
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
  State<DrinkGlassV2> createState() => _DrinkGlassV2State();
}

class _DrinkGlassV2State extends State<DrinkGlassV2>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;
  double _targetTilt = 0;
  double _tilt = 0;
  double _velocity = 0;
  double _energy = 0;

  DrinkMotionProfile get profile => DrinkMotionProfile.forDrink(widget.drink);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )
      ..addListener(_tick)
      ..repeat();
    _accelerometer = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _targetTilt = (event.x / 9.81).clamp(-1.0, 1.0);
    });
    _gyroscope = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      final magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _energy = math.max(_energy, (magnitude / 7).clamp(0.0, 1.0));
    });
  }

  void _tick() {
    if (!mounted || widget.paused) return;
    const dt = 1 / 60;
    final response = profile.tiltResponse;
    final acceleration = (_targetTilt - _tilt) * (22 * response) - _velocity * 7;
    _velocity += acceleration * dt;
    _tilt += _velocity * dt;
    _energy *= profile.damping;
    setState(() {});
  }

  @override
  void dispose() {
    _accelerometer?.cancel();
    _gyroscope?.cancel();
    _controller
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DrinkGlassV2Painter(
        drink: widget.drink,
        profile: profile,
        progress: _controller.value,
        tilt: _tilt,
        energy: _energy,
        fillLevel: widget.fillLevel,
        bubbles: widget.bubbles,
        condensation: widget.condensation,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _DrinkGlassV2Painter extends CustomPainter {
  const _DrinkGlassV2Painter({
    required this.drink,
    required this.profile,
    required this.progress,
    required this.tilt,
    required this.energy,
    required this.fillLevel,
    required this.bubbles,
    required this.condensation,
  });

  final Drink drink;
  final DrinkMotionProfile profile;
  final double progress;
  final double tilt;
  final double energy;
  final double fillLevel;
  final bool bubbles;
  final bool condensation;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final liquidTop = size.height * (1 - fillLevel.clamp(0.05, 0.96));
    final amplitude = size.height * 0.025 * profile.waveStrength * (0.35 + energy);
    final phase = progress * math.pi * 2 * profile.waveSpeed;

    final liquid = Path()..moveTo(0, liquidTop);
    const segments = 42;
    for (var i = 0; i <= segments; i++) {
      final x = size.width * i / segments;
      final nx = i / segments;
      final primary = math.sin(nx * math.pi * 2 + phase) * amplitude;
      final secondary = math.sin(nx * math.pi * 4 - phase * 1.35) * amplitude * 0.28;
      final tiltOffset = (nx - 0.5) * tilt * size.height * 0.20;
      liquid.lineTo(x, liquidTop + primary + secondary + tiltOffset);
    }
    liquid
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final liquidPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(drink.color, Colors.white, 0.18)!.withValues(alpha: 0.94),
          drink.color.withValues(alpha: 0.96),
          Color.lerp(drink.color, Colors.black, 0.35)!.withValues(alpha: 0.98),
        ],
      ).createShader(rect);
    canvas.drawPath(liquid, liquidPaint);

    final highlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.20),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.05),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, highlight);

    if (bubbles) _drawBubbles(canvas, size, liquidTop, phase);
    if (drink.ice) _drawIce(canvas, size, liquidTop, phase);
    if (drink.foam) _drawFoam(canvas, size, liquidTop, phase);
    if (condensation) _drawCondensation(canvas, size);
  }

  void _drawBubbles(Canvas canvas, Size size, double liquidTop, double phase) {
    final count = (18 * profile.bubbleDensity).round();
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.42);
    for (var i = 0; i < count; i++) {
      final seed = i * 17.17;
      final x = size.width * (0.10 + ((math.sin(seed) + 1) / 2) * 0.80);
      final travel = (progress * (0.25 + (i % 5) * 0.05) + i * 0.071) % 1;
      final y = size.height - travel * (size.height - liquidTop);
      final radius = 1.2 + (i % 4) * 0.65;
      canvas.drawCircle(Offset(x, y + math.sin(phase + i) * 2), radius, paint);
    }
  }

  void _drawIce(Canvas canvas, Size size, double liquidTop, double phase) {
    final mobility = profile.iceMobility;
    for (var i = 0; i < 4; i++) {
      final x = size.width * (0.22 + i * 0.18) + math.sin(phase + i) * 8 * mobility;
      final y = liquidTop + size.height * (0.13 + (i % 2) * 0.12) +
          math.cos(phase * 0.8 + i) * 5 * mobility;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(phase + i) * 0.16 * mobility);
      final cube = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 34, height: 28),
        const Radius.circular(7),
      );
      canvas.drawRRect(
        cube,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.52),
              const Color(0xFFBDEBFF).withValues(alpha: 0.18),
            ],
          ).createShader(cube.outerRect),
      );
      canvas.restore();
    }
  }

  void _drawFoam(Canvas canvas, Size size, double liquidTop, double phase) {
    final height = size.height * 0.07 * profile.foamPersistence;
    final paint = Paint()..color = const Color(0xFFFFF2D2).withValues(alpha: 0.90);
    final foam = Path()..moveTo(0, liquidTop + height);
    for (var i = 0; i <= 36; i++) {
      final x = size.width * i / 36;
      final y = liquidTop + math.sin(i * 0.85 + phase) * 3.5;
      foam.lineTo(x, y);
    }
    foam
      ..lineTo(size.width, liquidTop + height)
      ..close();
    canvas.drawPath(foam, paint);
  }

  void _drawCondensation(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.24);
    for (var i = 0; i < 14; i++) {
      final x = size.width * (0.08 + ((i * 37) % 83) / 100);
      final y = size.height * (0.12 + ((i * 53) % 76) / 100);
      final radius = 1.2 + (i % 3) * 0.7;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrinkGlassV2Painter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.tilt != tilt ||
        oldDelegate.energy != energy ||
        oldDelegate.drink != drink ||
        oldDelegate.fillLevel != fillLevel;
  }
}
