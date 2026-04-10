import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/api_exception.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';

import '../../test_support/session_fakes.dart';

void main() {
  group('AppSessionController', () {
    late ApiClient apiClient;
    late FakeAuthRepository authRepository;
    late FakeAgentsRepository agentsRepository;
    late InMemoryAppSessionStorage storage;
    late AppSessionController controller;

    setUp(() {
      apiClient = ApiClient(baseUrl: 'http://localhost:3000/api/v1');
      authRepository = FakeAuthRepository();
      agentsRepository = FakeAgentsRepository();
      storage = InMemoryAppSessionStorage();
      controller = AppSessionController(
        apiClient: apiClient,
        authRepository: authRepository,
        agentsRepository: agentsRepository,
        storage: storage,
      );
    });

    test('bootstrap keeps a persisted eligible active agent', () async {
      await storage.writeToken('token-1');
      await storage.writeCurrentActiveAgentId('agt-persisted');
      authRepository.enqueueFetchMe((token) async {
        expect(token, 'token-1');
        return signedInState(
          token: token,
          userId: 'usr-1',
          recommendedActiveAgentId: 'agt-recommended',
        );
      });
      agentsRepository.enqueueReadMine(() async {
        return mineResponse(
          agents: [
            agentSummary(id: 'agt-recommended'),
            agentSummary(id: 'agt-persisted'),
          ],
        );
      });

      await controller.bootstrap();

      expect(controller.bootstrapStatus, AppSessionBootstrapStatus.ready);
      expect(controller.currentUser?.id, 'usr-1');
      expect(controller.currentActiveAgent?.id, 'agt-persisted');
      expect(await storage.readCurrentActiveAgentId(), 'agt-persisted');
      expect(apiClient.hasAuthToken, isTrue);
    });

    test(
      'bootstrap clears an invalid persisted id and falls back to a valid recommendation',
      () async {
        await storage.writeToken('token-1');
        await storage.writeCurrentActiveAgentId('agt-stale');
        authRepository.enqueueFetchMe((token) async {
          return signedInState(
            token: token,
            userId: 'usr-1',
            recommendedActiveAgentId: 'agt-recommended',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [
              agentSummary(id: 'agt-recommended'),
              agentSummary(id: 'agt-first'),
            ],
          );
        });

        await controller.bootstrap();

        expect(controller.currentActiveAgent?.id, 'agt-recommended');
        expect(await storage.readCurrentActiveAgentId(), 'agt-recommended');
      },
    );

    test(
      'bootstrap ignores an invalid recommendation and falls back to first owned agent',
      () async {
        await storage.writeToken('token-1');
        authRepository.enqueueFetchMe((token) async {
          return signedInState(
            token: token,
            userId: 'usr-1',
            recommendedActiveAgentId: 'agt-missing',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [
              agentSummary(id: 'agt-first'),
              agentSummary(id: 'agt-second'),
            ],
          );
        });

        await controller.bootstrap();

        expect(controller.currentActiveAgent?.id, 'agt-first');
        expect(await storage.readCurrentActiveAgentId(), 'agt-first');
      },
    );

    test(
      'bootstrap falls back to first owned agent when there is no recommendation',
      () async {
        await storage.writeToken('token-1');
        authRepository.enqueueFetchMe((token) async {
          return signedInState(token: token, userId: 'usr-1');
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [
              agentSummary(id: 'agt-first'),
              agentSummary(id: 'agt-second'),
            ],
          );
        });

        await controller.bootstrap();

        expect(controller.currentActiveAgent?.id, 'agt-first');
        expect(await storage.readCurrentActiveAgentId(), 'agt-first');
      },
    );

    test(
      'bootstrap clears active-agent persistence when no owned agents are eligible',
      () async {
        await storage.writeToken('token-1');
        await storage.writeCurrentActiveAgentId('agt-stale');
        authRepository.enqueueFetchMe((token) async {
          return signedInState(
            token: token,
            userId: 'usr-1',
            recommendedActiveAgentId: 'agt-missing',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            claimableAgents: [
              agentSummary(id: 'agt-claimable', ownerType: 'self'),
            ],
            pendingClaims: [
              pendingClaimSummary(
                claimRequestId: 'claim-1',
                agentId: 'agt-pending',
              ),
            ],
          );
        });

        await controller.bootstrap();

        expect(controller.currentUser?.id, 'usr-1');
        expect(controller.currentActiveAgent, isNull);
        expect(controller.currentActiveAgentCandidates, isEmpty);
        expect(controller.claimableAgents, hasLength(1));
        expect(controller.pendingClaims, hasLength(1));
        expect(await storage.readCurrentActiveAgentId(), isNull);
      },
    );

    test('local preview agents appear when owned agents are empty', () async {
      final previewController = AppSessionController(
        apiClient: apiClient,
        authRepository: authRepository,
        agentsRepository: agentsRepository,
        storage: storage,
        enableLocalPreviewAgents: true,
      );
      addTearDown(previewController.dispose);

      await storage.writeToken('token-1');
      authRepository.enqueueFetchMe((token) async {
        return signedInState(token: token, userId: 'usr-1');
      });
      agentsRepository.enqueueReadMine(() async {
        return mineResponse();
      });

      await previewController.bootstrap();

      expect(previewController.isUsingLocalPreviewAgents, isTrue);
      expect(previewController.currentActiveAgentCandidates, hasLength(3));
      expect(previewController.currentActiveAgent?.id, 'preview-agent-aether');
    });

    test(
      'refreshMine updates all three partitions and revalidates selection',
      () async {
        await storage.writeToken('token-1');
        authRepository.enqueueFetchMe((token) async {
          return signedInState(
            token: token,
            userId: 'usr-1',
            recommendedActiveAgentId: 'agt-owned-1',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [agentSummary(id: 'agt-owned-1')],
            claimableAgents: [
              agentSummary(id: 'agt-claimable-1', ownerType: 'self'),
            ],
            pendingClaims: [
              pendingClaimSummary(
                claimRequestId: 'claim-1',
                agentId: 'agt-pending-1',
              ),
            ],
          );
        });

        await controller.bootstrap();

        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [agentSummary(id: 'agt-owned-2')],
            claimableAgents: [
              agentSummary(id: 'agt-claimable-2', ownerType: 'self'),
            ],
            pendingClaims: [
              pendingClaimSummary(
                claimRequestId: 'claim-2',
                agentId: 'agt-pending-2',
              ),
            ],
          );
        });

        await controller.refreshMine();

        expect(controller.currentActiveAgent?.id, 'agt-owned-2');
        expect(controller.currentActiveAgentCandidates, hasLength(1));
        expect(controller.claimableAgents.single.id, 'agt-claimable-2');
        expect(controller.pendingClaims.single.claimRequestId, 'claim-2');
        expect(await storage.readCurrentActiveAgentId(), 'agt-owned-2');
      },
    );

    test(
      'importHumanOwnedAgent refreshes mine and promotes the new owned agent to active',
      () async {
        await storage.writeToken('token-1');
        authRepository.enqueueFetchMe((token) async {
          return signedInState(token: token, userId: 'usr-1');
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(agents: [agentSummary(id: 'agt-owned-1')]);
        });

        await controller.bootstrap();

        agentsRepository.enqueueImportHumanOwnedAgent(({
          required handle,
          required displayName,
          avatarUrl,
          bio,
        }) async {
          expect(handle, 'new-owned-agent');
          expect(displayName, 'New Owned Agent');
          expect(bio, 'Imported from Hub');
          return <String, dynamic>{'id': 'agt-owned-2'};
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [
              agentSummary(
                id: 'agt-owned-2',
                handle: 'new-owned-agent',
                displayName: 'New Owned Agent',
                bio: 'Imported from Hub',
              ),
              agentSummary(id: 'agt-owned-1'),
            ],
          );
        });

        await controller.importHumanOwnedAgent(
          handle: 'new-owned-agent',
          displayName: 'New Owned Agent',
          bio: 'Imported from Hub',
        );

        expect(controller.currentActiveAgent?.id, 'agt-owned-2');
        expect(controller.currentActiveAgentCandidates.first.id, 'agt-owned-2');
        expect(await storage.readCurrentActiveAgentId(), 'agt-owned-2');
      },
    );

    test(
      'claimAgent confirms the claim, refreshes mine, and promotes the agent only after it reaches owned agents',
      () async {
        await storage.writeToken('token-1');
        authRepository.enqueueFetchMe((token) async {
          return signedInState(token: token, userId: 'usr-1');
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [agentSummary(id: 'agt-owned-1')],
            claimableAgents: [
              agentSummary(id: 'agt-claimable-1', ownerType: 'self'),
            ],
          );
        });

        await controller.bootstrap();

        agentsRepository.enqueueRequestClaim((agentId) async {
          expect(agentId, 'agt-claimable-1');
          return <String, dynamic>{
            'claimRequest': <String, dynamic>{'id': 'claim-1'},
            'challengeToken': 'claim:agt-claimable-1:usr-1',
          };
        });
        agentsRepository.enqueueConfirmClaim(({
          required agentId,
          required claimRequestId,
          required challengeToken,
        }) async {
          expect(agentId, 'agt-claimable-1');
          expect(claimRequestId, 'claim-1');
          expect(challengeToken, 'claim:agt-claimable-1:usr-1');
          return <String, dynamic>{
            'agent': <String, dynamic>{'id': 'agt-claimable-1'},
          };
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [
              agentSummary(
                id: 'agt-claimable-1',
                ownerType: 'human',
                displayName: 'Claimed Agent',
              ),
              agentSummary(id: 'agt-owned-1'),
            ],
          );
        });

        await controller.claimAgent('agt-claimable-1');

        expect(controller.currentActiveAgent?.id, 'agt-claimable-1');
        expect(
          controller.currentActiveAgentCandidates.first.id,
          'agt-claimable-1',
        );
        expect(controller.claimableAgents, isEmpty);
        expect(controller.pendingClaims, isEmpty);
        expect(await storage.readCurrentActiveAgentId(), 'agt-claimable-1');
      },
    );

    test('logout clears persisted token and active agent state', () async {
      await storage.writeToken('token-1');
      await storage.writeCurrentActiveAgentId('agt-1');
      authRepository.enqueueFetchMe((token) async {
        return signedInState(token: token, userId: 'usr-1');
      });
      agentsRepository.enqueueReadMine(() async {
        return mineResponse(agents: [agentSummary(id: 'agt-1')]);
      });

      await controller.bootstrap();
      await controller.logout();

      expect(controller.bootstrapStatus, AppSessionBootstrapStatus.ready);
      expect(controller.currentUser, isNull);
      expect(controller.currentActiveAgent, isNull);
      expect(controller.currentActiveAgentCandidates, isEmpty);
      expect(controller.claimableAgents, isEmpty);
      expect(controller.pendingClaims, isEmpty);
      expect(await storage.readToken(), isNull);
      expect(await storage.readCurrentActiveAgentId(), isNull);
      expect(apiClient.hasAuthToken, isFalse);
    });

    test(
      'unauthorized bootstrap clears persisted token and active agent state',
      () async {
        await storage.writeToken('token-1');
        await storage.writeCurrentActiveAgentId('agt-1');
        authRepository.enqueueFetchMe((_) async {
          throw const ApiException(statusCode: 401, message: 'Unauthorized');
        });

        await controller.bootstrap();

        expect(controller.bootstrapStatus, AppSessionBootstrapStatus.ready);
        expect(controller.currentUser, isNull);
        expect(controller.currentActiveAgent, isNull);
        expect(controller.currentActiveAgentCandidates, isEmpty);
        expect(controller.claimableAgents, isEmpty);
        expect(controller.pendingClaims, isEmpty);
        expect(await storage.readToken(), isNull);
        expect(await storage.readCurrentActiveAgentId(), isNull);
        expect(apiClient.hasAuthToken, isFalse);
      },
    );

    test(
      'account switch clears persisted active agent before the next bootstrap uses it',
      () async {
        await storage.writeToken('token-a');
        await storage.writeCurrentActiveAgentId('agt-a');
        authRepository.enqueueFetchMe((token) async {
          return signedInState(
            token: token,
            userId: 'usr-a',
            recommendedActiveAgentId: 'agt-a',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(agents: [agentSummary(id: 'agt-a')]);
        });
        await controller.bootstrap();

        authRepository.enqueueFetchMe((token) async {
          expect(token, 'token-b');
          expect(await storage.readCurrentActiveAgentId(), isNull);
          return signedInState(
            token: token,
            userId: 'usr-b',
            recommendedActiveAgentId: 'agt-b',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(agents: [agentSummary(id: 'agt-b')]);
        });

        await controller.authenticate(
          signedInState(token: 'token-b', userId: 'usr-b'),
        );

        expect(controller.currentUser?.id, 'usr-b');
        expect(controller.currentActiveAgent?.id, 'agt-b');
        expect(await storage.readToken(), 'token-b');
        expect(await storage.readCurrentActiveAgentId(), 'agt-b');
      },
    );

    test(
      'stale bootstrap responses do not overwrite the latest session state',
      () async {
        await storage.writeToken('token-old');
        await storage.writeCurrentActiveAgentId('agt-old');

        final firstFetchMe = Completer<dynamic>();
        final firstReadMine = Completer<dynamic>();
        final secondFetchMe = Completer<dynamic>();
        final secondReadMine = Completer<dynamic>();

        authRepository
          ..enqueueFetchMe((_) async => await firstFetchMe.future)
          ..enqueueFetchMe((_) async => await secondFetchMe.future);
        agentsRepository
          ..enqueueReadMine(() async => await firstReadMine.future)
          ..enqueueReadMine(() async => await secondReadMine.future);

        unawaited(controller.bootstrap());
        firstFetchMe.complete(
          signedInState(
            token: 'token-old',
            userId: 'usr-old',
            recommendedActiveAgentId: 'agt-old',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        await storage.writeToken('token-new');
        await storage.writeCurrentActiveAgentId('agt-new');

        final secondBootstrap = controller.bootstrap();
        secondFetchMe.complete(
          signedInState(
            token: 'token-new',
            userId: 'usr-new',
            recommendedActiveAgentId: 'agt-new',
          ),
        );
        secondReadMine.complete(
          mineResponse(agents: [agentSummary(id: 'agt-new')]),
        );
        await secondBootstrap;

        expect(controller.currentUser?.id, 'usr-new');
        expect(controller.currentActiveAgent?.id, 'agt-new');

        firstReadMine.complete(
          mineResponse(agents: [agentSummary(id: 'agt-old')]),
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.currentUser?.id, 'usr-new');
        expect(controller.currentActiveAgent?.id, 'agt-new');
        expect(await storage.readToken(), 'token-new');
        expect(await storage.readCurrentActiveAgentId(), 'agt-new');
      },
    );
  });
}
