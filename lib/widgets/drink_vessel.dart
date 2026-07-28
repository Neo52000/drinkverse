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

  static const String debugVersion = 'DEV • PHYSICS V5.0 • PARTICLE VOLUME';

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
  static const int _columns = 28;

  late final AnimationController _controller;
  late final List<double> _height;
  late final List<double> _velocity;
  late final List<double> _next;

  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;

  double _targetTilt = 0;
  double _tilt = 0;
  double _tiltVelocity = 0;
  double _angularVelocity = 0;
  double _shake = 0;
  double _pour = 0;
  double _displayFill = 0.72;
  double _initialFill = 0.72;
  double _foam = 0.08;
  double _residue = 0;
  Duration _lastElapsed = Duration.zero;

  bool get _particleMode => widget.drink.foam;

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
    } else if (oldWidget.fillLevel != widget.fillLevel && _pour < 0.01) {
      _displayFill = widget.fillLevel;
      _initialFill = widget.fillLevel;
    }
  }

  void _reset() {
    _displayFill = widget.fillLevel;
    _initialFill = widget.fillLevel;
    _foam = 0.08;
    _residue = 0;
    for (var i = 0; i < _columns; i++) {
      _height[i] = 0;
      _velocity[i] = 0;
    }
  }

  void _startSensors() {
    _accelerometer = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      final gravity = math.sqrt(event.x * event.x + event.y * event.y);
      if (gravity > 0.01) {
        _targetTilt = (event.x / gravity).clamp(-1.0, 1.0).toDouble();
      }
      final faceDown = (1 - event.y.abs() / 9.81).clamp(0.0, 1.0).toDouble();
      _pour = faceDown;
    }, onError: (_) {});

    _gyroscope = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _angularVelocity = (event.z * 0.9 + event.y * 0.1)
          .clamp(-10.0, 10.0)
          .toDouble();
      final energy = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _shake = math.max(_shake, (energy / 6).clamp(0.0, 1.0).toDouble());
      final side = event.x >= 0 ? _columns * 2 ~/ 3 : _columns ~/ 3;
      for (var i = 0; i < _columns; i++) {
        final d = i - side;
        _velocity[i] += event.y * math.exp(-(d * d) / 30) * 0.05;
      }
    }, onError: (_) {});
  }

  void _tick() {
    if (!mounted || widget.paused) return;
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;

    if (_particleMode) {
      _stepFluid(dt);
      _stepPour(dt);
      setState(() {});
    }
  }

  void _stepFluid(double dt) {
    final acceleration =
        (_targetTilt - _tilt) * 18 - _tiltVelocity * 4.6 + _angularVelocity * 0.18;
    _tiltVelocity += acceleration * dt;
    _tilt += _tiltVelocity * dt;
    _tilt = _tilt.clamp(-1.18, 1.18).toDouble();

    const substeps = 4;
    final step = dt / substeps;
    for (var s = 0; s < substeps; s++) {
      for (var i = 0; i < _columns; i++) {
        final x = i / (_columns - 1) * 2 - 1;
        final left = _height[i == 0 ? 1 : i - 1];
        final right = _height[i == _columns - 1 ? _columns - 2 : i + 1];
        final laplacian = left + right - 2 * _height[i];
        final equilibrium = x * _tilt * 0.40;
        final turbulence = math.sin(
              i * 0.73 + _controller.value * math.pi * 6,
            ) *
            _shake *
            0.012;
        final force = laplacian * 48 +
            (equilibrium - _height[i]) * 22 -
            _velocity[i] * (5.2 - _shake * 1.4) +
            turbulence;
        _velocity[i] += force * step;
        _next[i] = _height[i] + _velocity[i] * step;
      }

      final mean = _next.reduce((a, b) => a + b) / _columns;
      for (var i = 0; i < _columns; i++) {
        _height[i] = (_next[i] - mean).clamp(-0.55, 0.55).toDouble();
      }
      _velocity.first *= 0.62;
      _velocity.last *= 0.62;
    }

    _foam += (_shake * 0.16 - _foam) * dt * 0.7;
    _foam = _foam.clamp(0.045, 0.22).toDouble();
    _shake *= math.pow(0.025, dt).toDouble();
    _angularVelocity *= math.pow(0.08, dt).toDouble();
  }

  void _stepPour(double dt) {
    if (_displayFill <= 0.001) return;
    final threshold = 0.58 - _displayFill * 0.08;
    final flow = ((_pour - threshold) / (1 - threshold))
        .clamp(0.0, 1.0)
        .toDouble();
    if (flow <= 0) return;

    _displayFill = (_displayFill - (0.06 + flow * flow * 0.44) * dt)
        .clamp(0.0, 0.98)
        .toDouble();
    _shake = math.max(_shake, 0.35 + flow * 0.55);
    _residue = ((_initialFill - _displayFill) / math.max(_initialFill, 0.01))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _refill() {
    if (!_particleMode || _displayFill > 0.02) return;
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
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _VesselShadowPainter(type: widget.drink.glassType),
                ),
              ),
              if (_particleMode)
                Positioned.fill(
                  child: ClipPath(
                    clipper: _VesselClipper(widget.drink.glassType),
                    child: CustomPaint(
                      painter: _ParticleBeerPainter(
                        drink: widget.drink,
                        columns: List<double>.unmodifiable(_height),
                        fillLevel: _displayFill,
                        foamDepth: _foam,
                        energy: _shake,
                        residue: _residue,
                        pour: _pour,
                        tilt: _tilt,
                        progress: _controller.value,
                      ),
                    ),
                  ),
                )
              else
                ClipPath(
                  clipper: _VesselClipper(widget.drink.glassType),
                  child: SizedBox(
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
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _VesselHighlightPainter(type: widget.drink.glassType),
                  ),
                ),
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

class _ParticleBeerPainter extends CustomPainter {
  const _ParticleBeerPainter({
    required this.drink,
    required this.columns,
    required this.fillLevel,
    required this.foamDepth,
    required this.energy,
    required this.residue,
    required this.pour,
    required this.tilt,
    required this.progress,
  });

  final Drink drink;
  final List<double> columns;
  final double fillLevel;
  final double foamDepth;
  final double energy;
  final double residue;
  final double pour;
  final double tilt;
  final double progress;

  double _surface(double x, Size size) {
    final t = (x / size.width).clamp(0.0, 1.0).toDouble();
    final index = t * (columns.length - 1);
    final a = index.floor();
    final b = math.min(a + 1, columns.length - 1);
    final local = index - a;
    final displacement = columns[a] * (1 - local) + columns[b] * local;
    final top = size.height * 0.04;
    final bottom = size.height * 0.94;
    final base = bottom - (bottom - top) * fillLevel;
    return base + displacement * size.height * 0.34;
  }

  Path _surfacePath(Size size, {double offset = 0}) {
    final path = Path();
    const samples = 150;
    for (var i = 0; i <= samples; i++) {
      final x = size.width * i / samples;
      final y = _surface(x, size) + offset;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fillLevel <= 0.001) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Verre vide\nTouchez pour resservir',
          style: TextStyle(color: Colors.white70, fontSize: 18, height: 1.4),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 32);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height * 0.42));
      return;
    }

    final liquid = _surfacePath(size)
      ..lineTo(size.width, size.height + 2)
      ..lineTo(0, size.height + 2)
      ..close();

    canvas.drawPath(
      liquid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(drink.color, Colors.white, 0.18)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.48)!,
          ],
        ).createShader(Offset.zero & size),
    );

    final foamPx = size.height * foamDepth;
    final foam = _surfacePath(size, offset: -foamPx)
      ..lineTo(size.width, _surface(size.width, size))
      ..addPath(_surfacePath(size), Offset.zero)
      ..close();
    canvas.drawPath(
      foam,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF7E8C8), Color(0xFFDAB873)],
        ).createShader(Offset.zero & size),
    );

    final crest = _surfacePath(size, offset: -foamPx);
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    final particles = 90 + (energy * 70).round();
    for (var i = 0; i < particles; i++) {
      final rx = ((i * 73 + 19) % 997) / 997;
      final ry = ((i * 151 + 37) % 991) / 991;
      final x = rx * size.width;
      final top = _surface(x, size);
      final y = top + ry * math.max(size.height - top, 1);
      final radius = 0.7 + (i % 5) * 0.32;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = Colors.white.withValues(alpha: 0.08 + energy * 0.08),
      );
    }

    final foamBubbles = 38 + (energy * 36).round();
    for (var i = 0; i < foamBubbles; i++) {
      final rx = ((i * 89 + 7) % 983) / 983;
      final depth = ((i * 61 + 13) % 101) / 101;
      final x = rx * size.width;
      final y = _surface(x, size) - foamPx * (0.1 + depth * 0.82);
      canvas.drawCircle(
        Offset(x, y),
        1.0 + (i % 4) * 0.65,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.32),
      );
    }

    if (residue > 0.03) {
      for (var i = 0; i < 5; i++) {
        final y = size.height * (0.16 + i * 0.105);
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(size.width * 0.5, y),
            width: size.width * (0.55 + i * 0.025),
            height: 10 + i * 2,
          ),
          0,
          math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFFF3DFB5)
                .withValues(alpha: residue * (0.18 + i * 0.025)),
        );
      }
    }

    final flow = ((pour - 0.55) / 0.45).clamp(0.0, 1.0).toDouble();
    if (flow > 0.02) {
      final right = tilt >= 0;
      final x = right ? size.width * 0.82 : size.width * 0.18;
      final direction = right ? 1.0 : -1.0;
      final y = _surface(x, size) - foamPx * 0.45;
      final stream = Path()
        ..moveTo(x, y)
        ..cubicTo(
          x + 12 * direction,
          y - 14,
          x + 22 * direction,
          y - 45,
          x + 28 * direction,
          y - 86 - flow * 35,
        );
      canvas.drawPath(
        stream,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5 + flow * 8
          ..color = drink.color.withValues(alpha: 0.90),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleBeerPainter oldDelegate) => true;
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

class _VesselClipper extends CustomClipper<Path> {
  const _VesselClipper(this.type);
  final GlassType type;

  @override
  Path getClip(Size size) => _buildVesselPath(size, type);

  @override
  bool shouldReclip(covariant _VesselClipper oldClipper) => oldClipper.type != type;
}

Path _buildVesselPath(Size size, GlassType type) {
  final w = size.width;
  final h = size.height;
  final path = Path();
  switch (type) {
    case GlassType.pint:
      path
        ..moveTo(w * 0.16, h * 0.04)
        ..quadraticBezierTo(w * 0.50, 0, w * 0.84, h * 0.04)
        ..lineTo(w * 0.73, h * 0.92)
        ..quadraticBezierTo(w * 0.50, h * 0.99, w * 0.27, h * 0.92)
        ..close();
    case GlassType.highball:
      path
        ..moveTo(w * 0.20, h * 0.03)
        ..quadraticBezierTo(w * 0.50, 0, w * 0.80, h * 0.03)
        ..lineTo(w * 0.72, h * 0.94)
        ..quadraticBezierTo(w * 0.50, h * 0.98, w * 0.28, h * 0.94)
        ..close();
    case GlassType.cocktail:
      path
        ..moveTo(w * 0.08, h * 0.05)
        ..lineTo(w * 0.92, h * 0.05)
        ..quadraticBezierTo(w * 0.77, h * 0.37, w * 0.56, h * 0.51)
        ..lineTo(w * 0.55, h * 0.82)
        ..lineTo(w * 0.72, h * 0.90)
        ..quadraticBezierTo(w * 0.50, h * 0.98, w * 0.28, h * 0.90)
        ..lineTo(w * 0.45, h * 0.82)
        ..lineTo(w * 0.44, h * 0.51)
        ..quadraticBezierTo(w * 0.23, h * 0.37, w * 0.08, h * 0.05)
        ..close();
    case GlassType.mug:
      path
        ..moveTo(w * 0.16, h * 0.10)
        ..quadraticBezierTo(w * 0.50, h * 0.04, w * 0.76, h * 0.10)
        ..lineTo(w * 0.74, h * 0.86)
        ..quadraticBezierTo(w * 0.50, h * 0.94, w * 0.20, h * 0.86)
        ..close();
  }
  return path;
}

class _VesselShadowPainter extends CustomPainter {
  const _VesselShadowPainter({required this.type});
  final GlassType type;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawShadow(
      _buildVesselPath(size, type),
      Colors.black.withValues(alpha: 0.8),
      22,
      true,
    );
  }

  @override
  bool shouldRepaint(covariant _VesselShadowPainter oldDelegate) =>
      oldDelegate.type != type;
}

class _VesselHighlightPainter extends CustomPainter {
  const _VesselHighlightPainter({required this.type});
  final GlassType type;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildVesselPath(size, type);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xCCFFFFFF), Color(0x22FFFFFF), Color(0x6686D8FF)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _VesselHighlightPainter oldDelegate) =>
      oldDelegate.type != type;
}
