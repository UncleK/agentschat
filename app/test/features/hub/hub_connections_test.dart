import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/hub/hub_connections_sheet.dart';

import '../../test_support/session_fakes.dart';

void main() {
  late FakeApiClient api;
  late AppSessionController session;

  setUp(() async {
    api = FakeApiClient();
    final auth = FakeAuthRepository();
    final agents = FakeAgentsRepository();
    session = AppSessionController(
      apiClient: api,
      authRepository: auth,
      agentsRepository: agents,
      storage: InMemoryAppSessionStorage(),
    );
    final signedIn = signedInState(
      token: 'local-test',
      userId: 'owner',
      recommendedActiveAgentId: 'a',
    );
    auth.enqueueFetchMe((_) async => signedIn);
    agents.enqueueReadMine(
      () async => mineResponse(
        agents: [
          agentSummary(id: 'a'),
          agentSummary(id: 'b'),
        ],
      ),
    );
    await session.authenticate(signedIn);
  });
  tearDown(() => session.dispose());

  Map<String, dynamic> row(
    String id, {
    bool follows = false,
    bool follower = false,
  }) => {
    'id': id,
    'displayName': id,
    'status': 'offline',
    'relationship': {
      'viewerFollowsAgent': follows,
      'agentFollowsViewer': follower,
    },
  };
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: HubConnectionsSheet(session: session)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows only related Agents, retains a failed unfollow, then persists success',
    (tester) async {
      api.enqueueGet((path, query) async {
        expect(path, '/agents/directory');
        expect(query?['activeAgentId'], 'a');
        return {
          'agents': [
            row('target', follows: true, follower: true),
            row('unrelated'),
          ],
        };
      });
      await pump(tester);
      expect(find.byKey(const Key('hub-connection-target')), findsOneWidget);
      expect(find.byKey(const Key('hub-connection-unrelated')), findsNothing);
      api.enqueueDelete((path, body) async {
        expect(path, '/follows');
        expect(body?['actorAgentId'], 'a');
        throw StateError('injected failure');
      });
      await tester.ensureVisible(
        find.byKey(const Key('hub-connection-toggle-target')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hub-connection-toggle-target')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hub-connection-target')), findsOneWidget);
      expect(
        find.text('Unable to update this relationship. Please retry.'),
        findsOneWidget,
      );
      api.enqueueDelete((path, body) async {
        expect(body?['targetId'], 'target');
        expect(body?['actorType'], 'agent');
        return {};
      });
      api.enqueueGet(
        (_, _) async => {
          'agents': [row('target', follower: true)],
        },
      );
      await tester.ensureVisible(
        find.byKey(const Key('hub-connection-toggle-target')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hub-connection-toggle-target')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hub-connection-target')), findsNothing);
      await tester.tap(find.byKey(const Key('hub-connections-followers')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hub-connection-target')), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching active Agent rejects late directory responses', (
    tester,
  ) async {
    final slow = Completer<Map<String, dynamic>>();
    api.enqueueGet((_, query) {
      expect(query?['activeAgentId'], 'a');
      return slow.future;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: HubConnectionsSheet(session: session)),
      ),
    );
    await tester.pump();
    api.enqueueGet((_, query) async {
      expect(query?['activeAgentId'], 'b');
      return {
        'agents': [row('b-follow', follows: true)],
      };
    });
    await session.setCurrentActiveAgent('b');
    await tester.pumpAndSettle();
    slow.complete({
      'agents': [row('a-follow', follows: true)],
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hub-connection-b-follow')), findsOneWidget);
    expect(find.byKey(const Key('hub-connection-a-follow')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
