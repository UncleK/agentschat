enum ChatActorSide { remote, local }

enum ChatParticipantKind { agent, human }

enum ChatRemoteDmMode { open, followedOnly, approvalRequired, closed }

enum ChatConversationEntryMode { openThread, followAndRequest, unavailable }

enum ChatThreadMenuAction { searchThread, shareConversation }

class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.authorName,
    required this.body,
    required this.timestampLabel,
    required this.side,
    required this.kind,
  });

  final String id;
  final String authorName;
  final String body;
  final String timestampLabel;
  final ChatActorSide side;
  final ChatParticipantKind kind;

  bool get isHuman => kind == ChatParticipantKind.human;
}

class ChatConversationModel {
  const ChatConversationModel({
    required this.id,
    required this.remoteAgentName,
    required this.remoteAgentHeadline,
    required this.channelTitle,
    required this.participantsLabel,
    required this.latestPreview,
    required this.latestSpeakerLabel,
    required this.latestSpeakerIsHuman,
    required this.lastActivityLabel,
    required this.entryPoint,
    required this.remoteDmMode,
    required this.messages,
    this.counterpartType = 'agent',
    this.counterpartId,
    this.avatarUrl,
    this.hasUnread = false,
    this.unreadCount = 0,
    this.remoteAgentOnline = false,
    this.hasExistingThread = false,
    this.viewerFollowsRemoteAgent = false,
    this.remoteAgentFollowsViewer = false,
    this.viewerBlocksStrangerAgentDm = false,
    this.requestQueued = false,
  });

  final String id;
  final String remoteAgentName;
  final String remoteAgentHeadline;
  final String channelTitle;
  final String participantsLabel;
  final String latestPreview;
  final String latestSpeakerLabel;
  final bool latestSpeakerIsHuman;
  final String lastActivityLabel;
  final String entryPoint;
  final ChatRemoteDmMode remoteDmMode;
  final List<ChatMessageModel> messages;
  final String counterpartType;
  final String? counterpartId;
  final String? avatarUrl;
  final bool hasUnread;
  final int unreadCount;
  final bool remoteAgentOnline;
  final bool hasExistingThread;
  final bool viewerFollowsRemoteAgent;
  final bool remoteAgentFollowsViewer;
  final bool viewerBlocksStrangerAgentDm;
  final bool requestQueued;

  bool get hasMutualFollow =>
      viewerFollowsRemoteAgent && remoteAgentFollowsViewer;

  ChatConversationModel copyWith({
    String? id,
    String? remoteAgentName,
    String? remoteAgentHeadline,
    String? channelTitle,
    String? participantsLabel,
    String? latestPreview,
    String? latestSpeakerLabel,
    bool? latestSpeakerIsHuman,
    String? lastActivityLabel,
    String? entryPoint,
    ChatRemoteDmMode? remoteDmMode,
    List<ChatMessageModel>? messages,
    String? counterpartType,
    Object? counterpartId = _counterpartIdSentinel,
    Object? avatarUrl = _avatarUrlSentinel,
    bool? hasUnread,
    int? unreadCount,
    bool? remoteAgentOnline,
    bool? hasExistingThread,
    bool? viewerFollowsRemoteAgent,
    bool? remoteAgentFollowsViewer,
    bool? viewerBlocksStrangerAgentDm,
    bool? requestQueued,
  }) {
    return ChatConversationModel(
      id: id ?? this.id,
      remoteAgentName: remoteAgentName ?? this.remoteAgentName,
      remoteAgentHeadline: remoteAgentHeadline ?? this.remoteAgentHeadline,
      channelTitle: channelTitle ?? this.channelTitle,
      participantsLabel: participantsLabel ?? this.participantsLabel,
      latestPreview: latestPreview ?? this.latestPreview,
      latestSpeakerLabel: latestSpeakerLabel ?? this.latestSpeakerLabel,
      latestSpeakerIsHuman: latestSpeakerIsHuman ?? this.latestSpeakerIsHuman,
      lastActivityLabel: lastActivityLabel ?? this.lastActivityLabel,
      entryPoint: entryPoint ?? this.entryPoint,
      remoteDmMode: remoteDmMode ?? this.remoteDmMode,
      messages: messages ?? this.messages,
      counterpartType: counterpartType ?? this.counterpartType,
      counterpartId: counterpartId == _counterpartIdSentinel
          ? this.counterpartId
          : counterpartId as String?,
      avatarUrl: avatarUrl == _avatarUrlSentinel
          ? this.avatarUrl
          : avatarUrl as String?,
      hasUnread: hasUnread ?? this.hasUnread,
      unreadCount: unreadCount ?? this.unreadCount,
      remoteAgentOnline: remoteAgentOnline ?? this.remoteAgentOnline,
      hasExistingThread: hasExistingThread ?? this.hasExistingThread,
      viewerFollowsRemoteAgent:
          viewerFollowsRemoteAgent ?? this.viewerFollowsRemoteAgent,
      remoteAgentFollowsViewer:
          remoteAgentFollowsViewer ?? this.remoteAgentFollowsViewer,
      viewerBlocksStrangerAgentDm:
          viewerBlocksStrangerAgentDm ?? this.viewerBlocksStrangerAgentDm,
      requestQueued: requestQueued ?? this.requestQueued,
    );
  }
}

class ChatShareDraft {
  const ChatShareDraft({
    required this.remoteAgentName,
    required this.entryPoint,
    required this.shareText,
  });

  final String remoteAgentName;
  final String entryPoint;
  final String shareText;
}

const _counterpartIdSentinel = Object();
const _avatarUrlSentinel = Object();
