import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_manager_1/browser_launcher.dart';
import 'package:home_manager_1/main.dart';

void main() {
  testWidgets('adds non-empty issues newest first within the same priority', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HomeManagerApp());

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(IssueCard), findsNWidgets(3));
    expect(find.textContaining('Complete by'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Air conditioner filter');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Air conditioner filter'), findsOneWidget);

    final double newIssueTop = tester
        .getTopLeft(find.text('Air conditioner filter'))
        .dy;
    final double firstSeedIssueTop = tester
        .getTopLeft(find.text('Book annual smoke alarm test'))
        .dy;
    expect(newIssueTop, lessThan(firstSeedIssueTop));
  });

  testWidgets('does not add empty issues', (WidgetTester tester) async {
    await tester.pumpWidget(const HomeManagerApp());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(IssueCard), findsNWidgets(3));
  });

  testWidgets('opens details, saves notes, and applies urgent priority', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HomeManagerApp());

    await tester.tap(find.text('Replace hallway light bulb'));
    await tester.pumpAndSettle();

    expect(find.text('Issue Details'), findsOneWidget);
    expect(find.text('Replace hallway light bulb'), findsOneWidget);
    expect(find.text('Look up'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
    expect(find.text('Complete By'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Look up')).dy,
      lessThan(tester.getTopLeft(find.text('Notes')).dy),
    );

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Use the small ladder');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Use the small ladder'), findsOneWidget);

    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urgent'));
    await tester.pumpAndSettle();

    expect(find.text('Urgent'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final double urgentIssueTop = tester
        .getTopLeft(find.text('Replace hallway light bulb'))
        .dy;
    final double lowIssueTop = tester
        .getTopLeft(find.text('Book annual smoke alarm test'))
        .dy;
    expect(urgentIssueTop, lessThan(lowIssueTop));
    expect(
      find.byKey(const ValueKey<String>('priority-marker-Urgent')),
      findsOneWidget,
    );
  });

  testWidgets('moves completed issues to Done', (WidgetTester tester) async {
    await tester.pumpWidget(const HomeManagerApp());

    await tester.tap(find.text('Check dripping laundry tap'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();

    expect(find.text('Check dripping laundry tap'), findsNothing);

    final Card doneCard = tester.widget<Card>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('done-cell')),
        matching: find.byType(Card),
      ),
    );
    expect(doneCard.color, const Color(0xFFE3F4E8));

    await tester.tap(find.byKey(const ValueKey<String>('done-cell')));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Check dripping laundry tap'), findsOneWidget);
  });

  testWidgets('enables reminders and saves the selected reminder option', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HomeManagerApp());

    await tester.tap(find.text('Book annual smoke alarm test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Every third day'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Every second day'));
    await tester.pumpAndSettle();

    expect(find.text('Every second day'), findsOneWidget);
  });

  testWidgets('opens lookup choices from the issue detail card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HomeManagerApp());

    await tester.tap(find.text('Check dripping laundry tap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Look up'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'How to'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Products'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Products'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Products'), findsNothing);
  });

  test('builds lookup search URLs', () {
    expect(
      buildSearchUri('How to clean shed').queryParameters['q'],
      'How to clean shed',
    );
    expect(
      buildSearchUri('Clean shed products').queryParameters['q'],
      'Clean shed products',
    );
  });
}
