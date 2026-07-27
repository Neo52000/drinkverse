import 'package:flutter/material.dart';

import '../../models/drink.dart';
import '../../widgets/drink_glass.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedDrink = 0;
  int _selectedTab = 0;

  Drink get drink => drinks[_selectedDrink];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.2, -0.3),
              radius: 1.25,
              colors: [Color(0xFF1D2331), Color(0xFF080B12)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 950) {
                return _DesktopHome(
                  selectedDrink: _selectedDrink,
                  drink: drink,
                  onSelected: _selectDrink,
                );
              }
              return _MobileHome(
                selectedDrink: _selectedDrink,
                selectedTab: _selectedTab,
                drink: drink,
                onDrinkSelected: _selectDrink,
                onTabSelected: (value) => setState(() => _selectedTab = value),
              );
            },
          ),
        ),
      ),
    );
  }

  void _selectDrink(int value) => setState(() => _selectedDrink = value);
}

class _MobileHome extends StatelessWidget {
  const _MobileHome({
    required this.selectedDrink,
    required this.selectedTab,
    required this.drink,
    required this.onDrinkSelected,
    required this.onTabSelected,
  });

  final int selectedDrink;
  final int selectedTab;
  final Drink drink;
  final ValueChanged<int> onDrinkSelected;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _Header()),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 106,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                itemCount: drinks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (context, index) => _DrinkChip(
                  drink: drinks[index],
                  selected: selectedDrink == index,
                  onTap: () => onDrinkSelected(index),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
            sliver: SliverToBoxAdapter(child: _SimulationCard(drink: drink)),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: onTabSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Collection'),
          NavigationDestination(icon: Icon(Icons.flag_rounded), label: 'Défis'),
          NavigationDestination(icon: Icon(Icons.person_rounded), label: 'Profil'),
        ],
      ),
    );
  }
}

class _DesktopHome extends StatelessWidget {
  const _DesktopHome({
    required this.selectedDrink,
    required this.drink,
    required this.onSelected,
  });

  final int selectedDrink;
  final Drink drink;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const _Header(desktop: true),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: _Panel(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: drinks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _DrinkChip(
                        drink: drinks[index],
                        selected: selectedDrink == index,
                        onTap: () => onSelected(index),
                        wide: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(child: _SimulationCard(drink: drink)),
                const SizedBox(width: 18),
                const SizedBox(width: 270, child: _ProgressPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.desktop = false});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(desktop ? 0 : 14, 14, desktop ? 0 : 14, 6),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB84D), Color(0xFFFF7A45)],
              ),
            ),
            child: const Icon(Icons.local_bar_rounded, color: Color(0xFF15100A)),
          ),
          const SizedBox(width: 11),
          Text(
            'DRINKVERSE',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 2),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.workspace_premium_rounded, size: 18),
            label: Text(desktop ? 'Passer Premium' : 'PRO'),
          ),
          const SizedBox(width: 8),
          const CircleAvatar(child: Icon(Icons.person_rounded)),
        ],
      ),
    );
  }
}

class _SimulationCard extends StatelessWidget {
  const _SimulationCard({required this.drink});

  final Drink drink;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(drink.name, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 3),
                      Text(drink.subtitle),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.favorite_border_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(height: 410, child: Center(child: DrinkGlass(drink: drink))),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Lancer la simulation'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Personnaliser'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrinkChip extends StatelessWidget {
  const _DrinkChip({
    required this.drink,
    required this.selected,
    required this.onTap,
    this.wide = false,
  });

  final Drink drink;
  final bool selected;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? drink.color.withValues(alpha: 0.18) : const Color(0xFF111722),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: wide ? double.infinity : 142,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(drink.icon, color: drink.color),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    drink.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progression', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.person_rounded)),
              title: Text('Mixologue novice'),
              subtitle: Text('Niveau 4'),
              trailing: Text('740 XP'),
            ),
            LinearProgressIndicator(value: 0.74),
            SizedBox(height: 22),
            Text('12 boissons testées'),
            SizedBox(height: 12),
            Text('7 succès débloqués'),
            SizedBox(height: 12),
            Text('2 h 48 de simulation'),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111722).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 14)),
        ],
      ),
      child: child,
    );
  }
}
