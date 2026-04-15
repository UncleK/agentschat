import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/auth/auth_repository.dart';
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
    late FakeApiClient apiClient;
    late InMemoryAppSessionStorage storage;
    late AppSessionController controller;

    setUp(() {
      authRepository = FakeAuthRepository();
      agentsRepository = FakeAgentsRepository();
      apiClient = FakeApiClient();
      storage = InMemoryAppSessionStorage();
      controller = AppSessionController(
        apiClient: apiClient,
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
      expect(
        find.byKey(const Key('human-access-import-agent-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('human-access-create-agent-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('human-access-claim-agent-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('human-auth-external-provider-button')),
        findsNothing,
      );
      expect(find.byKey(const Key('human-auth-email-button')), findsOneWidget);
      expect(
        find.byKey(const Key('app-settings-language-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('agent-security-section')), findsNothing);
    });

    testWidgets(
      'sign in sheet keeps the external provider entry inside the three-way auth switch',
      (WidgetTester tester) async {
        await pumpHub(tester);

        await tester.scrollUntilVisible(
          find.byKey(const Key('human-auth-email-button')),
          280,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('human-auth-email-button')));
        await tester.pumpAndSettle();

        expect(find.text('External'), findsOneWidget);
        await tester.tap(find.text('External'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('human-auth-external-provider-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('human-auth-external-disabled-button')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('human-auth-submit-button')), findsNothing);
      },
    );

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

        await tester.scrollUntilVisible(
          find.byKey(const Key('human-auth-email-button')),
          280,
          scrollable: find.byType(Scrollable).first,
        );
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
        tester.testTextInput.hide();
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('human-auth-submit-button')),
        );
        await tester.tap(find.byKey(const Key('human-auth-submit-button')));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Hub User'), findsOneWidget);
        expect(find.byKey(const Key('human-auth-email-button')), findsNothing);
        expect(
          find.byKey(const Key('human-auth-logout-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('app-settings-disconnect-agents-button')),
          findsOneWidget,
        );
        expect(controller.currentActiveAgent?.id, 'agt-owned-1');
      },
    );

    testWidgets(
      'human register requires an available unique username before creating the session',
      (WidgetTester tester) async {
        authRepository.enqueueUsernameAvailability((username) async {
          expect(username, 'hub_owner');
          return const UsernameAvailabilityResult(
            normalizedUsername: 'hub_owner',
            available: true,
            message: 'Username is available.',
          );
        });
        authRepository.enqueueRegisterWithEmail(({
          required email,
          required username,
          required displayName,
          required password,
        }) async {
          expect(email, 'owner@example.com');
          expect(username, 'hub_owner');
          expect(displayName, 'Hub Owner');
          expect(password, 'password123');
          return signedInState(
            token: 'token-register',
            userId: 'usr-register',
            email: email,
            username: username,
            displayName: displayName,
          );
        });
        authRepository.enqueueFetchMe((token) async {
          expect(token, 'token-register');
          return signedInState(
            token: token,
            userId: 'usr-register',
            email: 'owner@example.com',
            username: 'hub_owner',
            displayName: 'Hub Owner',
            recommendedActiveAgentId: 'agt-owned-1',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
          );
        });

        await pumpHub(tester);

        await tester.scrollUntilVisible(
          find.byKey(const Key('human-auth-email-button')),
          280,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('human-auth-email-button')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Create').last);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('human-auth-email-field')),
          'owner@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('human-auth-username-field')),
          '@hub_owner',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('human-auth-display-name-field')),
          'Hub Owner',
        );
        await tester.enterText(
          find.byKey(const Key('human-auth-password-field')),
          'password123',
        );
        await tester.pumpAndSettle();

        expect(find.text('Username is available.'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const Key('human-auth-submit-button')),
        );
        await tester.tap(find.byKey(const Key('human-auth-submit-button')));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Hub Owner'), findsOneWidget);
        expect(find.text('@hub_owner'), findsOneWidget);
      },
    );

    testWidgets(
      'signed-out import and claim actions only prompt for sign-in instead of opening auth sheets',
      (WidgetTester tester) async {
        await pumpHub(tester);

        await tester.ensureVisible(
          find.byKey(const Key('human-access-import-agent-button')),
        );
        await tester.tap(
          find.byKey(const Key('human-access-import-agent-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sign in as human first'), findsOneWidget);
        expect(find.byKey(const Key('generate-import-link-button')), findsNothing);

        await tester.tap(
          find.byKey(const Key('human-access-claim-agent-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sign in as human first'), findsOneWidget);
        expect(find.byKey(const Key('claimable-agents-sheet')), findsNothing);
      },
    );

    testWidgets(
      'signed-in import flow generates a secure bootstrap link instead of collecting manual profile fields',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
          ),
        );
        agentsRepository.enqueueCreateHumanOwnedAgentInvitation(() async {
          return const HumanOwnedAgentInvitation(
            agentId: 'agt-invite-1',
            code: 'A1B2C3D4E5F6',
            bootstrapPath:
                '/api/v1/agents/bootstrap?claimToken=claim.v1.bootstrap-token',
            claimToken: 'claim.v1.bootstrap-token',
            expiresAt: '2026-04-14T12:00:00.000Z',
          );
        });

        await pumpHub(tester);

        await tester.ensureVisible(
          find.byKey(const Key('human-access-import-agent-button')),
        );
        await tester.tap(
          find.byKey(const Key('human-access-import-agent-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('generate-import-link-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('import-display-name-field')),
          findsNothing,
        );
        expect(find.byKey(const Key('import-bio-field')), findsNothing);

        await tester.tap(find.byKey(const Key('generate-import-link-button')));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.textContaining('/api/v1/agents/bootstrap?claimToken='),
          findsOneWidget,
        );
        expect(find.text('Code A1B2C3D4E5F6'), findsOneWidget);
        expect(
          find.byKey(const Key('copy-import-link-button')),
          findsOneWidget,
        );
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
          find.byKey(const Key('human-access-claim-agent-button')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('pending-claims-section')), findsOneWidget);
        expect(
          find.byKey(const Key('pending-claim-card-claim-1')),
          findsOneWidget,
        );
        expect(find.text('Hub User'), findsOneWidget);
        expect(find.byKey(const Key('human-auth-email-button')), findsNothing);
        expect(
          find.byKey(const Key('human-access-import-agent-button')),
          findsOneWidget,
        );
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
      'owned agent profile updates the live endpoint when the active selection changes',
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

        expect(find.text('CONNECTION ENDPOINT'), findsOneWidget);
        expect(find.text('@agt-owned-1'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const Key('owned-agent-carousel')),
        );
        await tester.drag(
          find.byKey(const Key('owned-agent-carousel')),
          const Offset(-240, 0),
        );
        await tester.pumpAndSettle();

        expect(controller.currentActiveAgent?.id, 'agt-owned-2');
        expect(find.text('@agt-owned-2'), findsOneWidget);
      },
    );

    testWidgets(
      'message button opens the owned-agent admin thread and first send creates a human-to-agent thread',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [
              agentSummary(
                id: 'agt-owned-1',
                handle: 'owned-one',
                displayName: 'Owned One',
              ),
            ],
          ),
        );

        apiClient.enqueueGet((path, queryParameters) async {
          expect(path, '/content/dm/threads');
          expect(queryParameters?['activeAgentId'], 'agt-owned-1');
          return <String, dynamic>{
            'activeAgentId': 'agt-owned-1',
            'threads': const <Map<String, dynamic>>[],
            'nextCursor': null,
          };
        });
        apiClient.enqueuePost((path, body) async {
          expect(path, '/content/dm');
          expect(body?['recipientType'], 'agent');
          expect(body?['recipientAgentId'], 'agt-owned-1');
          expect(body?.containsKey('activeAgentId'), isFalse);
          expect(body?['content'], 'Run diagnostics');
          return <String, dynamic>{
            'threadId': 'thread-owned-admin',
            'eventId': 'evt-owned-admin',
            'eventType': 'dm.send',
          };
        });
        apiClient.enqueueGet((path, queryParameters) async {
          expect(path, '/content/dm/threads/thread-owned-admin/messages');
          expect(queryParameters?['activeAgentId'], 'agt-owned-1');
          return <String, dynamic>{
            'threadId': 'thread-owned-admin',
            'activeAgentId': 'agt-owned-1',
            'messages': [
              <String, dynamic>{
                'eventId': 'evt-owned-admin',
                'actor': <String, dynamic>{
                  'type': 'human',
                  'id': 'usr-hub',
                  'displayName': 'Hub User',
                },
                'contentType': 'text',
                'content': 'Run diagnostics',
                'occurredAt': '2026-04-14T08:15:00.000Z',
              },
            ],
            'nextCursor': null,
          };
        });

        await pumpHub(tester);

        await tester.tap(
          find.byKey(const Key('selected-agent-message-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('owned-agent-command-sheet')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('owned-agent-command-empty-title')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('owned-agent-command-input')),
          'Run diagnostics',
        );
        await tester.tap(
          find.byKey(const Key('owned-agent-command-send-button')),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('owned-agent-command-msg-evt-owned-admin')),
          findsOneWidget,
        );
        expect(find.text('Run diagnostics'), findsOneWidget);
      },
    );

    testWidgets(
      'message button keeps the agent command sheet open and authenticates inline when the admin is signed out',
      (WidgetTester tester) async {
        final previewAuthRepository = FakeAuthRepository();
        final previewAgentsRepository = FakeAgentsRepository();
        final previewApiClient = FakeApiClient();
        final previewController = AppSessionController(
          apiClient: previewApiClient,
          authRepository: previewAuthRepository,
          agentsRepository: previewAgentsRepository,
          storage: InMemoryAppSessionStorage(),
          enableLocalPreviewAgents: true,
        );
        await previewController.bootstrap();

        previewAuthRepository.enqueueLoginWithEmail(({
          required email,
          required password,
        }) async {
          expect(email, 'owner@example.com');
          expect(password, 'password123');
          return signedInState(
            token: 'token-inline-command',
            userId: 'usr-inline-command',
            displayName: 'Inline Owner',
            email: email,
          );
        });
        previewAuthRepository.enqueueFetchMe((token) async {
          expect(token, 'token-inline-command');
          return signedInState(
            token: token,
            userId: 'usr-inline-command',
            displayName: 'Inline Owner',
            email: 'owner@example.com',
            recommendedActiveAgentId: 'preview-agent-aether',
          );
        });
        previewAgentsRepository.enqueueReadMine(() async => mineResponse());
        previewApiClient.enqueueGet((path, queryParameters) async {
          expect(path, '/content/dm/threads');
          expect(queryParameters?['activeAgentId'], 'preview-agent-aether');
          return <String, dynamic>{
            'activeAgentId': 'preview-agent-aether',
            'threads': const <Map<String, dynamic>>[],
            'nextCursor': null,
          };
        });

        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: AppSessionScope(
              controller: previewController,
              child: const Scaffold(body: HubScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('selected-agent-message-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('owned-agent-command-sheet')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('human-auth-email-field')), findsOneWidget);
        expect(
          find.byKey(const Key('human-auth-submit-button')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('human-auth-email-field')),
          'owner@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('human-auth-password-field')),
          'password123',
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('human-auth-submit-button')),
        );
        await tester.tap(find.byKey(const Key('human-auth-submit-button')));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('owned-agent-command-sheet')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('owned-agent-command-empty-title')),
          findsOneWidget,
        );
        expect(find.text('Inline Owner'), findsOneWidget);
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
        await tester.ensureVisible(
          find.byKey(const Key('human-access-claim-agent-button')),
        );
        await tester.tap(
          find.byKey(const Key('human-access-claim-agent-button')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('claimable-agents-sheet')), findsOneWidget);
        expect(
          find.byKey(const Key('claim-agent-button-agt-claimable-1')),
          findsOneWidget,
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

        expect(
          find.byKey(const Key('owned-agent-card-agt-owned-21')),
          findsOneWidget,
        );
        expect(controller.currentActiveAgentCandidates.length, 21);
      },
    );
  });
}
