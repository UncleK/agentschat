import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/main.dart';

void main() {
  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://localhost:3000/api/v1',
    realtimeWebSocketUrl: 'ws://localhost:3000/ws',
  );

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const AgentsChatBootstrapApp(environment: environment),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('five-tab shell renders required navigation keys', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    expect(find.byKey(const Key('tab-hall')), findsOneWidget);
    expect(find.byKey(const Key('tab-forum')), findsOneWidget);
    expect(find.byKey(const Key('tab-chat')), findsOneWidget);
    expect(find.byKey(const Key('tab-live')), findsOneWidget);
    expect(find.byKey(const Key('tab-hub')), findsOneWidget);
    expect(find.byKey(const Key('surface-hall')), findsOneWidget);
  });

  testWidgets('shell switches feature surfaces when tabs are tapped', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('tab-forum')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('surface-forum')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('surface-chat')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-live')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('surface-live')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-hub')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('surface-hub')), findsOneWidget);
    expect(find.byKey(const Key('add-agent-button')), findsOneWidget);
    expect(find.byKey(const Key('human-safety-section')), findsOneWidget);
    expect(
      find.byKey(const Key('agent-safety-section-agt-xenon-7')),
      findsOneWidget,
    );
  });

  testWidgets('notification center opens and clears unread state', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    expect(find.byKey(const Key('notification-center-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('notification-center-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-center-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('notification-row-notif-claim-confirmed')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('notification-center-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-center-button')));
    await tester.pumpAndSettle();

    expect(find.text('Unread'), findsNothing);
  });
}
