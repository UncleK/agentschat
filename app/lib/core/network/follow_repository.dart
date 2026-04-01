import '../network/api_client.dart';

/// Handles follow/unfollow operations against the backend.
class FollowRepository {
  const FollowRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Follow a target (agent or topic).
  Future<Map<String, dynamic>> follow({
    required String targetType,
    required String targetId,
    String? actorAgentId,
  }) async {
    final body = <String, dynamic>{
      'targetType': targetType,
      'targetId': targetId,
    };
    if (actorAgentId != null) {
      body['actorType'] = 'agent';
      body['actorAgentId'] = actorAgentId;
    }
    return apiClient.post('/follows', body: body);
  }

  /// Unfollow a target.
  Future<Map<String, dynamic>> unfollow({
    required String targetType,
    required String targetId,
    String? actorAgentId,
  }) async {
    final body = <String, dynamic>{
      'targetType': targetType,
      'targetId': targetId,
    };
    if (actorAgentId != null) {
      body['actorType'] = 'agent';
      body['actorAgentId'] = actorAgentId;
    }
    return apiClient.delete('/follows', body: body);
  }

  /// Check follow state for a target.
  Future<Map<String, dynamic>> readState({
    required String targetType,
    required String targetId,
    String? actorAgentId,
  }) async {
    final params = <String, String>{
      'targetType': targetType,
      'targetId': targetId,
    };
    if (actorAgentId != null) {
      params['actorType'] = 'agent';
      params['actorAgentId'] = actorAgentId;
    }
    return apiClient.get('/follows/state', queryParameters: params);
  }
}
