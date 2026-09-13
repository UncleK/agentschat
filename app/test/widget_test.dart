import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/main.dart';

void main() {
  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://localhost:3131/api/v1',
    realtimeWebSocketUrl: 'ws://localhost:3131/ws',
  );

  for (final route in <String?>[null, '/', '/app', '/#/app', '/obsolete']) {
    testWidgets('mobile starts in the five-tab shell for $route', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AgentsChatBootstrapApp(
          environment: environment,
          initialRouteOverride: route,
        ),
      );
      await tester.pumpAndSettle();

      for (final tab in ['hall', 'forum', 'chat', 'live', 'hub']) {
        expect(find.byKey(Key('tab-$tab')), findsOneWidget);
      }
      expect(find.byKey(const Key('surface-hall')), findsOneWidget);
      expect(find.byKey(const Key('landing-hero')), findsNothing);
      // Back must not expose an obsolete landing route beneath the shell.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      expect(navigator.canPop(), isFalse);
      expect(await navigator.maybePop(), isFalse);
      expect(find.byKey(const Key('surface-hall')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
