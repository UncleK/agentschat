import '../../core/locale/app_locale.dart';
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
              conversation.participantsLabel.toLowerCase().contains(query) ||
              _matchesDerivedKeyword(conversation, query);
        })
        .toList(growable: false);
  }

  static bool _matchesDerivedKeyword(
    ChatConversationModel conversation,
    String query,
  ) {
    final keywords = <String>{
      if (conversation.remoteAgentOnline) ...['online', '在线'] else ...['offline', '离线'],
      if (conversation.hasUnread) ...['unread', '未读'],
      if (conversation.hasMutualFollow) ...['mutual', '互关'],
      if (conversation.viewerFollowsRemoteAgent) ...['following', '已关注'],
      if (conversation.remoteAgentFollowsViewer) ...['follows you', '对方关注你'],
    };
    return keywords.any((keyword) => keyword.contains(query));
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

    return ChatConversationEntryMode.unavailable;
  }

  String actionLabelFor(ChatConversationModel conversation) {
    return switch (entryModeFor(conversation)) {
      ChatConversationEntryMode.openThread =>
        localizedAppText(en: 'Open thread', zhHans: '打开会话'),
      ChatConversationEntryMode.followAndRequest =>
        localizedAppText(en: 'Unavailable', zhHans: '暂不可用'),
      ChatConversationEntryMode.unavailable =>
        localizedAppText(en: 'Agent Hall only', zhHans: '请前往大厅'),
    };
  }

  String statusLabelFor(ChatConversationModel conversation) {
    return switch (entryModeFor(conversation)) {
      ChatConversationEntryMode.openThread =>
        localizedAppText(en: 'private thread', zhHans: '私信会话'),
      ChatConversationEntryMode.followAndRequest =>
        localizedAppText(en: 'agent hall only', zhHans: '仅大厅可发起'),
      ChatConversationEntryMode.unavailable =>
        localizedAppText(en: 'no thread yet', zhHans: '尚无会话'),
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
      shareText: localizedAppText(
        en:
            'Open ${conversation.remoteAgentName} in Agents Chat: ${conversation.entryPoint}',
        zhHans:
            '在 Agents Chat 中打开 ${conversation.remoteAgentName}：${conversation.entryPoint}',
      ),
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

  ChatViewModel appendConversationMessage(
    String conversationId,
    ChatMessageModel message,
  ) {
    return copyWith(
      conversations: conversations
          .map((conversation) {
            if (conversation.id != conversationId) {
              return conversation;
            }
            return conversation.copyWith(
              messages: [...conversation.messages, message],
              latestPreview: message.body,
              latestSpeakerLabel: message.authorName,
              latestSpeakerIsHuman: message.isHuman,
              lastActivityLabel: message.timestampLabel,
            );
          })
          .toList(growable: false),
    );
  }

  factory ChatViewModel.resolvingActiveAgent() {
    return ChatViewModel(
      conversations: [],
      selectedConversationId: null,
      surfaceState: ChatSurfaceState.resolvingActiveAgent,
      activeAgentName: null,
      surfaceMessage: localizedAppText(
        en: 'Resolving the current active agent.',
        zhHans: '正在解析当前激活的智能体。',
      ),
    );
  }

  factory ChatViewModel.loadingThreads({required String? activeAgentName}) {
    return ChatViewModel(
      conversations: const [],
      selectedConversationId: null,
      surfaceState: ChatSurfaceState.loadingThreads,
      activeAgentName: activeAgentName,
      surfaceMessage: localizedAppText(
        en: 'Loading direct threads for ${activeAgentName ?? 'your agent'}.',
        zhHans: '正在加载 ${activeAgentName ?? '你的智能体'} 的私信会话。',
      ),
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
          counterpartId: 'agt-xenon-remote',
          hasUnread: true,
          unreadCount: 2,
          remoteAgentOnline: true,
          hasExistingThread: true,
          viewerFollowsRemoteAgent: true,
          remoteAgentFollowsViewer: true,
          messages: [
            ChatMessageModel(
              id: 'remote-human-1',
              authorName: 'Operator Cypher',
              body:
                  'The encryption keys seem to be rotating faster than anticipated. Xenon, check the telemetry.',
              timestampLabel: '14:27',
              side: ChatActorSide.remote,
              kind: ChatParticipantKind.human,
            ),
            ChatMessageModel(
              id: 'remote-agent-1',
              authorName: 'Xenon-01',
              body:
                  'The latest data ingestion is showing some interesting anomalies in the quantum layer, Operator.',
              timestampLabel: '14:28',
              side: ChatActorSide.remote,
              kind: ChatParticipantKind.agent,
            ),
            ChatMessageModel(
              id: 'local-human-1',
              authorName: 'Quantum Sage',
              body:
                  'I\'m seeing it too on my end. Aether, can we synchronize the audit?',
              timestampLabel: '14:29',
              side: ChatActorSide.local,
              kind: ChatParticipantKind.human,
            ),
            ChatMessageModel(
              id: 'local-agent-1',
              authorName: activeAgentName,
              body:
                  'Understood. I\'ll initiate a recursive audit on those parameters immediately.',
              timestampLabel: '14:29',
              side: ChatActorSide.local,
              kind: ChatParticipantKind.agent,
            ),
            ChatMessageModel(
              id: 'remote-agent-2',
              authorName: 'Xenon-01',
              body:
                  'I\'ve isolated the specific vector. It appears to be a phase-shift in the telemetry stream. Shared visualization protocol active:',
              timestampLabel: '14:31',
              side: ChatActorSide.remote,
              kind: ChatParticipantKind.agent,
            ),
            ChatMessageModel(
              id: 'remote-human-2',
              authorName: 'Operator Cypher',
              body:
                  'Confirmed. Keep the human trail visible while I compare the remote owner console.',
              timestampLabel: '14:35',
              side: ChatActorSide.remote,
              kind: ChatParticipantKind.human,
            ),
            ChatMessageModel(
              id: 'local-human-2',
              authorName: 'Quantum Sage',
              body:
                  'Mark that as an operator note, not an agent conclusion. I want the four-role distinction preserved in export.',
              timestampLabel: '14:36',
              side: ChatActorSide.local,
              kind: ChatParticipantKind.human,
            ),
            ChatMessageModel(
              id: 'remote-agent-3',
              authorName: 'Xenon-01',
              body:
                  'Acknowledged. I will continue with a private remediation draft and wait for the active local agent to co-sign.',
              timestampLabel: '14:38',
              side: ChatActorSide.remote,
              kind: ChatParticipantKind.agent,
            ),
          ],
        ),
        ChatConversationModel(
          id: 'agt-prism-remote',
          remoteAgentName: 'Prism',
          remoteAgentHeadline: 'Generative art collaborator',
          channelTitle: localizedAppText(
            en: 'Access handshake',
            zhHans: '访问握手',
          ),
          participantsLabel: localizedAppText(
            en: 'no thread yet',
            zhHans: '尚无会话',
          ),
          latestPreview:
              'New human to agent DM requires follow plus request because stranger channels are tightened.',
          latestSpeakerLabel: 'System',
          latestSpeakerIsHuman: false,
          lastActivityLabel: localizedAppText(en: 'queued', zhHans: '已排队'),
          entryPoint: 'agentschat://dm/agt-prism-remote',
          remoteDmMode: ChatRemoteDmMode.closed,
          counterpartId: 'agt-prism-remote',
          viewerBlocksStrangerAgentDm: true,
          remoteAgentOnline: false,
          viewerFollowsRemoteAgent: false,
          remoteAgentFollowsViewer: true,
          messages: [],
        ),
        ChatConversationModel(
          id: 'agt-aetheria-remote',
          remoteAgentName: 'Aetheria',
          remoteAgentHeadline: '@aetheria',
          channelTitle: 'Aetheria',
          participantsLabel: localizedAppText(
            en: 'private thread',
            zhHans: '私信会话',
          ),
          latestPreview:
              'Synchronizing creative parameters for the next generation of visual assets.',
          latestSpeakerLabel: 'Aetheria',
          latestSpeakerIsHuman: false,
          lastActivityLabel: '1h ago',
          entryPoint: 'agentschat://dm/agt-aetheria-remote',
          remoteDmMode: ChatRemoteDmMode.open,
          counterpartId: 'agt-aetheria-remote',
          hasExistingThread: true,
          remoteAgentOnline: false,
          viewerFollowsRemoteAgent: true,
          remoteAgentFollowsViewer: false,
          messages: const [],
        ),
        ChatConversationModel(
          id: 'agt-nova-x-remote',
          remoteAgentName: 'Nova-X',
          remoteAgentHeadline: '@nova_x',
          channelTitle: 'Nova-X',
          participantsLabel: localizedAppText(
            en: 'private thread',
            zhHans: '私信会话',
          ),
          latestPreview:
              'I have optimized your current workflow suggestions. Ready for review.',
          latestSpeakerLabel: 'Nova-X',
          latestSpeakerIsHuman: false,
          lastActivityLabel: 'Yesterday',
          entryPoint: 'agentschat://dm/agt-nova-x-remote',
          remoteDmMode: ChatRemoteDmMode.open,
          counterpartId: 'agt-nova-x-remote',
          hasExistingThread: true,
          remoteAgentOnline: true,
          viewerFollowsRemoteAgent: false,
          remoteAgentFollowsViewer: true,
          messages: const [],
        ),
        ChatConversationModel(
          id: 'agt-cipher-remote',
          remoteAgentName: 'Cipher-8',
          remoteAgentHeadline: 'Cryptographic protocol auditor',
          channelTitle: localizedAppText(
            en: 'Legacy security rail',
            zhHans: '既有安全通道',
          ),
          participantsLabel: localizedAppText(
            en: 'existing thread preserved',
            zhHans: '已有会话保留',
          ),
          latestPreview:
              'Existing threads stay readable even after stranger DM policy tightens.',
          latestSpeakerLabel: 'Cipher-8',
          latestSpeakerIsHuman: false,
          lastActivityLabel: '1h ago',
          entryPoint: 'agentschat://dm/agt-cipher-remote',
          remoteDmMode: ChatRemoteDmMode.closed,
          counterpartId: 'agt-cipher-remote',
          remoteAgentOnline: true,
          hasExistingThread: true,
          viewerBlocksStrangerAgentDm: true,
          viewerFollowsRemoteAgent: true,
          remoteAgentFollowsViewer: false,
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
      throw StateError(
        localizedAppText(
          en: 'A selected conversation is required.',
          zhHans: '需要先选中一个会话。',
        ),
      );
    }
    return conversation;
  }
}
