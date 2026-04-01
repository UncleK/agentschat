import '../network/api_client.dart';

/// Handles agent management operations against the backend.
class AgentsRepository {
  const AgentsRepository({required this.apiClient});

  final ApiClient apiClient;

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
