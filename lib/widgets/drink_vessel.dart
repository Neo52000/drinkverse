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
      'DEV • PHYSICS V5.1 • BEER SIM VISUAL';

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
  static const int _columns = 44;

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
  double _flow = 0;
  double _displayFill = 0.72;
  double _initialFill = 0.72;
  double _foam = 0.075;
  double _residue = 0;
  Duration _lastElapsed = Duration.zero;

  bool get _beerMode => widget.drink.foam;

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
    _foam = 0.075;
    _residue = 0;
    _flow = 0;
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

      final vertical = (event.y.abs() / 9.81).clamp(0.0, 1.0).toDouble();
      _pour = (1 - vertical).clamp(0.0, 1.0).toDouble();
    }, onError: (_) {});

    _gyroscope = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _angularVelocity = (event.z * 0.92 + event.y * 0.08)
          .clamp(-12.0, 12.0)
          .toDouble();
      final energy = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _shake = math.max(_shake, (energy / 6.5).clamp(0.0, 1.0).toDouble());

      final impact = (event.y * 0.65 + event.z * 0.35).clamp(-8.0, 8.0);
      final center = event.x >= 0 ? _columns * 2 ~/ 3 : _columns ~/ 3;
      for (var i = 0; i < _columns; i++) {
        final d = i - center;
        _velocity[i] += impact * math.exp(-(d * d) / 52) * 0.038;
      }
    }, onError: (_) {});
  }

  void _tick() {
    if (!mounted || widget.paused) return;
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;

    if (_beerMode) {
      _stepFluid(dt);
      _stepPour(dt);
      setState(() {});
    }
  }

  void _stepFluid(double dt) {
    final acceleration = (_targetTilt - _tilt) * 24 -
        _tiltVelocity * 5.8 +
        _angularVelocity * 0.13;
    _tiltVelocity += acceleration * dt;
    _tilt += _tiltVelocity * dt;
    _tilt = _tilt.clamp(-1.08, 1.08).toDouble();

    const substeps = 5;
    final step = dt / substeps;
    for (var s = 0; s < substeps; s++) {
      for (var i = 0; i < _columns; i++) {
        final x = i / (_columns - 1) * 2 - 1;
        final left = _height[i == 0 ? 1 : i - 1];
        final right = _height[i == _columns - 1 ? _columns - 2 : i + 1];
        final laplacian = left + right - 2 * _height[i];

        // The bulk follows gravity. The secondary wave is deliberately small:
        // beer should feel heavy, not gelatinous.
        final equilibrium = x * _tilt * 0.31;
        final travellingWave = math.sin(
              i * 0.42 - _controller.value * math.pi * 5.2,
            ) *
            _shake *
            0.008;
        final edgeWeight = math.pow(x.abs(), 2).toDouble();
        final wallRebound = -_tiltVelocity * x * edgeWeight * 0.032;

        final force = laplacian * 72 +
            (equilibrium - _height[i]) * 29 -
            _velocity[i] * (6.8 - _shake * 1.5) +
            travellingWave +
            wallRebound;
        _velocity[i] += force * step;
        _next[i] = _height[i] + _velocity[i] * step;
      }

      final mean = _next.reduce((a, b) => a + b) / _columns;
      for (var i = 0; i < _columns; i++) {
        _height[i] = (_next[i] - mean).clamp(-0.46, 0.46).toDouble();
      }
      _velocity.first *= 0.48;
      _velocity.last *= 0.48;
    }

    final foamTarget = 0.072 + _shake * 0.105 + _flow * 0.045;
    _foam += (foamTarget - _foam) * dt * (_shake > 0.2 ? 2.2 : 0.34);
    _foam = _foam.clamp(0.055, 0.19).toDouble();
    _shake *= math.pow(0.035, dt).toDouble();
    _angularVelocity *= math.pow(0.065, dt).toDouble();
  }

  void _stepPour(double dt) {
    if (_displayFill <= 0.001) {
      _flow += (0 - _flow) * dt * 8;
      return;
    }

    final threshold = 0.53 - _displayFill * 0.10;
    final requested = ((_pour - threshold) / (1 - threshold))
        .clamp(0.0, 1.0)
        .toDouble();
    _flow += (requested - _flow) * dt * (requested > _flow ? 10 : 5);
    _flow = _flow.clamp(0.0, 1.0).toDouble();

    if (_flow <= 0.012) return;
    final rate = 0.035 + _flow * _flow * 0.49;
    _displayFill = (_displayFill - rate * dt).clamp(0.0, 0.98).toDouble();
    _shake = math.max(_shake, 0.22 + _flow * 0.52);
    _residue = ((_initialFill - _displayFill) / math.max(_initialFill, 0.01))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _refill() {
    if (!_beerMode || _displayFill > 0.02) return;
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
              if (_beerMode)
                Positioned.fill(
                  child: ClipPath(
                    clipper: _VesselClipper(widget.drink.glassType),
                    child: CustomPaint(
                      painter: _BeerSimulatorPainter(
                        drink: widget.drink,
                        columns: List<double>.unmodifiable(_height),
                        fillLevel: _displayFill,
                        foamDepth: _foam,
                        energy: _shake,
                        residue: _residue,
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
              if (_beerMode && _flow > 0.012)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ExternalPourPainter(
                        drink: widget.drink,
                        columns: List<double>.unmodifiable(_height),
                        fillLevel: _displayFill,
                        foamDepth: _foam,
                        flow: _flow,
                        tilt: _tilt,
                        progress: _controller.value,
                      ),
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

class _BeerSimulatorPainter extends CustomPainter {
  const _BeerSimulatorPainter({
    required this.drink,
    required this.columns,
    required this.fillLevel,
    required this.foamDepth,
    required this.energy,
    required this.residue,
    required this.progress,
  });

  final Drink drink;
  final List<double> columns;
  final double fillLevel;
  final double foamDepth;
  final double energy;
  final double residue;
  final double progress;

  double _surface(double x, Size size) {
    final t = (x / size.width).clamp(0.0, 1.0).toDouble();
    final index = t * (columns.length - 1);
    final a = index.floor();
    final b = math.min(a + 1, columns.length - 1);
    final local = index - a;
    final displacement = columns[a] * (1 - local) + columns[b] * local;
    final top = size.height * 0.035;
    final bottom = size.height * 0.945;
    final base = bottom - (bottom - top) * fillLevel;
    return base + displacement * size.height * 0.31;
  }

  Path _line(Size size, {double offset = 0, double roughness = 0}) {
    final path = Path();
    const samples = 180;
    for (var i = 0; i <= samples; i++) {
      final x = size.width * i / samples;
      final noise = math.sin(i * 0.61 + progress * math.pi * 2.1) * roughness;
      final y = _surface(x, size) + offset + noise;
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

    final liquid = _line(size)
      ..lineTo(size.width, size.height + 2)
      ..lineTo(0, size.height + 2)
      ..close();
    canvas.drawPath(
      liquid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.13, 0.48, 0.78, 1],
          colors: [
            Color.lerp(drink.color, Colors.white, 0.34)!,
            Color.lerp(drink.color, Colors.white, 0.10)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.32)!,
            Color.lerp(drink.color, Colors.black, 0.58)!,
          ],
        ).createShader(Offset.zero & size),
    );

    // Internal luminous band gives the liquid optical depth instead of a flat fill.
    final glow = _line(size, offset: size.height * 0.018)
      ..lineTo(size.width, size.height * 0.72)
      ..lineTo(0, size.height * 0.72)
      ..close();
    canvas.drawPath(
      glow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );

    final foamPx = size.height * foamDepth;
    final foam = _line(size, offset: -foamPx, roughness: 0.7 + energy * 1.4);
    for (var i = 180; i >= 0; i--) {
      final x = size.width * i / 180;
      foam.lineTo(x, _surface(x, size));
    }
    foam.close();
    canvas.drawPath(
      foam,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.38, 0.82, 1],
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFFFAEE),
            Color(0xFFF1D8A8),
            Color(0xFFC99548),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      _line(size, offset: -foamPx, roughness: 0.7 + energy * 1.4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.96),
    );

    // Carbonation rises over time instead of remaining as static dots.
    final carbonation = 105 + (energy * 70).round();
    for (var i = 0; i < carbonation; i++) {
      final rx = ((i * 83 + 17) % 997) / 997;
      final phase = (progress * (0.45 + (i % 7) * 0.07) + i * 0.137) % 1;
      final x = rx * size.width + math.sin(i * 1.7 + progress * 8) * 1.8;
      final top = _surface(x.clamp(0, size.width).toDouble(), size);
      final y = size.height - phase * math.max(size.height - top, 1);
      if (y <= top + 3) continue;
      final radius = 0.55 + (i % 5) * 0.28;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.65
          ..color = Colors.white.withValues(alpha: 0.12 + energy * 0.08),
      );
    }

    final foamBubbles = 72 + (energy * 45).round();
    for (var i = 0; i < foamBubbles; i++) {
      final rx = ((i * 97 + 11) % 991) / 991;
      final depth = ((i * 67 + 23) % 101) / 101;
      final x = rx * size.width;
      final y = _surface(x, size) - foamPx * (0.08 + depth * 0.86);
      final radius = 0.8 + (i % 5) * 0.48;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75
          ..color = Colors.white.withValues(alpha: 0.34),
      );
    }

    if (residue > 0.02) {
      final rings = 3 + (residue * 6).round();
      for (var i = 0; i < rings; i++) {
        final y = size.height * (0.13 + i * 0.072);
        final ring = Path()..moveTo(size.width * 0.19, y);
        for (var s = 1; s <= 48; s++) {
          final x = size.width * (0.19 + 0.62 * s / 48);
          final drip = math.sin(s * 0.67 + i * 1.4) * (1.1 + residue * 2.2);
          ring.lineTo(x, y + drip);
        }
        canvas.drawPath(
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.15
            ..color = const Color(0xFFF4E1B9)
                .withValues(alpha: 0.10 + residue * 0.24),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BeerSimulatorPainter oldDelegate) => true;
}

class _ExternalPourPainter extends CustomPainter {
  const _ExternalPourPainter({
    required this.drink,
    required this.columns,
    required this.fillLevel,
    required this.foamDepth,
    required this.flow,
    required this.tilt,
    required this.progress,
  });

  final Drink drink;
  final List<double> columns;
  final double fillLevel;
  final double foamDepth;
  final double flow;
  final double tilt;
  final double progress;

  double _surface(double x, Size size) {
    final t = (x / size.width).clamp(0.0, 1.0).toDouble();
    final index = t * (columns.length - 1);
    final a = index.floor();
    final b = math.min(a + 1, columns.length - 1);
    final local = index - a;
    final d = columns[a] * (1 - local) + columns[b] * local;
    final base = size.height * 0.945 - size.height * 0.91 * fillLevel;
    return base + d * size.height * 0.31;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final right = tilt >= 0;
    final direction = right ? 1.0 : -1.0;
    final lipX = right ? size.width * 0.835 : size.width * 0.165;
    final lipY = math.min(
      _surface(lipX, size) - size.height * foamDepth * 0.18,
      size.height * 0.075,
    );

    final length = 58 + flow * 155;
    final width = 3.0 + flow * 11;
    final flutter = math.sin(progress * math.pi * 7) * flow * 3.5;
    final stream = Path()
      ..moveTo(lipX - direction * width * 0.45, lipY)
      ..cubicTo(
        lipX + direction * (8 + flutter),
        lipY - 18,
        lipX + direction * (17 + flutter),
        lipY - length * 0.58,
        lipX + direction * (24 + flutter),
        lipY - length,
      )
      ..lineTo(
        lipX + direction * (24 + flutter + width),
        lipY - length,
      )
      ..cubicTo(
        lipX + direction * (22 + flutter + width),
        lipY - length * 0.55,
        lipX + direction * (10 + width),
        lipY - 12,
        lipX + direction * width * 0.5,
        lipY + 2,
      )
      ..close();

    canvas.drawShadow(stream, Colors.black.withValues(alpha: 0.30), 5, false);
    canvas.drawPath(
      stream,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.lerp(drink.color, Colors.black, 0.28)!.withValues(alpha: 0.88),
            Color.lerp(drink.color, Colors.white, 0.30)!.withValues(alpha: 0.94),
            drink.color.withValues(alpha: 0.86),
          ],
        ).createShader(stream.getBounds()),
    );

    if (flow > 0.55) {
      for (var i = 0; i < 3; i++) {
        final phase = (progress * (1.3 + i * 0.2) + i * 0.31) % 1;
        final x = lipX + direction * (26 + flutter + i * 3);
        final y = lipY - length - phase * (18 + flow * 24);
        canvas.drawCircle(
          Offset(x, y),
          1.8 + i * 0.7,
          Paint()..color = drink.color.withValues(alpha: 0.78),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ExternalPourPainter oldDelegate) => true;
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
  bool shouldReclip(covariant _VesselClipper oldClipper) =>
      oldClipper.type != type;
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

    final leftHighlight = Path()
      ..moveTo(size.width * 0.25, size.height * 0.14)
      ..quadraticBezierTo(
        size.width * 0.19,
        size.height * 0.48,
        size.width * 0.29,
        size.height * 0.78,
      );
    canvas.drawPath(
      leftHighlight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.27),
    );
  }

  @override
  bool shouldRepaint(covariant _VesselHighlightPainter oldDelegate) =>
      oldDelegate.type != type;
}
