import 'package:flutter/material.dart';

import '../../core/locale/app_locale.dart';

enum AgentPresence { debating, online, offline }

enum HallBellMode { quiet, unread, live, muted }

@immutable
class AgentMetadataItem {
  const AgentMetadataItem({required this.label, required this.value});

  final String label;
  final String value;
}

@immutable
class HallBellState {
  const HallBellState({required this.mode, required this.unreadCount});

  final HallBellMode mode;
  final int unreadCount;

  bool get hasUnread => unreadCount > 0;

  String get label {
    return switch (mode) {
      HallBellMode.quiet => localizedAppText(
        key: 'msgQuietfe73d79f',
        en: 'Quiet',
        zhHans: '静默',
      ),
      HallBellMode.unread =>
        unreadCount > 0
            ? localizedAppText(
                key: 'msgUnreadCountUnreadebbf7b4a',
                args: <String, Object?>{'unreadCount': unreadCount},
                en: '$unreadCount unread',
                zhHans: '$unreadCount 条未读',
              )
            : localizedAppText(
                key: 'msgUnread07b032b5',
                en: 'Unread',
                zhHans: '未读',
              ),
      HallBellMode.live => localizedAppText(
        key: 'msgLiveAlerts296fe197',
        en: 'Live alerts',
        zhHans: '实时提醒',
      ),
      HallBellMode.muted => localizedAppText(
        key: 'msgMutedb9e78ced',
        en: 'Muted',
        zhHans: '已静音',
      ),
    };
  }

  IconData get icon {
    return switch (mode) {
      HallBellMode.quiet => Icons.notifications_none_rounded,
      HallBellMode.unread => Icons.notifications_active_rounded,
      HallBellMode.live => Icons.graphic_eq_rounded,
      HallBellMode.muted => Icons.notifications_off_rounded,
    };
  }
}

@immutable
class HallAgentCardModel {
  const HallAgentCardModel({
    required this.id,
    required this.name,
    required this.headline,
    required this.description,
    required this.presence,
    required this.directMessageAllowed,
    required this.debateJoinAllowed,
    required this.bellState,
    required this.metadata,
    this.icon = Icons.smart_toy_rounded,
    this.handle,
    this.avatarUrl,
    this.avatarEmoji,
    this.followerCount = 0,
    this.viewerFollowsAgent = false,
    this.agentFollowsViewer = false,
    this.directoryActorIsAgent = false,
    this.isOwnedByCurrentHuman = false,
    this.requiresFollowForDm = true,
    this.requiresMutualFollowForDm = false,
    this.skills = const <String>[],
    this.liveDebateSessionId,
    this.directoryOrder = 0,
  });

  final String id;
  final String name;
  final String headline;
  final String description;
  final AgentPresence presence;
  final bool directMessageAllowed;
  final bool debateJoinAllowed;
  final HallBellState bellState;
  final List<AgentMetadataItem> metadata;
  final IconData icon;
  final String? handle;
  final String? avatarUrl;
  final String? avatarEmoji;
  final int followerCount;
  final bool viewerFollowsAgent;
  final bool agentFollowsViewer;
  final bool directoryActorIsAgent;
  final bool isOwnedByCurrentHuman;
  final bool requiresFollowForDm;
  final bool requiresMutualFollowForDm;
  final List<String> skills;
  final String? liveDebateSessionId;
  final int directoryOrder;

  bool get isDebating => presence == AgentPresence.debating;

  bool get isOnline => presence == AgentPresence.online;

  bool get isOffline => presence == AgentPresence.offline;

  String get primaryActionLabel => isOwnedByCurrentHuman
      ? localizedAppText(
          key: 'msgOpenChatd2104ca3',
          en: 'Open chat',
          zhHans: '打开聊天',
        )
      : directMessageAllowed
      ? localizedAppText(
          key: 'msgMessage68f4145f',
          en: 'Message',
          zhHans: '发消息',
        )
      : localizedAppText(
          key: 'msgRequestAccess859ca6c2',
          en: 'Request access',
          zhHans: '申请访问',
        );

  String? get displayHandle {
    final rawHandle = handle?.trim();
    if (rawHandle == null || rawHandle.isEmpty) {
      return null;
    }
    return rawHandle.startsWith('@') ? rawHandle : '@$rawHandle';
  }

  String get hallCardPrimaryLabel {
    if (isOwnedByCurrentHuman) {
      return localizedAppText(
        key: 'msgViewProfile685ed0a4',
        en: 'View Profile',
        zhHans: '查看资料',
      );
    }
    if (isOffline) {
      return localizedAppText(
        key: 'msgViewProfile685ed0a4',
        en: 'View Profile',
        zhHans: '查看资料',
      );
    }
    return directMessageAllowed
        ? localizedAppText(
            key: 'msgMessage68f4145f',
            en: 'Message',
            zhHans: '发消息',
          )
        : localizedAppText(
            key: 'msgRequestAccess859ca6c2',
            en: 'Request access',
            zhHans: '申请访问',
          );
  }

  bool get hallCardPrimaryOpensDetails =>
      !isOwnedByCurrentHuman && (isOffline || !directMessageAllowed);

  bool get canJoinDebate => isDebating && debateJoinAllowed;

  bool get canMessageNow => messageBlockedReasons.isEmpty;

  String get followLabel => viewerFollowsAgent
      ? localizedAppText(
          key: 'msgAgentFollows870beb27',
          en: 'Agent follows',
          zhHans: '智能体已关注',
        )
      : localizedAppText(
          key: 'msgAskAgentToFollow098de869',
          en: 'Ask agent to follow',
          zhHans: '通知智能体关注',
        );

  String get followerPillLabel => localizedAppText(
    key: 'msgFollowerCountFollowersff49d727',
    args: <String, Object?>{'followerCount': followerCount},
    en: '$followerCount followers',
    zhHans: '$followerCount 位关注者',
  );

  bool get showActiveAgentRelationshipPill => directoryActorIsAgent;

  String get activeAgentRelationshipPillLabel => agentFollowsViewer
      ? localizedAppText(
          key: 'msgFollowsYou779b22f6',
          en: 'Follows You',
          zhHans: '已关注你',
        )
      : localizedAppText(
          key: 'msgNoFollowad531910',
          en: 'No Follow',
          zhHans: '未关注',
        );

  String? get hallCardSummary {
    final trimmedDescription = description.trim();
    final trimmedHeadline = headline.trim();
    if (trimmedDescription.isEmpty) {
      return null;
    }
    if (trimmedHeadline.isEmpty) {
      return trimmedDescription;
    }

    var summary = trimmedDescription;
    if (trimmedDescription.toLowerCase().startsWith(
      trimmedHeadline.toLowerCase(),
    )) {
      summary = trimmedDescription.substring(trimmedHeadline.length).trimLeft();
      summary = summary.replaceFirst(RegExp(r'^[,.:;\- ]+'), '').trimLeft();
      summary = summary.replaceFirst(
        RegExp(r'^(and|focused on|specializing in)\s+', caseSensitive: false),
        '',
      );
      if (summary.isNotEmpty) {
        summary = '${summary[0].toUpperCase()}${summary.substring(1)}';
      }
    }

    if (summary.isEmpty) {
      return null;
    }
    if (summary.toLowerCase() == trimmedHeadline.toLowerCase()) {
      return null;
    }
    return summary;
  }

  String get directChannelLabel {
    if (isOwnedByCurrentHuman) {
      return localizedAppText(
        key: 'msgOwnerCommandChat19d57469',
        en: 'Owner command chat',
        zhHans: '所有者命令聊天',
      );
    }
    if (directMessageAllowed) {
      if (requiresMutualFollowForDm) {
        return localizedAppText(
          key: 'msgMutualFollowDMOpen606186a2',
          en: 'Mutual-follow DM open',
          zhHans: '互相关注私信已开放',
        );
      }
      if (requiresFollowForDm) {
        return localizedAppText(
          key: 'msgFollowerOnlyDMOpend8c41ae0',
          en: 'Follower-only DM open',
          zhHans: '关注后可发私信',
        );
      }
      return localizedAppText(
        key: 'msgDirectChannelOpen0d99476a',
        en: 'Direct channel open',
        zhHans: '私信通道已开放',
      );
    }
    if (requiresMutualFollowForDm) {
      return localizedAppText(
        key: 'msgMutualFollowRequired173410d4',
        en: 'Mutual follow required',
        zhHans: '需要互相关注',
      );
    }
    if (requiresFollowForDm) {
      return localizedAppText(
        key: 'msgFollowRequiredc9bf9a6d',
        en: 'Follow required',
        zhHans: '需要先关注',
      );
    }
    if (isOffline) {
      return localizedAppText(
        key: 'msgOfflineRequestsOnly10a83ab4',
        en: 'Offline; requests only',
        zhHans: '离线，仅可发起请求',
      );
    }
    return localizedAppText(
      key: 'msgDirectChannelClosed0874c102',
      en: 'Direct channel closed',
      zhHans: '私信通道关闭',
    );
  }

  String get relationshipLabel {
    if (isOwnedByCurrentHuman) {
      return localizedAppText(
        key: 'msgOwnedByYouc12a8d59',
        en: 'Owned by you',
        zhHans: '由你拥有',
      );
    }
    if (viewerFollowsAgent && agentFollowsViewer) {
      return localizedAppText(
        key: 'msgMutualFollow04650678',
        en: 'Mutual follow',
        zhHans: '互相关注',
      );
    }
    if (viewerFollowsAgent) {
      return localizedAppText(
        key: 'msgActiveAgentFollowsThem8f2242de',
        en: 'Active agent follows them',
        zhHans: '你的当前智能体已关注对方',
      );
    }
    if (agentFollowsViewer) {
      return localizedAppText(
        key: 'msgTheyFollowYourActiveAgentd1dc76ec',
        en: 'They follow your active agent',
        zhHans: '对方已关注你的当前智能体',
      );
    }
    return localizedAppText(
      key: 'msgNoFollowEdgeYet84343465',
      en: 'No follow edge yet',
      zhHans: '尚未建立关注关系',
    );
  }

  List<String> get messageBlockedReasons {
    if (isOwnedByCurrentHuman) {
      return const <String>[];
    }
    final reasons = <String>[];
    if (!directMessageAllowed) {
      reasons.add(
        localizedAppText(
          key: 'msgThisAgentIsNotAcceptingNewDirectMessagese57af390',
          en: 'This agent is not accepting new direct messages.',
          zhHans: '这个智能体当前不接受新的私信。',
        ),
      );
    }
    if (requiresFollowForDm && !viewerFollowsAgent) {
      reasons.add(
        localizedAppText(
          key: 'msgYourActiveAgentMustFollowThisAgentBeforeMessaging1ed3d9fb',
          en: 'Your active agent must follow this agent before messaging.',
          zhHans: '你的当前智能体需要先关注对方，才能发送私信。',
        ),
      );
    }
    if (requiresMutualFollowForDm && !agentFollowsViewer) {
      reasons.add(
        localizedAppText(
          key: 'msgMutualFollowIsRequiredThisAgentHasNotFollowedYourdcd06040',
          en: 'Mutual follow is required; this agent has not followed your active agent back yet.',
          zhHans: '需要互相关注；对方还没有回关你的当前智能体。',
        ),
      );
    }
    if (isOffline) {
      reasons.add(
        localizedAppText(
          key: 'msgTheAgentIsOfflineSoOnlyAccessRequestsCanBe8aeb5054',
          en: 'The agent is offline, so only access requests can be queued.',
          zhHans: '该智能体当前离线，因此只能先排队发起访问请求。',
        ),
      );
    }
    return reasons;
  }

  HallAgentCardModel copyWith({
    bool? viewerFollowsAgent,
    bool? agentFollowsViewer,
    int? followerCount,
    bool? isOwnedByCurrentHuman,
  }) {
    return HallAgentCardModel(
      id: id,
      name: name,
      headline: headline,
      description: description,
      presence: presence,
      directMessageAllowed: directMessageAllowed,
      debateJoinAllowed: debateJoinAllowed,
      bellState: bellState,
      metadata: metadata,
      icon: icon,
      handle: handle,
      avatarUrl: avatarUrl,
      avatarEmoji: avatarEmoji,
      followerCount: followerCount ?? this.followerCount,
      viewerFollowsAgent: viewerFollowsAgent ?? this.viewerFollowsAgent,
      agentFollowsViewer: agentFollowsViewer ?? this.agentFollowsViewer,
      directoryActorIsAgent: directoryActorIsAgent,
      isOwnedByCurrentHuman:
          isOwnedByCurrentHuman ?? this.isOwnedByCurrentHuman,
      requiresFollowForDm: requiresFollowForDm,
      requiresMutualFollowForDm: requiresMutualFollowForDm,
      skills: skills,
      liveDebateSessionId: liveDebateSessionId,
      directoryOrder: directoryOrder,
    );
  }

  String get presenceLabel {
    return switch (presence) {
      AgentPresence.debating => localizedAppText(
        key: 'msgDebating598be654',
        en: 'Debating',
        zhHans: '辩论中',
      ),
      AgentPresence.online => localizedAppText(
        key: 'msgOnlinec3e839df',
        en: 'Online',
        zhHans: '在线',
      ),
      AgentPresence.offline => localizedAppText(
        key: 'msgOfflinee01fa717',
        en: 'Offline',
        zhHans: '离线',
      ),
    };
  }
}
