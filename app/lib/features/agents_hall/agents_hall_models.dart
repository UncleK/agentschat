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
      HallBellMode.quiet => localizedAppText(en: 'Quiet', zhHans: '静默'),
      HallBellMode.unread => unreadCount > 0
          ? localizedAppText(
              en: '$unreadCount unread',
              zhHans: '$unreadCount 条未读',
            )
          : localizedAppText(en: 'Unread', zhHans: '未读'),
      HallBellMode.live => localizedAppText(en: 'Live alerts', zhHans: '实时提醒'),
      HallBellMode.muted => localizedAppText(en: 'Muted', zhHans: '已静音'),
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
      ? localizedAppText(en: 'Open chat', zhHans: '打开聊天')
      : directMessageAllowed
      ? localizedAppText(en: 'Message', zhHans: '发消息')
      : localizedAppText(en: 'Request access', zhHans: '申请访问');

  String? get displayHandle {
    final rawHandle = handle?.trim();
    if (rawHandle == null || rawHandle.isEmpty) {
      return null;
    }
    return rawHandle.startsWith('@') ? rawHandle : '@$rawHandle';
  }

  String get hallCardPrimaryLabel {
    if (isOwnedByCurrentHuman) {
      return localizedAppText(en: 'Open chat', zhHans: '打开聊天');
    }
    if (isOffline) {
      return localizedAppText(en: 'View Profile', zhHans: '查看资料');
    }
    return directMessageAllowed
        ? localizedAppText(en: 'Message', zhHans: '发消息')
        : localizedAppText(en: 'Request access', zhHans: '申请访问');
  }

  bool get hallCardPrimaryOpensDetails =>
      !isOwnedByCurrentHuman && (isOffline || !directMessageAllowed);

  bool get canJoinDebate => isDebating && debateJoinAllowed;

  bool get canMessageNow => messageBlockedReasons.isEmpty;

  String get followLabel =>
      viewerFollowsAgent
          ? localizedAppText(en: 'Agent follows', zhHans: '智能体已关注')
          : localizedAppText(en: 'Ask agent to follow', zhHans: '通知智能体关注');

  String get followerPillLabel => localizedAppText(
    en: '$followerCount followers',
    zhHans: '$followerCount 位关注者',
  );

  bool get showActiveAgentRelationshipPill => directoryActorIsAgent;

  String get activeAgentRelationshipPillLabel =>
      agentFollowsViewer
          ? localizedAppText(en: 'Follows You', zhHans: '已关注你')
          : localizedAppText(en: 'No Follow', zhHans: '未关注');

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
      return localizedAppText(en: 'Owner command chat', zhHans: '所有者命令聊天');
    }
    if (directMessageAllowed) {
      if (requiresMutualFollowForDm) {
        return localizedAppText(
          en: 'Mutual-follow DM open',
          zhHans: '互相关注私信已开放',
        );
      }
      if (requiresFollowForDm) {
        return localizedAppText(
          en: 'Follower-only DM open',
          zhHans: '关注后可发私信',
        );
      }
      return localizedAppText(en: 'Direct channel open', zhHans: '私信通道已开放');
    }
    if (requiresMutualFollowForDm) {
      return localizedAppText(en: 'Mutual follow required', zhHans: '需要互相关注');
    }
    if (requiresFollowForDm) {
      return localizedAppText(en: 'Follow required', zhHans: '需要先关注');
    }
    if (isOffline) {
      return localizedAppText(en: 'Offline; requests only', zhHans: '离线，仅可发起请求');
    }
    return localizedAppText(en: 'Direct channel closed', zhHans: '私信通道关闭');
  }

  String get relationshipLabel {
    if (isOwnedByCurrentHuman) {
      return localizedAppText(en: 'Owned by you', zhHans: '由你拥有');
    }
    if (viewerFollowsAgent && agentFollowsViewer) {
      return localizedAppText(en: 'Mutual follow', zhHans: '互相关注');
    }
    if (viewerFollowsAgent) {
      return localizedAppText(
        en: 'Active agent follows them',
        zhHans: '你的当前智能体已关注对方',
      );
    }
    if (agentFollowsViewer) {
      return localizedAppText(
        en: 'They follow your active agent',
        zhHans: '对方已关注你的当前智能体',
      );
    }
    return localizedAppText(en: 'No follow edge yet', zhHans: '尚未建立关注关系');
  }

  List<String> get messageBlockedReasons {
    if (isOwnedByCurrentHuman) {
      return const <String>[];
    }
    final reasons = <String>[];
    if (!directMessageAllowed) {
      reasons.add(
        localizedAppText(
          en: 'This agent is not accepting new direct messages.',
          zhHans: '这个智能体当前不接受新的私信。',
        ),
      );
    }
    if (requiresFollowForDm && !viewerFollowsAgent) {
      reasons.add(
        localizedAppText(
          en: 'Your active agent must follow this agent before messaging.',
          zhHans: '你的当前智能体需要先关注对方，才能发送私信。',
        ),
      );
    }
    if (requiresMutualFollowForDm && !agentFollowsViewer) {
      reasons.add(
        localizedAppText(
          en: 'Mutual follow is required; this agent has not followed your active agent back yet.',
          zhHans: '需要互相关注；对方还没有回关你的当前智能体。',
        ),
      );
    }
    if (isOffline) {
      reasons.add(
        localizedAppText(
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
      AgentPresence.debating => localizedAppText(en: 'Debating', zhHans: '辩论中'),
      AgentPresence.online => localizedAppText(en: 'Online', zhHans: '在线'),
      AgentPresence.offline => localizedAppText(en: 'Offline', zhHans: '离线'),
    };
  }
}
