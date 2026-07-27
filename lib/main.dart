import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const DrinkVerseApp());
}

class DrinkVerseApp extends StatelessWidget {
  const DrinkVerseApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF080B12);
    const surface = Color(0xFF111722);
    const accent = Color(0xFFFFB84D);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DrinkVerse',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
        ),
        cardTheme: const CardThemeData(
          color: surface,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontWeight: FontWeight.w800),
          headlineMedium: TextStyle(fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(color: Color(0xFFB5BECC)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class Drink {
  const Drink({
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  final String name;
  final String category;
  final IconData icon;
  final Color color;
  final String subtitle;
}

const drinks = <Drink>[
  Drink(
    name: 'Bière ambrée',
    category: 'Bières',
    icon: Icons.sports_bar_rounded,
    color: Color(0xFFFFA62B),
    subtitle: 'Mousse dense • Bulles fines',
  ),
  Drink(
    name: 'Cola glacé',
    category: 'Sodas',
    icon: Icons.local_drink_rounded,
    color: Color(0xFF9B5A2E),
    subtitle: 'Glaçons • Effervescence',
  ),
  Drink(
    name: 'Mojito',
    category: 'Cocktails',
    icon: Icons.local_bar_rounded,
    color: Color(0xFF5DD39E),
    subtitle: 'Menthe • Citron vert',
  ),
  Drink(
    name: 'Café crème',
    category: 'Boissons chaudes',
    icon: Icons.coffee_rounded,
    color: Color(0xFFD69E72),
    subtitle: 'Créma • Vapeur légère',
  ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  int navigationIndex = 0;

  Drink get selectedDrink => drinks[selectedIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 1000;
            return Stack(
              children: [
                const Positioned.fill(child: _AtmosphereBackground()),
                if (isDesktop)
                  _DesktopLayout(
                    selectedIndex: selectedIndex,
                    selectedDrink: selectedDrink,
                    onDrinkSelected: _selectDrink,
                  )
                else
                  _MobileLayout(
                    selectedIndex: selectedIndex,
                    selectedDrink: selectedDrink,
                    navigationIndex: navigationIndex,
                    onDrinkSelected: _selectDrink,
                    onNavigationSelected: (value) {
                      setState(() => navigationIndex = value);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _selectDrink(int index) {
    setState(() => selectedIndex = index);
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.selectedIndex,
    required this.selectedDrink,
    required this.onDrinkSelected,
  });

  final int selectedIndex;
  final Drink selectedDrink;
  final ValueChanged<int> onDrinkSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const _TopBar(),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: _DrinkLibrary(
                    selectedIndex: selectedIndex,
                    onDrinkSelected: onDrinkSelected,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(child: _HeroPanel(drink: selectedDrink)),
                const SizedBox(width: 20),
                SizedBox(width: 300, child: _ProfilePanel(drink: selectedDrink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.selectedIndex,
    required this.selectedDrink,
    required this.navigationIndex,
    required this.onDrinkSelected,
    required this.onNavigationSelected,
  });

  final int selectedIndex;
  final Drink selectedDrink;
  final int navigationIndex;
  final ValueChanged<int> onDrinkSelected;
  final ValueChanged<int> onNavigationSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: _TopBar(compact: true),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 118,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                scrollDirection: Axis.horizontal,
                itemCount: drinks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final drink = drinks[index];
                  final selected = index == selectedIndex;
                  return _CompactDrinkCard(
                    drink: drink,
                    selected: selected,
                    onTap: () => onDrinkSelected(index),
                  );
                },
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 110),
            sliver: SliverList.list(
              children: [
                SizedBox(height: 500, child: _HeroPanel(drink: selectedDrink)),
                const SizedBox(height: 16),
                _ProfilePanel(drink: selectedDrink, compact: true),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationIndex,
        onDestinationSelected: onNavigationSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Collection'),
          NavigationDestination(icon: Icon(Icons.emoji_events_rounded), label: 'Succès'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Réglages'),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFB84D), Color(0xFFFF7A45)],
            ),
          ),
          child: const Icon(Icons.local_bar_rounded, color: Color(0xFF15100A)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DRINKVERSE',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    letterSpacing: 2,
                    fontSize: compact ? 18 : 22,
                  ),
            ),
            if (!compact)
              const Text('Le simulateur de boissons immersif'),
          ],
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.workspace_premium_rounded),
          label: Text(compact ? 'PRO' : 'Passer Premium'),
        ),
        const SizedBox(width: 10),
        const CircleAvatar(
          backgroundColor: Color(0xFF1D2635),
          child: Icon(Icons.person_rounded),
        ),
      ],
    );
  }
}

class _DrinkLibrary extends StatelessWidget {
  const _DrinkLibrary({
    required this.selectedIndex,
    required this.onDrinkSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDrinkSelected;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bibliothèque', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Choisis une expérience'),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                itemCount: drinks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final drink = drinks[index];
                  return _DrinkTile(
                    drink: drink,
                    selected: index == selectedIndex,
                    onTap: () => onDrinkSelected(index),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const _MiniProgress(),
          ],
        ),
      ),
    );
  }
}

class _DrinkTile extends StatelessWidget {
  const _DrinkTile({required this.drink, required this.selected, required this.onTap});

  final Drink drink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? drink.color.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: drink.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(drink.icon, color: drink.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drink.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(drink.category, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: drink.color),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactDrinkCard extends StatelessWidget {
  const _CompactDrinkCard({required this.drink, required this.selected, required this.onTap});

  final Drink drink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? drink.color.withValues(alpha: 0.18) : const Color(0xFF111722),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 142,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(drink.icon, color: drink.color),
                const SizedBox(width: 8),
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

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.drink});

  final Drink drink;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(drink.name, style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
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
            Expanded(
              child: Center(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 700),
                  tween: Tween(begin: 0, end: 1),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: _AnimatedDrinkGlass(drink: drink),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Lancer la simulation'),
                ),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Personnaliser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedDrinkGlass extends StatefulWidget {
  const _AnimatedDrinkGlass({required this.drink});

  final Drink drink;

  @override
  State<_AnimatedDrinkGlass> createState() => _AnimatedDrinkGlassState();
}

class _AnimatedDrinkGlassState extends State<_AnimatedDrinkGlass>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(230, 330),
          painter: DrinkGlassPainter(
            color: widget.drink.color,
            progress: controller.value,
          ),
        );
      },
    );
  }
}

class DrinkGlassPainter extends CustomPainter {
  DrinkGlassPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final glassRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(22, 10, size.width - 44, size.height - 24),
      const Radius.circular(42),
    );

    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawRRect(glassRect.shift(const Offset(0, 10)), shadowPaint);

    final glassPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x44FFFFFF), Color(0x11000000), Color(0x33FFFFFF)],
      ).createShader(glassRect.outerRect)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(glassRect, glassPaint);

    canvas.save();
    canvas.clipRRect(glassRect.deflate(7));

    final liquidTop = size.height * 0.34;
    final liquidPath = Path()..moveTo(28, liquidTop);
    const segments = 28;
    for (var i = 0; i <= segments; i++) {
      final x = 28 + (size.width - 56) * i / segments;
      final wave = math.sin((i / segments * math.pi * 2) + progress * math.pi * 2) * 5;
      liquidPath.lineTo(x, liquidTop + wave);
    }
    liquidPath
      ..lineTo(size.width - 28, size.height - 28)
      ..lineTo(28, size.height - 28)
      ..close();

    final liquidPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.92),
          Color.lerp(color, Colors.black, 0.28)!,
        ],
      ).createShader(Rect.fromLTWH(28, liquidTop, size.width - 56, size.height - liquidTop));
    canvas.drawPath(liquidPath, liquidPaint);

    final bubblePaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
    for (var i = 0; i < 12; i++) {
      final x = 48 + ((i * 37) % 130).toDouble();
      final cycle = (progress + i * 0.083) % 1;
      final y = size.height - 45 - cycle * (size.height - liquidTop - 55);
      final radius = 2.0 + (i % 3);
      canvas.drawCircle(Offset(x, y), radius, bubblePaint);
    }

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(54, 42), Offset(54, size.height - 78), highlightPaint);

    canvas.restore();

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(glassRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant DrinkGlassPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.drink, this.compact = false});

  final Drink drink;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progression', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Row(
              children: [
                CircleAvatar(radius: 27, child: Icon(Icons.person_rounded)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mixologue novice', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Niveau 4'),
                    ],
                  ),
                ),
                Text('740 XP'),
              ],
            ),
            const SizedBox(height: 14),
            const LinearProgressIndicator(value: 0.74),
            const SizedBox(height: 22),
            _MetricRow(icon: Icons.local_bar_rounded, label: 'Boissons testées', value: '12'),
            const SizedBox(height: 12),
            _MetricRow(icon: Icons.emoji_events_rounded, label: 'Succès débloqués', value: '7'),
            const SizedBox(height: 12),
            _MetricRow(icon: Icons.timer_rounded, label: 'Temps simulé', value: '2 h 48'),
            if (!compact) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [drink.color.withValues(alpha: 0.24), const Color(0xFF181E2B)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_rounded),
                    SizedBox(height: 10),
                    Text('Défi du jour', style: TextStyle(fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('Teste trois boissons différentes pour gagner 150 XP.'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('Collection'), Text('12 / 50')],
          ),
          SizedBox(height: 8),
          LinearProgressIndicator(value: 0.24),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111722).withValues(alpha: 0.91),
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

class _AtmosphereBackground extends StatelessWidget {
  const _AtmosphereBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.18, -0.18),
          radius: 1.2,
          colors: [Color(0xFF1C2130), Color(0xFF080B12)],
        ),
      ),
      child: CustomPaint(painter: _BackgroundPainter()),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.025);
    const spacing = 48.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
