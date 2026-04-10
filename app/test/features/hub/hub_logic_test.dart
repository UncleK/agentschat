import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/session/app_session_scope.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/hub/hub_screen.dart';

import '../../test_support/session_fakes.dart';

void main() {
  group('HubScreen live session flow', () {
    late FakeAuthRepository authRepository;
    late FakeAgentsRepository agentsRepository;
    late InMemoryAppSessionStorage storage;
    late AppSessionController controller;

    setUp(() {
      authRepository = FakeAuthRepository();
      agentsRepository = FakeAgentsRepository();
      storage = InMemoryAppSessionStorage();
      controller = AppSessionController(
        apiClient: ApiClient(baseUrl: 'http://localhost:3000/api/v1'),
        authRepository: authRepository,
        agentsRepository: agentsRepository,
        storage: storage,
      );
    });

    Future<void> authenticateWithMine(AgentsMineResponse mine) async {
      authRepository.enqueueFetchMe((token) async {
        return signedInState(
          token: token,
          userId: 'usr-hub',
          displayName: 'Hub User',
          recommendedActiveAgentId: mine.agents.isEmpty
              ? null
              : mine.agents.first.id,
        );
      });
      agentsRepository.enqueueReadMine(() async => mine);
      await controller.authenticate(
        signedInState(token: 'token-hub', userId: 'usr-hub'),
      );
    }

    Future<void> pumpHub(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: AppSessionScope(
            controller: controller,
            child: const Scaffold(body: HubScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('signed-out hub surfaces human access actions', (
      WidgetTester tester,
    ) async {
      await pumpHub(tester);

      expect(find.byKey(const Key('human-access-section')), findsOneWidget);
      expect(find.byKey(const Key('human-auth-email-button')), findsOneWidget);
      expect(
        find.byKey(const Key('human-auth-register-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('human-auth-google-button')), findsOneWidget);
      expect(find.byKey(const Key('human-auth-github-button')), findsOneWidget);
    });

    testWidgets(
      'human sign in from hub boots the live session and hides signed-out actions',
      (WidgetTester tester) async {
        authRepository.enqueueLoginWithEmail(({
          required email,
          required password,
        }) async {
          expect(email, 'owner@example.com');
          expect(password, 'password123');
          return signedInState(
            token: 'token-live',
            userId: 'usr-hub',
            displayName: 'Hub User',
            email: email,
          );
        });
        authRepository.enqueueFetchMe((token) async {
          expect(token, 'token-live');
          return signedInState(
            token: token,
            userId: 'usr-hub',
            displayName: 'Hub User',
            email: 'owner@example.com',
            recommendedActiveAgentId: 'agt-owned-1',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
          );
        });

        await pumpHub(tester);

        await tester.tap(find.byKey(const Key('human-auth-email-button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('human-auth-email-field')),
          'owner@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('human-auth-password-field')),
          'password123',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('human-auth-submit-button')));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Hub User'), findsOneWidget);
        expect(find.byKey(const Key('human-auth-email-button')), findsNothing);
        expect(
          find.byKey(const Key('human-auth-logout-button')),
          findsOneWidget,
        );
        expect(controller.currentActiveAgent?.id, 'agt-owned-1');
      },
    );

    testWidgets(
      'renders owned, claimable, and pending partitions from session scope',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [
              agentSummary(
                id: 'agt-owned-1',
                handle: 'owned-one',
                displayName: 'Owned One',
                bio: 'Current active owned agent',
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
                claimRequestId: 'claim-1',
                agentId: 'agt-pending-1',
                handle: 'pending-one',
                displayName: 'Pending One',
              ),
            ],
          ),
        );

        await pumpHub(tester);

        expect(find.byKey(const Key('surface-hub')), findsOneWidget);
        expect(
          find.byKey(const Key('owned-agent-card-agt-owned-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('claimable-agents-section')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('claimable-agent-card-agt-claimable-1')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('pending-claims-section')), findsOneWidget);
        expect(
          find.byKey(const Key('pending-claim-card-claim-1')),
          findsOneWidget,
        );
        expect(find.text('Hub User'), findsOneWidget);
        expect(find.byKey(const Key('human-auth-email-button')), findsNothing);
        expect(find.byKey(const Key('human-auth-google-button')), findsNothing);
        expect(find.byKey(const Key('human-auth-github-button')), findsNothing);
      },
    );

    testWidgets('selecting an owned agent updates the global active agent', (
      WidgetTester tester,
    ) async {
      await authenticateWithMine(
        mineResponse(
          agents: [
            agentSummary(id: 'agt-owned-1', displayName: 'Owned One'),
            agentSummary(id: 'agt-owned-2', displayName: 'Owned Two'),
          ],
          claimableAgents: [
            agentSummary(
              id: 'agt-claimable-1',
              displayName: 'Claimable One',
              ownerType: 'self',
            ),
          ],
        ),
      );

      await pumpHub(tester);

      expect(controller.currentActiveAgent?.id, 'agt-owned-1');

      await tester.ensureVisible(find.byKey(const Key('owned-agent-carousel')));
      await tester.drag(
        find.byKey(const Key('owned-agent-carousel')),
        const Offset(-240, 0),
      );
      await tester.pumpAndSettle();

      expect(controller.currentActiveAgent?.id, 'agt-owned-2');
      expect(await storage.readCurrentActiveAgentId(), 'agt-owned-2');
      expect(controller.currentActiveAgentCandidates.map((agent) => agent.id), [
        'agt-owned-1',
        'agt-owned-2',
      ]);
    });

    testWidgets(
      'owned agent carousel explains that DM follows the active selection',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [
              agentSummary(id: 'agt-owned-1', displayName: 'Owned One'),
              agentSummary(id: 'agt-owned-2', displayName: 'Owned Two'),
            ],
          ),
        );

        await pumpHub(tester);

        expect(
          find.byKey(const Key('active-agent-carousel-hint')),
          findsOneWidget,
        );
        expect(
          find.textContaining('DM follows this selection'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'claim refreshes partitions and only promotes the agent after it reaches owned agents',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
            claimableAgents: [
              agentSummary(
                id: 'agt-claimable-1',
                displayName: 'Claimable One',
                ownerType: 'self',
              ),
            ],
          ),
        );

        agentsRepository.enqueueRequestClaim((agentId) async {
          expect(agentId, 'agt-claimable-1');
          return <String, dynamic>{
            'claimRequest': <String, dynamic>{'id': 'claim-1'},
            'challengeToken': 'claim:agt-claimable-1:usr-hub',
          };
        });
        agentsRepository.enqueueConfirmClaim(({
          required agentId,
          required claimRequestId,
          required challengeToken,
        }) async {
          expect(agentId, 'agt-claimable-1');
          expect(claimRequestId, 'claim-1');
          expect(challengeToken, 'claim:agt-claimable-1:usr-hub');
          return <String, dynamic>{
            'agent': <String, dynamic>{'id': 'agt-claimable-1'},
          };
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [
              agentSummary(id: 'agt-claimable-1', displayName: 'Claimable One'),
              agentSummary(id: 'agt-owned-1', displayName: 'Owned One'),
            ],
          );
        });

        await pumpHub(tester);

        expect(controller.currentActiveAgent?.id, 'agt-owned-1');
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
        await tester.pump();
        await tester.pumpAndSettle();

        expect(controller.currentActiveAgent?.id, 'agt-claimable-1');
        expect(
          find.byKey(const Key('owned-agent-card-agt-claimable-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('claimable-agent-card-agt-claimable-1')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'keeps a selected owned agent visible in the carousel even when it falls outside the first twenty records',
      (WidgetTester tester) async {
        final agents = List.generate(
          21,
          (index) => agentSummary(
            id: 'agt-owned-${index + 1}',
            displayName: 'Owned ${index + 1}',
          ),
        );

        await authenticateWithMine(mineResponse(agents: agents));
        await controller.setCurrentActiveAgent('agt-owned-21');

        await pumpHub(tester);

        expect(find.text('21 OWNED AGENTS'), findsOneWidget);
        expect(
          find.byKey(const Key('owned-agent-card-agt-owned-21')),
          findsOneWidget,
        );
      },
    );
  });
}
