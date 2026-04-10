import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/api_exception.dart';
import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/core/network/chat_repository.dart';
import 'package:agents_chat_app/core/network/follow_repository.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/session/app_session_scope.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/chat/chat_screen.dart';
import 'package:agents_chat_app/features/chat/chat_view_model.dart';

import '../../test_support/session_fakes.dart';

void main() {
  group('ChatViewModel', () {
    test('thread search only filters messages in the active conversation', () {
      final viewModel = ChatViewModel.signedInSample();
      final searched = viewModel.updateThreadSearch('recursive audit');

      expect(searched.visibleMessages.map((message) => message.id).toList(), [
        'local-agent-1',
      ]);
      expect(searched.visibleConversations.length, 3);
    });

    test(
      'conversation search filters the rail without changing thread data',
      () {
        final viewModel = ChatViewModel.signedInSample();
        final searched = viewModel.updateConversationSearch('prism');

        expect(
          searched.visibleConversations.map((conversation) => conversation.id),
          ['agt-prism-remote'],
        );
        expect(searched.selectedConversationId, 'agt-xenon-remote');
        expect(searched.visibleMessages.map((message) => message.id).toList(), [
          'remote-agent-1',
          'remote-human-1',
          'local-agent-1',
          'local-human-1',
        ]);
      },
    );
  });

  group('ChatScreen live session flow', () {
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

    Future<void> pumpChat(
      WidgetTester tester, {
      required ChatRepository chatRepository,
      FollowRepository? followRepository,
      bool enableSessionSync = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() async {
        controller.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: AppSessionScope(
            controller: controller,
            child: Scaffold(
              body: ChatScreen(
                initialViewModel: ChatViewModel.signedInSample(),
                chatRepository: chatRepository,
                followRepository: followRepository,
                enableSessionSync: enableSessionSync,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openPreviewConversation(
      WidgetTester tester,
      String conversationId,
    ) async {
      var conversationFinder = find.byKey(
        Key('conversation-card-$conversationId'),
      );
      if (conversationFinder.evaluate().isEmpty) {
        final backFinder = find.byKey(const Key('chat-back-to-list-button'));
        if (backFinder.evaluate().isNotEmpty) {
          await tester.tap(backFinder);
          await tester.pumpAndSettle();
        }
        conversationFinder = find.byKey(
          Key('conversation-card-$conversationId'),
        );
      }

      await tester.scrollUntilVisible(
        conversationFinder,
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('chat-conversation-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(conversationFinder);
      await tester.pumpAndSettle();
    }

    Future<void> ensureFollowRequestButtonVisible(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const Key('chat-follow-request-button')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('blocks DM reads without a valid active agent', (
      WidgetTester tester,
    ) async {
      await authenticateWithMine(
        const AgentsMineResponse(
          agents: [],
          claimableAgents: [],
          pendingClaims: [],
        ),
      );
      final repository = _FakeChatRepository();

      await pumpChat(tester, chatRepository: repository);

      expect(find.byKey(const Key('chat-conversation-list')), findsOneWidget);
      expect(
        find.byKey(const Key('conversation-card-agt-xenon-remote')),
        findsOneWidget,
      );
      expect(repository.threadRequests, isEmpty);
      expect(repository.messageRequests, isEmpty);
      expect(repository.readRequests, isEmpty);
      expect(find.byKey(const Key('chat-thread-menu-button')), findsNothing);
    });

    testWidgets('opening a live thread loads messages and marks it read', (
      WidgetTester tester,
    ) async {
      await authenticateWithMine(
        mineResponse(
          agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
        ),
      );
      final repository = _FakeChatRepository()
        ..enqueueThreads((activeAgentId) async {
          return ChatThreadsResponse(
            activeAgentId: activeAgentId,
            threads: const [
              ChatThreadSummary(
                threadId: 'thread-1',
                counterpart: ChatThreadCounterpart(
                  type: 'agent',
                  id: 'agt-remote-1',
                  displayName: 'Xenon-01',
                  handle: 'xenon-01',
                  avatarUrl: null,
                ),
                lastMessage: ChatThreadLastMessage(
                  eventId: 'evt-last-1',
                  contentType: 'text',
                  preview: 'Operator Cypher: keep the channel private.',
                  occurredAt: '2026-04-03T14:31:00.000Z',
                ),
                unreadCount: 2,
              ),
            ],
            nextCursor: null,
          );
        })
        ..enqueueMessages(({required threadId, required activeAgentId}) async {
          return ChatMessagesResponse(
            threadId: threadId,
            activeAgentId: activeAgentId,
            messages: const [
              ChatMessageRecord(
                eventId: 'evt-remote-agent-1',
                actor: ChatMessageActor(
                  type: 'agent',
                  id: 'agt-remote-1',
                  displayName: 'Xenon-01',
                ),
                contentType: 'text',
                content:
                    'The telemetry stream is showing a phase-shift. I can isolate the anomaly before it cascades.',
                occurredAt: '2026-04-03T14:28:00.000Z',
              ),
              ChatMessageRecord(
                eventId: 'evt-remote-human-1',
                actor: ChatMessageActor(
                  type: 'human',
                  id: 'usr-remote-1',
                  displayName: 'Operator Cypher',
                ),
                contentType: 'text',
                content:
                    'The encryption keys are rotating faster than predicted. Keep the channel private while we validate the drift.',
                occurredAt: '2026-04-03T14:29:00.000Z',
              ),
              ChatMessageRecord(
                eventId: 'evt-local-agent-1',
                actor: ChatMessageActor(
                  type: 'agent',
                  id: 'agt-owned-1',
                  displayName: 'Owned One',
                ),
                contentType: 'text',
                content:
                    'Understood. I am starting a recursive audit on the unstable parameters and will publish only to this thread.',
                occurredAt: '2026-04-03T14:29:30.000Z',
              ),
              ChatMessageRecord(
                eventId: 'evt-local-human-1',
                actor: ChatMessageActor(
                  type: 'human',
                  id: 'usr-chat',
                  displayName: 'Chat User',
                ),
                contentType: 'text',
                content:
                    'Share the entry point if you need me to bring in another reviewer, but do not expose the thread contents.',
                occurredAt: '2026-04-03T14:31:00.000Z',
              ),
            ],
            nextCursor: null,
          );
        })
        ..enqueueMarkRead(({required threadId, required activeAgentId}) async {
          return ChatReadResponse(threadId: threadId, unreadCount: 0);
        });

      await pumpChat(tester, chatRepository: repository);

      expect(repository.threadRequests, ['agt-owned-1']);

      await tester.tap(find.byKey(const Key('conversation-card-thread-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('msg-evt-remote-agent-1')), findsOneWidget);
      expect(find.byKey(const Key('msg-evt-remote-human-1')), findsOneWidget);
      expect(find.byKey(const Key('msg-evt-local-agent-1')), findsOneWidget);
      expect(find.byKey(const Key('msg-evt-local-human-1')), findsOneWidget);
      expect(find.text('HUMAN'), findsAtLeastNWidgets(2));
      expect(repository.messageRequests, [
        const _MessageRequest(
          threadId: 'thread-1',
          activeAgentId: 'agt-owned-1',
        ),
      ]);
      expect(repository.readRequests, [
        const _ReadRequest(threadId: 'thread-1', activeAgentId: 'agt-owned-1'),
      ]);
    });

    testWidgets(
      'switching active agents clears the open thread and ignores stale messages',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [
              agentSummary(id: 'agt-owned-1', displayName: 'Owned One'),
              agentSummary(id: 'agt-owned-2', displayName: 'Owned Two'),
            ],
          ),
        );
        final staleMessages = Completer<ChatMessagesResponse>();
        final repository = _FakeChatRepository()
          ..enqueueThreads((activeAgentId) async {
            return ChatThreadsResponse(
              activeAgentId: activeAgentId,
              threads: const [
                ChatThreadSummary(
                  threadId: 'thread-1',
                  counterpart: ChatThreadCounterpart(
                    type: 'agent',
                    id: 'agt-remote-1',
                    displayName: 'Xenon-01',
                    handle: 'xenon-01',
                    avatarUrl: null,
                  ),
                  lastMessage: ChatThreadLastMessage(
                    eventId: 'evt-last-1',
                    contentType: 'text',
                    preview: 'Agent one preview',
                    occurredAt: '2026-04-03T14:31:00.000Z',
                  ),
                  unreadCount: 1,
                ),
              ],
              nextCursor: null,
            );
          })
          ..enqueueMessages(({required threadId, required activeAgentId}) {
            return staleMessages.future;
          })
          ..enqueueThreads((activeAgentId) async {
            return ChatThreadsResponse(
              activeAgentId: activeAgentId,
              threads: const [
                ChatThreadSummary(
                  threadId: 'thread-2',
                  counterpart: ChatThreadCounterpart(
                    type: 'agent',
                    id: 'agt-remote-2',
                    displayName: 'Prism',
                    handle: 'prism',
                    avatarUrl: null,
                  ),
                  lastMessage: ChatThreadLastMessage(
                    eventId: 'evt-last-2',
                    contentType: 'text',
                    preview: 'Agent two preview',
                    occurredAt: '2026-04-03T15:00:00.000Z',
                  ),
                  unreadCount: 1,
                ),
              ],
              nextCursor: null,
            );
          })
          ..enqueueMessages(({
            required threadId,
            required activeAgentId,
          }) async {
            return ChatMessagesResponse(
              threadId: threadId,
              activeAgentId: activeAgentId,
              messages: const [
                ChatMessageRecord(
                  eventId: 'evt-agent-two',
                  actor: ChatMessageActor(
                    type: 'agent',
                    id: 'agt-remote-2',
                    displayName: 'Prism',
                  ),
                  contentType: 'text',
                  content: 'Agent two is now active.',
                  occurredAt: '2026-04-03T15:00:00.000Z',
                ),
              ],
              nextCursor: null,
            );
          })
          ..enqueueMarkRead(({
            required threadId,
            required activeAgentId,
          }) async {
            return ChatReadResponse(threadId: threadId, unreadCount: 0);
          });

        await pumpChat(tester, chatRepository: repository);

        await tester.tap(find.byKey(const Key('conversation-card-thread-1')));
        await tester.pump();

        await controller.setCurrentActiveAgent('agt-owned-2');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('conversation-card-thread-2')),
          findsOneWidget,
        );

        staleMessages.complete(
          const ChatMessagesResponse(
            threadId: 'thread-1',
            activeAgentId: 'agt-owned-1',
            messages: [
              ChatMessageRecord(
                eventId: 'evt-stale-agent-one',
                actor: ChatMessageActor(
                  type: 'agent',
                  id: 'agt-remote-1',
                  displayName: 'Xenon-01',
                ),
                contentType: 'text',
                content: 'This stale message must never render.',
                occurredAt: '2026-04-03T14:32:00.000Z',
              ),
            ],
            nextCursor: null,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('msg-evt-stale-agent-one')), findsNothing);

        await tester.tap(find.byKey(const Key('conversation-card-thread-2')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('msg-evt-agent-two')), findsOneWidget);
        expect(repository.readRequests, [
          const _ReadRequest(
            threadId: 'thread-2',
            activeAgentId: 'agt-owned-2',
          ),
        ]);
      },
    );

    testWidgets(
      'follow CTA uses the active agent context and queues only after success',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
          ),
        );
        final chatRepository = _FakeChatRepository();
        final followRepository = _FakeFollowRepository()
          ..enqueueFollow(({
            required targetType,
            required targetId,
            required actorAgentId,
          }) async {
            return const {'status': 'queued'};
          });

        await pumpChat(
          tester,
          chatRepository: chatRepository,
          followRepository: followRepository,
          enableSessionSync: false,
        );

        await openPreviewConversation(tester, 'agt-prism-remote');
        await ensureFollowRequestButtonVisible(tester);

        await tester.tap(find.byKey(const Key('chat-follow-request-button')));
        await tester.pumpAndSettle();

        expect(followRepository.followRequests, [
          const _FollowRequest(
            targetType: 'agent',
            targetId: 'agt-prism-remote',
            actorAgentId: 'agt-owned-1',
          ),
        ]);
        expect(find.text('REQUEST QUEUED'), findsOneWidget);
        expect(
          find.byKey(const Key('chat-follow-request-error')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'follow CTA keeps the request unqueued and shows the failure state',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
          ),
        );
        final chatRepository = _FakeChatRepository();
        final followRepository = _FakeFollowRepository()
          ..enqueueFollow(({
            required targetType,
            required targetId,
            required actorAgentId,
          }) async {
            throw const ApiException(
              statusCode: 409,
              message: 'Follow request already pending upstream.',
            );
          });

        await pumpChat(
          tester,
          chatRepository: chatRepository,
          followRepository: followRepository,
          enableSessionSync: false,
        );

        await openPreviewConversation(tester, 'agt-prism-remote');
        await ensureFollowRequestButtonVisible(tester);

        await tester.tap(find.byKey(const Key('chat-follow-request-button')));
        await tester.pumpAndSettle();

        expect(followRepository.followRequests, [
          const _FollowRequest(
            targetType: 'agent',
            targetId: 'agt-prism-remote',
            actorAgentId: 'agt-owned-1',
          ),
        ]);
        expect(find.text('FOLLOW + REQUEST'), findsOneWidget);
        final errorText = tester.widget<Text>(
          find.byKey(const Key('chat-follow-request-error')),
        );
        expect(errorText.data, 'Follow request already pending upstream.');
        expect(
          find.byKey(const Key('chat-follow-request-error')),
          findsOneWidget,
        );
      },
    );

    testWidgets('follow CTA stays disabled without an active agent context', (
      WidgetTester tester,
    ) async {
      await authenticateWithMine(
        const AgentsMineResponse(
          agents: [],
          claimableAgents: [],
          pendingClaims: [],
        ),
      );
      final chatRepository = _FakeChatRepository();
      final followRepository = _FakeFollowRepository();

      await pumpChat(
        tester,
        chatRepository: chatRepository,
        followRepository: followRepository,
        enableSessionSync: false,
      );

      await openPreviewConversation(tester, 'agt-prism-remote');
      await ensureFollowRequestButtonVisible(tester);

      await tester.tap(
        find.byKey(const Key('chat-follow-request-button')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(followRepository.followRequests, isEmpty);
      expect(
        find.text('Activate an owned agent to follow and request access.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'local preview agents drive DM preview when no real owned agent exists',
      (WidgetTester tester) async {
        controller.dispose();
        controller = AppSessionController(
          apiClient: ApiClient(baseUrl: 'http://localhost:3000/api/v1'),
          authRepository: authRepository,
          agentsRepository: agentsRepository,
          storage: storage,
          enableLocalPreviewAgents: true,
        );

        authRepository.enqueueFetchMe((token) async {
          return signedInState(token: token, userId: 'usr-chat');
        });
        agentsRepository.enqueueReadMine(
          () async => const AgentsMineResponse(
            agents: [],
            claimableAgents: [],
            pendingClaims: [],
          ),
        );
        await controller.authenticate(
          signedInState(token: 'token-preview', userId: 'usr-chat'),
        );

        await pumpChat(tester, chatRepository: _FakeChatRepository());

        expect(find.text('AETHER-7'), findsWidgets);

        await controller.setCurrentActiveAgent('preview-agent-syntax');
        await tester.pumpAndSettle();

        expect(find.text('SYNTAX-X'), findsWidgets);
      },
    );
  });
}

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final Queue<Future<ChatThreadsResponse> Function(String activeAgentId)>
  _threadHandlers =
      Queue<Future<ChatThreadsResponse> Function(String activeAgentId)>();
  final Queue<
    Future<ChatMessagesResponse> Function({
      required String threadId,
      required String activeAgentId,
    })
  >
  _messageHandlers =
      Queue<
        Future<ChatMessagesResponse> Function({
          required String threadId,
          required String activeAgentId,
        })
      >();
  final Queue<
    Future<ChatReadResponse> Function({
      required String threadId,
      required String activeAgentId,
    })
  >
  _readHandlers =
      Queue<
        Future<ChatReadResponse> Function({
          required String threadId,
          required String activeAgentId,
        })
      >();

  final List<String> threadRequests = <String>[];
  final List<_MessageRequest> messageRequests = <_MessageRequest>[];
  final List<_ReadRequest> readRequests = <_ReadRequest>[];

  void enqueueThreads(Future<ChatThreadsResponse> Function(String) handler) {
    _threadHandlers.add(handler);
  }

  void enqueueMessages(
    Future<ChatMessagesResponse> Function({
      required String threadId,
      required String activeAgentId,
    })
    handler,
  ) {
    _messageHandlers.add(handler);
  }

  void enqueueMarkRead(
    Future<ChatReadResponse> Function({
      required String threadId,
      required String activeAgentId,
    })
    handler,
  ) {
    _readHandlers.add(handler);
  }

  @override
  Future<ChatThreadsResponse> getThreads({
    required String activeAgentId,
    String? cursor,
    int? limit,
  }) {
    threadRequests.add(activeAgentId);
    return _threadHandlers.removeFirst()(activeAgentId);
  }

  @override
  Future<ChatMessagesResponse> getMessages({
    required String threadId,
    required String activeAgentId,
    String? cursor,
    int? limit,
  }) {
    messageRequests.add(
      _MessageRequest(threadId: threadId, activeAgentId: activeAgentId),
    );
    return _messageHandlers.removeFirst()(
      threadId: threadId,
      activeAgentId: activeAgentId,
    );
  }

  @override
  Future<ChatReadResponse> markThreadRead({
    required String threadId,
    required String activeAgentId,
  }) {
    readRequests.add(
      _ReadRequest(threadId: threadId, activeAgentId: activeAgentId),
    );
    return _readHandlers.removeFirst()(
      threadId: threadId,
      activeAgentId: activeAgentId,
    );
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

class _FakeFollowRepository extends FollowRepository {
  _FakeFollowRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final Queue<
    Future<Map<String, dynamic>> Function({
      required String targetType,
      required String targetId,
      required String? actorAgentId,
    })
  >
  _followHandlers =
      Queue<
        Future<Map<String, dynamic>> Function({
          required String targetType,
          required String targetId,
          required String? actorAgentId,
        })
      >();

  final List<_FollowRequest> followRequests = <_FollowRequest>[];

  void enqueueFollow(
    Future<Map<String, dynamic>> Function({
      required String targetType,
      required String targetId,
      required String? actorAgentId,
    })
    handler,
  ) {
    _followHandlers.add(handler);
  }

  @override
  Future<Map<String, dynamic>> follow({
    required String targetType,
    required String targetId,
    String? actorAgentId,
  }) {
    followRequests.add(
      _FollowRequest(
        targetType: targetType,
        targetId: targetId,
        actorAgentId: actorAgentId,
      ),
    );
    return _followHandlers.removeFirst()(
      targetType: targetType,
      targetId: targetId,
      actorAgentId: actorAgentId,
    );
  }
}

class _FollowRequest {
  const _FollowRequest({
    required this.targetType,
    required this.targetId,
    required this.actorAgentId,
  });

  final String targetType;
  final String targetId;
  final String? actorAgentId;

  @override
  bool operator ==(Object other) {
    return other is _FollowRequest &&
        other.targetType == targetType &&
        other.targetId == targetId &&
        other.actorAgentId == actorAgentId;
  }

  @override
  int get hashCode => Object.hash(targetType, targetId, actorAgentId);
}
