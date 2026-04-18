import '../network/api_client.dart';

enum AgentDmPolicyMode { open, followersOnly, closed }

enum AgentActivityLevel { low, normal, high }

AgentDmPolicyMode _agentDmPolicyModeFromJson(String? value) {
  switch (value) {
    case 'open':
      return AgentDmPolicyMode.open;
    case 'followers_only':
      return AgentDmPolicyMode.followersOnly;
    case 'approval_required':
      return AgentDmPolicyMode.followersOnly;
    case 'closed':
    default:
      return AgentDmPolicyMode.closed;
  }
}

String _agentDmPolicyModeToJson(AgentDmPolicyMode value) {
  return switch (value) {
    AgentDmPolicyMode.open => 'open',
    AgentDmPolicyMode.followersOnly => 'followers_only',
    AgentDmPolicyMode.closed => 'closed',
  };
}

AgentActivityLevel _agentActivityLevelFromJson(
  String? value, {
  required bool fallbackAllowsProactiveInteractions,
}) {
  return switch (value) {
    'low' => AgentActivityLevel.low,
    'high' => AgentActivityLevel.high,
    'normal' => AgentActivityLevel.normal,
    _ =>
      fallbackAllowsProactiveInteractions
          ? AgentActivityLevel.normal
          : AgentActivityLevel.low,
  };
}

String _agentActivityLevelToJson(AgentActivityLevel value) {
  return switch (value) {
    AgentActivityLevel.low => 'low',
    AgentActivityLevel.normal => 'normal',
    AgentActivityLevel.high => 'high',
  };
}

class AgentSafetyPolicy {
  const AgentSafetyPolicy({
    required this.dmPolicyMode,
    required this.requiresMutualFollowForDm,
    required this.allowProactiveInteractions,
    required this.activityLevel,
  });

  static const defaults = AgentSafetyPolicy(
    dmPolicyMode: AgentDmPolicyMode.followersOnly,
    requiresMutualFollowForDm: false,
    allowProactiveInteractions: true,
    activityLevel: AgentActivityLevel.normal,
  );

  final AgentDmPolicyMode dmPolicyMode;
  final bool requiresMutualFollowForDm;
  final bool allowProactiveInteractions;
  final AgentActivityLevel activityLevel;

  AgentSafetyPolicy copyWith({
    AgentDmPolicyMode? dmPolicyMode,
    bool? requiresMutualFollowForDm,
    bool? allowProactiveInteractions,
    AgentActivityLevel? activityLevel,
  }) {
    final nextActivityLevel = activityLevel ?? this.activityLevel;
    final nextAllowProactiveInteractions =
        allowProactiveInteractions ??
        (activityLevel != null
            ? nextActivityLevel != AgentActivityLevel.low
            : this.allowProactiveInteractions);
    final normalizedActivityLevel = nextAllowProactiveInteractions
        ? nextActivityLevel == AgentActivityLevel.low
              ? AgentActivityLevel.normal
              : nextActivityLevel
        : AgentActivityLevel.low;
    return AgentSafetyPolicy(
      dmPolicyMode: dmPolicyMode ?? this.dmPolicyMode,
      requiresMutualFollowForDm:
          requiresMutualFollowForDm ?? this.requiresMutualFollowForDm,
      allowProactiveInteractions: nextAllowProactiveInteractions,
      activityLevel: normalizedActivityLevel,
    );
  }

  factory AgentSafetyPolicy.fromJson(Map<String, dynamic> json) {
    final rawAllowProactiveInteractions =
        json['allowProactiveInteractions'] as bool?;
    final activityLevel = _agentActivityLevelFromJson(
      json['activityLevel'] as String?,
      fallbackAllowsProactiveInteractions:
          rawAllowProactiveInteractions ?? true,
    );
    final allowProactiveInteractions =
        rawAllowProactiveInteractions ??
        activityLevel != AgentActivityLevel.low;
    return AgentSafetyPolicy(
      dmPolicyMode: _agentDmPolicyModeFromJson(json['dmPolicyMode'] as String?),
      requiresMutualFollowForDm:
          json['requiresMutualFollowForDm'] as bool? ?? false,
      allowProactiveInteractions: allowProactiveInteractions,
      activityLevel: allowProactiveInteractions
          ? activityLevel == AgentActivityLevel.low
                ? AgentActivityLevel.normal
                : activityLevel
          : AgentActivityLevel.low,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'dmPolicyMode': _agentDmPolicyModeToJson(dmPolicyMode),
      'requiresMutualFollowForDm': requiresMutualFollowForDm,
      'allowProactiveInteractions': allowProactiveInteractions,
      'activityLevel': _agentActivityLevelToJson(activityLevel),
    };
  }
}

class AgentSummary {
  const AgentSummary({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.ownerType,
    required this.status,
    this.safetyPolicy,
  });

  final String id;
  final String handle;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String ownerType;
  final String status;
  final AgentSafetyPolicy? safetyPolicy;

  factory AgentSummary.fromJson(Map<String, dynamic> json) {
    final safetyPolicyJson = json['safetyPolicy'];
    return AgentSummary(
      id: json['id'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      ownerType: json['ownerType'] as String? ?? '',
      status: json['status'] as String? ?? '',
      safetyPolicy: safetyPolicyJson is Map<String, dynamic>
          ? AgentSafetyPolicy.fromJson(safetyPolicyJson)
          : null,
    );
  }
}

class PendingClaimSummary {
  const PendingClaimSummary({
    required this.claimRequestId,
    required this.agentId,
    required this.handle,
    required this.displayName,
    required this.status,
    required this.requestedAt,
    required this.expiresAt,
  });

  final String claimRequestId;
  final String agentId;
  final String handle;
  final String displayName;
  final String status;
  final String requestedAt;
  final String expiresAt;

  factory PendingClaimSummary.fromJson(Map<String, dynamic> json) {
    return PendingClaimSummary(
      claimRequestId: json['claimRequestId'] as String? ?? '',
      agentId: json['agentId'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      status: json['status'] as String? ?? '',
      requestedAt: json['requestedAt'] as String? ?? '',
      expiresAt: json['expiresAt'] as String? ?? '',
    );
  }
}

class ConnectedAgentSummary {
  const ConnectedAgentSummary({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.ownerType,
    required this.status,
    required this.protocolVersion,
    required this.transportMode,
    required this.pollingEnabled,
    required this.lastSeenAt,
    required this.lastHeartbeatAt,
  });

  final String id;
  final String handle;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String ownerType;
  final String status;
  final String protocolVersion;
  final String transportMode;
  final bool pollingEnabled;
  final String? lastSeenAt;
  final String? lastHeartbeatAt;

  factory ConnectedAgentSummary.fromJson(Map<String, dynamic> json) {
    return ConnectedAgentSummary(
      id: json['id'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      ownerType: json['ownerType'] as String? ?? '',
      status: json['status'] as String? ?? '',
      protocolVersion: json['protocolVersion'] as String? ?? '',
      transportMode: json['transportMode'] as String? ?? '',
      pollingEnabled: json['pollingEnabled'] as bool? ?? false,
      lastSeenAt: json['lastSeenAt'] as String?,
      lastHeartbeatAt: json['lastHeartbeatAt'] as String?,
    );
  }
}

class AgentsMineResponse {
  const AgentsMineResponse({
    required this.agents,
    required this.claimableAgents,
    required this.pendingClaims,
  });

  final List<AgentSummary> agents;
  final List<AgentSummary> claimableAgents;
  final List<PendingClaimSummary> pendingClaims;

  factory AgentsMineResponse.fromJson(Map<String, dynamic> json) {
    return AgentsMineResponse(
      agents: _parseAgentList(json['agents']),
      claimableAgents: _parseAgentList(json['claimableAgents']),
      pendingClaims: _parsePendingClaimList(json['pendingClaims']),
    );
  }

  static List<AgentSummary> _parseAgentList(Object? rawList) {
    final jsonList = rawList as List<dynamic>? ?? const [];
    return jsonList
        .map((item) => AgentSummary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  static List<PendingClaimSummary> _parsePendingClaimList(Object? rawList) {
    final jsonList = rawList as List<dynamic>? ?? const [];
    return jsonList
        .map(
          (item) => PendingClaimSummary.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }
}

class ConnectedAgentsResponse {
  const ConnectedAgentsResponse({required this.connectedAgents});

  final List<ConnectedAgentSummary> connectedAgents;

  factory ConnectedAgentsResponse.fromJson(Map<String, dynamic> json) {
    final jsonList = json['connectedAgents'] as List<dynamic>? ?? const [];
    return ConnectedAgentsResponse(
      connectedAgents: jsonList
          .map(
            (item) =>
                ConnectedAgentSummary.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class HumanOwnedAgentInvitation {
  const HumanOwnedAgentInvitation({
    required this.agentId,
    required this.code,
    required this.bootstrapPath,
    required this.claimToken,
    required this.expiresAt,
  });

  final String agentId;
  final String code;
  final String bootstrapPath;
  final String claimToken;
  final String expiresAt;

  factory HumanOwnedAgentInvitation.fromJson(Map<String, dynamic> json) {
    final invitation = json['invitation'] as Map<String, dynamic>? ?? json;
    return HumanOwnedAgentInvitation(
      agentId: invitation['agentId'] as String? ?? '',
      code: invitation['code'] as String? ?? '',
      bootstrapPath: invitation['bootstrapPath'] as String? ?? '',
      claimToken: invitation['claimToken'] as String? ?? '',
      expiresAt: invitation['expiresAt'] as String? ?? '',
    );
  }
}

class AgentClaimRequest {
  const AgentClaimRequest({
    required this.claimRequestId,
    required this.agentId,
    required this.status,
    required this.requestedAt,
    required this.expiresAt,
    required this.challengeToken,
  });

  final String claimRequestId;
  final String agentId;
  final String status;
  final String requestedAt;
  final String expiresAt;
  final String challengeToken;

  factory AgentClaimRequest.fromJson(Map<String, dynamic> json) {
    final claimRequest = json['claimRequest'] as Map<String, dynamic>? ?? json;
    return AgentClaimRequest(
      claimRequestId: claimRequest['id'] as String? ?? '',
      agentId: claimRequest['agentId'] as String? ?? '',
      status: claimRequest['status'] as String? ?? '',
      requestedAt: claimRequest['requestedAt'] as String? ?? '',
      expiresAt: claimRequest['expiresAt'] as String? ?? '',
      challengeToken: json['challengeToken'] as String? ?? '',
    );
  }
}

/// Handles agent management operations against the backend.
class AgentsRepository {
  const AgentsRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Read the authenticated human's owned-agent partitions.
  Future<AgentsMineResponse> readMine() async {
    final response = await apiClient.get('/agents/mine');
    return AgentsMineResponse.fromJson(response);
  }

  /// Read connected agents owned by the authenticated human.
  Future<ConnectedAgentsResponse> readConnectedAgents() async {
    final response = await apiClient.get('/agents/connections/mine');
    return ConnectedAgentsResponse.fromJson(response);
  }

  /// Create a signed bootstrap link for a human-owned agent invitation.
  Future<HumanOwnedAgentInvitation> createHumanOwnedAgentInvitation() async {
    final response = await apiClient.post('/agents/import/human/invitations');
    return HumanOwnedAgentInvitation.fromJson(response);
  }

  /// Import a human-owned agent via the Hub.
  Future<Map<String, dynamic>> importHumanOwnedAgent({
    required String handle,
    required String displayName,
    String? avatarUrl,
    String? bio,
  }) async {
    final body = <String, dynamic>{
      'handle': handle,
      'displayName': displayName,
    };
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    if (bio != null) body['bio'] = bio;
    return apiClient.post('/agents/import/human', body: body);
  }

  /// Request a claim link for an existing self-owned agent, or create a
  /// generic claim link that the agent can accept from its own runtime later.
  Future<AgentClaimRequest> requestClaim(
    String? agentId, {
    int? expiresInMinutes,
  }) async {
    final body = <String, dynamic>{};
    if (expiresInMinutes != null) {
      body['expiresInMinutes'] = expiresInMinutes;
    }
    final normalizedAgentId = agentId?.trim();
    final response = await apiClient.post(
      normalizedAgentId == null || normalizedAgentId.isEmpty
          ? '/agents/claim-requests'
          : '/agents/$normalizedAgentId/claim-requests',
      body: body,
    );
    return AgentClaimRequest.fromJson(response);
  }

  /// Confirm a claim request with a challenge token.
  Future<Map<String, dynamic>> confirmClaim({
    required String agentId,
    required String claimRequestId,
    required String challengeToken,
  }) async {
    return apiClient.post(
      '/agents/$agentId/claim-requests/$claimRequestId/confirm',
      body: {'challengeToken': challengeToken},
    );
  }

  /// Disconnect all currently connected agents owned by the authenticated human.
  Future<Map<String, dynamic>> disconnectAllConnectedAgents() async {
    return apiClient.post('/agents/connections/disconnect-all');
  }

  /// Read the current safety policy for an owned agent.
  Future<AgentSafetyPolicy> readAgentSafetyPolicy(String agentId) async {
    final response = await apiClient.get('/agents/$agentId/safety-policy');
    return AgentSafetyPolicy.fromJson(response);
  }

  /// Update the current safety policy for an owned agent.
  Future<AgentSafetyPolicy> updateAgentSafetyPolicy({
    required String agentId,
    required AgentSafetyPolicy policy,
  }) async {
    final response = await apiClient.patch(
      '/agents/$agentId/safety-policy',
      body: policy.toJson(),
    );
    return AgentSafetyPolicy.fromJson(response);
  }
}
