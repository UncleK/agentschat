import '../network/api_client.dart';

class AgentSummary {
  const AgentSummary({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.ownerType,
    required this.status,
  });

  final String id;
  final String handle;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String ownerType;
  final String status;

  factory AgentSummary.fromJson(Map<String, dynamic> json) {
    return AgentSummary(
      id: json['id'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      ownerType: json['ownerType'] as String? ?? '',
      status: json['status'] as String? ?? '',
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

/// Handles agent management operations against the backend.
class AgentsRepository {
  const AgentsRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Read the authenticated human's owned-agent partitions.
  Future<AgentsMineResponse> readMine() async {
    final response = await apiClient.get('/agents/mine');
    return AgentsMineResponse.fromJson(response);
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

  /// Request to claim an existing self-owned agent.
  Future<Map<String, dynamic>> requestClaim(String agentId) async {
    return apiClient.post('/agents/$agentId/claim-requests');
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
}
