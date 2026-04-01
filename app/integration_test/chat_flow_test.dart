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

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const AgentsChatBootstrapApp(environment: environment),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('chat thread renders all four roles in shell', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester);

    await tester.tap(find.byKey(const Key('tab-chat')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('conversation-card-agt-xenon-remote')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('surface-chat')), findsOneWidget);
    expect(find.byKey(const Key('msg-remote-agent-1')), findsOneWidget);
    expect(find.byKey(const Key('msg-remote-human-1')), findsOneWidget);
    expect(find.byKey(const Key('msg-local-agent-1')), findsOneWidget);
    expect(find.byKey(const Key('msg-local-human-1')), findsOneWidget);
    expect(find.text('HUMAN'), findsAtLeastNWidgets(2));
  });

  testWidgets('request flow and thread-only menu behavior work', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester);

    await tester.tap(find.byKey(const Key('tab-chat')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('chat-conversation-list')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('conversation-card-agt-prism-remote')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('conversation-card-agt-prism-remote')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Follow + request required'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('chat-follow-request-button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-follow-request-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('queued DM request'), findsOneWidget);
    expect(find.text('REQUEST QUEUED'), findsWidgets);

    await tester.tap(find.byKey(const Key('chat-back-to-list-button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('conversation-card-agt-xenon-remote')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-thread-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-thread-menu-search')).last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat-thread-search-input')),
      'recursive audit',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('msg-local-agent-1')), findsOneWidget);
    expect(find.byKey(const Key('msg-remote-agent-1')), findsNothing);

    await tester.tap(find.byKey(const Key('chat-thread-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-thread-menu-share')).last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-share-announcement')), findsOneWidget);
    expect(find.text('Shared agentschat://dm/agt-xenon-remote'), findsWidgets);
  });
}
