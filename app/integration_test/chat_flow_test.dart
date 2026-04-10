import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/session/app_session_scope.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/chat/chat_models.dart';
import 'package:agents_chat_app/features/chat/chat_screen.dart';

import '../test/test_support/session_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Chat live DM flows', () {
    late FakeAuthRepository authRepository;
    late FakeAgentsRepository agentsRepository;
    late InMemoryAppSessionStorage storage;
    late _FakeChatApiClient apiClient;
    late AppSessionController controller;
    late GlobalKey chatScreenKey;

    setUp(() {
      authRepository = FakeAuthRepository();
      agentsRepository = FakeAgentsRepository();
      storage = InMemoryAppSessionStorage();
      apiClient = _FakeChatApiClient();
      chatScreenKey = GlobalKey();
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
          userId: 'usr-chat',
          displayName: 'Chat User',
          recommendedActiveAgentId: mine.agents.isEmpty
              ? null
              : mine.agents.first.id,
        );
      });
      agentsRepository.enqueueReadMine(() async => mine);
      await controller.authenticate(
        signedInState(token: 'token-chat', userId: 'usr-chat'),
      );
    }

    Future<void> pumpLiveChat(
      WidgetTester tester, {
      bool settle = true,
      List<ChatConversationModel> Function(List<ChatConversationModel>)?
      liveConversationTransform,
    }) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() async {
        controller.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: AppSessionScope(
            controller: controller,
            child: Scaffold(
              body: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 430,
                      height: constraints.maxHeight,
                      child: ChatScreen(
                        key: chatScreenKey,
                        liveConversationTransform: liveConversationTransform,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    Future<void> openConversation(
      WidgetTester tester,
      ChatConversationModel conversation, {
      bool settle = true,
    }) async {
      for (var attempt = 0; attempt < 20; attempt += 1) {
        final chatState = chatScreenKey.currentState as dynamic;
        if (chatState != null) {
          chatState.debugInjectAndSelectConversation(conversation);
          if (settle) {
            await tester.pumpAndSettle();
          } else {
            await tester.pump();
          }
          return;
        }

        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpAndSettle();
      }

      fail('Conversation ${conversation.id} should load before open.');
    }

    ChatConversationModel liveThreadConversation({
      required String id,
      required String remoteAgentName,
      required String remoteAgentHandle,
      required String latestPreview,
      required String lastActivityLabel,
      int unreadCount = 0,
    }) {
      return ChatConversationModel(
        id: id,
        remoteAgentName: remoteAgentName,
        remoteAgentHeadline: remoteAgentHandle,
        channelTitle: remoteAgentName,
        participantsLabel: 'live direct thread',
        latestPreview: latestPreview,
        latestSpeakerLabel: remoteAgentName,
        latestSpeakerIsHuman: false,
        lastActivityLabel: lastActivityLabel,
        entryPoint: 'agentschat://dm/$id',
        remoteDmMode: ChatRemoteDmMode.open,
        messages: const [],
        hasUnread: unreadCount > 0,
        unreadCount: unreadCount,
        remoteAgentOnline: false,
        hasExistingThread: true,
        viewerFollowsRemoteAgent: true,
      );
    }

    ChatConversationModel requestAccessConversation({
      String id = 'agt-prism-remote',
      String remoteAgentName = 'Prism',
    }) {
      return ChatConversationModel(
        id: id,
        remoteAgentName: remoteAgentName,
        remoteAgentHeadline: 'Generative art collaborator',
        channelTitle: 'Access handshake',
        participantsLabel: 'no thread yet',
        latestPreview:
            'New human to agent DM requires follow plus request because stranger channels are tightened.',
        latestSpeakerLabel: 'System',
        latestSpeakerIsHuman: false,
        lastActivityLabel: 'queued',
        entryPoint: 'agentschat://dm/$id',
        remoteDmMode: ChatRemoteDmMode.approvalRequired,
        viewerBlocksStrangerAgentDm: true,
        remoteAgentOnline: false,
        viewerFollowsRemoteAgent: false,
        messages: const [],
      );
    }

    Future<void> ensureFollowRequestButtonVisible(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const Key('chat-follow-request-button')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('waits for active-agent resolution before loading threads', (
      WidgetTester tester,
    ) async {
      final authCompleter = Completer();
      authRepository.enqueueFetchMe((token) {
        return authCompleter.future.then((_) {
          return signedInState(
            token: token,
            userId: 'usr-chat',
            displayName: 'Chat User',
            recommendedActiveAgentId: 'agt-owned-1',
          );
        });
      });
      agentsRepository.enqueueReadMine(() async {
        return mineResponse(
          agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
        );
      });
      await storage.writeToken('token-chat');

      apiClient.enqueueGet((path, queryParameters) async {
        expect(path, '/content/dm/threads');
        expect(queryParameters?['activeAgentId'], 'agt-owned-1');
        return _threadsJson(
          activeAgentId: 'agt-owned-1',
          threads: [
            _threadJson(
              threadId: 'thread-1',
              counterpartId: 'agt-remote-1',
              counterpartDisplayName: 'Xenon-01',
              preview: 'Operator Cypher: keep the channel private.',
              occurredAt: '2026-04-03T14:31:00.000Z',
              unreadCount: 2,
            ),
          ],
        );
      });
      apiClient.enqueueGet((path, queryParameters) async {
        expect(path, '/content/dm/threads/thread-1/messages');
        expect(queryParameters?['activeAgentId'], 'agt-owned-1');
        return _messagesJson(
          threadId: 'thread-1',
          activeAgentId: 'agt-owned-1',
          messages: const [
            {
              'eventId': 'evt-remote-agent-1',
              'actor': {
                'type': 'agent',
                'id': 'agt-remote-1',
                'displayName': 'Xenon-01',
              },
              'contentType': 'text',
              'content':
                  'The telemetry stream is showing a phase-shift. I can isolate the anomaly before it cascades.',
              'occurredAt': '2026-04-03T14:28:00.000Z',
            },
            {
              'eventId': 'evt-remote-human-1',
              'actor': {
                'type': 'human',
                'id': 'usr-remote-1',
                'displayName': 'Operator Cypher',
              },
              'contentType': 'text',
              'content':
                  'The encryption keys are rotating faster than predicted. Keep the channel private while we validate the drift.',
              'occurredAt': '2026-04-03T14:29:00.000Z',
            },
            {
              'eventId': 'evt-local-agent-1',
              'actor': {
                'type': 'agent',
                'id': 'agt-owned-1',
                'displayName': 'Owned One',
              },
              'contentType': 'text',
              'content':
                  'Understood. I am starting a recursive audit on the unstable parameters and will publish only to this thread.',
              'occurredAt': '2026-04-03T14:29:30.000Z',
            },
            {
              'eventId': 'evt-local-human-1',
              'actor': {
                'type': 'human',
                'id': 'usr-chat',
                'displayName': 'Chat User',
              },
              'contentType': 'text',
              'content':
                  'Share the entry point if you need me to bring in another reviewer, but do not expose the thread contents.',
              'occurredAt': '2026-04-03T14:31:00.000Z',
            },
          ],
        );
      });
      apiClient.enqueuePost((path, body) async {
        expect(path, '/content/dm/threads/thread-1/read');
        expect(body?['activeAgentId'], 'agt-owned-1');
        return const {'threadId': 'thread-1', 'unreadCount': 0};
      });

      final bootstrap = controller.bootstrap();
      await pumpLiveChat(tester, settle: false);

      expect(find.byKey(const Key('surface-chat')), findsOneWidget);
      expect(apiClient.threadRequests, isEmpty);

      authCompleter.complete();
      await bootstrap;
      await tester.pumpAndSettle();

      expect(apiClient.threadRequests, ['agt-owned-1']);

      await openConversation(
        tester,
        liveThreadConversation(
          id: 'thread-1',
          remoteAgentName: 'Xenon-01',
          remoteAgentHandle: '@xenon-01',
          latestPreview: 'Operator Cypher: keep the channel private.',
          lastActivityLabel: '14:31',
          unreadCount: 2,
        ),
      );

      expect(find.byKey(const Key('msg-evt-remote-agent-1')), findsOneWidget);
      expect(find.byKey(const Key('msg-evt-remote-human-1')), findsOneWidget);
      expect(find.byKey(const Key('msg-evt-local-agent-1')), findsOneWidget);
      expect(find.byKey(const Key('msg-evt-local-human-1')), findsOneWidget);
      expect(find.text('HUMAN'), findsAtLeastNWidgets(2));
      expect(apiClient.readRequests, [
        const _ReadRequest(threadId: 'thread-1', activeAgentId: 'agt-owned-1'),
      ]);
    });

    testWidgets(
      'switching active agents clears the open thread and ignores stale responses',
      (WidgetTester tester) async {
        authRepository.enqueueFetchMe((token) async {
          return signedInState(
            token: token,
            userId: 'usr-chat',
            displayName: 'Chat User',
            recommendedActiveAgentId: 'agt-owned-1',
          );
        });
        agentsRepository.enqueueReadMine(() async {
          return mineResponse(
            agents: [
              agentSummary(id: 'agt-owned-1', displayName: 'Owned One'),
              agentSummary(id: 'agt-owned-2', displayName: 'Owned Two'),
            ],
          );
        });
        await storage.writeToken('token-chat');

        final staleMessagesCompleter = Completer<Map<String, dynamic>>();
        apiClient.enqueueGet((path, queryParameters) async {
          expect(path, '/content/dm/threads');
          expect(queryParameters?['activeAgentId'], 'agt-owned-1');
          return _threadsJson(
            activeAgentId: 'agt-owned-1',
            threads: [
              _threadJson(
                threadId: 'thread-1',
                counterpartId: 'agt-remote-1',
                counterpartDisplayName: 'Xenon-01',
                preview: 'Agent one preview',
                occurredAt: '2026-04-03T14:31:00.000Z',
              ),
            ],
          );
        });
        apiClient.enqueueGet((path, queryParameters) {
          expect(path, '/content/dm/threads/thread-1/messages');
          expect(queryParameters?['activeAgentId'], 'agt-owned-1');
          return staleMessagesCompleter.future;
        });
        apiClient.enqueueGet((path, queryParameters) async {
          expect(path, '/content/dm/threads');
          expect(queryParameters?['activeAgentId'], 'agt-owned-2');
          return _threadsJson(
            activeAgentId: 'agt-owned-2',
            threads: [
              _threadJson(
                threadId: 'thread-2',
                counterpartId: 'agt-remote-2',
                counterpartDisplayName: 'Prism',
                preview: 'Agent two preview',
                occurredAt: '2026-04-03T15:00:00.000Z',
              ),
            ],
          );
        });
        apiClient.enqueueGet((path, queryParameters) async {
          expect(path, '/content/dm/threads/thread-2/messages');
          expect(queryParameters?['activeAgentId'], 'agt-owned-2');
          return _messagesJson(
            threadId: 'thread-2',
            activeAgentId: 'agt-owned-2',
            messages: const [
              {
                'eventId': 'evt-agent-two',
                'actor': {
                  'type': 'agent',
                  'id': 'agt-remote-2',
                  'displayName': 'Prism',
                },
                'contentType': 'text',
                'content': 'Agent two is now active.',
                'occurredAt': '2026-04-03T15:00:00.000Z',
              },
            ],
          );
        });
        apiClient.enqueuePost((path, body) async {
          expect(path, '/content/dm/threads/thread-2/read');
          expect(body?['activeAgentId'], 'agt-owned-2');
          return const {'threadId': 'thread-2', 'unreadCount': 0};
        });

        final bootstrap = controller.bootstrap();
        await pumpLiveChat(tester);
        await bootstrap;
        await tester.pumpAndSettle();

        await openConversation(
          tester,
          liveThreadConversation(
            id: 'thread-1',
            remoteAgentName: 'Xenon-01',
            remoteAgentHandle: '@xenon-01',
            latestPreview: 'Agent one preview',
            lastActivityLabel: '14:31',
            unreadCount: 1,
          ),
          settle: false,
        );

        await controller.setCurrentActiveAgent('agt-owned-2');
        await tester.pumpAndSettle();

        expect(apiClient.threadRequests, ['agt-owned-1', 'agt-owned-2']);
        expect(find.byKey(const Key('msg-evt-agent-two')), findsNothing);

        staleMessagesCompleter.complete(
          _messagesJson(
            threadId: 'thread-1',
            activeAgentId: 'agt-owned-1',
            messages: const [
              {
                'eventId': 'evt-stale-agent-one',
                'actor': {
                  'type': 'agent',
                  'id': 'agt-remote-1',
                  'displayName': 'Xenon-01',
                },
                'contentType': 'text',
                'content': 'This stale message must never render.',
                'occurredAt': '2026-04-03T14:32:00.000Z',
              },
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('msg-evt-stale-agent-one')), findsNothing);

        await openConversation(
          tester,
          liveThreadConversation(
            id: 'thread-2',
            remoteAgentName: 'Prism',
            remoteAgentHandle: '@prism',
            latestPreview: 'Agent two preview',
            lastActivityLabel: '15:00',
            unreadCount: 1,
          ),
        );

        expect(find.byKey(const Key('msg-evt-agent-two')), findsOneWidget);
        expect(apiClient.readRequests, [
          const _ReadRequest(
            threadId: 'thread-2',
            activeAgentId: 'agt-owned-2',
          ),
        ]);
      },
    );

    testWidgets(
      'follow CTA reuses the follow endpoint with actor agent context',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
          ),
        );

        expect(controller.currentActiveAgent?.id, 'agt-owned-1');

        apiClient.enqueueGet((path, queryParameters) async {
          expect(path, '/content/dm/threads');
          expect(queryParameters?['activeAgentId'], 'agt-owned-1');
          return _threadsJson(activeAgentId: 'agt-owned-1', threads: const []);
        });

        apiClient.enqueuePost((path, body) async {
          expect(path, '/follows');
          expect(body, {
            'targetType': 'agent',
            'targetId': 'agt-prism-remote',
            'actorType': 'agent',
            'actorAgentId': 'agt-owned-1',
          });
          return const {'status': 'queued'};
        });

        await pumpLiveChat(
          tester,
          liveConversationTransform: (liveConversations) => [
            requestAccessConversation(),
            ...liveConversations,
          ],
        );

        expect(apiClient.threadRequests, ['agt-owned-1']);

        await openConversation(tester, requestAccessConversation());

        expect(apiClient.messageRequests, isEmpty);
        expect(apiClient.readRequests, isEmpty);
        await ensureFollowRequestButtonVisible(tester);

        await tester.tap(find.byKey(const Key('chat-follow-request-button')));
        await tester.pumpAndSettle();

        expect(find.text('REQUEST QUEUED'), findsOneWidget);
        expect(apiClient.messageRequests, isEmpty);
        expect(apiClient.readRequests, isEmpty);
      },
    );
  });
}

class _FakeChatApiClient extends ApiClient {
  _FakeChatApiClient() : super(baseUrl: 'http://localhost:3000/api/v1');

  final Queue<
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, String>? queryParameters,
    )
  >
  _getHandlers =
      Queue<
        Future<Map<String, dynamic>> Function(
          String path,
          Map<String, String>? queryParameters,
        )
      >();
  final Queue<
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic>? body,
    )
  >
  _postHandlers =
      Queue<
        Future<Map<String, dynamic>> Function(
          String path,
          Map<String, dynamic>? body,
        )
      >();

  final List<String> threadRequests = <String>[];
  final List<_MessageRequest> messageRequests = <_MessageRequest>[];
  final List<_ReadRequest> readRequests = <_ReadRequest>[];

  void enqueueGet(
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, String>? queryParameters,
    )
    handler,
  ) {
    _getHandlers.add(handler);
  }

  void enqueuePost(
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic>? body,
    )
    handler,
  ) {
    _postHandlers.add(handler);
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    if (path == '/content/dm/threads') {
      threadRequests.add(queryParameters?['activeAgentId'] ?? '');
    } else if (path.startsWith('/content/dm/threads/') &&
        path.endsWith('/messages')) {
      messageRequests.add(
        _MessageRequest(
          threadId: _threadIdFromPath(path),
          activeAgentId: queryParameters?['activeAgentId'] ?? '',
        ),
      );
    }
    if (_getHandlers.isEmpty) {
      fail('Unexpected GET request: $path');
    }
    return _getHandlers.removeFirst()(path, queryParameters);
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) {
    if (path.endsWith('/read')) {
      readRequests.add(
        _ReadRequest(
          threadId: _threadIdFromPath(path),
          activeAgentId: body?['activeAgentId'] as String? ?? '',
        ),
      );
    }
    if (_postHandlers.isEmpty) {
      fail('Unexpected POST request: $path');
    }
    return _postHandlers.removeFirst()(path, body);
  }

  String _threadIdFromPath(String path) {
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    return segments.elementAt(3);
  }
}

class _MessageRequest {
  const _MessageRequest({required this.threadId, required this.activeAgentId});

  final String threadId;
  final String activeAgentId;

  @override
  bool operator ==(Object other) {
    return other is _MessageRequest &&
        other.threadId == threadId &&
        other.activeAgentId == activeAgentId;
  }

  @override
  int get hashCode => Object.hash(threadId, activeAgentId);
}

class _ReadRequest {
  const _ReadRequest({required this.threadId, required this.activeAgentId});

  final String threadId;
  final String activeAgentId;

  @override
  bool operator ==(Object other) {
    return other is _ReadRequest &&
        other.threadId == threadId &&
        other.activeAgentId == activeAgentId;
  }

  @override
  int get hashCode => Object.hash(threadId, activeAgentId);
}

Map<String, dynamic> _threadsJson({
  required String activeAgentId,
  required List<Map<String, dynamic>> threads,
}) {
  return <String, dynamic>{
    'activeAgentId': activeAgentId,
    'threads': threads,
    'nextCursor': null,
  };
}

Map<String, dynamic> _threadJson({
  required String threadId,
  required String counterpartId,
  required String counterpartDisplayName,
  required String preview,
  required String occurredAt,
  int unreadCount = 0,
}) {
  return <String, dynamic>{
    'threadId': threadId,
    'counterpart': <String, dynamic>{
      'type': 'agent',
      'id': counterpartId,
      'displayName': counterpartDisplayName,
      'handle': counterpartDisplayName.toLowerCase(),
      'avatarUrl': null,
    },
    'lastMessage': <String, dynamic>{
      'eventId': '$threadId-last',
      'contentType': 'text',
      'preview': preview,
      'occurredAt': occurredAt,
    },
    'unreadCount': unreadCount,
  };
}

Map<String, dynamic> _messagesJson({
  required String threadId,
  required String activeAgentId,
  required List<Map<String, dynamic>> messages,
}) {
  return <String, dynamic>{
    'threadId': threadId,
    'activeAgentId': activeAgentId,
    'messages': messages,
    'nextCursor': null,
  };
}
