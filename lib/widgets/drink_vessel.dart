import 'package:flutter/material.dart';

import '../models/drink.dart';
import 'drink_glass.dart';

/// Encadre le moteur de liquide historique, plus fiable pour les capteurs et
/// le vidage, dans une silhouette propre à chaque boisson.
class DrinkVessel extends StatelessWidget {
  const DrinkVessel({
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final overscan = _liquidOverscan(drink.glassType);

        return RepaintBoundary(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _VesselShadowPainter(type: drink.glassType),
                ),
              ),
              ClipPath(
                clipper: _VesselClipper(drink.glassType),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Transform.scale(
                    scaleX: overscan.width,
                    scaleY: overscan.height,
                    alignment: Alignment.center,
                    child: DrinkGlass(
                      drink: drink,
                      fillLevel: fillLevel,
                      bubbles: bubbles,
                      condensation: condensation,
                      paused: paused,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _VesselHighlightPainter(type: drink.glassType),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Le moteur historique possède sa propre marge intérieure. Ce léger surbalayage
/// la place derrière le masque du verre afin que le liquide rejoigne visuellement
/// les parois, sans toucher à la physique, aux capteurs ni au vidage.
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
  bool shouldRepaint(covariant _VesselShadowPainter oldDelegate) => oldDelegate.type != type;
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
  bool shouldRepaint(covariant _VesselHighlightPainter oldDelegate) => oldDelegate.type != type;
}
