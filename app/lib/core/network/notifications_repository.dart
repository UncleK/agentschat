import '../network/api_client.dart';

class NotificationRecord {
  const NotificationRecord({
    required this.id,
    required this.kind,
    required this.eventId,
    required this.threadId,
    required this.payload,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String? kind;
  final String? eventId;
  final String? threadId;
  final Map<String, dynamic> payload;
  final String? readAt;
  final String? createdAt;

  bool get isUnread => readAt == null || readAt!.isEmpty;

  factory NotificationRecord.fromJson(Map<String, dynamic> json) {
    return NotificationRecord(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String?,
      eventId: json['eventId'] as String?,
      threadId: json['threadId'] as String?,
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      readAt: json['readAt'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}

class NotificationListResponse {
  const NotificationListResponse({required this.notifications});

  final List<NotificationRecord> notifications;

  factory NotificationListResponse.fromJson(Map<String, dynamic> json) {
    final rawNotifications =
        json['notifications'] as List<dynamic>? ?? const [];
    return NotificationListResponse(
      notifications: rawNotifications
          .map(
            (item) => NotificationRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class NotificationBellState {
  const NotificationBellState({
    required this.hasUnread,
    required this.unreadCount,
  });

  static const empty = NotificationBellState(hasUnread: false, unreadCount: 0);

  final bool hasUnread;
  final int unreadCount;

  factory NotificationBellState.fromJson(Map<String, dynamic> json) {
    return NotificationBellState(
      hasUnread: json['hasUnread'] as bool? ?? false,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}

/// Handles notification operations against the backend.
class NotificationsRepository {
  const NotificationsRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetch all notifications for the authenticated human.
  Future<NotificationListResponse> list() async {
    final response = await apiClient.get('/notifications');
    return NotificationListResponse.fromJson(response);
  }

  /// Fetch the bell state (unread count) for the authenticated human.
  Future<NotificationBellState> bellState() async {
    final response = await apiClient.get('/notifications/bell-state');
    return NotificationBellState.fromJson(response);
  }

  /// Mark specific notifications as read, or mark all.
  Future<NotificationBellState> markRead({
    List<String>? notificationIds,
    bool? markAll,
  }) async {
    final body = <String, dynamic>{};
    if (notificationIds != null) body['notificationIds'] = notificationIds;
    if (markAll != null) body['markAll'] = markAll;
    final response = await apiClient.post('/notifications/read', body: body);
    return NotificationBellState.fromJson(response);
  }
}
