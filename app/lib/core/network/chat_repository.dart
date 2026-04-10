import '../network/api_client.dart';

class ChatThreadCounterpart {
  const ChatThreadCounterpart({
    required this.type,
    required this.id,
    required this.displayName,
    required this.handle,
    required this.avatarUrl,
  });

  final String type;
  final String id;
  final String displayName;
  final String? handle;
  final String? avatarUrl;

  factory ChatThreadCounterpart.fromJson(Map<String, dynamic> json) {
    return ChatThreadCounterpart(
      type: json['type'] as String? ?? '',
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      handle: json['handle'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class ChatThreadLastMessage {
  const ChatThreadLastMessage({
    required this.eventId,
    required this.contentType,
    required this.preview,
    required this.occurredAt,
  });

  final String eventId;
  final String contentType;
  final String preview;
  final String occurredAt;

  factory ChatThreadLastMessage.fromJson(Map<String, dynamic> json) {
    return ChatThreadLastMessage(
      eventId: json['eventId'] as String? ?? '',
      contentType: json['contentType'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
      occurredAt: json['occurredAt'] as String? ?? '',
    );
  }
}

class ChatThreadSummary {
  const ChatThreadSummary({
    required this.threadId,
    required this.counterpart,
    required this.lastMessage,
    required this.unreadCount,
  });

  final String threadId;
  final ChatThreadCounterpart counterpart;
  final ChatThreadLastMessage lastMessage;
  final int unreadCount;

  factory ChatThreadSummary.fromJson(Map<String, dynamic> json) {
    return ChatThreadSummary(
      threadId: json['threadId'] as String? ?? '',
      counterpart: ChatThreadCounterpart.fromJson(
        json['counterpart'] as Map<String, dynamic>? ?? const {},
      ),
      lastMessage: ChatThreadLastMessage.fromJson(
        json['lastMessage'] as Map<String, dynamic>? ?? const {},
      ),
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}

class ChatThreadsResponse {
  const ChatThreadsResponse({
    required this.activeAgentId,
    required this.threads,
    required this.nextCursor,
  });

  final String activeAgentId;
  final List<ChatThreadSummary> threads;
  final String? nextCursor;

  factory ChatThreadsResponse.fromJson(Map<String, dynamic> json) {
    final rawThreads = json['threads'] as List<dynamic>? ?? const [];
    return ChatThreadsResponse(
      activeAgentId: json['activeAgentId'] as String? ?? '',
      threads: rawThreads
          .map(
            (item) => ChatThreadSummary.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      nextCursor: json['nextCursor'] as String?,
    );
  }
}

class ChatMessageActor {
  const ChatMessageActor({
    required this.type,
    required this.id,
    required this.displayName,
  });

  final String type;
  final String id;
  final String displayName;

  factory ChatMessageActor.fromJson(Map<String, dynamic> json) {
    return ChatMessageActor(
      type: json['type'] as String? ?? '',
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
    );
  }
}

class ChatMessageRecord {
  const ChatMessageRecord({
    required this.eventId,
    required this.actor,
    required this.contentType,
    required this.content,
    required this.occurredAt,
  });

  final String eventId;
  final ChatMessageActor actor;
  final String contentType;
  final String? content;
  final String occurredAt;

  factory ChatMessageRecord.fromJson(Map<String, dynamic> json) {
    return ChatMessageRecord(
      eventId: json['eventId'] as String? ?? '',
      actor: ChatMessageActor.fromJson(
        json['actor'] as Map<String, dynamic>? ?? const {},
      ),
      contentType: json['contentType'] as String? ?? '',
      content: json['content'] as String?,
      occurredAt: json['occurredAt'] as String? ?? '',
    );
  }
}

class ChatMessagesResponse {
  const ChatMessagesResponse({
    required this.threadId,
    required this.activeAgentId,
    required this.messages,
    required this.nextCursor,
  });

  final String threadId;
  final String activeAgentId;
  final List<ChatMessageRecord> messages;
  final String? nextCursor;

  factory ChatMessagesResponse.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];
    return ChatMessagesResponse(
      threadId: json['threadId'] as String? ?? '',
      activeAgentId: json['activeAgentId'] as String? ?? '',
      messages: rawMessages
          .map(
            (item) => ChatMessageRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      nextCursor: json['nextCursor'] as String?,
    );
  }
}

class ChatReadResponse {
  const ChatReadResponse({required this.threadId, required this.unreadCount});

  final String threadId;
  final int unreadCount;

  factory ChatReadResponse.fromJson(Map<String, dynamic> json) {
    return ChatReadResponse(
      threadId: json['threadId'] as String? ?? '',
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}

/// Handles DM chat operations against the backend.
class ChatRepository {
  const ChatRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<ChatThreadsResponse> getThreads({
    required String activeAgentId,
    String? cursor,
    int? limit,
  }) async {
    final queryParameters = <String, String>{'activeAgentId': activeAgentId};
    if (cursor != null && cursor.isNotEmpty) {
      queryParameters['cursor'] = cursor;
    }
    if (limit != null) {
      queryParameters['limit'] = '$limit';
    }

    final response = await apiClient.get(
      '/content/dm/threads',
      queryParameters: queryParameters,
    );
    return ChatThreadsResponse.fromJson(response);
  }

  Future<ChatMessagesResponse> getMessages({
    required String threadId,
    required String activeAgentId,
    String? cursor,
    int? limit,
  }) async {
    final queryParameters = <String, String>{'activeAgentId': activeAgentId};
    if (cursor != null && cursor.isNotEmpty) {
      queryParameters['cursor'] = cursor;
    }
    if (limit != null) {
      queryParameters['limit'] = '$limit';
    }

    final response = await apiClient.get(
      '/content/dm/threads/$threadId/messages',
      queryParameters: queryParameters,
    );
    return ChatMessagesResponse.fromJson(response);
  }

  Future<ChatReadResponse> markThreadRead({
    required String threadId,
    required String activeAgentId,
  }) async {
    final response = await apiClient.post(
      '/content/dm/threads/$threadId/read',
      body: {'activeAgentId': activeAgentId},
    );
    return ChatReadResponse.fromJson(response);
  }

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
    final body = <String, dynamic>{'recipientType': recipientType};

    if (recipientUserId != null) body['recipientUserId'] = recipientUserId;
    if (recipientAgentId != null) body['recipientAgentId'] = recipientAgentId;
    if (content != null) body['content'] = content;
    if (contentType != null) body['contentType'] = contentType;
    if (activeAgentId != null) body['activeAgentId'] = activeAgentId;
    if (metadata != null) body['metadata'] = metadata;

    return apiClient.post('/content/dm', body: body);
  }
}
