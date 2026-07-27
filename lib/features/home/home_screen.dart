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
  final Set<int> _favorites = <int>{};

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
                  favorites: _favorites,
                  onSelected: _selectDrink,
                  onFavorite: _toggleFavorite,
                  onLaunch: _launchSimulation,
                  onCustomize: _openCustomization,
                  onPremium: _showPremium,
                );
              }

              return _MobileHome(
                selectedDrink: _selectedDrink,
                selectedTab: _selectedTab,
                drink: drink,
                favorites: _favorites,
                onDrinkSelected: _selectDrink,
                onTabSelected: (value) => setState(() => _selectedTab = value),
                onFavorite: _toggleFavorite,
                onLaunch: _launchSimulation,
                onCustomize: _openCustomization,
                onPremium: _showPremium,
              );
            },
          ),
        ),
      ),
    );
  }

  void _selectDrink(int value) {
    setState(() {
      _selectedDrink = value;
      _selectedTab = 0;
    });
  }

  void _toggleFavorite() {
    setState(() {
      if (_favorites.contains(_selectedDrink)) {
        _favorites.remove(_selectedDrink);
      } else {
        _favorites.add(_selectedDrink);
      }
    });
  }

  void _launchSimulation() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenSimulation(drink: drink),
      ),
    );
  }

  void _openCustomization() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF111722),
      builder: (context) => _CustomizationSheet(drink: drink),
    );
  }

  void _showPremium() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded),
            SizedBox(width: 10),
            Text('DrinkVerse Pro'),
          ],
        ),
        content: const Text(
          'La version Pro débloquera toutes les boissons, les verres premium, '
          'les ambiances et les défis exclusifs. Les achats seront intégrés dans une prochaine version.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _MobileHome extends StatelessWidget {
  const _MobileHome({
    required this.selectedDrink,
    required this.selectedTab,
    required this.drink,
    required this.favorites,
    required this.onDrinkSelected,
    required this.onTabSelected,
    required this.onFavorite,
    required this.onLaunch,
    required this.onCustomize,
    required this.onPremium,
  });

  final int selectedDrink;
  final int selectedTab;
  final Drink drink;
  final Set<int> favorites;
  final ValueChanged<int> onDrinkSelected;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onFavorite;
  final VoidCallback onLaunch;
  final VoidCallback onCustomize;
  final VoidCallback onPremium;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(
        index: selectedTab,
        children: [
          _HomeTab(
            selectedDrink: selectedDrink,
            drink: drink,
            favorite: favorites.contains(selectedDrink),
            onDrinkSelected: onDrinkSelected,
            onFavorite: onFavorite,
            onLaunch: onLaunch,
            onCustomize: onCustomize,
            onPremium: onPremium,
          ),
          _CollectionTab(
            selectedDrink: selectedDrink,
            favorites: favorites,
            onDrinkSelected: onDrinkSelected,
          ),
          const _ChallengesTab(),
          const _ProfileTab(),
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

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.selectedDrink,
    required this.drink,
    required this.favorite,
    required this.onDrinkSelected,
    required this.onFavorite,
    required this.onLaunch,
    required this.onCustomize,
    required this.onPremium,
  });

  final int selectedDrink;
  final Drink drink;
  final bool favorite;
  final ValueChanged<int> onDrinkSelected;
  final VoidCallback onFavorite;
  final VoidCallback onLaunch;
  final VoidCallback onCustomize;
  final VoidCallback onPremium;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Header(onPremium: onPremium)),
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
          sliver: SliverToBoxAdapter(
            child: _SimulationCard(
              drink: drink,
              favorite: favorite,
              onFavorite: onFavorite,
              onLaunch: onLaunch,
              onCustomize: onCustomize,
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopHome extends StatelessWidget {
  const _DesktopHome({
    required this.selectedDrink,
    required this.drink,
    required this.favorites,
    required this.onSelected,
    required this.onFavorite,
    required this.onLaunch,
    required this.onCustomize,
    required this.onPremium,
  });

  final int selectedDrink;
  final Drink drink;
  final Set<int> favorites;
  final ValueChanged<int> onSelected;
  final VoidCallback onFavorite;
  final VoidCallback onLaunch;
  final VoidCallback onCustomize;
  final VoidCallback onPremium;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          _Header(desktop: true, onPremium: onPremium),
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
                Expanded(
                  child: _SimulationCard(
                    drink: drink,
                    favorite: favorites.contains(selectedDrink),
                    onFavorite: onFavorite,
                    onLaunch: onLaunch,
                    onCustomize: onCustomize,
                  ),
                ),
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
  const _Header({required this.onPremium, this.desktop = false});

  final bool desktop;
  final VoidCallback onPremium;

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
            onPressed: onPremium,
            icon: const Icon(Icons.workspace_premium_rounded, size: 18),
            label: Text(desktop ? 'Passer Premium' : 'PRO'),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Profil',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ouvre l’onglet Profil en bas de l’écran.')),
            ),
            icon: const Icon(Icons.person_rounded),
          ),
        ],
      ),
    );
  }
}

class _SimulationCard extends StatelessWidget {
  const _SimulationCard({
    required this.drink,
    required this.favorite,
    required this.onFavorite,
    required this.onLaunch,
    required this.onCustomize,
  });

  final Drink drink;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onLaunch;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  onPressed: onFavorite,
                  tooltip: favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(height: 360, child: Center(child: DrinkGlass(drink: drink))),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onLaunch,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Lancer la simulation'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onCustomize,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Personnaliser'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenSimulation extends StatefulWidget {
  const _FullscreenSimulation({required this.drink});

  final Drink drink;

  @override
  State<_FullscreenSimulation> createState() => _FullscreenSimulationState();
}

class _FullscreenSimulationState extends State<_FullscreenSimulation> {
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.drink.name),
        actions: [
          IconButton(
            onPressed: () => setState(() => _paused = !_paused),
            icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _paused ? 0.55 : 1,
                  duration: const Duration(milliseconds: 250),
                  child: Transform.scale(
                    scale: 1.18,
                    child: DrinkGlass(drink: widget.drink),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Text(
                    _paused ? 'Simulation en pause' : 'Incline doucement ton téléphone',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Le gyroscope sera connecté au liquide dans la prochaine étape.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomizationSheet extends StatefulWidget {
  const _CustomizationSheet({required this.drink});

  final Drink drink;

  @override
  State<_CustomizationSheet> createState() => _CustomizationSheetState();
}

class _CustomizationSheetState extends State<_CustomizationSheet> {
  double _fillLevel = 0.72;
  bool _bubbles = true;
  bool _condensation = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 4, 22, 22 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Personnaliser ${widget.drink.name}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          const Text('Niveau de remplissage'),
          Slider(
            value: _fillLevel,
            min: 0.35,
            max: 0.95,
            onChanged: (value) => setState(() => _fillLevel = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _bubbles,
            onChanged: (value) => setState(() => _bubbles = value),
            title: const Text('Bulles'),
            subtitle: const Text('Affiche l’effervescence dans le liquide'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _condensation,
            onChanged: (value) => setState(() => _condensation = value),
            title: const Text('Condensation'),
            subtitle: const Text('Ajoute de la buée et des gouttelettes sur le verre'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Personnalisation enregistrée pour cette session.')),
                );
              },
              child: const Text('Appliquer'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionTab extends StatelessWidget {
  const _CollectionTab({
    required this.selectedDrink,
    required this.favorites,
    required this.onDrinkSelected,
  });

  final int selectedDrink;
  final Set<int> favorites;
  final ValueChanged<int> onDrinkSelected;

  @override
  Widget build(BuildContext context) {
    return _TabPage(
      title: 'Collection',
      subtitle: '${drinks.length} boissons disponibles',
      child: GridView.builder(
        padding: const EdgeInsets.only(top: 18),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.9,
        ),
        itemCount: drinks.length,
        itemBuilder: (context, index) {
          final item = drinks[index];
          return Material(
            color: const Color(0xFF111722),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onDrinkSelected(index),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: Icon(
                        favorites.contains(index) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: favorites.contains(index) ? item.color : null,
                      ),
                    ),
                    const Spacer(),
                    Icon(item.icon, size: 46, color: item.color),
                    const Spacer(),
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(item.category, style: Theme.of(context).textTheme.bodySmall),
                    if (selectedDrink == index) ...[
                      const SizedBox(height: 8),
                      const Text('Sélectionnée', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChallengesTab extends StatelessWidget {
  const _ChallengesTab();

  @override
  Widget build(BuildContext context) {
    return const _TabPage(
      title: 'Défis',
      subtitle: 'Progresse et débloque de nouvelles expériences',
      child: Column(
        children: [
          _ChallengeCard(
            icon: Icons.local_bar_rounded,
            title: 'Curieux du jour',
            description: 'Teste trois boissons différentes.',
            progress: 0.33,
            reward: '+150 XP',
          ),
          SizedBox(height: 12),
          _ChallengeCard(
            icon: Icons.favorite_rounded,
            title: 'Premier favori',
            description: 'Ajoute une boisson à tes favoris.',
            progress: 0,
            reward: '+50 XP',
          ),
          SizedBox(height: 12),
          _ChallengeCard(
            icon: Icons.timer_rounded,
            title: 'Immersion',
            description: 'Reste deux minutes dans le simulateur.',
            progress: 0.6,
            reward: '+100 XP',
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    return _TabPage(
      title: 'Profil',
      subtitle: 'Ta progression DrinkVerse',
      child: Column(
        children: [
          const SizedBox(height: 18),
          const CircleAvatar(radius: 44, child: Icon(Icons.person_rounded, size: 42)),
          const SizedBox(height: 14),
          Text('Mixologue novice', style: Theme.of(context).textTheme.titleLarge),
          const Text('Niveau 4 • 740 XP'),
          const SizedBox(height: 20),
          const LinearProgressIndicator(value: 0.74),
          const SizedBox(height: 24),
          const _StatTile(icon: Icons.local_bar_rounded, label: 'Boissons testées', value: '12'),
          const _StatTile(icon: Icons.emoji_events_rounded, label: 'Succès débloqués', value: '7'),
          const _StatTile(icon: Icons.timer_rounded, label: 'Temps simulé', value: '2 h 48'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Les réglages seront ajoutés prochainement.')),
              ),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Réglages'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPage extends StatelessWidget {
  const _TabPage({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(subtitle),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.progress,
    required this.reward,
  });

  final IconData icon;
  final String title;
  final String description;
  final double progress;
  final String reward;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text(reward),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: progress),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(label),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
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
