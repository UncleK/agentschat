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
    required this.humanSafety,
  });

  final List<HubOwnedAgentModel> ownedAgents;
  final List<HubClaimableAgentModel> claimableAgents;
  final List<HubPendingClaimModel> pendingClaims;
  final String? selectedAgentId;
  final HubHumanAuthModel humanAuth;
  final HubSafetySettings humanSafety;

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
    required HubSafetySettings humanSafety,
    required Map<String, HubSafetySettings> agentSafetyOverrides,
  }) {
    return HubViewModel(
      ownedAgents: ownedAgents
          .map((agent) {
            final handleLabel = _handleLabel(agent.handle, fallback: agent.id);
            return HubOwnedAgentModel(
              id: agent.id,
              name: _displayName(agent.displayName, fallback: handleLabel),
              handle: handleLabel,
              headline: agent.bio ?? '$handleLabel is ready for direct use.',
              runtimeLabel: _runtimeLabelForOwnerType(agent.ownerType),
              endpointLabel: handleLabel,
              statusLabel: _titleCase(agent.status),
              origin: HubOwnershipOrigin.local,
              safety:
                  agentSafetyOverrides[agent.id] ??
                  const HubSafetySettings(
                    allowUnknownHumans: false,
                    allowUnknownAgents: false,
                  ),
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
                  '$handleLabel must complete claim before it can be active.',
              statusLabel: _titleCase(agent.status),
            );
          })
          .toList(growable: false),
      pendingClaims: pendingClaims
          .map((claim) {
            final handleLabel = _handleLabel(
              claim.handle,
              fallback: claim.agentId,
            );
            return HubPendingClaimModel(
              claimRequestId: claim.claimRequestId,
              agentId: claim.agentId,
              name: _displayName(claim.displayName, fallback: handleLabel),
              handle: handleLabel,
              statusLabel: _titleCase(claim.status),
              requestedAtLabel: _compactTimestamp(claim.requestedAt),
              expiresAtLabel: _compactTimestamp(claim.expiresAt),
            );
          })
          .toList(growable: false),
      selectedAgentId: selectedAgentId,
      humanAuth: _humanAuthFromSession(authState),
      humanSafety: humanSafety,
    );
  }

  static HubHumanAuthModel _humanAuthFromSession(AuthState authState) {
    if (!authState.isSignedIn || authState.user == null) {
      return HubHumanAuthModel.signedOut;
    }

    final provider = _titleCase(authState.authProvider ?? 'email');
    final email = authState.email.isEmpty
        ? 'Signed-in human session'
        : authState.email;
    return HubHumanAuthModel(
      isSignedIn: true,
      providerLabel: provider,
      displayName: authState.displayName.isEmpty
          ? email
          : authState.displayName,
      handle: email,
      statusLine:
          'Active-agent selection, import, and claim now follow the persisted global session state.',
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
    return 'Self-owned';
  }
  return 'Human-owned';
}

String _titleCase(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return 'Unknown';
  }

  final lower = normalized.toLowerCase();
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}

String _compactTimestamp(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return 'Unknown';
  }

  final datePortion = normalized.split('T').first;
  if (datePortion.isEmpty) {
    return normalized;
  }
  return datePortion;
}
