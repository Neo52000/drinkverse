import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../models/drink.dart';
import '../../widgets/drink_vessel.dart';

class VesselSimulationScreen extends StatefulWidget {
  const VesselSimulationScreen({super.key, required this.drink});

  final Drink drink;

  @override
  State<VesselSimulationScreen> createState() => _VesselSimulationScreenState();
}

class _VesselSimulationScreenState extends State<VesselSimulationScreen> {
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drink = widget.drink;

    return PopScope(
      onPopInvokedWithResult: (_, __) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _controlsVisible = !_controlsVisible),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.12),
                    radius: 1.15,
                    colors: [
                      drink.color.withValues(alpha: 0.20),
                      AppTheme.background,
                      Colors.black,
                    ],
                  ),
                ),
                child: DrinkVessel(drink: drink),
              ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: SafeArea(
                    minimum: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.34),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          tooltip: 'Retour',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  child: SafeArea(
                    minimum: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Text(
                        'Incline le téléphone • Touchez l’écran pour masquer les commandes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
