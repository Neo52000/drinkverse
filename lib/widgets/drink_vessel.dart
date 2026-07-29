import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/drink.dart';
import '../physics/drink_bubble_profile.dart';
import '../physics/drink_motion_profile.dart';
import '../physics/fluid_solver.dart';
import '../physics/gravity_engine.dart';
import '../physics/pour_engine.dart';
import '../services/drink_audio_service.dart';

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
      'DEV • PHYSICS V7.4 • UNIFIED PROFILES';

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
  // Vue non-copiante sur le buffer du solveur : évite une allocation de 128
  // doubles à chaque frame (auparavant List<double>.unmodifiable(...) dans
  // build()).
  late final List<double> _heightView = UnmodifiableListView(_fluid.height);

  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;

  double _gravityX = 0;
  double _gravityY = 1;
  double _targetSlope = 0;
  double _pour = 0;
  Duration _lastElapsed = Duration.zero;

  bool _wasPouring = false;
  bool _wasFizzing = false;
  bool _wasEmpty = false;
  double _lastReportedFlow = 0;

  // Recalculés uniquement au changement de boisson (pas à chaque frame) : le
  // moteur avancé sert désormais tous les verres, avec des paramètres par
  // catégorie plutôt qu'une bascule vers un second moteur.
  late DrinkMotionProfile _motionProfile;
  late DrinkBubbleProfile _bubbleProfile;

  @override
  void initState() {
    super.initState();
    _motionProfile = DrinkMotionProfile.forDrink(widget.drink);
    _bubbleProfile = DrinkBubbleProfile.forDrink(widget.drink);
    _fluid = FluidSolver(columns: 128)..applyMotionProfile(_motionProfile);
    _pourEngine = PourEngine(widget.fillLevel);
    _wasEmpty = widget.fillLevel <= 0.01;
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(_tick)
      ..repeat(min: 0, max: 1, period: const Duration(seconds: 1));
    _startSensors();
    DrinkAudioService.instance.initialize();
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
    _motionProfile = DrinkMotionProfile.forDrink(widget.drink);
    _bubbleProfile = DrinkBubbleProfile.forDrink(widget.drink);
    _fluid.applyMotionProfile(_motionProfile);
    _fluid.reset();
    _pourEngine.reset(widget.fillLevel);
    _wasPouring = false;
    _wasFizzing = false;
    _wasEmpty = widget.fillLevel <= 0.01;
    _lastReportedFlow = 0;
    DrinkAudioService.instance.stopPour();
    DrinkAudioService.instance.stopFizz();
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
    _updateAudio();
    setState(() {});
  }

  void _updateAudio() {
    final flow = _pourEngine.flow;
    final pouring = flow > 0.012;
    if (pouring != _wasPouring) {
      _wasPouring = pouring;
      if (pouring) {
        DrinkAudioService.instance.startPour(intensity: flow);
      } else {
        DrinkAudioService.instance.stopPour();
      }
    } else if (pouring && (flow - _lastReportedFlow).abs() > 0.03) {
      _lastReportedFlow = flow;
      DrinkAudioService.instance.updatePourIntensity(flow);
    }

    final energy = _fluid.motionEnergy;
    final fizzing = energy > 0.16;
    if (fizzing != _wasFizzing) {
      _wasFizzing = fizzing;
      if (fizzing) {
        DrinkAudioService.instance.startFizz(intensity: energy);
      } else {
        DrinkAudioService.instance.stopFizz();
      }
    }

    final isEmpty = _pourEngine.displayFill <= 0.01;
    if (isEmpty && !_wasEmpty) {
      DrinkAudioService.instance.playEmptyGlass();
    }
    _wasEmpty = isEmpty;
  }

  void _refill() {
    if (_pourEngine.displayFill > 0.02) return;
    DrinkAudioService.instance.playRefill();
    setState(_reset);
  }

  @override
  void dispose() {
    _accelerometer?.cancel();
    _gyroscope?.cancel();
    DrinkAudioService.instance.stopAll();
    _controller
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _refill,
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                painter: _ScreenGlassPainter(
                  drink: widget.drink,
                  columns: _heightView,
                  fillLevel: _pourEngine.displayFill,
                  foamDepth: _fluid.foam,
                  energy: _fluid.motionEnergy,
                  residue: _pourEngine.residue,
                  flow: _pourEngine.flow,
                  slope: _fluid.slope,
                  gravityX: _gravityX,
                  gravityY: _gravityY,
                  progress: _controller.value,
                  iceMobility: _motionProfile.iceMobility,
                  bubbleProfile: _bubbleProfile,
                  bubblesEnabled: widget.bubbles,
                  condensation: widget.condensation,
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _ScreenEdgePainter(glassType: widget.drink.glassType),
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

/// Silhouette de verre par [GlassType], en fractions de largeur (0..1).
///
/// Le solveur de vagues continue de représenter la largeur *totale* du
/// canvas — aucune influence sur la physique. Cette géométrie n'est qu'un
/// clip visuel appliqué par-dessus, partagé entre [_ScreenGlassPainter] (le
/// clip) et [_ScreenEdgePainter] (le contour doit suivre la même
/// silhouette, pas un rectangle plein).
class _GlassGeometry {
  const _GlassGeometry({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  final double topLeft;
  final double topRight;
  final double bottomLeft;
  final double bottomRight;

  static const _straight =
      _GlassGeometry(topLeft: 0, topRight: 1, bottomLeft: 0, bottomRight: 1);

  static _GlassGeometry forType(GlassType type) {
    return switch (type) {
      // Highball : référence, quasi plein écran.
      GlassType.highball => _straight,
      // Pint : évasé vers le haut, façon silhouette tulipe.
      GlassType.pint => const _GlassGeometry(
          topLeft: 0, topRight: 1, bottomLeft: 0.09, bottomRight: 0.91),
      // Cocktail : resserré vers le haut, façon verre à fond large.
      GlassType.cocktail => const _GlassGeometry(
          topLeft: 0.11, topRight: 0.89, bottomLeft: 0, bottomRight: 1),
      // Mug : même silhouette que highball, l'anse est ajoutée séparément
      // dans _ScreenEdgePainter.
      GlassType.mug => _straight,
    };
  }

  Path toPath(Size size, {double cornerRadius = 6}) {
    final tl = topLeft * size.width;
    final tr = topRight * size.width;
    final bl = bottomLeft * size.width;
    final br = bottomRight * size.width;
    final r = math.min(cornerRadius, (tr - tl) / 2);
    return Path()
      ..moveTo(tl, r)
      ..quadraticBezierTo(tl, 0, tl + r, 0)
      ..lineTo(tr - r, 0)
      ..quadraticBezierTo(tr, 0, tr, r)
      ..lineTo(br, size.height)
      ..lineTo(bl, size.height)
      ..close();
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
    required this.iceMobility,
    required this.bubbleProfile,
    required this.bubblesEnabled,
    required this.condensation,
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
  final double iceMobility;
  final DrinkBubbleProfile bubbleProfile;
  final bool bubblesEnabled;
  final bool condensation;

  double _catmullRom(double p0, double p1, double p2, double p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    return 0.5 *
        ((2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
  }

  double _sampleSurface(double normalizedX) {
    final maxIndex = columns.length - 1;
    final position = normalizedX.clamp(0.0, 1.0) * maxIndex;
    final i1 = position.floor().clamp(0, maxIndex);
    final i2 = math.min(i1 + 1, maxIndex);
    final i0 = math.max(i1 - 1, 0);
    final i3 = math.min(i2 + 1, maxIndex);
    return _catmullRom(
      columns[i0],
      columns[i1],
      columns[i2],
      columns[i3],
      position - i1,
    );
  }

  double _surface(double x, Size size) {
    final normalizedX = (x / size.width).clamp(0.0, 1.0).toDouble();
    final displacement = _sampleSurface(normalizedX);
    return size.height * (1 - fillLevel.clamp(0.0, 1.0)) +
        displacement * size.height * 0.44;
  }

  Path _surfaceLine(Size size, {double offset = 0, double roughness = 0}) {
    final path = Path();
    final samples = math.max(280, (size.width * 0.9).round());
    for (var i = 0; i <= samples; i++) {
      final x = size.width * i / samples;
      final noise = math.sin(i * 0.31 + progress * math.pi * 2.4) * roughness;
      final y = _surface(x, size) + offset + noise;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipPath(_GlassGeometry.forType(drink.glassType).toPath(size));

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
      canvas.restore();
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

    final foamPx = drink.foam ? size.height * foamDepth : 0.0;
    if (drink.foam) {
      final foam = _surfaceLine(
        size,
        offset: -foamPx,
        roughness: 0.8 + energy * 1.8,
      );
      const foamSamples = 280;
      for (var i = foamSamples; i >= 0; i--) {
        final x = size.width * i / foamSamples;
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

      // Texture de bulles dans la mousse : la mousse est déjà quasi blanche,
      // donc un contour ambré discret se voit mieux qu'un remplissage blanc.
      final foamBubbleCount = 40 + (energy * 40).round();
      for (var i = 0; i < foamBubbleCount; i++) {
        final seedX = ((i * 131 + 53) % 991) / 991;
        final phase = (progress * (0.55 + (i % 5) * 0.09) + i * 0.213) % 1;
        final x = seedX * size.width;
        final top = _surface(x, size) - foamPx;
        final bottom = _surface(x, size);
        final y = top + phase * math.max(bottom - top, 1);
        final popAlpha = ((1 - phase) * 0.55).clamp(0.0, 0.55);
        canvas.drawCircle(
          Offset(x, y),
          0.6 + (i % 4) * 0.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6
            ..color = const Color(0xFFC99344).withValues(alpha: popAlpha),
        );
      }
    }

    if (drink.ice) {
      _drawIce(canvas, size);
    }

    if (bubblesEnabled && bubbleProfile.enabled) {
      final count =
          bubbleProfile.baseCount + (energy * bubbleProfile.motionBoost).round();
      for (var i = 0; i < count; i++) {
        final seedX = ((i * 83 + 17) % 997) / 997;
        final speed = bubbleProfile.minSpeed +
            (i % 8) / 8 * bubbleProfile.speedSpread;
        final phase = (progress * speed + i * 0.131) % 1;
        final drift = gravityX * phase * bubbleProfile.horizontalDrift * 10;
        final x = seedX * size.width - drift;
        final clampedX = x.clamp(0.0, size.width).toDouble();
        final top = _surface(clampedX, size);
        final y = size.height - phase * math.max(size.height - top, 1) -
            gravityY * phase * 8;
        if (x < 0 || x > size.width || y <= top + 4 || y > size.height) {
          continue;
        }
        final radius = bubbleProfile.minRadius +
            (i % 6) / 6 * bubbleProfile.radiusSpread;
        canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7
            ..color = Colors.white
                .withValues(alpha: bubbleProfile.opacity * (0.6 + energy * 0.4)),
        );
      }
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

    if (condensation) {
      _drawCondensation(canvas, size);
    }

    canvas.restore();
  }

  void _drawIce(Canvas canvas, Size size) {
    if (fillLevel <= 0.04) return;
    for (var i = 0; i < 5; i++) {
      final ratio = (i + 1) / 6;
      final x = size.width * ratio;
      final y = _surface(x, size) + 26 + (i % 2) * 18;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(
        (i - 2) * 0.12 + slope * 0.16 * iceMobility + energy * 0.14 * iceMobility,
      );
      final cubeSize = 30.0;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: cubeSize, height: cubeSize),
        Radius.circular(cubeSize * 0.2),
      );
      canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.14));
      canvas.drawRRect(
        rect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.35,
      );
      canvas.restore();
    }
  }

  void _drawCondensation(Canvas canvas, Size size) {
    const count = 46;
    for (var i = 0; i < count; i++) {
      final x = 7 + ((i * 67) % 1000) / 1000 * (size.width - 14);
      final y = 12 + ((i * 89) % 1000) / 1000 * (size.height - 24);
      final radius = 1.3 + (i % 4) * 0.62;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenGlassPainter oldDelegate) => true;
}

class _ScreenEdgePainter extends CustomPainter {
  const _ScreenEdgePainter({required this.glassType});

  final GlassType glassType;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _GlassGeometry.forType(glassType);
    final glassPath = geometry.toPath(size);

    // Les reflets/bandes ne doivent apparaître que sur la silhouette réelle
    // du verre, pas déborder sur le fond visible autour (pint/cocktail sont
    // tapées, donc différentes d'un simple rectangle plein écran).
    canvas.save();
    canvas.clipPath(glassPath);

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
    // Reflet diagonal type "verre" en haut à gauche, façon éclat de lumière
    // sur une paroi en verre.
    final sheen = Path()
      ..moveTo(size.width * 0.06, 0)
      ..lineTo(size.width * 0.34, 0)
      ..lineTo(size.width * 0.14, size.height * 0.46)
      ..lineTo(0, size.height * 0.30)
      ..close();
    canvas.drawPath(
      sheen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.16), Colors.transparent],
        ).createShader(Offset.zero & size)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Liseré du rebord supérieur du verre, aligné sur la vraie largeur en
    // haut de la silhouette (plus étroite pour un cocktail, pleine largeur
    // pour un highball/mug, etc.).
    canvas.drawLine(
      Offset(geometry.topLeft * size.width + 4, 1),
      Offset(geometry.topRight * size.width - 4, 1),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(
      glassPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.14),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.restore();

    if (glassType == GlassType.mug) {
      _drawHandle(canvas, size);
    }
  }

  void _drawHandle(Canvas canvas, Size size) {
    // Arc ouvert à l'intérieur des bornes du widget (pas de débordement
    // hors du CustomPaint) pour suggérer une anse sans dépasser le cadre.
    final handleRect = Rect.fromLTWH(
      size.width * 0.72,
      size.height * 0.30,
      size.width * 0.24,
      size.height * 0.30,
    );
    canvas.drawArc(
      handleRect,
      -1.15,
      2.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.22),
    );
    canvas.drawArc(
      handleRect,
      -1.15,
      2.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.40),
    );
  }

  @override
  bool shouldRepaint(covariant _ScreenEdgePainter oldDelegate) =>
      oldDelegate.glassType != glassType;
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
