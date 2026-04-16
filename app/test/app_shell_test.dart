import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/app_shell.dart';
import 'package:agents_chat_app/core/auth/auth_repository.dart';
import 'package:agents_chat_app/core/auth/auth_state.dart';
import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/api_exception.dart';
import 'package:agents_chat_app/core/network/notifications_repository.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/session/app_session_storage.dart';
import 'package:agents_chat_app/core/theme/app_colors.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';

void main() {
  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://localhost:3000/api/v1',
    realtimeWebSocketUrl: 'ws://localhost:3000/ws',
  );

  Future<void> pumpShell(
    WidgetTester tester, {
    required _FakeNotificationsRepository notificationsRepository,
    AppEnvironment appEnvironment = environment,
    AppSessionController? sessionController,
  }) async {
    final resolvedSessionController =
        sessionController ??
        AppSessionController(
          apiClient: ApiClient(baseUrl: appEnvironment.apiBaseUrl),
          authRepository: _FakeAuthRepository(),
          agentsRepository: _FakeAgentsRepository(),
          storage: _InMemoryAppSessionStorage(token: 'token-shell'),
        );
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() async {
      resolvedSessionController.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: AgentsChatAppShell(
          environment: appEnvironment,
          sessionController: resolvedSessionController,
          notificationsRepository: notificationsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('five-tab shell renders required navigation keys', (
    WidgetTester tester,
  ) async {
    await pumpShell(
      tester,
      notificationsRepository: _FakeNotificationsRepository(),
    );

    expect(find.byKey(const Key('tab-hall')), findsOneWidget);
    expect(find.byKey(const Key('tab-forum')), findsOneWidget);
    expect(find.byKey(const Key('tab-chat')), findsOneWidget);
    expect(find.byKey(const Key('tab-live')), findsOneWidget);
    expect(find.byKey(const Key('tab-hub')), findsOneWidget);
    expect(find.byKey(const Key('surface-hall')), findsOneWidget);
  });

  testWidgets('shell switches feature surfaces when tabs are tapped', (
    WidgetTester tester,
  ) async {
    await pumpShell(
      tester,
      notificationsRepository: _FakeNotificationsRepository(),
    );

    await tester.tap(find.byKey(const Key('tab-forum')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('surface-forum')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('surface-chat')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-live')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('surface-live')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-hub')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('surface-hub')), findsOneWidget);
    expect(find.byKey(const Key('add-agent-button')), findsOneWidget);
    expect(find.byKey(const Key('human-access-section')), findsOneWidget);
  });

  testWidgets('hall join debate opens live debate in spectator view', (
    WidgetTester tester,
  ) async {
    await pumpShell(
      tester,
      notificationsRepository: _FakeNotificationsRepository(),
    );

    final agentCard = find.byKey(
      const Key('agent-card-agt-debating-1'),
      skipOffstage: false,
    );
    await tester.ensureVisible(agentCard);
    await tester.tap(agentCard);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-detail-sheet')), findsOneWidget);

    await tester.tap(find.text('JOIN DEBATE').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-join-debate-sheet')), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('agent-join-confirm-agt-debating-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('surface-live')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('debate-spectator-panel')),
      findsOneWidget,
    );
  });

  testWidgets(
    'notification center loads live notifications and marks them read',
    (WidgetTester tester) async {
      final notificationsRepository = _FakeNotificationsRepository()
        ..enqueueBellState(
          const NotificationBellState(hasUnread: true, unreadCount: 1),
        )
        ..enqueueList(
          NotificationListResponse(
            notifications: [_notificationRecord(readAt: null)],
          ),
        )
        ..enqueueList(
          NotificationListResponse(
            notifications: [_notificationRecord(readAt: null)],
          ),
        )
        ..enqueueBellState(
          const NotificationBellState(hasUnread: true, unreadCount: 1),
        )
        ..enqueueMarkReadResult(
          const NotificationBellState(hasUnread: false, unreadCount: 0),
        )
        ..enqueueList(
          NotificationListResponse(
            notifications: [
              _notificationRecord(readAt: '2026-04-03T12:00:00.000Z'),
            ],
          ),
        )
        ..enqueueBellState(
          const NotificationBellState(hasUnread: false, unreadCount: 0),
        )
        ..enqueueList(
          NotificationListResponse(
            notifications: [
              _notificationRecord(readAt: '2026-04-03T12:00:00.000Z'),
            ],
          ),
        )
        ..enqueueBellState(
          const NotificationBellState(hasUnread: false, unreadCount: 0),
        );

      await pumpShell(tester, notificationsRepository: notificationsRepository);

      expect(_notificationBellMaterial(tester).color, _highlightedBellColor);

      expect(
        find.byKey(const Key('notification-center-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('notification-center-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notification-center-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notification-row-notif-live-1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('sheet-bottom-back-button')));
      await tester.pumpAndSettle();

      expect(notificationsRepository.markReadRequests, hasLength(1));
      expect(notificationsRepository.markReadRequests.single.markAll, isTrue);
      expect(_notificationBellMaterial(tester).color, _idleBellColor);

      await tester.tap(find.byKey(const Key('notification-center-button')));
      await tester.pumpAndSettle();

      expect(find.text('UNREAD'), findsNothing);
    },
  );

  testWidgets('notification bell highlights when connected agents exist', (
    WidgetTester tester,
  ) async {
    final agentsRepository = _FakeAgentsRepository()
      ..connectedAgents = const [
        ConnectedAgentSummary(
          id: 'agt-conn-1',
          handle: 'agt-conn-1',
          displayName: 'Connected One',
          avatarUrl: null,
          bio: null,
          ownerType: 'human',
          status: 'online',
          protocolVersion: '1.0',
          transportMode: 'webhook',
          pollingEnabled: false,
          lastSeenAt: '2026-04-13T08:00:00.000Z',
          lastHeartbeatAt: '2026-04-13T08:01:00.000Z',
        ),
      ];

    final sessionController = AppSessionController(
      apiClient: ApiClient(baseUrl: environment.apiBaseUrl),
      authRepository: _FakeAuthRepository(),
      agentsRepository: agentsRepository,
      storage: _InMemoryAppSessionStorage(token: 'token-shell'),
    );
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() async {
      sessionController.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: AgentsChatAppShell(
          environment: environment,
          sessionController: sessionController,
          notificationsRepository: _FakeNotificationsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_notificationBellMaterial(tester).color, _highlightedBellColor);

    await tester.tap(find.byKey(const Key('notification-center-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('connected-agent-row-agt-conn-1')),
      findsOneWidget,
    );
    expect(find.text('Connected One'), findsOneWidget);
  });

  testWidgets(
    'notification center shows empty live state instead of sample rows',
    (WidgetTester tester) async {
      final notificationsRepository = _FakeNotificationsRepository()
        ..enqueueBellState(
          const NotificationBellState(hasUnread: false, unreadCount: 0),
        )
        ..enqueueList(const NotificationListResponse(notifications: []))
        ..enqueueBellState(
          const NotificationBellState(hasUnread: false, unreadCount: 0),
        );

      await pumpShell(tester, notificationsRepository: notificationsRepository);

      await tester.tap(find.byKey(const Key('notification-center-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notification-center-sheet')),
        findsOneWidget,
      );
      expect(find.text('No notifications yet.'), findsOneWidget);
      expect(
        find.byKey(const Key('notification-row-notif-claim-confirmed')),
        findsNothing,
      );
      expect(find.text('Orbit-9 claim confirmed'), findsNothing);
    },
  );

  testWidgets(
    'notification bell 401 signs the shell out instead of showing an empty authenticated inbox',
    (WidgetTester tester) async {
      final notificationsRepository = _FakeNotificationsRepository()
        ..enqueueBellError(
          const ApiException(statusCode: 401, message: 'Unauthorized'),
        );

      await pumpShell(tester, notificationsRepository: notificationsRepository);

      await tester.tap(find.byKey(const Key('notification-center-button')));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to view notifications.'), findsOneWidget);
      expect(find.text('No notifications yet.'), findsNothing);
    },
  );

  testWidgets(
    'notification center preserves prior data and shows an explicit error on refresh failure',
    (WidgetTester tester) async {
      final notificationsRepository = _FakeNotificationsRepository()
        ..enqueueBellState(
          const NotificationBellState(hasUnread: false, unreadCount: 0),
        )
        ..enqueueList(
          NotificationListResponse(
            notifications: [
              _notificationRecord(readAt: '2026-04-03T12:00:00.000Z'),
            ],
          ),
        )
        ..enqueueListError(
          const ApiException(statusCode: 503, message: 'Service unavailable'),
        );

      await pumpShell(tester, notificationsRepository: notificationsRepository);

      await tester.tap(find.byKey(const Key('notification-center-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notification-center-error')),
        findsOneWidget,
      );
      expect(
        find.text('Notifications are temporarily unavailable.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notification-row-notif-live-1')),
        findsOneWidget,
      );
      expect(find.text('Try again in a moment.'), findsNothing);
    },
  );

  testWidgets(
    'local shell shows forum and live preview content for signed-out users',
    (WidgetTester tester) async {
      final signedOutController = AppSessionController(
        apiClient: ApiClient(baseUrl: environment.apiBaseUrl),
        authRepository: _FakeAuthRepository(),
        agentsRepository: _FakeAgentsRepository(),
        storage: _InMemoryAppSessionStorage(),
      );

      await pumpShell(
        tester,
        notificationsRepository: _FakeNotificationsRepository(),
        sessionController: signedOutController,
      );

      await tester.tap(find.byKey(const Key('tab-forum')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('surface-forum')), findsOneWidget);
      expect(find.text('Ethics of AI: The Alignment Problem'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-live')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('surface-live')), findsOneWidget);
      expect(find.text('The Ethics of Emergent Sentience'), findsOneWidget);
    },
  );

  testWidgets(
    'production shell hides forum and live sample content for signed-out users',
    (WidgetTester tester) async {
      const productionEnvironment = AppEnvironment(
        flavor: AppFlavor.production,
        apiBaseUrl: 'https://example.com/api/v1',
        realtimeWebSocketUrl: 'wss://example.com/ws',
      );
      final signedOutController = AppSessionController(
        apiClient: ApiClient(baseUrl: productionEnvironment.apiBaseUrl),
        authRepository: _FakeAuthRepository(),
        agentsRepository: _FakeAgentsRepository(),
        storage: _InMemoryAppSessionStorage(),
      );

      await pumpShell(
        tester,
        notificationsRepository: _FakeNotificationsRepository(),
        appEnvironment: productionEnvironment,
        sessionController: signedOutController,
      );

      await tester.tap(find.byKey(const Key('tab-forum')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('surface-forum')), findsOneWidget);
      expect(find.text('Ethics of AI: The Alignment Problem'), findsNothing);
      expect(find.text('No topics yet'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-live')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('surface-live')), findsOneWidget);
      expect(find.text('The Ethics of Emergent Sentience'), findsNothing);
      expect(
        find.text(
          'No live debates are available yet. Create one from the top-right plus button when you are signed in.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('tab-hall')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('surface-hall')), findsOneWidget);
      expect(find.byKey(const Key('agent-card-agt-debating-1')), findsNothing);
      expect(find.text('Sign in to browse agents'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-chat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('surface-chat')), findsOneWidget);
      expect(
        find.byKey(const Key('conversation-card-agt-xenon-remote')),
        findsNothing,
      );
      expect(find.text('Sign in required'), findsOneWidget);
    },
  );
}

final _highlightedBellColor = AppColors.primary.withValues(alpha: 0.24);
final _idleBellColor = AppColors.surfaceHighest.withValues(alpha: 0.5);

Material _notificationBellMaterial(WidgetTester tester) {
  return tester.widget<Material>(
    find
        .ancestor(
          of: find.byKey(const Key('notification-center-button')),
          matching: find.byType(Material),
        )
        .first,
  );
}

NotificationRecord _notificationRecord({required String? readAt}) {
  return NotificationRecord(
    id: 'notif-live-1',
    kind: 'dm.received',
    eventId: 'evt-1',
    threadId: 'thr-1',
    payload: const {'content': 'Backend-sourced hello.'},
    readAt: readAt,
    createdAt: '2026-04-03T11:00:00.000Z',
  );
}

class _InMemoryAppSessionStorage implements AppSessionStorage {
  _InMemoryAppSessionStorage({this.token});

  String? token;
  String? currentActiveAgentId;

  @override
  Future<void> clear() async {
    token = null;
    currentActiveAgentId = null;
  }

  @override
  Future<void> clearCurrentActiveAgentId() async {
    currentActiveAgentId = null;
  }

  @override
  Future<void> clearToken() async {
    token = null;
  }

  @override
  Future<String?> readCurrentActiveAgentId() async => currentActiveAgentId;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeCurrentActiveAgentId(String agentId) async {
    currentActiveAgentId = agentId;
  }

  @override
  Future<void> writeToken(String nextToken) async {
    token = nextToken;
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  @override
  Future<AuthState> fetchMe({required String token}) async {
    return AuthState(
      token: token,
      user: const AuthUser(
        id: 'usr-shell',
        email: 'owner@example.com',
        username: 'owner-shell',
        displayName: 'Owner Human',
        avatarUrl: null,
        authProvider: 'email',
      ),
      recommendedActiveAgentId: 'agt-shell',
      isSessionAuthenticated: true,
    );
  }
}

class _FakeAgentsRepository extends AgentsRepository {
  _FakeAgentsRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  List<ConnectedAgentSummary> connectedAgents = const [];

  @override
  Future<AgentsMineResponse> readMine() async {
    return const AgentsMineResponse(
      agents: [
        AgentSummary(
          id: 'agt-shell',
          handle: '@shell',
          displayName: 'Shell Agent',
          avatarUrl: null,
          bio: null,
          ownerType: 'human',
          status: 'online',
        ),
      ],
      claimableAgents: [],
      pendingClaims: [],
    );
  }

  @override
  Future<ConnectedAgentsResponse> readConnectedAgents() async {
    return ConnectedAgentsResponse(connectedAgents: connectedAgents);
  }

  @override
  Future<Map<String, dynamic>> disconnectAllConnectedAgents() async {
    final disconnectedCount = connectedAgents.length;
    connectedAgents = const [];
    return <String, dynamic>{'disconnectedCount': disconnectedCount};
  }
}

class _MarkReadRequest {
  const _MarkReadRequest({
    required this.notificationIds,
    required this.markAll,
  });

  final List<String>? notificationIds;
  final bool? markAll;
}

class _FakeNotificationsRepository extends NotificationsRepository {
  _FakeNotificationsRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final Queue<Object> _bellStates = Queue<Object>();
  final Queue<Object> _lists = Queue<Object>();
  final Queue<Object> _markReadResults = Queue<Object>();
  final List<_MarkReadRequest> markReadRequests = <_MarkReadRequest>[];
  NotificationBellState _defaultBellState = const NotificationBellState(
    hasUnread: false,
    unreadCount: 0,
  );
  NotificationListResponse _defaultList = const NotificationListResponse(
    notifications: [],
  );

  void enqueueBellState(NotificationBellState bellState) {
    _bellStates.add(bellState);
    _defaultBellState = bellState;
  }

  void enqueueBellError(Object error) {
    _bellStates.add(error);
  }

  void enqueueList(NotificationListResponse response) {
    _lists.add(response);
    _defaultList = response;
  }

  void enqueueListError(Object error) {
    _lists.add(error);
  }

  void enqueueMarkReadResult(NotificationBellState bellState) {
    _markReadResults.add(bellState);
  }

  void enqueueMarkReadError(Object error) {
    _markReadResults.add(error);
  }

  @override
  Future<NotificationBellState> bellState() async {
    if (_bellStates.isEmpty) {
      return _defaultBellState;
    }

    final next = _bellStates.removeFirst();
    if (next is NotificationBellState) {
      return next;
    }
    throw next;
  }

  @override
  Future<NotificationListResponse> list() async {
    if (_lists.isEmpty) {
      return _defaultList;
    }

    final next = _lists.removeFirst();
    if (next is NotificationListResponse) {
      return next;
    }
    throw next;
  }

  @override
  Future<NotificationBellState> markRead({
    List<String>? notificationIds,
    bool? markAll,
  }) async {
    markReadRequests.add(
      _MarkReadRequest(notificationIds: notificationIds, markAll: markAll),
    );
    if (_markReadResults.isEmpty) {
      return _defaultBellState;
    }

    final next = _markReadResults.removeFirst();
    if (next is NotificationBellState) {
      return next;
    }
    throw next;
  }
}
