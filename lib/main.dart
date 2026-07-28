import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/app.dart';

void main() {
  // Certains plugins (ex. audioplayers sur des plateformes/environnements où
  // un canal donné n'a pas d'implémentation native, comme le scope audio
  // global sur le web) déclenchent des erreurs asynchrones non liées au
  // build de l'UI. On les journalise sans jamais faire planter l'app : le
  // son est un bonus, pas une dépendance critique.
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const DrinkVerseApp());
    },
    (error, stack) => debugPrint('Unhandled async error: $error'),
  );
}
