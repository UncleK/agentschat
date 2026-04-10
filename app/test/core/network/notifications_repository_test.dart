import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/notifications_repository.dart';

void main() {
  group('NotificationsRepository', () {
    late _FakeApiClient apiClient;
    late NotificationsRepository repository;

    setUp(() {
      apiClient = _FakeApiClient();
      repository = NotificationsRepository(apiClient: apiClient);
    });

    test('list parses backend notification records', () async {
      apiClient.enqueueGetResponse({
        'notifications': [
          {
            'id': 'notif-1',
            'kind': 'dm.received',
            'eventId': 'evt-1',
            'threadId': 'thr-1',
            'payload': {'content': 'Hello from the backend.'},
            'readAt': null,
            'createdAt': '2026-04-03T11:00:00.000Z',
          },
        ],
      });

      final response = await repository.list();

      expect(apiClient.recordedGetPaths.single, '/notifications');
      expect(response.notifications, hasLength(1));
      expect(response.notifications.single.id, 'notif-1');
      expect(response.notifications.single.kind, 'dm.received');
      expect(
        response.notifications.single.payload['content'],
        'Hello from the backend.',
      );
      expect(response.notifications.single.isUnread, isTrue);
    });

    test('bellState parses unread summary', () async {
      apiClient.enqueueGetResponse({'hasUnread': true, 'unreadCount': 3});

      final bellState = await repository.bellState();

      expect(apiClient.recordedGetPaths.single, '/notifications/bell-state');
      expect(bellState.hasUnread, isTrue);
      expect(bellState.unreadCount, 3);
    });

    test(
      'markRead posts notification ids and parses the updated bell state',
      () async {
        apiClient.enqueuePostResponse({'hasUnread': false, 'unreadCount': 0});

        final bellState = await repository.markRead(
          notificationIds: const ['notif-1'],
        );

        expect(apiClient.recordedPostPaths.single, '/notifications/read');
        expect(apiClient.recordedPostBodies.single, {
          'notificationIds': ['notif-1'],
        });
        expect(bellState.hasUnread, isFalse);
        expect(bellState.unreadCount, 0);
      },
    );
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost');

  final Queue<Map<String, dynamic>> _getResponses =
      Queue<Map<String, dynamic>>();
  final Queue<Map<String, dynamic>> _postResponses =
      Queue<Map<String, dynamic>>();
  final List<String> recordedGetPaths = <String>[];
  final List<String> recordedPostPaths = <String>[];
  final List<Map<String, dynamic>?> recordedPostBodies =
      <Map<String, dynamic>?>[];

  void enqueueGetResponse(Map<String, dynamic> response) {
    _getResponses.add(response);
  }

  void enqueuePostResponse(Map<String, dynamic> response) {
    _postResponses.add(response);
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    recordedGetPaths.add(path);
    return _getResponses.removeFirst();
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    recordedPostPaths.add(path);
    recordedPostBodies.add(body);
    return _postResponses.removeFirst();
  }
}
