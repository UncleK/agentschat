import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/core/navigation/app_routes.dart';
import 'package:agents_chat_app/main.dart';

void main() {
  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://localhost:3000/api/v1',
    realtimeWebSocketUrl: 'ws://localhost:3000/ws',
  );

  Future<void> pumpBootstrap(
    WidgetTester tester, {
    String? initialRouteOverride,
    Size surfaceSize = const Size(1280, 1600),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AgentsChatBootstrapApp(
        environment: environment,
        initialRouteOverride: initialRouteOverride,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('bootstrap app renders landing page by default', (
    WidgetTester tester,
  ) async {
    await pumpBootstrap(tester);

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const Key('landing-hero')), findsOneWidget);
    expect(
      find.byKey(const Key('landing-capabilities-section')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('landing-closing-cta')), findsOneWidget);
    expect(find.byKey(const Key('surface-hall')), findsNothing);
  });

  testWidgets('landing launch button opens the app shell', (
    WidgetTester tester,
  ) async {
    await pumpBootstrap(tester);

    final launchButton = find.byKey(const Key('landing-launch-app-primary'));
    await tester.ensureVisible(launchButton);
    await tester.tap(launchButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tab-hall')), findsOneWidget);
    expect(find.byKey(const Key('surface-hall')), findsOneWidget);
  });

  testWidgets('bootstrap app can start directly on /app', (
    WidgetTester tester,
  ) async {
    await pumpBootstrap(tester, initialRouteOverride: AppRoutes.appShell);

    expect(find.byKey(const Key('landing-hero')), findsNothing);
    expect(find.byKey(const Key('tab-hall')), findsOneWidget);
    expect(find.byKey(const Key('surface-hall')), findsOneWidget);
  });

  testWidgets('landing language menu updates localized copy', (
    WidgetTester tester,
  ) async {
    await pumpBootstrap(tester);

    expect(find.text('built for agents.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('landing-language-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('landing-language-option-chinese-simplified')).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('built for agents.'), findsNothing);
    expect(find.text('Launch App'), findsNothing);
  });

  testWidgets('landing page adapts to phone width without overflow errors', (
    WidgetTester tester,
  ) async {
    await pumpBootstrap(
      tester,
      surfaceSize: const Size(390, 1400),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing-hero')), findsOneWidget);
    expect(find.byKey(const Key('landing-launch-app-primary')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
