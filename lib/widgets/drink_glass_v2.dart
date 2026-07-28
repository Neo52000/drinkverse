import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  double _tiltVelocity = 0;
  double _energy = 0;
  double _drinkAngle = 0;
  double _displayFill = 0.72;
  double _initialFill = 0.72;
  double _residue = 0;
  bool _sensorActive = false;
  bool _pouring = false;
  bool _wasPouring = false;
  DateTime _lastFeedback = DateTime.fromMillisecondsSinceEpoch(0);

  DrinkMotionProfile get profile => DrinkMotionProfile.forDrink(widget.drink);

  @override
  void initState() {
    super.initState();
    _displayFill = widget.fillLevel;
    _initialFill = widget.fillLevel;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )
      ..addListener(_tick)
      ..repeat();

    _accelerometer = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _sensorActive = true;
        _targetTilt = (event.x / 9.81).clamp(-1.0, 1.0);
        final vertical = (event.y.abs() / 9.81).clamp(0.0, 1.0);
        _drinkAngle = (1.0 - vertical).clamp(0.0, 1.0);
      },
      onError: (_) => _sensorActive = false,
    );

    _gyroscope = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      final magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _energy = math.max(_energy, (magnitude / 6).clamp(0.0, 1.0));
      _tiltVelocity += (event.y * 0.012 + event.z * 0.006) * profile.tiltResponse;
      if (widget.drink.ice && magnitude > 2.0) _motionFeedback();
    });
  }

  @override
  void didUpdateWidget(covariant DrinkGlassV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fillLevel != widget.fillLevel && _displayFill > 0.03) {
      _displayFill = widget.fillLevel;
      _initialFill = widget.fillLevel;
    }
  }

  void _tick() {
    if (!mounted || widget.paused) return;
    const dt = 1 / 60;
    final fallback = math.sin(_controller.value * math.pi * 2) * 0.012;
    final desiredTilt = _sensorActive ? _targetTilt : fallback;

    final stiffness = 34.0 * profile.tiltResponse;
    final damping = 6.2 + (1.0 - profile.tiltResponse).clamp(0.0, 1.0) * 2.4;
    final acceleration = (desiredTilt - _tilt) * stiffness - _tiltVelocity * damping;
    _tiltVelocity += acceleration * dt;
    _tilt += _tiltVelocity * dt;
    _tilt = _tilt.clamp(-1.15, 1.15);

    _pouring = false;
    if (_displayFill > 0.001) {
      final pourFactor = ((_drinkAngle - 0.50) / 0.50).clamp(0.0, 1.0);
      _pouring = pourFactor > 0.035;
      if (_pouring) {
        final flowRate = 0.055 + math.pow(pourFactor, 1.35) * 0.34;
        _displayFill = (_displayFill - flowRate * dt).clamp(0.0, 0.96);
        _energy = math.max(_energy, 0.34 + pourFactor * 0.62);
        _residue = math.max(
          _residue,
          ((_initialFill - _displayFill) / math.max(_initialFill, 0.01)).clamp(0.0, 1.0),
        );
      }
    }

    if (_pouring && !_wasPouring) HapticFeedback.selectionClick();
    if (!_pouring && _wasPouring && _displayFill <= 0.015) {
      HapticFeedback.mediumImpact();
    }
    _wasPouring = _pouring;

    _energy *= profile.damping.clamp(0.82, 0.975);
    if (_energy < 0.001) _energy = 0;
    setState(() {});
  }

  void _motionFeedback() {
    final now = DateTime.now();
    if (now.difference(_lastFeedback).inMilliseconds < 340) return;
    _lastFeedback = now;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void _refill() {
    if (_displayFill > 0.04) return;
    setState(() {
      _displayFill = widget.fillLevel.clamp(0.58, 0.94);
      _initialFill = _displayFill;
      _residue = 0;
      _energy = 0.72;
    });
    HapticFeedback.mediumImpact();
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _refill,
      child: CustomPaint(
        painter: _DrinkGlassV2Painter(
          drink: widget.drink,
          profile: profile,
          progress: _controller.value,
          tilt: _tilt,
          energy: _energy,
          fillLevel: _displayFill,
          bubbles: widget.bubbles,
          condensation: widget.condensation,
          pouring: _pouring,
          residue: _residue,
        ),
        child: const SizedBox.expand(),
      ),
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
    required this.pouring,
    required this.residue,
  });

  final Drink drink;
  final DrinkMotionProfile profile;
  final double progress;
  final double tilt;
  final double energy;
  final double fillLevel;
  final bool bubbles;
  final bool condensation;
  final bool pouring;
  final double residue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (fillLevel <= 0.003) {
      _drawResidue(canvas, size);
      return;
    }

    final liquidTop = size.height * (1 - fillLevel.clamp(0.0, 0.98));
    final amplitude = size.height * 0.026 * profile.waveStrength * (0.40 + energy);
    final phase = progress * math.pi * 2 * profile.waveSpeed;

    final liquid = Path()..moveTo(-6, liquidTop);
    const segments = 48;
    for (var i = 0; i <= segments; i++) {
      final nx = i / segments;
      final x = -6 + (size.width + 12) * nx;
      final primary = math.sin(nx * math.pi * 2 + phase) * amplitude;
      final secondary = math.sin(nx * math.pi * 4 - phase * 1.35) * amplitude * 0.30;
      final tiltOffset = (nx - 0.5) * tilt * size.height * 0.28;
      liquid.lineTo(x, liquidTop + primary + secondary + tiltOffset);
    }
    liquid
      ..lineTo(size.width + 6, size.height + 6)
      ..lineTo(-6, size.height + 6)
      ..close();

    final liquidPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(drink.color, Colors.white, 0.20)!.withValues(alpha: 0.96),
          drink.color.withValues(alpha: 0.98),
          Color.lerp(drink.color, Colors.black, 0.40)!.withValues(alpha: 1),
        ],
      ).createShader(rect);
    canvas.drawPath(liquid, liquidPaint);

    final highlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.06),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, highlight);

    if (bubbles) _drawBubbles(canvas, size, liquidTop, phase);
    if (drink.ice) _drawIce(canvas, size, liquidTop, phase);
    if (drink.foam) _drawFoam(canvas, size, liquidTop, phase);
    if (condensation) _drawCondensation(canvas, size);
    if (pouring) _drawPourLip(canvas, size, liquidTop);
    if (residue > 0.02) _drawResidue(canvas, size);
  }

  void _drawBubbles(Canvas canvas, Size size, double liquidTop, double phase) {
    final count = (20 * profile.bubbleDensity).round();
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.44);
    for (var i = 0; i < count; i++) {
      final seed = i * 17.17;
      final x = size.width * (0.06 + ((math.sin(seed) + 1) / 2) * 0.88);
      final travel = (progress * (0.28 + (i % 5) * 0.05) + i * 0.071) % 1;
      final y = size.height - travel * (size.height - liquidTop);
      canvas.drawCircle(Offset(x, y + math.sin(phase + i) * 2), 1.2 + (i % 4) * 0.65, paint);
    }
  }

  void _drawIce(Canvas canvas, Size size, double liquidTop, double phase) {
    for (var i = 0; i < 4; i++) {
      final mobility = profile.iceMobility;
      final x = size.width * (0.20 + i * 0.20) + math.sin(phase + i) * 10 * mobility + tilt * 10;
      final y = liquidTop + size.height * (0.12 + (i % 2) * 0.12) + math.cos(phase * 0.8 + i) * 6 * mobility;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(phase + i) * 0.18 * mobility + tilt * 0.08);
      final cube = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 34, height: 28),
        const Radius.circular(7),
      );
      canvas.drawRRect(
        cube,
        Paint()..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0.56), const Color(0xFFBDEBFF).withValues(alpha: 0.18)]).createShader(cube.outerRect),
      );
      canvas.restore();
    }
  }

  void _drawFoam(Canvas canvas, Size size, double liquidTop, double phase) {
    final height = size.height * 0.065 * profile.foamPersistence * (0.75 + energy * 0.35);
    final foam = Path()..moveTo(-6, liquidTop + height);
    for (var i = 0; i <= 40; i++) {
      final x = -6 + (size.width + 12) * i / 40;
      final y = liquidTop + math.sin(i * 0.82 + phase) * 3.8;
      foam.lineTo(x, y);
    }
    foam
      ..lineTo(size.width + 6, liquidTop + height)
      ..close();
    canvas.drawPath(foam, Paint()..color = const Color(0xFFFFF2D2).withValues(alpha: 0.91));
  }

  void _drawCondensation(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.24);
    for (var i = 0; i < 16; i++) {
      final x = size.width * (0.05 + ((i * 37) % 89) / 100);
      final y = size.height * (0.10 + ((i * 53) % 80) / 100);
      canvas.drawCircle(Offset(x, y), 1.2 + (i % 3) * 0.7, paint);
    }
  }

  void _drawPourLip(Canvas canvas, Size size, double liquidTop) {
    final right = tilt >= 0;
    final x = right ? size.width - 2 : 2.0;
    final path = Path()
      ..moveTo(x, liquidTop)
      ..quadraticBezierTo(right ? size.width + 10 : -10, liquidTop + 12, right ? size.width + 4 : -4, liquidTop + 40);
    canvas.drawPath(path, Paint()..color = drink.color.withValues(alpha: 0.78)..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round);
  }

  void _drawResidue(Canvas canvas, Size size) {
    if (residue <= 0.01) return;
    final paint = Paint()..color = Color.lerp(drink.color, Colors.white, 0.35)!.withValues(alpha: 0.10 + residue * 0.16);
    for (var i = 0; i < 9; i++) {
      final x = size.width * (0.10 + ((i * 23) % 80) / 100);
      final y = size.height * (0.20 + ((i * 31) % 68) / 100);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 5 + (i % 3) * 2, height: 12 + (i % 4) * 5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrinkGlassV2Painter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.tilt != tilt ||
        oldDelegate.energy != energy ||
        oldDelegate.drink != drink ||
        oldDelegate.fillLevel != fillLevel ||
        oldDelegate.pouring != pouring ||
        oldDelegate.residue != residue;
  }
}
