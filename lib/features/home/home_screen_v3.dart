import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/drink.dart';
import '../../widgets/drink_vessel.dart';
import 'vessel_simulation_screen.dart';

class HomeScreenV3 extends StatefulWidget {
  const HomeScreenV3({super.key});

  @override
  State<HomeScreenV3> createState() => _HomeScreenV3State();
}

class _HomeScreenV3State extends State<HomeScreenV3> {
  int _selectedIndex = 0;

  Drink get selectedDrink => drinks[_selectedIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppTheme.appGradient),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                sliver: SliverToBoxAdapter(child: _Header(drink: selectedDrink)),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: _HeroCard(
                    drink: selectedDrink,
                    onLaunch: () => _openSimulation(selectedDrink),
                  ),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Collection de verres',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                sliver: SliverGrid.builder(
                  itemCount: drinks.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, index) {
                    final drink = drinks[index];
                    return _DrinkCard(
                      drink: drink,
                      selected: index == _selectedIndex,
                      onTap: () {
                        setState(() => _selectedIndex = index);
                        _openSimulation(drink);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSimulation(Drink drink) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VesselSimulationScreen(drink: drink)),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.drink});

  final Drink drink;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: AppTheme.premiumGradient,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.local_bar_rounded, color: Color(0xFF211300)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DRINKVERSE',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              Text(
                'Des contenants adaptés à chaque boisson',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        Icon(drink.icon, color: drink.color),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.drink, required this.onLaunch});

  final Drink drink;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGlass,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: drink.color.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: drink.color.withValues(alpha: 0.10),
            blurRadius: 42,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drink.name, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(drink.subtitle),
                  ],
                ),
              ),
              Text(
                _glassLabel(drink.glassType),
                style: TextStyle(color: drink.color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 240,
            height: 320,
            child: DrinkVessel(drink: drink),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onLaunch,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Lancer la simulation'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrinkCard extends StatelessWidget {
  const _DrinkCard({required this.drink, required this.selected, required this.onTap});

  final Drink drink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? drink.color.withValues(alpha: 0.14) : AppTheme.surfaceGlass,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? drink.color.withValues(alpha: 0.70) : AppTheme.outline,
            ),
          ),
          child: Column(
            children: [
              Expanded(child: DrinkVessel(drink: drink, condensation: false)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  drink.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _glassLabel(drink.glassType),
                  style: TextStyle(color: drink.color, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _glassLabel(GlassType type) {
  return switch (type) {
    GlassType.pint => 'Pinte',
    GlassType.highball => 'Highball',
    GlassType.cocktail => 'Cocktail',
    GlassType.mug => 'Tasse',
  };
}
