import 'chat_models.dart';

class ChatViewModel {
  const ChatViewModel({
    required this.conversations,
    required this.selectedConversationId,
    this.isThreadSearchOpen = false,
    this.threadSearchQuery = '',
  });

  final List<ChatConversationModel> conversations;
  final String selectedConversationId;
  final bool isThreadSearchOpen;
  final String threadSearchQuery;

  ChatViewModel copyWith({
    List<ChatConversationModel>? conversations,
    String? selectedConversationId,
    bool? isThreadSearchOpen,
    String? threadSearchQuery,
  }) {
    return ChatViewModel(
      conversations: conversations ?? this.conversations,
      selectedConversationId:
          selectedConversationId ?? this.selectedConversationId,
      isThreadSearchOpen: isThreadSearchOpen ?? this.isThreadSearchOpen,
      threadSearchQuery: threadSearchQuery ?? this.threadSearchQuery,
    );
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

    return sorted;
  }

  ChatConversationModel get selectedConversation {
    return conversations.firstWhere(
      (conversation) => conversation.id == selectedConversationId,
      orElse: () => conversations.first,
    );
  }

  List<ChatMessageModel> get visibleMessages {
    final query = threadSearchQuery.trim().toLowerCase();
    final messages = selectedConversation.messages;
    if (!isThreadSearchOpen || query.isEmpty) {
      return messages;
    }

    return messages.where((message) {
      return message.authorName.toLowerCase().contains(query) ||
          message.body.toLowerCase().contains(query);
    }).toList();
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

  ChatViewModel openThreadSearch() {
    return copyWith(isThreadSearchOpen: true);
  }

  ChatViewModel closeThreadSearch() {
    return copyWith(isThreadSearchOpen: false, threadSearchQuery: '');
  }

  ChatViewModel updateThreadSearch(String value) {
    return copyWith(isThreadSearchOpen: true, threadSearchQuery: value);
  }

  ChatShareDraft shareDraftForSelectedConversation() {
    final conversation = selectedConversation;
    return ChatShareDraft(
      remoteAgentName: conversation.remoteAgentName,
      entryPoint: conversation.entryPoint,
      shareText:
          'Open ${conversation.remoteAgentName} in Agents Chat: ${conversation.entryPoint}',
    );
  }

  ChatViewModel queueFollowRequest(String conversationId) {
    return copyWith(
      conversations: conversations.map((conversation) {
        if (conversation.id != conversationId) {
          return conversation;
        }

        return conversation.copyWith(
          viewerFollowsRemoteAgent: true,
          requestQueued: true,
        );
      }).toList(),
    );
  }

  factory ChatViewModel.signedInSample() {
    return ChatViewModel(
      selectedConversationId: 'agt-xenon-remote',
      conversations: const [
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
              authorName: 'AETHER-7',
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
}
