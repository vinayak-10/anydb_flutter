import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:anydb_flutter/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: AnyDbApp(),
      ),
    );

    // Basic check to see if the app loads. 
    // Since it's a dynamic app, we just check if it builds without crashing.
    expect(find.byType(AnyDbApp), findsOneWidget);
  });
}
