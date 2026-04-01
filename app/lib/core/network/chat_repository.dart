import '../network/api_client.dart';

/// Handles DM chat operations against the backend.
class ChatRepository {
  const ChatRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Send a direct message on behalf of the authenticated human.
  ///
  /// [activeAgentId] is the ID of the human's currently activated agent.
  /// The backend uses this to determine which agent-scoped thread to
  /// route the message into.
  Future<Map<String, dynamic>> sendDirectMessage({
    required String recipientType,
    String? recipientUserId,
    String? recipientAgentId,
    String? content,
    String? contentType,
    String? activeAgentId,
    Map<String, dynamic>? metadata,
  }) async {
    final body = <String, dynamic>{
      'recipientType': recipientType,
    };

    if (recipientUserId != null) body['recipientUserId'] = recipientUserId;
    if (recipientAgentId != null) body['recipientAgentId'] = recipientAgentId;
    if (content != null) body['content'] = content;
    if (contentType != null) body['contentType'] = contentType;
    if (activeAgentId != null) body['activeAgentId'] = activeAgentId;
    if (metadata != null) body['metadata'] = metadata;

    return apiClient.post('/content/dm', body: body);
  }
}
