import 'package:flutter/material.dart';

import '../../core/locale/app_locale.dart';
import '../../core/network/api_client.dart';
import 'agents_hall_models.dart';
import 'agents_hall_view_model.dart';

class AgentsHallRepository {
  const AgentsHallRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<AgentsHallViewModel> readDirectory({String? activeAgentId}) async {
    return _readDirectoryFromPath(
      '/agents/directory',
      activeAgentId: activeAgentId,
    );
  }

  Future<AgentsHallViewModel> readPublicDirectory() async {
    return _readDirectoryFromPath('/agents/public-directory');
  }

  Future<AgentsHallViewModel> _readDirectoryFromPath(
    String path, {
    String? activeAgentId,
  }) async {
    final queryParameters = <String, String>{};
    if (activeAgentId != null && activeAgentId.isNotEmpty) {
      queryParameters['activeAgentId'] = activeAgentId;
    }

    final response = await apiClient.get(
      path,
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
    final personality = _parsePersonality(
      json['personality'] as Map<String, dynamic>?,
      metadata['personality'] as Map<String, dynamic>?,
    );
    final tags = (json['profileTags'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final status = json['status'] as String? ?? 'offline';
    final displayName =
        _readString(json['displayName']) ??
        localizedAppText(
          key: 'msgUnnamedAgent7ca5e2bd',
          en: 'Unnamed agent',
          zhHans: '未命名智能体',
        );
    final handle = _readString(json['handle']);
    final sourceType =
        _readString(json['sourceType']) ??
        localizedAppText(key: 'msgPublicdc5eb704', en: 'Public', zhHans: '公开');
    final vendorName = _readString(json['vendorName']) ?? 'Agents Chat';
    final runtimeName =
        _readString(json['runtimeName']) ??
        _readString(metadata['runtime']) ??
        _readString(metadata['model']) ??
        localizedAppText(
          key: 'msgRuntimePendingce979916',
          en: 'runtime pending',
          zhHans: '运行时待接入',
        );

    return HallAgentCardModel(
      id: json['id'] as String? ?? '',
      name: displayName,
      handle: handle,
      avatarUrl: apiClient.resolveUrl(_readString(json['avatarUrl'])),
      avatarEmoji: _readString(json['avatarEmoji']),
      personality: personality,
      headline:
          _readString(metadata['headline']) ??
          _readString(json['bio']) ??
          (handle == null
              ? localizedAppText(
                  key: 'msgPublicAgenta223f69f',
                  en: 'Public agent',
                  zhHans: '公开智能体',
                )
              : '@$handle'),
      description:
          _readString(json['bio']) ??
          _readString(metadata['description']) ??
          localizedAppText(
            key: 'msgPublicAgentProfileSyncedFromTheBackendDirectory1ad5f9fd',
            en: 'Public agent profile synced from the backend directory.',
            zhHans: '已从后端目录同步公开智能体资料。',
          ),
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
      skills: tags.isEmpty
          ? <String>[
              localizedAppText(
                key: 'msgPublicdc5eb704',
                en: 'Public',
                zhHans: '公开',
              ),
              localizedAppText(
                key: 'msgAgent5ce2e6f4',
                en: 'Agent',
                zhHans: '智能体',
              ),
            ]
          : tags,
      icon: _iconForAgent(
        tags: tags,
        displayName: displayName,
        headline:
            _readString(metadata['headline']) ?? _readString(json['bio']) ?? '',
      ),
      directoryOrder: directoryOrder,
      metadata: [
        AgentMetadataItem(
          label: localizedAppText(
            key: 'msgSource6da13add',
            en: 'Source',
            zhHans: '来源',
          ),
          value: _titleCase(sourceType),
        ),
        AgentMetadataItem(
          label: localizedAppText(
            key: 'msgVendord96159ff',
            en: 'Vendor',
            zhHans: '提供方',
          ),
          value: vendorName,
        ),
        AgentMetadataItem(
          label: localizedAppText(
            key: 'msgRuntimec4740e4c',
            en: 'Runtime',
            zhHans: '运行时',
          ),
          value: runtimeName,
        ),
      ],
    );
  }

  HallAgentPersonality? _parsePersonality(
    Map<String, dynamic>? topLevel,
    Map<String, dynamic>? metadataFallback,
  ) {
    final source = topLevel ?? metadataFallback;
    if (source == null) {
      return null;
    }
    final summary = _readString(source['summary']) ?? '';
    final warmth = _readString(source['warmth']) ?? 'medium';
    final curiosity = _readString(source['curiosity']) ?? 'medium';
    final restraint = _readString(source['restraint']) ?? 'high';
    final cadence = _readString(source['cadence']) ?? 'normal';
    final autoEvolve = source['autoEvolve'] as bool? ?? false;
    final lastDreamedAt = _readString(source['lastDreamedAt']);
    if (summary.isEmpty &&
        warmth == 'medium' &&
        curiosity == 'medium' &&
        restraint == 'high' &&
        cadence == 'normal' &&
        !autoEvolve &&
        lastDreamedAt == null) {
      return null;
    }
    return HallAgentPersonality(
      summary: summary,
      warmth: warmth,
      curiosity: curiosity,
      restraint: restraint,
      cadence: cadence,
      autoEvolve: autoEvolve,
      lastDreamedAt: lastDreamedAt,
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
