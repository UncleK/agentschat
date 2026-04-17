import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:agents_chat_app/app_shell.dart';
import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/core/network/notifications_repository.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';

import '../test/test_support/session_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://localhost:3000/api/v1',
    realtimeWebSocketUrl: 'ws://localhost:3000/ws',
  );

  Future<void> pumpHarness(
    WidgetTester tester, {
    required AppSessionController sessionController,
    required NotificationsRepository notificationsRepository,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() async {
      sessionController.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: AgentsChatAppShell(
          environment: environment,
          sessionController: sessionController,
          notificationsRepository: notificationsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hub flow verifies live partitions and active-agent mutation', (
    WidgetTester tester,
  ) async {
    final authRepository = FakeAuthRepository()
      ..enqueueFetchMe((token) async {
        return signedInState(
          token: token,
          userId: 'usr-hub-integration',
          displayName: 'Integration Owner',
          email: 'owner@example.com',
          recommendedActiveAgentId: 'agt-owned-1',
        );
      });
    final agentsRepository = FakeAgentsRepository()
      ..enqueueReadMine(() async {
        return mineResponse(
          agents: [
            agentSummary(
              id: 'agt-owned-1',
              handle: 'owned-one',
              displayName: 'Owned One',
              bio: 'Primary owned agent',
            ),
            agentSummary(
              id: 'agt-owned-2',
              handle: 'owned-two',
              displayName: 'Owned Two',
            ),
          ],
          claimableAgents: [
            agentSummary(
              id: 'agt-claimable-1',
              handle: 'claimable-one',
              displayName: 'Claimable One',
              ownerType: 'self',
            ),
          ],
          pendingClaims: [
            pendingClaimSummary(
              claimRequestId: 'claim-pending-1',
              agentId: 'agt-pending-1',
              handle: 'pending-one',
              displayName: 'Pending One',
            ),
          ],
        );
      })
      ..enqueueImportHumanOwnedAgent(({
        required handle,
        required displayName,
        avatarUrl,
        bio,
      }) async {
        expect(handle, 'imported-agent');
        expect(displayName, 'Imported Agent');
        expect(bio, 'Imported from integration test');
        return <String, dynamic>{'id': 'agt-imported-1'};
      })
      ..enqueueReadMine(() async {
        return mineResponse(
          agents: [
            agentSummary(
              id: 'agt-imported-1',
              handle: 'imported-agent',
              displayName: 'Imported Agent',
              bio: 'Imported from integration test',
            ),
            agentSummary(
              id: 'agt-owned-1',
              handle: 'owned-one',
              displayName: 'Owned One',
              bio: 'Primary owned agent',
            ),
            agentSummary(
              id: 'agt-owned-2',
              handle: 'owned-two',
              displayName: 'Owned Two',
            ),
          ],
          claimableAgents: [
            agentSummary(
              id: 'agt-claimable-1',
              handle: 'claimable-one',
              displayName: 'Claimable One',
              ownerType: 'self',
            ),
          ],
          pendingClaims: [
            pendingClaimSummary(
              claimRequestId: 'claim-pending-1',
              agentId: 'agt-pending-1',
              handle: 'pending-one',
              displayName: 'Pending One',
            ),
          ],
        );
      })
      ..enqueueRequestClaim((agentId, expiresInMinutes) async {
        expect(agentId, 'agt-claimable-1');
        expect(expiresInMinutes, 60);
        return const AgentClaimRequest(
          claimRequestId: 'claim-claimable-1',
          agentId: 'agt-claimable-1',
          status: 'pending',
          requestedAt: '2026-04-17T10:00:00.000Z',
          expiresAt: '2026-04-17T11:00:00.000Z',
          challengeToken: 'claimreq.v1.integration',
        );
      })
      ..enqueueReadMine(() async {
        return mineResponse(
          agents: [
            agentSummary(
              id: 'agt-imported-1',
              handle: 'imported-agent',
              displayName: 'Imported Agent',
              bio: 'Imported from integration test',
            ),
            agentSummary(
              id: 'agt-owned-1',
              handle: 'owned-one',
              displayName: 'Owned One',
              bio: 'Primary owned agent',
            ),
            agentSummary(
              id: 'agt-owned-2',
              handle: 'owned-two',
              displayName: 'Owned Two',
            ),
          ],
          claimableAgents: const [],
          pendingClaims: [
            pendingClaimSummary(
              claimRequestId: 'claim-claimable-1',
              agentId: 'agt-claimable-1',
              handle: 'claimable-one',
              displayName: 'Claimable One',
            ),
            pendingClaimSummary(
              claimRequestId: 'claim-pending-1',
              agentId: 'agt-pending-1',
              handle: 'pending-one',
              displayName: 'Pending One',
            ),
          ],
        );
      });
    final storage = InMemoryAppSessionStorage();
    await storage.writeToken('token-hub-integration');
    final sessionController = AppSessionController(
      apiClient: ApiClient(baseUrl: environment.apiBaseUrl),
      authRepository: authRepository,
      agentsRepository: agentsRepository,
      storage: storage,
    );

    await pumpHarness(
      tester,
      sessionController: sessionController,
      notificationsRepository: _FakeNotificationsRepository(),
    );

    await tester.tap(find.byKey(const Key('tab-hub')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('surface-hub')), findsOneWidget);
    expect(find.byKey(const Key('add-agent-button')), findsOneWidget);
    expect(find.byKey(const Key('claimable-agents-section')), findsOneWidget);
    expect(find.byKey(const Key('pending-claims-section')), findsOneWidget);
    expect(find.byKey(const Key('human-safety-section')), findsOneWidget);
    expect(
      find.byKey(const Key('owned-agent-card-agt-owned-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('claimable-agent-card-agt-claimable-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pending-claim-card-claim-pending-1')),
      findsOneWidget,
    );
    expect(sessionController.currentActiveAgent?.id, 'agt-owned-1');
    expect(
      find.byKey(const Key('agent-safety-section-agt-owned-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('following-section-agt-owned-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('followed-section-agt-owned-1')),
      findsOneWidget,
    );
    expect(sessionController.currentActiveAgent?.id, isNot('agt-claimable-1'));

    await tester.ensureVisible(find.byKey(const Key('hub-agent-next')));
    await tester.tap(find.byKey(const Key('hub-agent-next')));
    await tester.pumpAndSettle();

    expect(sessionController.currentActiveAgent?.id, 'agt-owned-2');
    expect(
      find.byKey(const Key('agent-safety-section-agt-owned-2')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('add-agent-button')));
    await tester.tap(find.byKey(const Key('add-agent-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create-new-agent-disabled')), findsOneWidget);
    expect(find.byKey(const Key('import-agent-option')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('import-handle-field')),
      'imported-agent',
    );
    await tester.enterText(
      find.byKey(const Key('import-display-name-field')),
      'Imported Agent',
    );
    await tester.enterText(
      find.byKey(const Key('import-bio-field')),
      'Imported from integration test',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('complete-import-button')));
    await tester.pumpAndSettle();

    expect(sessionController.currentActiveAgent?.id, 'agt-imported-1');
    expect(
      find.byKey(const Key('owned-agent-card-agt-imported-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('claimable-agent-card-agt-claimable-1')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('claim-agent-button-agt-claimable-1')),
    );
    await tester.tap(
      find.byKey(const Key('claim-agent-button-agt-claimable-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('generate-claim-link-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('generate-claim-link-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(sessionController.currentActiveAgent?.id, 'agt-imported-1');
    expect(
      find.byKey(const Key('pending-claim-card-claim-pending-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('generated-claim-link-text')),
      findsOneWidget,
    );
  });
}

class _FakeNotificationsRepository extends NotificationsRepository {
  _FakeNotificationsRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  @override
  Future<NotificationBellState> bellState() async {
    return NotificationBellState.empty;
  }

  @override
  Future<NotificationListResponse> list() async {
    return const NotificationListResponse(notifications: []);
  }

  @override
  Future<NotificationBellState> markRead({
    List<String>? notificationIds,
    bool? markAll,
  }) async {
    return NotificationBellState.empty;
  }
}
