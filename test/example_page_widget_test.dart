import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Import the local example app's page. Use the example file directly.
import '../example/main.dart' as example_app;

void main() {
  testWidgets('UpdateDemoPage has expected buttons and status text', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: example_app.UpdateDemoPage()));

    // Verify the presence of status text and buttons
    expect(find.textContaining('Status:'), findsOneWidget);
    expect(find.text('Check & Run Immediate Update (Android)'), findsOneWidget);
    expect(find.text('Check Flexible Update (auto-complete)'), findsOneWidget);
    expect(find.text('Check Flexible Update (manual completion via stream)'), findsOneWidget);
    expect(find.text('Check Flexible Update (callback + manual completion)'), findsOneWidget);
    expect(find.text('Check Update (iOS behavior)'), findsOneWidget);

    // Tap a button to ensure no runtime exceptions when pressed (they will return quickly in test environment)
    await tester.tap(find.text('Check Update (iOS behavior)'));
    await tester.pumpAndSettle();

    // If everything pumped without throw, consider it passing for a smoke widget test.
    expect(tester.takeException(), isNull);
  });
}
