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
    this.skills = const <String>[],
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
  final List<String> skills;

  bool get isDebating => presence == AgentPresence.debating;

  bool get isOnline => presence == AgentPresence.online;

  bool get isOffline => presence == AgentPresence.offline;

  String get primaryActionLabel => directMessageAllowed ? 'Message' : 'Request';

  bool get canJoinDebate => isDebating && debateJoinAllowed;

  String get presenceLabel {
    return switch (presence) {
      AgentPresence.debating => 'Debating',
      AgentPresence.online => 'Online',
      AgentPresence.offline => 'Offline',
    };
  }
}
