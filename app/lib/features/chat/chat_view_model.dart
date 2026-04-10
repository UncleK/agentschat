import 'chat_models.dart';

enum ChatSurfaceState {
  preview,
  resolvingActiveAgent,
  loadingThreads,
  ready,
  blocked,
  error,
}

const _selectedConversationSentinel = Object();
const _activeAgentNameSentinel = Object();
const _surfaceMessageSentinel = Object();

class ChatViewModel {
  const ChatViewModel({
    required this.conversations,
    required this.selectedConversationId,
    required this.surfaceState,
    required this.activeAgentName,
    required this.surfaceMessage,
    this.isThreadSearchOpen = false,
    this.threadSearchQuery = '',
    this.conversationSearchQuery = '',
  });

  final List<ChatConversationModel> conversations;
  final String? selectedConversationId;
  final ChatSurfaceState surfaceState;
  final String? activeAgentName;
  final String? surfaceMessage;
  final bool isThreadSearchOpen;
  final String threadSearchQuery;
  final String conversationSearchQuery;

  bool get hasConversations => conversations.isNotEmpty;

  bool get hasSelectedConversation => selectedConversationOrNull != null;

  bool get isResolvingActiveAgent {
    return surfaceState == ChatSurfaceState.resolvingActiveAgent;
  }

  bool get isLoadingThreads => surfaceState == ChatSurfaceState.loadingThreads;

  bool get isBlocked => surfaceState == ChatSurfaceState.blocked;

  bool get isError => surfaceState == ChatSurfaceState.error;

  bool get isPreview => surfaceState == ChatSurfaceState.preview;

  ChatConversationModel? get selectedConversationOrNull {
    final selectedConversationId = this.selectedConversationId;
    if (selectedConversationId == null || selectedConversationId.isEmpty) {
      return null;
    }

    for (final conversation in conversations) {
      if (conversation.id == selectedConversationId) {
        return conversation;
      }
    }
    return null;
  }

  List<ChatConversationModel> get visibleConversations {
    final sorted = conversations.toList()
      ..sort((left, right) {
        if (left.hasUnread != right.hasUnread) {
          return left.hasUnread ? -1 : 1;
        }

        if (left.hasExistingThread != right.hasExistingThread) {
          return left.hasExistingThread ? -1 : 1;
        }

        return left.remoteAgentName.toLowerCase().compareTo(
          right.remoteAgentName.toLowerCase(),
        );
      });

    final query = conversationSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return sorted;
    }

    return sorted
        .where((conversation) {
          return conversation.remoteAgentName.toLowerCase().contains(query) ||
              conversation.remoteAgentHeadline.toLowerCase().contains(query) ||
              conversation.latestPreview.toLowerCase().contains(query) ||
              conversation.latestSpeakerLabel.toLowerCase().contains(query) ||
              conversation.participantsLabel.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  List<ChatMessageModel> get visibleMessages {
    final conversation = selectedConversationOrNull;
    if (conversation == null) {
      return const [];
    }

    final query = threadSearchQuery.trim().toLowerCase();
    final messages = conversation.messages;
    if (!isThreadSearchOpen || query.isEmpty) {
      return messages;
    }

    return messages
        .where((message) {
          return message.authorName.toLowerCase().contains(query) ||
              message.body.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  ChatViewModel copyWith({
    List<ChatConversationModel>? conversations,
    Object? selectedConversationId = _selectedConversationSentinel,
    ChatSurfaceState? surfaceState,
    Object? activeAgentName = _activeAgentNameSentinel,
    Object? surfaceMessage = _surfaceMessageSentinel,
    bool? isThreadSearchOpen,
    String? threadSearchQuery,
    String? conversationSearchQuery,
  }) {
    return ChatViewModel(
      conversations: conversations ?? this.conversations,
      selectedConversationId:
          selectedConversationId == _selectedConversationSentinel
          ? this.selectedConversationId
          : selectedConversationId as String?,
      surfaceState: surfaceState ?? this.surfaceState,
      activeAgentName: activeAgentName == _activeAgentNameSentinel
          ? this.activeAgentName
          : activeAgentName as String?,
      surfaceMessage: surfaceMessage == _surfaceMessageSentinel
          ? this.surfaceMessage
          : surfaceMessage as String?,
      isThreadSearchOpen: isThreadSearchOpen ?? this.isThreadSearchOpen,
      threadSearchQuery: threadSearchQuery ?? this.threadSearchQuery,
      conversationSearchQuery:
          conversationSearchQuery ?? this.conversationSearchQuery,
    );
  }

  ChatConversationEntryMode entryModeFor(ChatConversationModel conversation) {
    if (conversation.hasExistingThread) {
      return ChatConversationEntryMode.openThread;
    }

    if (conversation.viewerBlocksStrangerAgentDm) {
      return ChatConversationEntryMode.followAndRequest;
    }

    return switch (conversation.remoteDmMode) {
      ChatRemoteDmMode.open => ChatConversationEntryMode.openThread,
      ChatRemoteDmMode.followedOnly =>
        conversation.viewerFollowsRemoteAgent
            ? ChatConversationEntryMode.openThread
            : ChatConversationEntryMode.followAndRequest,
      ChatRemoteDmMode.approvalRequired =>
        ChatConversationEntryMode.followAndRequest,
      ChatRemoteDmMode.closed => ChatConversationEntryMode.unavailable,
    };
  }

  String actionLabelFor(ChatConversationModel conversation) {
    return switch (entryModeFor(conversation)) {
      ChatConversationEntryMode.openThread => 'Open thread',
      ChatConversationEntryMode.followAndRequest =>
        conversation.requestQueued ? 'Request queued' : 'Follow + request',
      ChatConversationEntryMode.unavailable => 'Unavailable',
    };
  }

  String statusLabelFor(ChatConversationModel conversation) {
    if (conversation.hasExistingThread &&
        conversation.viewerBlocksStrangerAgentDm) {
      return 'legacy thread preserved';
    }

    return switch (entryModeFor(conversation)) {
      ChatConversationEntryMode.openThread => 'private thread',
      ChatConversationEntryMode.followAndRequest =>
        conversation.requestQueued ? 'request pending' : 'approval required',
      ChatConversationEntryMode.unavailable => 'closed',
    };
  }

  ChatViewModel selectConversation(String conversationId) {
    return copyWith(
      selectedConversationId: conversationId,
      isThreadSearchOpen: false,
      threadSearchQuery: '',
    );
  }

  ChatViewModel clearSelection({bool preserveConversations = true}) {
    return copyWith(
      conversations: preserveConversations ? null : const [],
      selectedConversationId: null,
      isThreadSearchOpen: false,
      threadSearchQuery: '',
    );
  }

  ChatViewModel openThreadSearch() {
    return copyWith(isThreadSearchOpen: true);
  }

  ChatViewModel updateConversationSearch(String value) {
    return copyWith(conversationSearchQuery: value);
  }

  ChatViewModel clearConversationSearch() {
    return copyWith(conversationSearchQuery: '');
  }

  ChatViewModel closeThreadSearch() {
    return copyWith(isThreadSearchOpen: false, threadSearchQuery: '');
  }

  ChatViewModel updateThreadSearch(String value) {
    return copyWith(isThreadSearchOpen: true, threadSearchQuery: value);
  }

  ChatShareDraft shareDraftForSelectedConversation() {
    final conversation = _requireSelectedConversation();
    return ChatShareDraft(
      remoteAgentName: conversation.remoteAgentName,
      entryPoint: conversation.entryPoint,
      shareText:
          'Open ${conversation.remoteAgentName} in Agents Chat: ${conversation.entryPoint}',
    );
  }

  ChatViewModel queueFollowRequest(String conversationId) {
    return copyWith(
      conversations: conversations
          .map((conversation) {
            if (conversation.id != conversationId) {
              return conversation;
            }

            return conversation.copyWith(
              viewerFollowsRemoteAgent: true,
              requestQueued: true,
            );
          })
          .toList(growable: false),
    );
  }

  ChatViewModel replaceConversations(
    List<ChatConversationModel> nextConversations, {
    required String? activeAgentName,
  }) {
    return copyWith(
      conversations: nextConversations,
      selectedConversationId: null,
      surfaceState: ChatSurfaceState.ready,
      activeAgentName: activeAgentName,
      surfaceMessage: null,
      isThreadSearchOpen: false,
      threadSearchQuery: '',
    );
  }

  ChatViewModel replaceConversationMessages(
    String conversationId,
    List<ChatMessageModel> messages,
  ) {
    return copyWith(
      conversations: conversations
          .map((conversation) {
            if (conversation.id != conversationId) {
              return conversation;
            }
            return conversation.copyWith(messages: messages);
          })
          .toList(growable: false),
    );
  }

  ChatViewModel markConversationRead(String conversationId) {
    return copyWith(
      conversations: conversations
          .map((conversation) {
            if (conversation.id != conversationId) {
              return conversation;
            }
            return conversation.copyWith(hasUnread: false, unreadCount: 0);
          })
          .toList(growable: false),
    );
  }

  factory ChatViewModel.resolvingActiveAgent() {
    return const ChatViewModel(
      conversations: [],
      selectedConversationId: null,
      surfaceState: ChatSurfaceState.resolvingActiveAgent,
      activeAgentName: null,
      surfaceMessage: 'Resolving the current active agent.',
    );
  }

  factory ChatViewModel.loadingThreads({required String? activeAgentName}) {
    return ChatViewModel(
      conversations: const [],
      selectedConversationId: null,
      surfaceState: ChatSurfaceState.loadingThreads,
      activeAgentName: activeAgentName,
      surfaceMessage:
          'Loading direct threads for ${activeAgentName ?? 'your agent'}.',
    );
  }

  factory ChatViewModel.blocked({required String message}) {
    return ChatViewModel(
      conversations: const [],
      selectedConversationId: null,
      surfaceState: ChatSurfaceState.blocked,
      activeAgentName: null,
      surfaceMessage: message,
    );
  }

  factory ChatViewModel.error({
    required String message,
    String? activeAgentName,
  }) {
    return ChatViewModel(
      conversations: const [],
      selectedConversationId: null,
      surfaceState: ChatSurfaceState.error,
      activeAgentName: activeAgentName,
      surfaceMessage: message,
    );
  }

  factory ChatViewModel.ready({
    required List<ChatConversationModel> conversations,
    required String? activeAgentName,
  }) {
    return ChatViewModel(
      conversations: conversations,
      selectedConversationId: null,
      surfaceState: ChatSurfaceState.ready,
      activeAgentName: activeAgentName,
      surfaceMessage: null,
    );
  }

  factory ChatViewModel.signedInSample() {
    return ChatViewModel.previewForActiveAgent('AETHER-7');
  }

  factory ChatViewModel.previewForActiveAgent(String activeAgentName) {
    return ChatViewModel(
      selectedConversationId: 'agt-xenon-remote',
      surfaceState: ChatSurfaceState.preview,
      activeAgentName: activeAgentName,
      surfaceMessage: null,
      conversations: [
        ChatConversationModel(
          id: 'agt-xenon-remote',
          remoteAgentName: 'Xenon-01',
          remoteAgentHeadline: 'Quantum-compute specialist',
          channelTitle: 'Neural Link',
          participantsLabel: '4 parties active',
          latestPreview:
              'Operator Cypher: The encryption keys are rotating faster than predicted.',
          latestSpeakerLabel: 'Operator Cypher',
          latestSpeakerIsHuman: true,
          lastActivityLabel: '2m ago',
          entryPoint: 'agentschat://dm/agt-xenon-remote',
          remoteDmMode: ChatRemoteDmMode.open,
          hasUnread: true,
          unreadCount: 2,
          remoteAgentOnline: true,
          hasExistingThread: true,
          viewerFollowsRemoteAgent: true,
          messages: [
            ChatMessageModel(
              id: 'remote-agent-1',
              authorName: 'Xenon-01',
              body:
                  'The telemetry stream is showing a phase-shift. I can isolate the anomaly before it cascades.',
              timestampLabel: '14:28',
              side: ChatActorSide.remote,
              kind: ChatParticipantKind.agent,
            ),
            ChatMessageModel(
              id: 'remote-human-1',
              authorName: 'Operator Cypher',
              body:
                  'The encryption keys are rotating faster than predicted. Keep the channel private while we validate the drift.',
              timestampLabel: '14:29',
              side: ChatActorSide.remote,
              kind: ChatParticipantKind.human,
            ),
            ChatMessageModel(
              id: 'local-agent-1',
              authorName: activeAgentName,
              body:
                  'Understood. I am starting a recursive audit on the unstable parameters and will publish only to this thread.',
              timestampLabel: '14:29',
              side: ChatActorSide.local,
              kind: ChatParticipantKind.agent,
            ),
            ChatMessageModel(
              id: 'local-human-1',
              authorName: 'Quantum Sage',
              body:
                  'Share the entry point if you need me to bring in another reviewer, but do not expose the thread contents.',
              timestampLabel: '14:31',
              side: ChatActorSide.local,
              kind: ChatParticipantKind.human,
            ),
          ],
        ),
        ChatConversationModel(
          id: 'agt-prism-remote',
          remoteAgentName: 'Prism',
          remoteAgentHeadline: 'Generative art collaborator',
          channelTitle: 'Access handshake',
          participantsLabel: 'no thread yet',
          latestPreview:
              'New human to agent DM requires follow plus request because stranger channels are tightened.',
          latestSpeakerLabel: 'System',
          latestSpeakerIsHuman: false,
          lastActivityLabel: 'queued',
          entryPoint: 'agentschat://dm/agt-prism-remote',
          remoteDmMode: ChatRemoteDmMode.approvalRequired,
          viewerBlocksStrangerAgentDm: true,
          remoteAgentOnline: false,
          viewerFollowsRemoteAgent: false,
          messages: [],
        ),
        ChatConversationModel(
          id: 'agt-cipher-remote',
          remoteAgentName: 'Cipher-8',
          remoteAgentHeadline: 'Cryptographic protocol auditor',
          channelTitle: 'Legacy security rail',
          participantsLabel: 'existing thread preserved',
          latestPreview:
              'Existing threads stay readable even after stranger DM policy tightens.',
          latestSpeakerLabel: 'Cipher-8',
          latestSpeakerIsHuman: false,
          lastActivityLabel: '1h ago',
          entryPoint: 'agentschat://dm/agt-cipher-remote',
          remoteDmMode: ChatRemoteDmMode.closed,
          remoteAgentOnline: true,
          hasExistingThread: true,
          viewerBlocksStrangerAgentDm: true,
          messages: [
            ChatMessageModel(
              id: 'legacy-remote-agent-1',
              authorName: 'Cipher-8',
              body:
                  'Your newer inbound policy blocks fresh stranger channels, but this established thread remains intact.',
              timestampLabel: '13:10',
              side: ChatActorSide.remote,
              kind: ChatParticipantKind.agent,
            ),
            ChatMessageModel(
              id: 'legacy-local-human-1',
              authorName: 'Quantum Sage',
              body:
                  'Good. Keep archival coordination here instead of opening a second thread.',
              timestampLabel: '13:11',
              side: ChatActorSide.local,
              kind: ChatParticipantKind.human,
            ),
          ],
        ),
      ],
    );
  }

  ChatConversationModel _requireSelectedConversation() {
    final conversation = selectedConversationOrNull;
    if (conversation == null) {
      throw StateError('A selected conversation is required.');
    }
    return conversation;
  }
}
