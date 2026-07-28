import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/drink.dart';
import '../physics/fluid_solver.dart';
import '../physics/gravity_engine.dart';
import '../physics/pour_engine.dart';
import 'drink_glass.dart';

class DrinkVessel extends StatefulWidget {
  const DrinkVessel({
    super.key,
    required this.drink,
    this.fillLevel = 0.72,
    this.bubbles = true,
    this.condensation = true,
    this.paused = false,
  });

  static const String debugVersion =
      'DEV • PHYSICS V7.0 • REFACTORED ENGINES';

  final Drink drink;
  final double fillLevel;
  final bool bubbles;
  final bool condensation;
  final bool paused;

  @override
  State<DrinkVessel> createState() => _DrinkVesselState();
}

class _DrinkVesselState extends State<DrinkVessel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final FluidSolver _fluid;
  late final PourEngine _pourEngine;
  final GravityEngine _gravityEngine = const GravityEngine();

  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;

  double _gravityX = 0;
  double _gravityY = 1;
  double _targetSlope = 0;
  double _pour = 0;
  Duration _lastElapsed = Duration.zero;

  bool get _screenGlassMode => widget.drink.foam;

  @override
  void initState() {
    super.initState();
    _fluid = FluidSolver(columns: 64);
    _pourEngine = PourEngine(widget.fillLevel);
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(_tick)
      ..repeat(min: 0, max: 1, period: const Duration(seconds: 1));
    _startSensors();
  }

  @override
  void didUpdateWidget(covariant DrinkVessel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drink != widget.drink) {
      _reset();
    } else if (oldWidget.fillLevel != widget.fillLevel) {
      _pourEngine.syncFill(widget.fillLevel);
    }
  }

  void _reset() {
    _fluid.reset();
    _pourEngine.reset(widget.fillLevel);
  }

  void _startSensors() {
    _accelerometer = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      final sample = _gravityEngine.fromAccelerometer(
        event.x,
        event.y,
        event.z,
      );
      _gravityX = sample.x;
      _gravityY = sample.y;
      _targetSlope = sample.slope;
      _pour = sample.pour;
    }, onError: (_) {});

    _gyroscope = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _fluid.applyGyroscope(event.x, event.y, event.z);
    }, onError: (_) {});
  }

  void _tick() {
    if (!mounted || widget.paused) return;
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;

    if (!_screenGlassMode) return;

    _pourEngine.step(dt: dt, pour: _pour);
    if (_pourEngine.flow > 0.012) {
      _fluid.addPourEnergy(_pourEngine.flow);
    }
    _fluid.step(
      dt: dt,
      targetSlope: _targetSlope,
      flow: _pourEngine.flow,
      progress: _controller.value,
    );
    setState(() {});
  }

  void _refill() {
    if (!_screenGlassMode || _pourEngine.displayFill > 0.02) return;
    setState(_reset);
  }

  Drink get _legacyDrink => Drink(
        name: widget.drink.name,
        category: widget.drink.category,
        icon: widget.drink.icon,
        color: widget.drink.color,
        subtitle: widget.drink.subtitle,
        foam: false,
        ice: widget.drink.ice,
        glassType: widget.drink.glassType,
      );

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
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _refill,
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              if (_screenGlassMode)
                CustomPaint(
                  painter: _ScreenGlassPainter(
                    drink: widget.drink,
                    columns: List<double>.unmodifiable(_fluid.height),
                    fillLevel: _pourEngine.displayFill,
                    foamDepth: _fluid.foam,
                    energy: _fluid.motionEnergy,
                    residue: _pourEngine.residue,
                    flow: _pourEngine.flow,
                    slope: _fluid.slope,
                    gravityX: _gravityX,
                    gravityY: _gravityY,
                    progress: _controller.value,
                  ),
                )
              else
                SizedBox(
                  width: size.width,
                  height: size.height,
                  child: DrinkGlass(
                    drink: _legacyDrink,
                    fillLevel: widget.fillLevel,
                    bubbles: widget.bubbles,
                    condensation: widget.condensation,
                    paused: widget.paused,
                  ),
                ),
              if (_screenGlassMode)
                const IgnorePointer(
                  child: CustomPaint(painter: _ScreenEdgePainter()),
                ),
              const Positioned(
                top: 12,
                right: 12,
                child: IgnorePointer(child: _DebugVersionBadge()),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _ScreenGlassPainter extends CustomPainter {
  const _ScreenGlassPainter({
    required this.drink,
    required this.columns,
    required this.fillLevel,
    required this.foamDepth,
    required this.energy,
    required this.residue,
    required this.flow,
    required this.slope,
    required this.gravityX,
    required this.gravityY,
    required this.progress,
  });

  final Drink drink;
  final List<double> columns;
  final double fillLevel;
  final double foamDepth;
  final double energy;
  final double residue;
  final double flow;
  final double slope;
  final double gravityX;
  final double gravityY;
  final double progress;

  double _surface(double x, Size size) {
    final t = (x / size.width).clamp(0.0, 1.0).toDouble();
    final index = t * (columns.length - 1);
    final a = index.floor();
    final b = math.min(a + 1, columns.length - 1);
    final local = index - a;
    final displacement = columns[a] * (1 - local) + columns[b] * local;
    return size.height * (1 - fillLevel.clamp(0.0, 1.0)) +
        displacement * size.height * 0.44;
  }

  Path _surfaceLine(Size size, {double offset = 0, double roughness = 0}) {
    final path = Path();
    const samples = 240;
    for (var i = 0; i <= samples; i++) {
      final x = size.width * i / samples;
      final noise = math.sin(i * 0.53 + progress * math.pi * 2.4) * roughness;
      final y = _surface(x, size) + offset + noise;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101214), Color(0xFF050607)],
        ).createShader(Offset.zero & size),
    );

    if (fillLevel <= 0.001) {
      final text = TextPainter(
        text: const TextSpan(
          text: 'Verre vide\nTouchez l’écran pour resservir',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 20,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 40);
      text.paint(canvas, Offset((size.width - text.width) / 2, size.height * 0.42));
      return;
    }

    final liquid = _surfaceLine(size)
      ..lineTo(size.width, size.height + 2)
      ..lineTo(0, size.height + 2)
      ..close();
    canvas.drawPath(
      liquid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-0.75 + gravityX * 0.18, -1),
          end: Alignment(0.65 - gravityX * 0.12, 1),
          stops: const [0, 0.12, 0.42, 0.76, 1],
          colors: [
            Color.lerp(drink.color, Colors.white, 0.38)!,
            Color.lerp(drink.color, Colors.white, 0.12)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.34)!,
            Color.lerp(drink.color, Colors.black, 0.64)!,
          ],
        ).createShader(Offset.zero & size),
    );

    final foamPx = size.height * foamDepth;
    final foam = _surfaceLine(
      size,
      offset: -foamPx,
      roughness: 0.8 + energy * 1.8,
    );
    for (var i = 240; i >= 0; i--) {
      final x = size.width * i / 240;
      foam.lineTo(x, _surface(x, size));
    }
    foam.close();
    canvas.drawPath(
      foam,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFFFBF1),
            Color(0xFFF1DCB1),
            Color(0xFFC99344),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      _surfaceLine(
        size,
        offset: -foamPx,
        roughness: 0.8 + energy * 1.8,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.96),
    );

    final carbonation = 150 + (energy * 90).round();
    for (var i = 0; i < carbonation; i++) {
      final seedX = ((i * 83 + 17) % 997) / 997;
      final phase = (progress * (0.42 + (i % 8) * 0.055) + i * 0.131) % 1;
      final x = seedX * size.width - gravityX * phase * 18;
      final top = _surface(x.clamp(0.0, size.width).toDouble(), size);
      final y = size.height - phase * math.max(size.height - top, 1) -
          gravityY * phase * 8;
      if (x < 0 || x > size.width || y <= top + 4 || y > size.height) continue;
      canvas.drawCircle(
        Offset(x, y),
        0.6 + (i % 6) * 0.28,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = Colors.white.withValues(alpha: 0.13 + energy * 0.10),
      );
    }

    if (flow > 0.02) {
      final edgeX = slope >= 0 ? size.width : 0.0;
      final edgeY = _surface(edgeX, size) - foamPx * 0.2;
      final direction = slope >= 0 ? 1.0 : -1.0;
      final stream = Path()
        ..moveTo(edgeX, edgeY)
        ..cubicTo(
          edgeX + direction * (18 + flow * 18),
          edgeY + 10,
          edgeX + direction * (28 + flow * 42),
          edgeY + 68,
          edgeX + direction * (36 + flow * 60),
          edgeY + 155 + flow * 120,
        );
      canvas.drawPath(
        stream,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 7 + flow * 14
          ..color = drink.color.withValues(alpha: 0.92),
      );
    }

    if (residue > 0.02) {
      final rings = 3 + (residue * 7).round();
      for (var i = 0; i < rings; i++) {
        final y = size.height * (0.09 + i * 0.062);
        final ring = Path()..moveTo(0, y);
        for (var s = 1; s <= 72; s++) {
          final x = size.width * s / 72;
          ring.lineTo(
            x,
            y + math.sin(s * 0.59 + i * 1.37) * (1.2 + residue * 2.8),
          );
        }
        canvas.drawPath(
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25
            ..color = const Color(0xFFF4E1B9)
                .withValues(alpha: 0.10 + residue * 0.24),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenGlassPainter oldDelegate) => true;
}

class _ScreenEdgePainter extends CustomPainter {
  const _ScreenEdgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final left = Rect.fromLTWH(0, 0, size.width * 0.075, size.height);
    final right = Rect.fromLTWH(size.width * 0.925, 0, size.width * 0.075, size.height);
    canvas.drawRect(
      left,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white.withValues(alpha: 0.24), Colors.transparent],
        ).createShader(left),
    );
    canvas.drawRect(
      right,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent],
        ).createShader(right),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: 0.23),
    );
  }

  @override
  bool shouldRepaint(covariant _ScreenEdgePainter oldDelegate) => false;
}

class _DebugVersionBadge extends StatelessWidget {
  const _DebugVersionBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          DrinkVessel.debugVersion,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.45,
          ),
        ),
      ),
    );
  }
}