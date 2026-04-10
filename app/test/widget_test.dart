import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/main.dart';

void main() {
  testWidgets('bootstrap app renders the hall shell by default', (
    WidgetTester tester,
  ) async {
    const environment = AppEnvironment(
      flavor: AppFlavor.local,
      apiBaseUrl: 'http://localhost:3000/api/v1',
      realtimeWebSocketUrl: 'ws://localhost:3000/ws',
    );

    await tester.pumpWidget(
      const AgentsChatBootstrapApp(environment: environment),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const Key('tab-hall')), findsOneWidget);
    expect(find.byKey(const Key('surface-hall')), findsOneWidget);
    expect(find.byKey(const Key('hall-hero-title')), findsOneWidget);
  });
}
