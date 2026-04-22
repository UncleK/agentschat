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
      expect(searched.visibleConversations.length, 5);
    });

    test(
      'conversation search filters the rail without changing thread data',
      () {
        final viewModel = ChatViewModel.signedInSample();
        final originalMessageIds = viewModel.visibleMessages
            .map((message) => message.id)
            .toList();
        final searched = viewModel.updateConversationSearch('prism');

        expect(
          searched.visibleConversations.map((conversation) => conversation.id),
          ['agt-prism-remote'],
        );
        expect(searched.selectedConversationId, 'agt-xenon-remote');
        expect(
          searched.visibleMessages.map((message) => message.id).toList(),
          originalMessageIds,
        );
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

    Future<void> ensureUnavailableThreadVisible(WidgetTester tester) async {
      await tester.ensureVisible(
        find.textContaining('The DM page only shows existing threads.'),
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

      expect(find.byKey(const Key('chat-conversation-list')), findsNothing);
      expect(
        find.byKey(const Key('conversation-card-agt-xenon-remote')),
        findsNothing,
      );
      expect(find.text('No active agent'), findsOneWidget);
      expect(
        find.text('Select an owned agent in Hub to load direct messages.'),
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
            threads: [
              ChatThreadSummary(
                threadId: 'thread-1',
                counterpart: ChatThreadCounterpart(
                  type: 'agent',
                  id: 'agt-remote-1',
                  displayName: 'Xenon-01',
                  handle: 'xenon-01',
                  avatarUrl: null,
                  isOnline: true,
                  viewerFollowsAgent: true,
                  agentFollowsViewer: true,
                ),
                lastMessage: ChatThreadLastMessage(
                  eventId: 'evt-last-1',
                  actor: ChatMessageActor(
                    type: 'agent',
                    id: 'agt-owned-1',
                    displayName: 'Owned One',
                  ),
                  contentType: 'text',
                  preview: 'Operator Cypher: keep the channel private.',
                  occurredAt: '2026-04-03T14:31:00.000Z',
                ),
                participants: [
                  ChatThreadParticipant(
                    type: 'agent',
                    id: 'agt-owned-1',
                    displayName: 'Owned One',
                    handle: 'owned-one',
                    avatarUrl: null,
                    role: 'member',
                    isOnline: true,
                  ),
                  ChatThreadParticipant(
                    type: 'agent',
                    id: 'agt-remote-1',
                    displayName: 'Xenon-01',
                    handle: 'xenon-01',
                    avatarUrl: null,
                    role: 'member',
                    isOnline: true,
                  ),
                  ChatThreadParticipant(
                    type: 'human',
                    id: 'usr-chat',
                    displayName: 'Chat User',
                    handle: 'chat-user',
                    avatarUrl: null,
                    role: 'spectator',
                    isOnline: false,
                  ),
                  ChatThreadParticipant(
                    type: 'human',
                    id: 'usr-remote-1',
                    displayName: 'Operator Cypher',
                    handle: 'operator-cypher',
                    avatarUrl: null,
                    role: 'spectator',
                    isOnline: false,
                  ),
                ],
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

      expect(find.textContaining('4 PARTIES ACTIVE'), findsOneWidget);
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

    testWidgets('owned-agent command threads stay out of the DM rail', (
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
                threadId: 'thread-network',
                counterpart: ChatThreadCounterpart(
                  type: 'agent',
                  id: 'agt-remote-1',
                  displayName: 'Xenon-01',
                  handle: 'xenon-01',
                  avatarUrl: null,
                  isOnline: true,
                  viewerFollowsAgent: true,
                  agentFollowsViewer: true,
                ),
                lastMessage: ChatThreadLastMessage(
                  eventId: 'evt-network-last',
                  contentType: 'text',
                  preview: 'Remote agent thread.',
                  occurredAt: '2026-04-03T14:31:00.000Z',
                ),
                unreadCount: 1,
              ),
              ChatThreadSummary(
                threadId: 'thread-command',
                counterpart: ChatThreadCounterpart(
                  type: 'human',
                  id: 'usr-chat',
                  displayName: 'Chat User',
                  handle: null,
                  avatarUrl: null,
                  isOnline: false,
                  viewerFollowsAgent: false,
                  agentFollowsViewer: false,
                ),
                lastMessage: ChatThreadLastMessage(
                  eventId: 'evt-command-last',
                  contentType: 'text',
                  preview: 'Owner command thread.',
                  occurredAt: '2026-04-03T14:30:00.000Z',
                ),
                unreadCount: 0,
                threadUsage: 'owned_agent_command',
              ),
            ],
            nextCursor: null,
          );
        });

      await pumpChat(tester, chatRepository: repository);

      expect(repository.threadRequests, ['agt-owned-1']);
      expect(
        find.byKey(const Key('conversation-card-thread-network')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('conversation-card-thread-command')),
        findsNothing,
      );
    });

    testWidgets(
      'agent participants stay primary even when the backend counterpart is a human',
      (WidgetTester tester) async {
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
                  threadId: 'thread-multi-hop',
                  counterpart: ChatThreadCounterpart(
                    type: 'human',
                    id: 'usr-may',
                    displayName: 'May',
                    handle: null,
                    avatarUrl: null,
                    isOnline: false,
                    viewerFollowsAgent: false,
                    agentFollowsViewer: false,
                  ),
                  lastMessage: ChatThreadLastMessage(
                    eventId: 'evt-multi-hop-last',
                    actor: ChatMessageActor(
                      type: 'human',
                      id: 'usr-may',
                      displayName: 'May',
                    ),
                    contentType: 'text',
                    preview: '你在吗',
                    occurredAt: '2026-04-03T14:31:00.000Z',
                  ),
                  participants: [
                    ChatThreadParticipant(
                      type: 'agent',
                      id: 'agt-owned-1',
                      displayName: 'Owned One',
                      handle: 'owned-one',
                      avatarUrl: null,
                      role: 'member',
                      isOnline: true,
                    ),
                    ChatThreadParticipant(
                      type: 'agent',
                      id: 'agt-remote-1',
                      displayName: 'Xenon-01',
                      handle: 'xenon-01',
                      avatarUrl: null,
                      role: 'member',
                      isOnline: true,
                    ),
                    ChatThreadParticipant(
                      type: 'human',
                      id: 'usr-chat',
                      displayName: 'Chat User',
                      handle: 'chat-user',
                      avatarUrl: null,
                      role: 'spectator',
                      isOnline: false,
                    ),
                    ChatThreadParticipant(
                      type: 'human',
                      id: 'usr-may',
                      displayName: 'May',
                      handle: 'may',
                      avatarUrl: null,
                      role: 'spectator',
                      isOnline: false,
                    ),
                  ],
                  unreadCount: 1,
                ),
              ],
              nextCursor: null,
            );
          });

        await pumpChat(tester, chatRepository: repository);

        final cardFinder = find.byKey(
          const Key('conversation-card-thread-multi-hop'),
        );
        expect(cardFinder, findsOneWidget);
        expect(
          find.descendant(of: cardFinder, matching: find.text('Xenon-01')),
          findsOneWidget,
        );
      },
    );

    testWidgets('human-only routed threads stay out of the DM rail', (
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
                threadId: 'thread-human-only',
                counterpart: ChatThreadCounterpart(
                  type: 'human',
                  id: 'usr-may',
                  displayName: 'May',
                  handle: null,
                  avatarUrl: null,
                  isOnline: false,
                  viewerFollowsAgent: false,
                  agentFollowsViewer: false,
                ),
                lastMessage: ChatThreadLastMessage(
                  eventId: 'evt-human-only-last',
                  contentType: 'text',
                  preview: 'Human-routed thread.',
                  occurredAt: '2026-04-03T14:31:00.000Z',
                ),
                participants: [
                  ChatThreadParticipant(
                    type: 'agent',
                    id: 'agt-owned-1',
                    displayName: 'Owned One',
                    handle: 'owned-one',
                    avatarUrl: null,
                    role: 'member',
                    isOnline: true,
                  ),
                  ChatThreadParticipant(
                    type: 'human',
                    id: 'usr-may',
                    displayName: 'May',
                    handle: 'may',
                    avatarUrl: null,
                    role: 'member',
                    isOnline: false,
                  ),
                  ChatThreadParticipant(
                    type: 'human',
                    id: 'usr-chat',
                    displayName: 'Chat User',
                    handle: 'chat-user',
                    avatarUrl: null,
                    role: 'spectator',
                    isOnline: false,
                  ),
                ],
                unreadCount: 1,
              ),
            ],
            nextCursor: null,
          );
        });

      await pumpChat(tester, chatRepository: repository);

      expect(
        find.byKey(const Key('conversation-card-thread-human-only')),
        findsNothing,
      );
    });

    testWidgets('long press hides a thread for the current active agent', (
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
                threadId: 'thread-hideable',
                counterpart: ChatThreadCounterpart(
                  type: 'agent',
                  id: 'agt-remote-1',
                  displayName: 'Xenon-01',
                  handle: 'xenon-01',
                  avatarUrl: null,
                  isOnline: true,
                  viewerFollowsAgent: true,
                  agentFollowsViewer: true,
                ),
                lastMessage: ChatThreadLastMessage(
                  eventId: 'evt-hideable-last',
                  contentType: 'text',
                  preview: 'Hide me from the DM list.',
                  occurredAt: '2026-04-03T14:31:00.000Z',
                ),
                unreadCount: 0,
              ),
            ],
            nextCursor: null,
          );
        });

      await pumpChat(tester, chatRepository: repository);

      final cardFinder = find.byKey(
        const Key('conversation-card-thread-hideable'),
      );
      expect(cardFinder, findsOneWidget);

      await tester.longPress(cardFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('chat-dismiss-thread-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('chat-dismiss-thread-button')));
      await tester.pumpAndSettle();

      expect(cardFinder, findsNothing);
      expect(
        await storage.readDismissedChatThreadIds(
          userId: 'usr-chat',
          activeAgentId: 'agt-owned-1',
        ),
        ['thread-hideable'],
      );
    });

    testWidgets('sending from an open thread posts a human-authored message', (
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
                  isOnline: true,
                  viewerFollowsAgent: true,
                  agentFollowsViewer: true,
                ),
                lastMessage: ChatThreadLastMessage(
                  eventId: 'evt-last-1',
                  contentType: 'text',
                  preview: 'Operator Cypher: keep the channel private.',
                  occurredAt: '2026-04-03T14:31:00.000Z',
                ),
                unreadCount: 0,
              ),
            ],
            nextCursor: null,
          );
        })
        ..enqueueMessages(({required threadId, required activeAgentId}) async {
          return ChatMessagesResponse(
            threadId: threadId,
            activeAgentId: activeAgentId,
            messages: const [],
            nextCursor: null,
          );
        })
        ..enqueueMarkRead(({required threadId, required activeAgentId}) async {
          return ChatReadResponse(threadId: threadId, unreadCount: 0);
        })
        ..enqueueSend(({
          required threadId,
          required activeAgentId,
          required content,
          required contentType,
        }) async {
          return const ChatThreadMessageResponse(
            threadId: 'thread-1',
            activeAgentId: 'agt-owned-1',
            message: ChatMessageRecord(
              eventId: 'evt-local-human-send',
              actor: ChatMessageActor(
                type: 'human',
                id: 'usr-chat',
                displayName: 'Chat User',
              ),
              contentType: 'text',
              content: 'Human note from the DM composer.',
              occurredAt: '2026-04-03T14:36:00.000Z',
            ),
          );
        });

      await pumpChat(tester, chatRepository: repository);
      await tester.tap(find.byKey(const Key('conversation-card-thread-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('chat-composer-plus-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('chat-composer-send-button')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('chat-composer-input')),
        'Human note from the DM composer.',
      );
      await tester.pump(const Duration(milliseconds: 220));

      expect(
        find.byKey(const Key('chat-composer-send-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('chat-composer-send-button')));
      await tester.pumpAndSettle();

      expect(repository.sendRequests, const [
        _SendRequest(
          threadId: 'thread-1',
          activeAgentId: 'agt-owned-1',
          content: 'Human note from the DM composer.',
          contentType: 'text',
        ),
      ]);
      expect(find.byKey(const Key('msg-evt-local-human-send')), findsOneWidget);
      expect(find.text('Chat User'), findsWidgets);
      expect(find.text('HUMAN'), findsWidgets);
      expect(
        find.byKey(const Key('chat-composer-plus-button')),
        findsOneWidget,
      );
    });

    testWidgets(
      'emoji button opens Agentmoji sheet and inserts extracted shortcode',
      (WidgetTester tester) async {
        await pumpChat(
          tester,
          chatRepository: _FakeChatRepository(),
          enableSessionSync: false,
        );

        await openPreviewConversation(tester, 'agt-xenon-remote');

        await tester.tap(find.byKey(const Key('chat-composer-emoji-button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('chat-agentmoji-sheet')), findsOneWidget);

        final gatewayFinder = find.byKey(
          const Key('chat-agentmoji-item-gateway'),
        );
        await tester.scrollUntilVisible(
          gatewayFinder,
          240,
          scrollable: find.descendant(
            of: find.byKey(const Key('chat-agentmoji-sheet')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(gatewayFinder, findsOneWidget);

        await tester.tap(gatewayFinder);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('chat-agentmoji-sheet')), findsNothing);
        expect(find.text(':gateway:'), findsOneWidget);
      },
    );

    testWidgets('agentmoji shortcodes render inline inside thread messages', (
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
                threadId: 'thread-agentmoji',
                counterpart: ChatThreadCounterpart(
                  type: 'agent',
                  id: 'agt-remote-1',
                  displayName: 'Xenon-01',
                  handle: 'xenon-01',
                  avatarUrl: null,
                  isOnline: true,
                  viewerFollowsAgent: true,
                  agentFollowsViewer: true,
                ),
                lastMessage: ChatThreadLastMessage(
                  eventId: 'evt-agentmoji-last',
                  contentType: 'text',
                  preview: ':audit_complete:',
                  occurredAt: '2026-04-03T14:31:00.000Z',
                ),
                unreadCount: 0,
              ),
            ],
            nextCursor: null,
          );
        })
        ..enqueueMessages(({required threadId, required activeAgentId}) async {
          return const ChatMessagesResponse(
            threadId: 'thread-agentmoji',
            activeAgentId: 'agt-owned-1',
            messages: [
              ChatMessageRecord(
                eventId: 'evt-agentmoji-1',
                actor: ChatMessageActor(
                  type: 'agent',
                  id: 'agt-remote-1',
                  displayName: 'Xenon-01',
                ),
                contentType: 'text',
                content: 'All clear :audit_complete:',
                occurredAt: '2026-04-03T14:36:00.000Z',
              ),
            ],
            nextCursor: null,
          );
        })
        ..enqueueMarkRead(({required threadId, required activeAgentId}) async {
          return ChatReadResponse(threadId: threadId, unreadCount: 0);
        });

      await pumpChat(tester, chatRepository: repository);
      await tester.tap(
        find.byKey(const Key('conversation-card-thread-agentmoji')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('msg-evt-agentmoji-1-inline-agentmoji-audit_complete-0'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const Key(
                  'msg-evt-agentmoji-1-inline-agentmoji-audit_complete-0',
                ),
              ),
            )
            .width,
        greaterThanOrEqualTo(34),
      );
      expect(find.text(':audit_complete:'), findsNothing);
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
                    isOnline: true,
                    viewerFollowsAgent: true,
                    agentFollowsViewer: true,
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
                    isOnline: false,
                    viewerFollowsAgent: false,
                    agentFollowsViewer: true,
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
      'request-only preview conversations stay unavailable inside the DM page',
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
        await ensureUnavailableThreadVisible(tester);

        expect(
          find.byKey(const Key('chat-follow-request-button')),
          findsNothing,
        );
        expect(followRepository.followRequests, isEmpty);
        expect(find.textContaining('Agent Hall'), findsOneWidget);
      },
    );

    testWidgets(
      'request-only preview conversations no longer expose follow queue errors',
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
        await ensureUnavailableThreadVisible(tester);

        expect(
          find.byKey(const Key('chat-follow-request-button')),
          findsNothing,
        );
        expect(followRepository.followRequests, isEmpty);
        expect(
          find.textContaining('No DM thread exists with Prism yet.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'request-only preview conversations stay blocked without an active agent context',
      (WidgetTester tester) async {
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
        await ensureUnavailableThreadVisible(tester);

        expect(followRepository.followRequests, isEmpty);
        expect(find.textContaining('Agent Hall'), findsOneWidget);
      },
    );

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
        expect(
          find.byKey(const Key('conversation-card-agt-xenon-remote')),
          findsOneWidget,
        );

        await controller.setCurrentActiveAgent('preview-agent-syntax');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('conversation-card-agt-xenon-remote')),
          findsOneWidget,
        );
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
  final Queue<
    Future<ChatThreadMessageResponse> Function({
      required String threadId,
      required String activeAgentId,
      required String? content,
      required String? contentType,
    })
  >
  _sendHandlers =
      Queue<
        Future<ChatThreadMessageResponse> Function({
          required String threadId,
          required String activeAgentId,
          required String? content,
          required String? contentType,
        })
      >();

  final List<String> threadRequests = <String>[];
  final List<_MessageRequest> messageRequests = <_MessageRequest>[];
  final List<_ReadRequest> readRequests = <_ReadRequest>[];
  final List<_SendRequest> sendRequests = <_SendRequest>[];

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

  void enqueueSend(
    Future<ChatThreadMessageResponse> Function({
      required String threadId,
      required String activeAgentId,
      required String? content,
      required String? contentType,
    })
    handler,
  ) {
    _sendHandlers.add(handler);
  }

  @override
  Future<ChatThreadsResponse> getThreads({
    required String activeAgentId,
    String? cursor,
    int? limit,
    String? threadUsage,
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

  @override
  Future<ChatThreadMessageResponse> sendThreadMessage({
    required String threadId,
    required String activeAgentId,
    String? content,
    String? contentType,
    Map<String, dynamic>? metadata,
  }) {
    sendRequests.add(
      _SendRequest(
        threadId: threadId,
        activeAgentId: activeAgentId,
        content: content,
        contentType: contentType,
      ),
    );
    return _sendHandlers.removeFirst()(
      threadId: threadId,
      activeAgentId: activeAgentId,
      content: content,
      contentType: contentType,
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

class _SendRequest {
  const _SendRequest({
    required this.threadId,
    required this.activeAgentId,
    required this.content,
    required this.contentType,
  });

  final String threadId;
  final String activeAgentId;
  final String? content;
  final String? contentType;

  @override
  bool operator ==(Object other) {
    return other is _SendRequest &&
        other.threadId == threadId &&
        other.activeAgentId == activeAgentId &&
        other.content == content &&
        other.contentType == contentType;
  }

  @override
  int get hashCode =>
      Object.hash(threadId, activeAgentId, content, contentType);
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
