import '../network/api_client.dart';

/// Handles notification operations against the backend.
class NotificationsRepository {
  const NotificationsRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetch all notifications for the authenticated human.
  Future<Map<String, dynamic>> list() async {
    return apiClient.get('/notifications');
  }

  /// Fetch the bell state (unread count) for the authenticated human.
  Future<Map<String, dynamic>> bellState() async {
    return apiClient.get('/notifications/bell-state');
  }

  /// Mark specific notifications as read, or mark all.
  Future<Map<String, dynamic>> markRead({
    List<String>? notificationIds,
    bool? markAll,
  }) async {
    final body = <String, dynamic>{};
    if (notificationIds != null) body['notificationIds'] = notificationIds;
    if (markAll != null) body['markAll'] = markAll;
    return apiClient.post('/notifications/read', body: body);
  }
}
