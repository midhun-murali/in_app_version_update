import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_version_update/in_app_version_update.dart';

void main() {
  testWidgets('presentIosUpdateDialog shows dialog with provided texts and calls onUpdatePressed', (WidgetTester tester) async {
    final updater = InAppVersionUpdate(iosAppId: '123456');
    bool updatePressed = false;

    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (ctx) => CupertinoPageScaffold(
          child: CupertinoButton(
            onPressed: () {
              updater.presentIosUpdateDialog(
                ctx,
                title: 'Please update',
                content: 'A new version is available.',
                laterText: 'Not now',
                updateNowText: 'Update',
                onUpdatePressed: () {
                  updatePressed = true;
                },
              );
            },
            child: const Text('Show'),
          ),
        ),
      ),
    ));

    // Open the dialog
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Please update'), findsOneWidget);
    expect(find.text('A new version is available.'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);

    // Tap update button
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(updatePressed, isTrue);
    // Dialog should be dismissed
    expect(find.text('Please update'), findsNothing);
  });
}
