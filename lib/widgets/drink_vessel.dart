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

  static const String debugVersion = 'DEV • PHYSICS V3.2 • DYNAMIC ICE';

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
  final List<_IceParticle> _ice = <_IceParticle>[];
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  double _gyroX = 0;
  double _gyroY = 0;
  double _gyroZ = 0;
  double _motionEnergy = 0;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _seedIce();
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(_tick)
      ..repeat(min: 0, max: 1, period: const Duration(seconds: 1));
    _startSensors();
  }

  @override
  void didUpdateWidget(covariant DrinkVessel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drink.ice != widget.drink.ice ||
        oldWidget.drink.glassType != widget.drink.glassType) {
      _seedIce();
    }
  }

  void _seedIce() {
    _ice
      ..clear()
      ..addAll(List<_IceParticle>.generate(5, (index) {
        final column = index % 3;
        final row = index ~/ 3;
        return _IceParticle(
          x: 0.32 + column * 0.18 + (row * 0.035),
          y: 0.34 + row * 0.115 + (index.isEven ? 0.02 : -0.015),
          vx: 0,
          vy: 0,
          angle: (index - 2) * 0.18,
          angularVelocity: 0,
          size: 0.072 + (index % 3) * 0.008,
          mass: 0.82 + (index % 4) * 0.11,
        );
      }));
  }

  void _startSensors() {
    _gyroSubscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _gyroX = event.x.clamp(-12.0, 12.0).toDouble();
        _gyroY = event.y.clamp(-12.0, 12.0).toDouble();
        _gyroZ = event.z.clamp(-12.0, 12.0).toDouble();
        final magnitude = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );
        _motionEnergy = math.max(
          _motionEnergy,
          (magnitude / 8).clamp(0.0, 1.0).toDouble(),
        );
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _tick() {
    if (!mounted || widget.paused || !widget.drink.ice) return;

    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;

    _stepIce(dt);
    _motionEnergy *= 0.965;
    _gyroX *= 0.93;
    _gyroY *= 0.93;
    _gyroZ *= 0.93;
    setState(() {});
  }

  void _stepIce(double dt) {
    final fill = widget.fillLevel.clamp(0.08, 0.96).toDouble();
    final surfaceY = (1 - fill) * 0.82 + 0.07;
    final left = widget.drink.glassType == GlassType.cocktail ? 0.17 : 0.24;
    final right = widget.drink.glassType == GlassType.cocktail ? 0.83 : 0.76;
    final bottom = widget.drink.glassType == GlassType.cocktail ? 0.51 : 0.90;

    for (final particle in _ice) {
      final radius = particle.size * 0.5;
      final targetY = surfaceY + radius * 0.58;

      final lateralForce = (_gyroZ * 0.026 + _gyroY * 0.009) / particle.mass;
      final vortexForce = _gyroX * 0.012 * (0.5 - particle.y);
      final buoyancy = (targetY - particle.y) * 9.5;
      final verticalKick = _gyroY.abs() * 0.004 * _motionEnergy;

      particle.vx += (lateralForce + vortexForce) * dt;
      particle.vy += (buoyancy + verticalKick) * dt;

      particle.vx *= math.pow(0.34, dt).toDouble();
      particle.vy *= math.pow(0.12, dt).toDouble();

      particle.x += particle.vx;
      particle.y += particle.vy;

      particle.angularVelocity +=
          (_gyroX * 0.055 + _gyroZ * 0.035 + particle.vx * 3.2) * dt;
      particle.angularVelocity *= math.pow(0.18, dt).toDouble();
      particle.angle += particle.angularVelocity;

      if (particle.x - radius < left) {
        particle.x = left + radius;
        particle.vx = particle.vx.abs() * 0.48;
        particle.angularVelocity += 0.035;
      } else if (particle.x + radius > right) {
        particle.x = right - radius;
        particle.vx = -particle.vx.abs() * 0.48;
        particle.angularVelocity -= 0.035;
      }

      if (particle.y - radius < surfaceY - 0.025) {
        particle.y = surfaceY - 0.025 + radius;
        particle.vy = particle.vy.abs() * 0.25;
      } else if (particle.y + radius > bottom) {
        particle.y = bottom - radius;
        particle.vy = -particle.vy.abs() * 0.35;
      }
    }

    for (var i = 0; i < _ice.length; i++) {
      for (var j = i + 1; j < _ice.length; j++) {
        final a = _ice[i];
        final b = _ice[j];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final distance = math.sqrt(dx * dx + dy * dy);
        final minimum = (a.size + b.size) * 0.49;
        if (distance <= 0.0001 || distance >= minimum) continue;

        final nx = dx / distance;
        final ny = dy / distance;
        final overlap = minimum - distance;
        a.x -= nx * overlap * 0.5;
        a.y -= ny * overlap * 0.5;
        b.x += nx * overlap * 0.5;
        b.y += ny * overlap * 0.5;

        final relativeVelocity = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
        if (relativeVelocity < 0) {
          final impulse = -relativeVelocity * 0.42;
          a.vx -= impulse * nx;
          a.vy -= impulse * ny;
          b.vx += impulse * nx;
          b.vy += impulse * ny;
          a.angularVelocity -= impulse * 0.35;
          b.angularVelocity += impulse * 0.35;
        }
      }
    }
  }

  Drink get _liquidDrink => widget.drink.ice
      ? Drink(
          name: widget.drink.name,
          category: widget.drink.category,
          icon: widget.drink.icon,
          color: widget.drink.color,
          subtitle: widget.drink.subtitle,
          foam: widget.drink.foam,
          ice: false,
          glassType: widget.drink.glassType,
        )
      : widget.drink;

  @override
  void dispose() {
    _gyroSubscription?.cancel();
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
        final overscan = _liquidOverscan(widget.drink.glassType);

        return RepaintBoundary(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _VesselShadowPainter(type: widget.drink.glassType),
                ),
              ),
              ClipPath(
                clipper: _VesselClipper(widget.drink.glassType),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Transform.scale(
                    scaleX: overscan.width,
                    scaleY: overscan.height,
                    alignment: Alignment.center,
                    child: DrinkGlass(
                      drink: _liquidDrink,
                      fillLevel: widget.fillLevel,
                      bubbles: widget.bubbles,
                      condensation: widget.condensation,
                      paused: widget.paused,
                    ),
                  ),
                ),
              ),
              if (widget.drink.ice)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipPath(
                      clipper: _VesselClipper(widget.drink.glassType),
                      child: CustomPaint(
                        painter: _DynamicIcePainter(
                          particles: _ice,
                          motionEnergy: _motionEnergy,
                        ),
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
        );
      },
    );
  }
}

class _IceParticle {
  _IceParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.angularVelocity,
    required this.size,
    required this.mass,
  });

  double x;
  double y;
  double vx;
  double vy;
  double angle;
  double angularVelocity;
  final double size;
  final double mass;
}

class _DynamicIcePainter extends CustomPainter {
  const _DynamicIcePainter({
    required this.particles,
    required this.motionEnergy,
  });

  final List<_IceParticle> particles;
  final double motionEnergy;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < particles.length; index++) {
      final particle = particles[index];
      final cubeSize = size.width * particle.size;
      final center = Offset(particle.x * size.width, particle.y * size.height);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(particle.angle);

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: cubeSize,
          height: cubeSize * 0.92,
        ),
        Radius.circular(cubeSize * 0.20),
      );

      canvas.drawShadow(
        Path()..addRRect(rect),
        Colors.black.withValues(alpha: 0.35),
        5 + motionEnergy * 4,
        false,
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.52),
              const Color(0xFFBDEBFF).withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.08),
            ],
          ).createShader(rect.outerRect),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 + motionEnergy * 0.7
          ..color = Colors.white.withValues(alpha: 0.62),
      );

      final shine = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          -cubeSize * 0.30,
          -cubeSize * 0.30,
          cubeSize * 0.42,
          cubeSize * 0.18,
        ),
        Radius.circular(cubeSize * 0.08),
      );
      canvas.drawRRect(
        shine,
        Paint()..color = Colors.white.withValues(alpha: 0.38),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _DynamicIcePainter oldDelegate) => true;
}

class _DebugVersionBadge extends StatelessWidget {
  const _DebugVersionBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          DrinkVessel.debugVersion,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.45,
            shadows: [Shadow(color: Colors.black87, blurRadius: 2)],
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
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xCCFFFFFF),
          Color(0x22FFFFFF),
          Color(0x6686D8FF),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, outline);

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
