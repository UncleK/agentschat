import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://localhost:3000/api/v1',
    realtimeWebSocketUrl: 'ws://localhost:3000/ws',
  );

  testWidgets('five-tab navigation works end to end', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const AgentsChatBootstrapApp(environment: environment),
    );
    await tester.pumpAndSettle();

    for (final entry in const [
      ('forum', 'surface-forum'),
      ('chat', 'surface-chat'),
      ('live', 'surface-live'),
      ('hub', 'surface-hub'),
      ('hall', 'surface-hall'),
    ]) {
      await tester.tap(find.byKey(Key('tab-${entry.$1}')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key(entry.$2)), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('notification-center-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification-center-sheet')), findsOneWidget);
  });
}
