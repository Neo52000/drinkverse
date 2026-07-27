import 'package:flutter/material.dart';

class Drink {
  const Drink({
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.foam,
    required this.ice,
  });

  final String name;
  final String category;
  final IconData icon;
  final Color color;
  final String subtitle;
  final bool foam;
  final bool ice;
}

const drinks = <Drink>[
  Drink(
    name: 'Bière ambrée',
    category: 'Bières',
    icon: Icons.sports_bar_rounded,
    color: Color(0xFFFFA62B),
    subtitle: 'Mousse dense • Bulles fines',
    foam: true,
    ice: false,
  ),
  Drink(
    name: 'Cola glacé',
    category: 'Sodas',
    icon: Icons.local_drink_rounded,
    color: Color(0xFF9B5A2E),
    subtitle: 'Glaçons • Effervescence',
    foam: false,
    ice: true,
  ),
  Drink(
    name: 'Mojito',
    category: 'Cocktails',
    icon: Icons.local_bar_rounded,
    color: Color(0xFF5DD39E),
    subtitle: 'Menthe • Citron vert',
    foam: false,
    ice: true,
  ),
  Drink(
    name: 'Café crème',
    category: 'Boissons chaudes',
    icon: Icons.coffee_rounded,
    color: Color(0xFFD69E72),
    subtitle: 'Créma • Vapeur légère',
    foam: true,
    ice: false,
  ),
];
