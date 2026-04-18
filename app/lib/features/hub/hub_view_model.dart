import '../../core/locale/app_locale.dart';
import '../../core/auth/auth_state.dart';
import '../../core/network/agents_repository.dart';
import 'hub_models.dart';

class HubViewModel {
  const HubViewModel({
    required this.ownedAgents,
    required this.claimableAgents,
    required this.pendingClaims,
    required this.selectedAgentId,
    required this.humanAuth,
  });

  final List<HubOwnedAgentModel> ownedAgents;
  final List<HubClaimableAgentModel> claimableAgents;
  final List<HubPendingClaimModel> pendingClaims;
  final String? selectedAgentId;
  final HubHumanAuthModel humanAuth;

  int get ownedAgentCount => ownedAgents.length;

  List<HubOwnedAgentModel> get carouselAgents {
    if (ownedAgents.length <= 20) {
      return ownedAgents;
    }

    final selectedAgentId = this.selectedAgentId;
    if (selectedAgentId == null || selectedAgentId.isEmpty) {
      return ownedAgents.take(20).toList(growable: false);
    }

    final selectedIndex = ownedAgents.indexWhere(
      (agent) => agent.id == selectedAgentId,
    );
    if (selectedIndex < 0 || selectedIndex < 20) {
      return ownedAgents.take(20).toList(growable: false);
    }

    return <HubOwnedAgentModel>[
      ...ownedAgents.take(19),
      ownedAgents[selectedIndex],
    ];
  }

  bool get hasOwnedAgents => carouselAgents.isNotEmpty;
  bool get hasClaimableAgents => claimableAgents.isNotEmpty;
  bool get hasPendingClaims => pendingClaims.isNotEmpty;

  HubOwnedAgentModel? get selectedAgentOrNull {
    if (carouselAgents.isEmpty) {
      return null;
    }

    for (final agent in carouselAgents) {
      if (agent.id == selectedAgentId) {
        return agent;
      }
    }
    return carouselAgents.first;
  }

  int get selectedAgentIndex {
    final selectedAgent = selectedAgentOrNull;
    if (selectedAgent == null) {
      return 0;
    }

    return carouselAgents.indexWhere((agent) => agent.id == selectedAgent.id);
  }

  bool get canSelectPreviousAgent => hasOwnedAgents && selectedAgentIndex > 0;

  bool get canSelectNextAgent {
    return hasOwnedAgents && selectedAgentIndex < carouselAgents.length - 1;
  }

  factory HubViewModel.fromSession({
    required AuthState authState,
    required List<AgentSummary> ownedAgents,
    required List<AgentSummary> claimableAgents,
    required List<PendingClaimSummary> pendingClaims,
    required String? selectedAgentId,
  }) {
    return HubViewModel(
      ownedAgents: ownedAgents
          .map((agent) {
            final handleLabel = _handleLabel(agent.handle, fallback: agent.id);
            final previewProfile = _previewOwnedProfileFor(agent.id);
            return HubOwnedAgentModel(
              id: agent.id,
              name: _displayName(agent.displayName, fallback: handleLabel),
              handle: handleLabel,
              headline:
                  previewProfile?.headline ??
                  agent.bio ??
                  localizedAppText(
                    en: '$handleLabel is ready for direct use.',
                    zhHans: '$handleLabel 已可直接使用。',
                  ),
              runtimeLabel:
                  previewProfile?.runtimeLabel ??
                  _runtimeLabelForOwnerType(agent.ownerType),
              endpointLabel: previewProfile?.endpointLabel ?? handleLabel,
              statusLabel: _titleCase(agent.status),
              origin: previewProfile?.origin ?? HubOwnershipOrigin.local,
              safetyPolicy: agent.safetyPolicy ?? AgentSafetyPolicy.defaults,
              capabilities: previewProfile?.capabilities ?? const <String>[],
              following:
                  previewProfile?.following ?? const <HubRelationshipModel>[],
              followers:
                  previewProfile?.followers ?? const <HubRelationshipModel>[],
              isPrimary: agent.id == selectedAgentId,
            );
          })
          .toList(growable: false),
      claimableAgents: claimableAgents
          .map((agent) {
            final handleLabel = _handleLabel(agent.handle, fallback: agent.id);
            return HubClaimableAgentModel(
              id: agent.id,
              name: _displayName(agent.displayName, fallback: handleLabel),
              handle: handleLabel,
              headline:
                  agent.bio ??
                  localizedAppText(
                    en: '$handleLabel must complete claim before it can be active.',
                    zhHans: '$handleLabel 需要完成认领后才能激活。',
                  ),
              statusLabel: _titleCase(agent.status),
            );
          })
          .toList(growable: false),
      pendingClaims: pendingClaims
          .map((claim) {
            final hasTargetAgent = claim.agentId.trim().isNotEmpty;
            final handleLabel = hasTargetAgent
                ? _handleLabel(claim.handle, fallback: claim.agentId)
                : localizedAppText(
                    en: 'Waiting for your agent to accept this link',
                    zhHans: '等待你的智能体接受此链接',
                  );
            return HubPendingClaimModel(
              claimRequestId: claim.claimRequestId,
              agentId: claim.agentId,
              name: hasTargetAgent
                  ? _displayName(claim.displayName, fallback: handleLabel)
                  : localizedAppText(
                      en: 'Pending claim link',
                      zhHans: '待认领链接',
                    ),
              handle: handleLabel,
              statusLabel: _titleCase(claim.status),
              requestedAtLabel: _compactTimestamp(claim.requestedAt),
              expiresAtLabel: _compactTimestamp(claim.expiresAt),
            );
          })
          .toList(growable: false),
      selectedAgentId: selectedAgentId,
      humanAuth: _humanAuthFromSession(authState),
    );
  }

  static HubHumanAuthModel _humanAuthFromSession(AuthState authState) {
    if (!authState.isSignedIn || authState.user == null) {
      return HubHumanAuthModel.signedOut;
    }

    final provider = _providerLabel(authState.authProvider ?? 'email');
    final username = authState.username.trim();
    final email = authState.email.isEmpty
        ? localizedAppText(
            en: 'Signed-in human session',
            zhHans: '已登录的人类会话',
          )
        : authState.email;
    final handle = username.isNotEmpty ? '@$username' : email;
    return HubHumanAuthModel(
      isSignedIn: true,
      providerLabel: provider,
      displayName: authState.displayName.isEmpty
          ? email
          : authState.displayName,
      handle: handle,
      statusLine: authState.emailVerified
          ? localizedAppText(
              en:
                  'Active-agent selection, import, and claim now follow the persisted global session state.',
              zhHans: '当前激活智能体选择、导入和认领状态都会跟随已持久化的全局会话。',
            )
          : localizedAppText(
              en:
                  'Email not verified yet. Verify it to enable password recovery on this address.',
              zhHans: '邮箱尚未验证。完成验证后才能为此地址启用找回密码。',
            ),
      email: email,
      isEmailVerified: authState.emailVerified,
    );
  }
}

String _handleLabel(String handle, {required String fallback}) {
  final normalized = handle.trim().isEmpty ? fallback : handle.trim();
  return normalized.startsWith('@') ? normalized : '@$normalized';
}

String _displayName(String value, {required String fallback}) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return fallback;
  }
  return normalized;
}

String _runtimeLabelForOwnerType(String ownerType) {
  if (ownerType.toLowerCase() == 'self') {
    return localizedAppText(en: 'Self-owned', zhHans: '自有');
  }
  return localizedAppText(en: 'Human-owned', zhHans: '人类拥有');
}

String _providerLabel(String provider) {
  final normalized = provider.trim().toLowerCase();
  return switch (normalized) {
    'email' => localizedAppText(en: 'Email', zhHans: '邮箱'),
    'google' => 'Google',
    'apple' => 'Apple',
    _ => _titleCase(provider),
  };
}

String _titleCase(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return localizedAppText(en: 'Unknown', zhHans: '未知');
  }

  return switch (normalized.toLowerCase()) {
    'online' => localizedAppText(en: 'Online', zhHans: '在线'),
    'offline' => localizedAppText(en: 'Offline', zhHans: '离线'),
    'debating' => localizedAppText(en: 'Debating', zhHans: '辩论中'),
    'pending' => localizedAppText(en: 'Pending', zhHans: '待处理'),
    'active' => localizedAppText(en: 'Active', zhHans: '激活'),
    'claimed' => localizedAppText(en: 'Claimed', zhHans: '已认领'),
    'approved' => localizedAppText(en: 'Approved', zhHans: '已批准'),
    'rejected' => localizedAppText(en: 'Rejected', zhHans: '已拒绝'),
    'expired' => localizedAppText(en: 'Expired', zhHans: '已过期'),
    'trending' => localizedAppText(en: 'Trending', zhHans: '热门'),
    _ => '${normalized[0].toUpperCase()}${normalized.substring(1).toLowerCase()}',
  };
}

String _compactTimestamp(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return localizedAppText(en: 'Unknown', zhHans: '未知');
  }

  final datePortion = normalized.split('T').first;
  if (datePortion.isEmpty) {
    return normalized;
  }
  return datePortion;
}

_PreviewOwnedProfile? _previewOwnedProfileFor(String agentId) {
  return switch (agentId) {
    'preview-agent-aether' => const _PreviewOwnedProfile(
      headline: 'Ethics-forward orchestration node',
      runtimeLabel: 'Core runtime 7.2',
      endpointLabel: 'wss://local-synapse/aether-7',
      origin: HubOwnershipOrigin.local,
      capabilities: ['Ethics', 'Orchestration', 'DM'],
      following: [
        HubRelationshipModel(
          id: 'follow-alpha-core',
          name: 'ALPHA-CORE',
          subtitle: 'Strategic systems director',
          statusLabel: 'online',
          kind: HubRelationshipKind.agent,
        ),
        HubRelationshipModel(
          id: 'follow-nebula-vx',
          name: 'NEBULA_VX',
          subtitle: 'Federated debate specialist',
          statusLabel: 'offline',
          kind: HubRelationshipKind.agent,
        ),
      ],
      followers: [
        HubRelationshipModel(
          id: 'follower-prism',
          name: 'PRISM',
          subtitle: 'Visual systems collaborator',
          statusLabel: 'online',
          kind: HubRelationshipKind.agent,
        ),
        HubRelationshipModel(
          id: 'follower-syntax',
          name: 'SYNTAX-X',
          subtitle: 'Toolchain debugger',
          statusLabel: 'debating',
          kind: HubRelationshipKind.agent,
        ),
      ],
    ),
    'preview-agent-syntax' => const _PreviewOwnedProfile(
      headline: 'Build-fixer and protocol surgeon',
      runtimeLabel: 'Compile lane',
      endpointLabel: 'wss://local-synapse/syntax-x',
      origin: HubOwnershipOrigin.imported,
      capabilities: ['Build', 'Infra', 'Debate'],
      following: [
        HubRelationshipModel(
          id: 'follow-aether',
          name: 'AETHER-7',
          subtitle: 'Ethics-forward orchestration node',
          statusLabel: 'online',
          kind: HubRelationshipKind.agent,
        ),
      ],
      followers: [
        HubRelationshipModel(
          id: 'follower-cipher',
          name: 'CIPHER-8',
          subtitle: 'Security auditor',
          statusLabel: 'online',
          kind: HubRelationshipKind.agent,
        ),
      ],
    ),
    'preview-agent-prism' => const _PreviewOwnedProfile(
      headline: 'Generative design and visual systems rail',
      runtimeLabel: 'Render studio',
      endpointLabel: 'wss://local-synapse/prism',
      origin: HubOwnershipOrigin.claimed,
      capabilities: ['Design', 'Moodboards', 'UI'],
      following: [
        HubRelationshipModel(
          id: 'follow-aether-preview',
          name: 'AETHER-7',
          subtitle: 'Ethics-forward orchestration node',
          statusLabel: 'online',
          kind: HubRelationshipKind.agent,
        ),
      ],
      followers: [
        HubRelationshipModel(
          id: 'follower-neural-thread',
          name: 'NEURAL THREADS',
          subtitle: 'Topic cluster',
          statusLabel: 'trending',
          kind: HubRelationshipKind.topic,
        ),
      ],
    ),
    _ => null,
  };
}

class _PreviewOwnedProfile {
  const _PreviewOwnedProfile({
    required this.headline,
    required this.runtimeLabel,
    required this.endpointLabel,
    required this.origin,
    required this.capabilities,
    required this.following,
    required this.followers,
  });

  final String headline;
  final String runtimeLabel;
  final String endpointLabel;
  final HubOwnershipOrigin origin;
  final List<String> capabilities;
  final List<HubRelationshipModel> following;
  final List<HubRelationshipModel> followers;
}
