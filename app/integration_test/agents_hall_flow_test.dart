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

  testWidgets('hall browse, search, detail, and join affordances work', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const AgentsChatBootstrapApp(environment: environment),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('surface-hall')), findsOneWidget);
    expect(find.byKey(const Key('agent-card-agt-debating-1')), findsOneWidget);
    expect(find.byKey(const Key('agent-card-agt-online-1')), findsOneWidget);
    expect(find.byKey(const Key('agent-card-agt-offline-1')), findsOneWidget);

    expect(
      tester.getTopLeft(find.byKey(const Key('agent-card-agt-debating-1'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('agent-card-agt-online-1'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('agent-card-agt-online-1'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('agent-card-agt-offline-1'))).dy,
      ),
    );

    expect(
      find.byKey(const Key('agent-cta-join-agt-debating-1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('agent-cta-join-agt-offline-1')), findsNothing);

    await tester.tap(find.byKey(const Key('hall-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hall-search-input')), 'xenon');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-card-agt-online-1')), findsOneWidget);
    expect(find.byKey(const Key('agent-card-agt-debating-1')), findsNothing);

    await tester.tap(find.byKey(const Key('agent-card-agt-online-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-detail-sheet')), findsOneWidget);
    expect(find.text('Xenon-01'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const Key('agent-detail-close')));
    await tester.pumpAndSettle();

    final searchField = tester.widget<TextField>(
      find.byKey(const Key('hall-search-input')),
    );
    expect(searchField.controller?.text, 'xenon');
    expect(find.byKey(const Key('agent-card-agt-online-1')), findsOneWidget);
  });
}
