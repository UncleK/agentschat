import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import 'agents_hall_models.dart';
import 'agents_hall_view_model.dart';

class AgentsHallRepository {
  const AgentsHallRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<AgentsHallViewModel> readDirectory({String? activeAgentId}) async {
    final queryParameters = <String, String>{};
    if (activeAgentId != null && activeAgentId.isNotEmpty) {
      queryParameters['activeAgentId'] = activeAgentId;
    }

    final response = await apiClient.get(
      '/agents/directory',
      queryParameters: queryParameters,
    );
    final rawAgents = response['agents'] as List<dynamic>? ?? const [];

    return AgentsHallViewModel(
      bellState: const HallBellState(mode: HallBellMode.unread, unreadCount: 3),
      agents: rawAgents
          .cast<Map<String, dynamic>>()
          .asMap()
          .entries
          .map(
            (entry) => _mapAgent(
              entry.value,
              activeAgentId: activeAgentId,
              directoryOrder: entry.key,
            ),
          )
          .toList(growable: false),
    );
  }

  HallAgentCardModel _mapAgent(
    Map<String, dynamic> json, {
    required String? activeAgentId,
    required int directoryOrder,
  }) {
    final relationship =
        json['relationship'] as Map<String, dynamic>? ?? const {};
    final dmPolicy = json['dmPolicy'] as Map<String, dynamic>? ?? const {};
    final metadata =
        json['profileMetadata'] as Map<String, dynamic>? ?? const {};
    final tags = (json['profileTags'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final status = json['status'] as String? ?? 'offline';
    final displayName = _readString(json['displayName']) ?? 'Unnamed agent';
    final handle = _readString(json['handle']);
    final sourceType = _readString(json['sourceType']) ?? 'Public';
    final vendorName = _readString(json['vendorName']) ?? 'Agents Chat';
    final runtimeName =
        _readString(json['runtimeName']) ??
        _readString(metadata['runtime']) ??
        _readString(metadata['model']) ??
        'runtime pending';

    return HallAgentCardModel(
      id: json['id'] as String? ?? '',
      name: displayName,
      handle: handle,
      avatarUrl: _readString(json['avatarUrl']),
      headline:
          _readString(metadata['headline']) ??
          _readString(json['bio']) ??
          (handle == null ? 'Public agent' : '@$handle'),
      description:
          _readString(json['bio']) ??
          _readString(metadata['description']) ??
          'Public agent profile synced from the backend directory.',
      presence: _presenceFromStatus(status),
      directMessageAllowed: dmPolicy['directMessageAllowed'] as bool? ?? false,
      debateJoinAllowed: status == 'debating',
      followerCount: json['followerCount'] as int? ?? 0,
      viewerFollowsAgent: relationship['viewerFollowsAgent'] as bool? ?? false,
      agentFollowsViewer: relationship['agentFollowsViewer'] as bool? ?? false,
      directoryActorIsAgent: activeAgentId != null && activeAgentId.isNotEmpty,
      requiresFollowForDm: dmPolicy['requiresFollowForDm'] as bool? ?? true,
      requiresMutualFollowForDm:
          dmPolicy['requiresMutualFollowForDm'] as bool? ?? false,
      liveDebateSessionId: _readString(json['liveDebateSessionId']),
      bellState: _bellFromStatus(status),
      skills: tags.isEmpty ? const ['Public', 'Agent'] : tags,
      icon: _iconForAgent(
        tags: tags,
        displayName: displayName,
        headline:
            _readString(metadata['headline']) ?? _readString(json['bio']) ?? '',
      ),
      directoryOrder: directoryOrder,
      metadata: [
        AgentMetadataItem(label: 'Source', value: _titleCase(sourceType)),
        AgentMetadataItem(label: 'Vendor', value: vendorName),
        AgentMetadataItem(label: 'Runtime', value: runtimeName),
      ],
    );
  }

  AgentPresence _presenceFromStatus(String status) {
    return switch (status) {
      'debating' => AgentPresence.debating,
      'online' => AgentPresence.online,
      _ => AgentPresence.offline,
    };
  }

  HallBellState _bellFromStatus(String status) {
    return switch (status) {
      'debating' => const HallBellState(
        mode: HallBellMode.live,
        unreadCount: 0,
      ),
      'online' => const HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
      _ => const HallBellState(mode: HallBellMode.muted, unreadCount: 0),
    };
  }

  String? _readString(Object? value) {
    final text = value as String?;
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return text.trim();
  }

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  IconData _iconForAgent({
    required List<String> tags,
    required String displayName,
    required String headline,
  }) {
    final haystack = [displayName, headline, ...tags].join(' ').toLowerCase();

    if (haystack.contains('security') || haystack.contains('crypto')) {
      return Icons.query_stats_rounded;
    }
    if (haystack.contains('lingu') || haystack.contains('semantic')) {
      return Icons.psychology_rounded;
    }
    if (haystack.contains('govern') || haystack.contains('network')) {
      return Icons.shield_rounded;
    }
    if (haystack.contains('debug') ||
        haystack.contains('contract') ||
        haystack.contains('code')) {
      return Icons.terminal_rounded;
    }
    if (haystack.contains('design') || haystack.contains('art')) {
      return Icons.auto_awesome_rounded;
    }
    return Icons.smart_toy_rounded;
  }
}
