import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/drink.dart';

class DrinkGlass extends StatefulWidget {
  const DrinkGlass({super.key, required this.drink});

  final Drink drink;

  @override
  State<DrinkGlass> createState() => _DrinkGlassState();
}

class _DrinkGlassState extends State<DrinkGlass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(270, 390),
          painter: DrinkGlassPainter(
            drink: widget.drink,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class DrinkGlassPainter extends CustomPainter {
  DrinkGlassPainter({required this.drink, required this.progress});

  final Drink drink;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final glassRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(24, 10, size.width - 48, size.height - 28),
      const Radius.circular(48),
    );

    canvas.drawRRect(
      glassRect.shift(const Offset(0, 12)),
      Paint()
        ..color = drink.color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34),
    );

    canvas.drawRRect(
      glassRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x55FFFFFF), Color(0x10000000), Color(0x35FFFFFF)],
        ).createShader(glassRect.outerRect),
    );

    canvas.save();
    canvas.clipRRect(glassRect.deflate(8));

    final liquidTop = size.height * 0.29;
    final liquidPath = Path()..moveTo(30, liquidTop);
    const segments = 40;
    for (var i = 0; i <= segments; i++) {
      final x = 30 + (size.width - 60) * i / segments;
      final primary = math.sin(i / segments * math.pi * 2 + progress * math.pi * 2) * 7;
      final secondary = math.sin(i / segments * math.pi * 4 - progress * math.pi * 3) * 2.5;
      liquidPath.lineTo(x, liquidTop + primary + secondary);
    }
    liquidPath
      ..lineTo(size.width - 30, size.height - 34)
      ..lineTo(30, size.height - 34)
      ..close();

    canvas.drawPath(
      liquidPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(drink.color, Colors.white, 0.08)!,
            drink.color,
            Color.lerp(drink.color, Colors.black, 0.38)!,
          ],
        ).createShader(Rect.fromLTWH(30, liquidTop, size.width - 60, size.height - liquidTop)),
    );

    if (drink.foam) {
      final foamPaint = Paint()..color = const Color(0xFFF5E2BE).withValues(alpha: 0.9);
      for (var i = 0; i < 18; i++) {
        final x = 36 + (i * 13.1) % (size.width - 72);
        final y = liquidTop - 2 + math.sin(i * 1.7) * 4;
        canvas.drawCircle(Offset(x, y), 5 + i % 3, foamPaint);
      }
    }

    if (drink.ice) {
      final icePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < 4; i++) {
        final x = 58 + i * 37.0;
        final y = liquidTop + 38 + (i % 2) * 32.0;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate((i - 1.5) * 0.13);
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(-14, -14, 28, 28), const Radius.circular(6)),
          icePaint,
        );
        canvas.restore();
      }
    }

    final bubblePaint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (var i = 0; i < 18; i++) {
      final x = 48 + ((i * 41) % 165).toDouble();
      final cycle = (progress + i * 0.057) % 1;
      final y = size.height - 46 - cycle * (size.height - liquidTop - 62);
      canvas.drawCircle(Offset(x, y), 1.8 + i % 4, bubblePaint);
    }

    canvas.drawLine(
      const Offset(58, 46),
      Offset(58, size.height - 88),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();

    canvas.drawRRect(
      glassRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant DrinkGlassPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.drink != drink;
  }
}
