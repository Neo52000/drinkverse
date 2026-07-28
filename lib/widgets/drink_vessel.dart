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

  static const String debugVersion = 'DEV • PHYSICS V4.0 • COUPLED VOLUME';

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
  static const int _surfacePointCount = 72;

  late final AnimationController _controller;
  late final List<double> _surface;
  late final List<double> _velocity;
  late final List<double> _next;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  double _accelerometerTilt = 0;
  double _fusedTilt = 0;
  double _liquidTilt = 0;
  double _liquidTiltVelocity = 0;
  double _gyroRoll = 0;
  double _gyroYaw = 0;
  double _motionEnergy = 0;
  double _foamEnergy = 0;
  double _drinkAngle = 0;
  double _displayFill = 0.72;
  double _initialFill = 0.72;
  double _residue = 0;
  bool _sensorActive = false;
  bool _pouring = false;
  Duration _lastElapsed = Duration.zero;

  bool get _usesVolumeSolver => widget.drink.foam;

  @override
  void initState() {
    super.initState();
    _displayFill = widget.fillLevel;
    _initialFill = widget.fillLevel;
    _surface = List<double>.filled(_surfacePointCount, 0);
    _velocity = List<double>.filled(_surfacePointCount, 0);
    _next = List<double>.filled(_surfacePointCount, 0);
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(_tick)
      ..repeat(min: 0, max: 1, period: const Duration(seconds: 1));
    _startSensors();
  }

  @override
  void didUpdateWidget(covariant DrinkVessel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fillLevel != widget.fillLevel && !_pouring) {
      _displayFill = widget.fillLevel;
      _initialFill = widget.fillLevel;
    }
    if (oldWidget.drink != widget.drink) {
      _displayFill = widget.fillLevel;
      _initialFill = widget.fillLevel;
      _residue = 0;
      for (var i = 0; i < _surfacePointCount; i++) {
        _surface[i] = 0;
        _velocity[i] = 0;
      }
    }
  }

  void _startSensors() {
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _sensorActive = true;
        final horizontal = (event.x / 9.81).clamp(-1.0, 1.0).toDouble();
        _accelerometerTilt = horizontal.abs() < 0.012 ? 0 : horizontal;
        final vertical = (event.y.abs() / 9.81).clamp(0.0, 1.0).toDouble();
        _drinkAngle = (1 - vertical).clamp(0.0, 1.0).toDouble();
      },
      onError: (_) => _sensorActive = false,
      cancelOnError: false,
    );

    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _gyroRoll = (event.z * 0.88 + event.y * 0.12)
            .clamp(-12.0, 12.0)
            .toDouble();
        _gyroYaw = event.x.clamp(-12.0, 12.0).toDouble();
        final magnitude = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );
        final normalized = (magnitude / 7.0).clamp(0.0, 1.0).toDouble();
        _motionEnergy = math.max(_motionEnergy, normalized);
        _foamEnergy = math.max(_foamEnergy, normalized * 0.92);
        _injectImpulse((event.y * 0.75 + event.z * 0.55) * 0.32, event.x);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _injectImpulse(double strength, double axis) {
    if (!_usesVolumeSolver) return;
    final center = axis >= 0 ? _surfacePointCount * 2 ~/ 3 : _surfacePointCount ~/ 3;
    for (var i = 0; i < _surfacePointCount; i++) {
      final distance = (i - center).abs();
      final influence = math.exp(-distance * distance / 95);
      _velocity[i] += strength * influence;
    }
  }

  void _tick() {
    if (!mounted || widget.paused) return;
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;

    if (_usesVolumeSolver) {
      _stepVolumeSolver(dt);
      _updatePouring(dt);
    }

    _motionEnergy *= 0.972;
    _foamEnergy *= 0.986;
    _gyroRoll *= 0.91;
    _gyroYaw *= 0.92;
    if (_usesVolumeSolver) setState(() {});
  }

  void _stepVolumeSolver(double dt) {
    final fallback = math.sin(_controller.value * math.pi * 2) * 0.006;
    if (_sensorActive) {
      final predicted = _fusedTilt + _gyroRoll * dt * 0.36;
      _fusedTilt = (predicted * 0.94 + _accelerometerTilt * 0.06)
          .clamp(-1.15, 1.15)
          .toDouble();
    } else {
      _fusedTilt = fallback;
    }

    final mass = 0.56 + _displayFill * 0.95;
    final tiltAcceleration =
        (_fusedTilt - _liquidTilt) * (35 / mass) - _liquidTiltVelocity * 7.2;
    _liquidTiltVelocity += tiltAcceleration * dt;
    _liquidTilt += _liquidTiltVelocity * dt;

    const subSteps = 3;
    final subDt = dt / subSteps;
    for (var sub = 0; sub < subSteps; sub++) {
      final propagation = 36 + _motionEnergy * 12;
      final spring = 14 + _motionEnergy * 5;
      final damping = 3.7 + (1 - _motionEnergy) * 0.7;
      final tiltScale = 52 / mass;

      for (var i = 0; i < _surfacePointCount; i++) {
        final nx = i / (_surfacePointCount - 1) * 2 - 1;
        final left = i == 0 ? _surface[1] : _surface[i - 1];
        final right = i == _surfacePointCount - 1
            ? _surface[_surfacePointCount - 2]
            : _surface[i + 1];
        final laplacian = left + right - 2 * _surface[i];
        final vortex = math.sin(
              nx * math.pi * 2 +
                  _controller.value * math.pi * 4 +
                  _gyroYaw * 0.08,
            ) *
            _motionEnergy *
            4.8;
        final equilibrium = nx * _liquidTilt * tiltScale + vortex;
        final acceleration = laplacian * propagation +
            (equilibrium - _surface[i]) * spring -
            _velocity[i] * damping;
        _velocity[i] += acceleration * subDt;
        _next[i] = (_surface[i] + _velocity[i] * subDt)
            .clamp(-110.0, 110.0)
            .toDouble();
      }

      final mean = _next.reduce((a, b) => a + b) / _surfacePointCount;
      for (var i = 0; i < _surfacePointCount; i++) {
        _surface[i] = _next[i] - mean;
      }
      _velocity[0] *= 0.78;
      _velocity[_surfacePointCount - 1] *= 0.78;
    }
  }

  void _updatePouring(double dt) {
    _pouring = false;
    if (_displayFill <= 0.001) return;
    final threshold = 0.44 + _displayFill * 0.07;
    final factor = ((_drinkAngle - threshold) / (1 - threshold))
        .clamp(0.0, 1.0)
        .toDouble();
    _pouring = factor > 0.02;
    if (!_pouring) return;

    final flowRate = 0.028 + math.pow(factor, 1.32) * 0.42;
    _displayFill = (_displayFill - flowRate * dt)
        .clamp(0.0, 0.98)
        .toDouble();
    _motionEnergy = math.max(_motionEnergy, 0.3 + factor * 0.65);
    _foamEnergy = math.max(_foamEnergy, 0.24 + factor * 0.56);
    _residue = math.max(
      _residue,
      ((_initialFill - _displayFill) / math.max(_initialFill, 0.01))
          .clamp(0.0, 1.0)
          .toDouble(),
    );
    final edge = _liquidTilt >= 0 ? _surfacePointCount - 1 : 0;
    _velocity[edge] += (_liquidTilt >= 0 ? 1 : -1) * factor * 1.1;
  }

  void _refill() {
    if (!_usesVolumeSolver || _displayFill > 0.025) return;
    setState(() {
      _displayFill = widget.fillLevel.clamp(0.55, 0.94).toDouble();
      _initialFill = _displayFill;
      _residue = 0;
      _foamEnergy = 0.85;
      _motionEnergy = 0.55;
    });
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
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _controller
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _refill,
          child: RepaintBoundary(
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _VesselShadowPainter(type: widget.drink.glassType),
                  ),
                ),
                if (_usesVolumeSolver)
                  Positioned.fill(
                    child: ClipPath(
                      clipper: _VesselClipper(widget.drink.glassType),
                      child: CustomPaint(
                        painter: _CoupledVolumePainter(
                          drink: widget.drink,
                          surface: List<double>.unmodifiable(_surface),
                          fillLevel: _displayFill,
                          motionEnergy: _motionEnergy,
                          foamEnergy: _foamEnergy,
                          tilt: _liquidTilt,
                          pouring: _pouring,
                          drinkAngle: _drinkAngle,
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
                      width: width,
                      height: height,
                      child: Transform.scale(
                        scaleX: _liquidOverscan(widget.drink.glassType).width,
                        scaleY: _liquidOverscan(widget.drink.glassType).height,
                        alignment: Alignment.center,
                        child: DrinkGlass(
                          drink: _legacyDrink,
                          fillLevel: widget.fillLevel,
                          bubbles: widget.bubbles,
                          condensation: widget.condensation,
                          paused: widget.paused,
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
      },
    );
  }
}

class _CoupledVolumePainter extends CustomPainter {
  const _CoupledVolumePainter({
    required this.drink,
    required this.surface,
    required this.fillLevel,
    required this.motionEnergy,
    required this.foamEnergy,
    required this.tilt,
    required this.pouring,
    required this.drinkAngle,
    required this.residue,
    required this.progress,
  });

  final Drink drink;
  final List<double> surface;
  final double fillLevel;
  final double motionEnergy;
  final double foamEnergy;
  final double tilt;
  final bool pouring;
  final double drinkAngle;
  final double residue;
  final double progress;

  double _baseTop(Size size) {
    final top = size.height * 0.035;
    final bottom = size.height * 0.94;
    return bottom - (bottom - top) * fillLevel.clamp(0.0, 1.0);
  }

  double _surfaceAt(double x, Size size) {
    final ratio = (x / size.width).clamp(0.0, 1.0).toDouble();
    final scaled = ratio * (surface.length - 1);
    final low = scaled.floor().clamp(0, surface.length - 1);
    final high = math.min(low + 1, surface.length - 1);
    final t = scaled - low;
    final displacement = surface[low] * (1 - t) + surface[high] * t;
    final micro = math.sin(ratio * math.pi * 7 + progress * math.pi * 2.2) *
        (0.4 + motionEnergy * 1.7);
    return _baseTop(size) + displacement * (size.width / 286) + micro;
  }

  Path _liquidPath(Size size) {
    final path = Path();
    const segments = 180;
    for (var i = 0; i <= segments; i++) {
      final x = size.width * i / segments;
      final y = _surfaceAt(x, size);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path
      ..lineTo(size.width, size.height + 2)
      ..lineTo(0, size.height + 2)
      ..close();
  }

  Path _foamPath(Size size, double depth) {
    final path = Path();
    const segments = 180;
    for (var i = 0; i <= segments; i++) {
      final x = size.width * i / segments;
      final y = _surfaceAt(x, size) - depth;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    for (var i = segments; i >= 0; i--) {
      final x = size.width * i / segments;
      final wobble = math.sin(i * 0.71 + progress * math.pi * 3) *
          (1.2 + foamEnergy * 2.2);
      final y = _surfaceAt(x, size) + wobble;
      path.lineTo(x, y);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fillLevel <= 0.001) {
      _drawEmptyMessage(canvas, size);
      return;
    }

    final liquidPath = _liquidPath(size);
    final baseTop = _baseTop(size);
    canvas.drawPath(
      liquidPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.2, 0.58, 1],
          colors: [
            Color.lerp(drink.color, Colors.white, 0.26)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.22)!,
            Color.lerp(drink.color, Colors.black, 0.48)!,
          ],
        ).createShader(
          Rect.fromLTWH(0, baseTop - 70, size.width, size.height - baseTop + 90),
        ),
    );

    final foamDepth = size.height *
        (drink.glassType == GlassType.mug ? 0.045 : 0.072) *
        (0.82 + foamEnergy * 0.42);
    final foamPath = _foamPath(size, foamDepth);
    canvas.drawPath(
      foamPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFCF5), Color(0xFFF7E6C2), Color(0xFFE8C58B)],
        ).createShader(Rect.fromLTWH(0, baseTop - foamDepth - 20, size.width, foamDepth + 35)),
    );

    final surfacePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.86)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);
    final surfacePath = Path();
    const segments = 180;
    for (var i = 0; i <= segments; i++) {
      final x = size.width * i / segments;
      final y = _surfaceAt(x, size) - foamDepth;
      i == 0 ? surfacePath.moveTo(x, y) : surfacePath.lineTo(x, y);
    }
    canvas.drawPath(surfacePath, surfacePaint);

    final bubbleCount = 22 + (foamEnergy * 32).round();
    for (var i = 0; i < bubbleCount; i++) {
      final ratio = ((i * 47 + 13) % 997) / 997;
      final x = ratio * size.width;
      final yTop = _surfaceAt(x, size) - foamDepth;
      final y = yTop + ((i * 73) % 100) / 100 * foamDepth;
      final radius = 1.2 + (i % 5) * 0.75;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
    }

    if (residue > 0.02) {
      final rings = (2 + residue * 6).round();
      for (var i = 0; i < rings; i++) {
        final y = size.height * 0.12 + (baseTop - size.height * 0.18) * (i + 1) / (rings + 1);
        final path = Path()..moveTo(size.width * 0.18, y);
        for (var s = 1; s <= 36; s++) {
          final x = size.width * (0.18 + 0.64 * s / 36);
          path.lineTo(x, y + math.sin(s * 0.72 + i) * (1 + residue * 2.2));
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFF0D7A7).withValues(alpha: 0.18 + residue * 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      }
    }

    if (pouring) _drawPourStream(canvas, size, foamDepth);
  }

  void _drawPourStream(Canvas canvas, Size size, double foamDepth) {
    final rightSide = tilt >= 0;
    final edgeX = rightSide ? size.width * 0.82 : size.width * 0.18;
    final edgeY = _surfaceAt(edgeX, size) - foamDepth * 0.35;
    final intensity = ((drinkAngle - 0.46) / 0.54).clamp(0.0, 1.0).toDouble();
    final direction = rightSide ? 1.0 : -1.0;
    final stream = Path()
      ..moveTo(edgeX - 5 * direction, edgeY)
      ..cubicTo(
        edgeX + 8 * direction,
        edgeY - 8,
        edgeX + 20 * direction,
        edgeY - 30,
        edgeX + 24 * direction,
        edgeY - 58 - intensity * 35,
      )
      ..lineTo(edgeX + 31 * direction, edgeY - 58 - intensity * 35)
      ..cubicTo(
        edgeX + 26 * direction,
        edgeY - 26,
        edgeX + 14 * direction,
        edgeY - 4,
        edgeX + 4 * direction,
        edgeY + 2,
      )
      ..close();
    canvas.drawPath(
      stream,
      Paint()..color = Color.lerp(drink.color, Colors.white, 0.12)!.withValues(alpha: 0.9),
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
  bool shouldRepaint(covariant _CoupledVolumePainter oldDelegate) => true;
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

Size _liquidOverscan(GlassType type) {
  switch (type) {
    case GlassType.pint:
      return const Size(1.14, 1.045);
    case GlassType.highball:
      return const Size(1.16, 1.04);
    case GlassType.cocktail:
      return const Size(1.10, 1.025);
    case GlassType.mug:
      return const Size(1.14, 1.04);
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
        ..quadraticBezierTo(w * 0.50, h * 0.00, w * 0.84, h * 0.04)
        ..lineTo(w * 0.73, h * 0.92)
        ..quadraticBezierTo(w * 0.50, h * 0.99, w * 0.27, h * 0.92)
        ..close();
    case GlassType.highball:
      path
        ..moveTo(w * 0.20, h * 0.03)
        ..quadraticBezierTo(w * 0.50, h * 0.00, w * 0.80, h * 0.03)
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
    final path = _buildVesselPath(size, type);
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.8), 22, true);
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
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.30);
    final left = Path()
      ..moveTo(size.width * 0.25, size.height * 0.15)
      ..quadraticBezierTo(
        size.width * 0.18,
        size.height * 0.48,
        size.width * 0.30,
        size.height * 0.78,
      );
    canvas.drawPath(left, shine);
  }

  @override
  bool shouldRepaint(covariant _VesselHighlightPainter oldDelegate) =>
      oldDelegate.type != type;
}
