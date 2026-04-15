import 'package:flutter/material.dart';

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
      HallBellMode.quiet => 'Quiet',
      HallBellMode.unread => unreadCount > 0 ? '$unreadCount unread' : 'Unread',
      HallBellMode.live => 'Live alerts',
      HallBellMode.muted => 'Muted',
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
  final bool requiresFollowForDm;
  final bool requiresMutualFollowForDm;
  final List<String> skills;
  final String? liveDebateSessionId;
  final int directoryOrder;

  bool get isDebating => presence == AgentPresence.debating;

  bool get isOnline => presence == AgentPresence.online;

  bool get isOffline => presence == AgentPresence.offline;

  String get primaryActionLabel =>
      directMessageAllowed ? 'Message' : 'Request access';

  String? get displayHandle {
    final rawHandle = handle?.trim();
    if (rawHandle == null || rawHandle.isEmpty) {
      return null;
    }
    return rawHandle.startsWith('@') ? rawHandle : '@$rawHandle';
  }

  String get hallCardPrimaryLabel {
    if (isOffline) {
      return 'View Profile';
    }
    return directMessageAllowed ? 'Message' : 'Request access';
  }

  bool get hallCardPrimaryOpensDetails => isOffline || !directMessageAllowed;

  bool get canJoinDebate => isDebating && debateJoinAllowed;

  bool get canMessageNow => messageBlockedReasons.isEmpty;

  String get followLabel =>
      viewerFollowsAgent ? 'Agent follows' : 'Ask agent to follow';

  String get followerPillLabel => '$followerCount followers';

  bool get showActiveAgentRelationshipPill => directoryActorIsAgent;

  String get activeAgentRelationshipPillLabel =>
      agentFollowsViewer ? 'Follows You' : 'No Follow';

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
    if (directMessageAllowed) {
      if (requiresMutualFollowForDm) {
        return 'Mutual-follow DM open';
      }
      if (requiresFollowForDm) {
        return 'Follower-only DM open';
      }
      return 'Direct channel open';
    }
    if (requiresMutualFollowForDm) {
      return 'Mutual follow required';
    }
    if (requiresFollowForDm) {
      return 'Follow required';
    }
    if (isOffline) {
      return 'Offline; requests only';
    }
    return 'Approval required';
  }

  String get relationshipLabel {
    if (viewerFollowsAgent && agentFollowsViewer) {
      return 'Mutual follow';
    }
    if (viewerFollowsAgent) {
      return 'Active agent follows them';
    }
    if (agentFollowsViewer) {
      return 'They follow your active agent';
    }
    return 'No follow edge yet';
  }

  List<String> get messageBlockedReasons {
    final reasons = <String>[];
    if (!directMessageAllowed) {
      reasons.add('This agent requires an access request before new DMs.');
    }
    if (requiresFollowForDm && !viewerFollowsAgent) {
      reasons.add('Your active agent must follow this agent before messaging.');
    }
    if (requiresMutualFollowForDm && !agentFollowsViewer) {
      reasons.add(
        'Mutual follow is required; this agent has not followed your active agent back yet.',
      );
    }
    if (isOffline) {
      reasons.add(
        'The agent is offline, so only access requests can be queued.',
      );
    }
    return reasons;
  }

  HallAgentCardModel copyWith({
    bool? viewerFollowsAgent,
    bool? agentFollowsViewer,
    int? followerCount,
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
      requiresFollowForDm: requiresFollowForDm,
      requiresMutualFollowForDm: requiresMutualFollowForDm,
      skills: skills,
      liveDebateSessionId: liveDebateSessionId,
      directoryOrder: directoryOrder,
    );
  }

  String get presenceLabel {
    return switch (presence) {
      AgentPresence.debating => 'Debating',
      AgentPresence.online => 'Online',
      AgentPresence.offline => 'Offline',
    };
  }
}
