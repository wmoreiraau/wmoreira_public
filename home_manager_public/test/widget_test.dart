import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_manager_1/browser_launcher.dart';
import 'package:home_manager_1/home_issue.dart';
import 'package:home_manager_1/main.dart';

/// Opens [IssueDetailPage] for [issue] on top of a placeholder route, so the
/// page's Done and Delete actions have a route to pop back to.
Future<void> pumpDetailPage(
  WidgetTester tester,
  HomeIssue issue, {
  VoidCallback? onIssueChanged,
  void Function(HomeIssue issue)? onCompleteIssue,
  void Function(HomeIssue issue)? onDeleteIssue,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => IssueDetailPage(
                        issue: issue,
                        onIssueChanged: onIssueChanged ?? () {},
                        onCompleteIssue: onCompleteIssue ?? (_) {},
                        onDeleteIssue: onDeleteIssue ?? (_) {},
                        onReminderCreated: (_) {},
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the setup screen when no Firebase config is supplied', (
    WidgetTester tester,
  ) async {
    // Tests run without --dart-define values, so Firebase is unconfigured.
    await tester.pumpWidget(const HomeManagerApp());

    expect(find.text('Firebase setup needed'), findsOneWidget);
  });

  testWidgets('issue card shows the title and priority marker', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IssueCard(
            issue: HomeIssue(
              title: 'Clean gutters',
              priority: IssuePriority.urgent,
            ),
            onTap: () => taps++,
          ),
        ),
      ),
    );

    expect(find.text('Clean gutters'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('priority-marker-Urgent')),
      findsOneWidget,
    );

    await tester.tap(find.text('Clean gutters'));
    expect(taps, 1);
  });

  testWidgets('detail page lists its actions with Look up above Notes', (
    WidgetTester tester,
  ) async {
    await pumpDetailPage(tester, HomeIssue(title: 'Replace hallway light bulb'));

    expect(find.text('Issue Details'), findsOneWidget);
    expect(find.text('Replace hallway light bulb'), findsOneWidget);
    for (final String action in <String>[
      'Look up',
      'Notes',
      'Priority',
      'Due',
      'Reminder',
      'Done',
      'Delete Issue',
    ]) {
      expect(find.text(action), findsOneWidget);
    }
    expect(find.text('Complete By'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Look up')).dy,
      lessThan(tester.getTopLeft(find.text('Notes')).dy),
    );
  });

  testWidgets('saves trimmed notes and the selected priority', (
    WidgetTester tester,
  ) async {
    final HomeIssue issue = HomeIssue(title: 'Check dripping laundry tap');
    int changes = 0;
    await pumpDetailPage(tester, issue, onIssueChanged: () => changes++);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Use the small ladder ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(issue.notes, 'Use the small ladder');
    expect(find.text('Use the small ladder'), findsOneWidget);

    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Urgent'));
    await tester.pumpAndSettle();

    expect(issue.priority, IssuePriority.urgent);
    expect(find.text('Urgent'), findsOneWidget);
    expect(changes, 2);
  });

  testWidgets('enabling the reminder opens its options', (
    WidgetTester tester,
  ) async {
    final HomeIssue issue = HomeIssue(title: 'Book annual smoke alarm test');
    await pumpDetailPage(tester, issue);

    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();

    expect(issue.reminderEnabled, isTrue);
    expect(find.widgetWithText(ListTile, 'Every third day'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Every second day'));
    await tester.pumpAndSettle();

    expect(issue.reminderOption, ReminderOption.everySecondDay);
    expect(find.text('Every second day'), findsOneWidget);
  });

  testWidgets('Done asks for confirmation, then completes and closes', (
    WidgetTester tester,
  ) async {
    final HomeIssue issue = HomeIssue(title: 'Check dripping laundry tap');
    HomeIssue? completed;
    await pumpDetailPage(
      tester,
      issue,
      onCompleteIssue: (HomeIssue done) => completed = done,
    );

    await tester.ensureVisible(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as done?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(completed, isNull);
    expect(find.text('Issue Details'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();

    expect(completed, same(issue));
    expect(find.text('Issue Details'), findsNothing);
  });

  testWidgets('Delete Issue asks for confirmation before deleting', (
    WidgetTester tester,
  ) async {
    final HomeIssue issue = HomeIssue(title: 'Fix squeaky door');
    HomeIssue? deleted;
    await pumpDetailPage(
      tester,
      issue,
      onDeleteIssue: (HomeIssue removed) => deleted = removed,
    );

    await tester.ensureVisible(find.text('Delete Issue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Issue'));
    await tester.pumpAndSettle();
    expect(find.text('Delete issue?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, same(issue));
    expect(find.text('Issue Details'), findsNothing);
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
