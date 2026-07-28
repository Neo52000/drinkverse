import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/drink.dart';
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
      'DEV • PHYSICS V6.0 • SCREEN IS THE GLASS';

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
  static const int _columns = 64;

  late final AnimationController _controller;
  late final List<double> _height;
  late final List<double> _velocity;
  late final List<double> _next;

  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;

  double _gravityX = 0;
  double _gravityY = 1;
  double _targetSlope = 0;
  double _slope = 0;
  double _slopeVelocity = 0;
  double _rotationImpulse = 0;
  double _motionEnergy = 0;
  double _pour = 0;
  double _flow = 0;
  double _displayFill = 0.72;
  double _initialFill = 0.72;
  double _foam = 0.085;
  double _residue = 0;
  Duration _lastElapsed = Duration.zero;

  bool get _screenGlassMode => widget.drink.foam;

  @override
  void initState() {
    super.initState();
    _displayFill = widget.fillLevel;
    _initialFill = widget.fillLevel;
    _height = List<double>.filled(_columns, 0);
    _velocity = List<double>.filled(_columns, 0);
    _next = List<double>.filled(_columns, 0);
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
    } else if (oldWidget.fillLevel != widget.fillLevel && _flow < 0.01) {
      _displayFill = widget.fillLevel;
      _initialFill = widget.fillLevel;
    }
  }

  void _reset() {
    _displayFill = widget.fillLevel;
    _initialFill = widget.fillLevel;
    _foam = 0.085;
    _residue = 0;
    _flow = 0;
    _slope = 0;
    _slopeVelocity = 0;
    for (var i = 0; i < _columns; i++) {
      _height[i] = 0;
      _velocity[i] = 0;
    }
  }

  void _startSensors() {
    _accelerometer = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      final magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      if (magnitude > 0.1) {
        _gravityX = (event.x / magnitude).clamp(-1.0, 1.0).toDouble();
        _gravityY = (event.y / magnitude).clamp(-1.0, 1.0).toDouble();
        _targetSlope = (_gravityX / math.max(_gravityY.abs(), 0.22))
            .clamp(-1.35, 1.35)
            .toDouble();
        _pour = (1 - _gravityY.abs()).clamp(0.0, 1.0).toDouble();
      }
    }, onError: (_) {});

    _gyroscope = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _rotationImpulse = (event.z * 0.88 + event.y * 0.12)
          .clamp(-14.0, 14.0)
          .toDouble();
      final energy = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _motionEnergy = math.max(
        _motionEnergy,
        (energy / 7.0).clamp(0.0, 1.0).toDouble(),
      );

      final center = event.x >= 0 ? _columns * 3 ~/ 4 : _columns ~/ 4;
      final impulse = (event.y * 0.72 + event.z * 0.28).clamp(-9.0, 9.0);
      for (var i = 0; i < _columns; i++) {
        final distance = i - center;
        _velocity[i] += impulse * math.exp(-(distance * distance) / 90) * 0.032;
      }
    }, onError: (_) {});
  }

  void _tick() {
    if (!mounted || widget.paused) return;
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;

    if (_screenGlassMode) {
      _stepScreenFluid(dt);
      _stepPour(dt);
      setState(() {});
    }
  }

  void _stepScreenFluid(double dt) {
    final slopeAcceleration = (_targetSlope - _slope) * 28 -
        _slopeVelocity * 6.4 +
        _rotationImpulse * 0.16;
    _slopeVelocity += slopeAcceleration * dt;
    _slope += _slopeVelocity * dt;
    _slope = _slope.clamp(-1.45, 1.45).toDouble();

    const substeps = 6;
    final step = dt / substeps;
    for (var s = 0; s < substeps; s++) {
      for (var i = 0; i < _columns; i++) {
        final x = i / (_columns - 1) * 2 - 1;
        final left = _height[i == 0 ? 1 : i - 1];
        final right = _height[i == _columns - 1 ? _columns - 2 : i + 1];
        final laplacian = left + right - 2 * _height[i];
        final equilibrium = x * _slope * 0.42;
        final travellingWave = math.sin(
              i * 0.34 - _controller.value * math.pi * 4.8,
            ) *
            _motionEnergy *
            0.006;
        final wallPressure = -_slopeVelocity * x * x.abs() * 0.045;
        final force = laplacian * 96 +
            (equilibrium - _height[i]) * 34 -
            _velocity[i] * (7.4 - _motionEnergy * 1.9) +
            travellingWave +
            wallPressure;
        _velocity[i] += force * step;
        _next[i] = _height[i] + _velocity[i] * step;
      }

      final mean = _next.reduce((a, b) => a + b) / _columns;
      for (var i = 0; i < _columns; i++) {
        _height[i] = (_next[i] - mean).clamp(-0.62, 0.62).toDouble();
      }
      _velocity.first *= 0.38;
      _velocity.last *= 0.38;
    }

    final foamTarget = 0.082 + _motionEnergy * 0.12 + _flow * 0.055;
    _foam += (foamTarget - _foam) * dt * (_motionEnergy > 0.16 ? 2.6 : 0.28);
    _foam = _foam.clamp(0.06, 0.22).toDouble();
    _motionEnergy *= math.pow(0.032, dt).toDouble();
    _rotationImpulse *= math.pow(0.055, dt).toDouble();
  }

  void _stepPour(double dt) {
    if (_displayFill <= 0.001) {
      _flow += (0 - _flow) * dt * 9;
      return;
    }

    final threshold = 0.58 - _displayFill * 0.13;
    final requested = ((_pour - threshold) / (1 - threshold))
        .clamp(0.0, 1.0)
        .toDouble();
    _flow += (requested - _flow) * dt * (requested > _flow ? 11 : 5.5);
    _flow = _flow.clamp(0.0, 1.0).toDouble();

    if (_flow <= 0.012) return;
    final rate = 0.03 + _flow * _flow * 0.54;
    _displayFill = (_displayFill - rate * dt).clamp(0.0, 0.98).toDouble();
    _motionEnergy = math.max(_motionEnergy, 0.24 + _flow * 0.56);
    _residue = ((_initialFill - _displayFill) / math.max(_initialFill, 0.01))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _refill() {
    if (!_screenGlassMode || _displayFill > 0.02) return;
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
                    columns: List<double>.unmodifiable(_height),
                    fillLevel: _displayFill,
                    foamDepth: _foam,
                    energy: _motionEnergy,
                    residue: _residue,
                    flow: _flow,
                    slope: _slope,
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
                const IgnorePointer(child: CustomPaint(painter: _ScreenEdgePainter())),
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
    final base = size.height * (1 - fillLevel.clamp(0.0, 1.0));
    return base + displacement * size.height * 0.44;
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
      final tp = TextPainter(
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
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height * 0.42));
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

    final glow = _surfaceLine(size, offset: size.height * 0.015)
      ..lineTo(size.width, size.height * 0.56)
      ..lineTo(0, size.height * 0.56)
      ..close();
    canvas.drawPath(
      glow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.20),
            Colors.transparent,
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
          stops: [0, 0.35, 0.78, 1],
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
        ..strokeWidth = 3.0
        ..color = Colors.white.withValues(alpha: 0.96),
    );

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

    final carbonation = 150 + (energy * 90).round();
    final upwardX = -gravityX;
    final upwardY = -gravityY;
    for (var i = 0; i < carbonation; i++) {
      final seedX = ((i * 83 + 17) % 997) / 997;
      final phase = (progress * (0.42 + (i % 8) * 0.055) + i * 0.131) % 1;
      final x = seedX * size.width + upwardX * phase * 18 + math.sin(i * 1.7) * 2;
      final top = _surface(x.clamp(0.0, size.width).toDouble(), size);
      final y = size.height - phase * math.max(size.height - top, 1) + upwardY * phase * 8;
      if (x < 0 || x > size.width || y <= top + 4 || y > size.height) continue;
      final radius = 0.6 + (i % 6) * 0.28;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = Colors.white.withValues(alpha: 0.13 + energy * 0.10),
      );
    }

    final foamBubbles = 96 + (energy * 58).round();
    for (var i = 0; i < foamBubbles; i++) {
      final rx = ((i * 97 + 11) % 991) / 991;
      final depth = ((i * 67 + 23) % 101) / 101;
      final x = rx * size.width;
      final y = _surface(x, size) - foamPx * (0.08 + depth * 0.86);
      canvas.drawCircle(
        Offset(x, y),
        0.9 + (i % 5) * 0.52,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75
          ..color = Colors.white.withValues(alpha: 0.36),
      );
    }

    if (residue > 0.02) {
      final rings = 3 + (residue * 7).round();
      for (var i = 0; i < rings; i++) {
        final y = size.height * (0.09 + i * 0.062);
        final ring = Path()..moveTo(0, y);
        for (var s = 1; s <= 72; s++) {
          final x = size.width * s / 72;
          final drip = math.sin(s * 0.59 + i * 1.37) * (1.2 + residue * 2.8);
          ring.lineTo(x, y + drip);
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
    final top = Rect.fromLTWH(0, 0, size.width, size.height * 0.045);

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
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.15), Colors.transparent],
        ).createShader(top),
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
