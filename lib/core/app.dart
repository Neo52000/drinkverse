import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import 'app_theme.dart';

class DrinkVerseApp extends StatelessWidget {
  const DrinkVerseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DrinkVerse',
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
