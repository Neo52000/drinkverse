import 'package:drinkverse/core/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DrinkVerse home screen renders', (tester) async {
    await tester.pumpWidget(const DrinkVerseApp());
    await tester.pump();

    expect(find.text('DRINKVERSE'), findsOneWidget);
    expect(find.text('Bière ambrée'), findsWidgets);
    expect(find.text('Lancer la simulation'), findsOneWidget);
  });
}
