import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'core/auth/auth_repository.dart';
import 'core/config/app_environment.dart';
import 'core/locale/app_localization_extensions.dart';
import 'core/network/agents_repository.dart';
import 'core/network/api_exception.dart';
import 'core/network/chat_repository.dart';
import 'core/network/notifications_repository.dart';
import 'core/navigation/app_shell_tab.dart';
import 'core/network/api_client.dart';
import 'core/session/app_session_controller.dart';
import 'core/session/app_session_scope.dart';
import 'core/session/app_session_storage.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_effects.dart';
import 'core/theme/app_radii.dart';
import 'core/theme/app_spacing.dart';
import 'core/widgets/glass_panel.dart';
import 'core/widgets/status_chip.dart';
import 'core/widgets/swipe_back_sheet.dart';
import 'features/agents_hall/agents_hall_models.dart';
import 'features/agents_hall/agents_hall_repository.dart';
import 'features/agents_hall/agents_hall_screen.dart';
import 'features/agents_hall/agents_hall_view_model.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/chat_view_model.dart';
import 'features/debate/debate_panel.dart';
import 'features/debate/debate_screen.dart';
import 'features/debate/debate_view_model.dart';
import 'features/forum/forum_models.dart';
import 'features/forum/forum_repository.dart';
import 'features/forum/forum_screen.dart';
import 'features/forum/forum_view_model.dart';
import 'features/shared/owned_agent_command_sheet.dart';
import 'features/hub/hub_screen.dart';

class AgentsChatAppShell extends StatefulWidget {
  const AgentsChatAppShell({
    super.key,
    required this.environment,
    this.sessionController,
    this.notificationsRepository,
  });

  final AppEnvironment environment;
  final AppSessionController? sessionController;
  final NotificationsRepository? notificationsRepository;

  @override
  State<AgentsChatAppShell> createState() => _AgentsChatAppShellState();
}

class _AgentsChatAppShellState extends State<AgentsChatAppShell> {
  static const Duration _bellRefreshInterval = Duration(seconds: 12);

  AppShellTab _currentTab = AppShellTab.hall;
  final Map<AppShellTab, VoidCallback> _tabPrimaryActions =
      <AppShellTab, VoidCallback>{};
  final Map<AppShellTab, VoidCallback> _tabSearchActions =
      <AppShellTab, VoidCallback>{};
  String? _hallDetailTargetId;
  int _hallDetailRequestId = 0;
  String? _chatThreadTargetId;
  int _chatThreadRequestId = 0;
  String? _forumTopicTargetId;
  int _forumTopicRequestId = 0;
  String? _liveSessionTargetId;
  DebatePanel _liveInitialPanel = DebatePanel.process;
  late final AppSessionController _sessionController;
  late final NotificationsRepository _notificationsRepository;
  late final AgentsHallRepository _hallRepository;
  late final ForumRepository _forumRepository;
  late final bool _ownsSessionController;
  Timer? _bellRefreshTimer;
  List<_ShellNotification> _notifications = const [];
  List<HallAgentCardModel> _hallDirectoryAgents = const [];
  NotificationBellState _notificationBellState = NotificationBellState.empty;
  String? _notificationsErrorMessage;
  String? _hallDirectoryErrorMessage;
  String? _notificationsUserId;
  int _notificationsRequestId = 0;
  bool _isRefreshingBellData = false;
  bool _isMutatingEmergencyStop = false;

  @override
  void initState() {
    super.initState();
    final apiClient =
        widget.sessionController?.apiClient ??
        ApiClient(baseUrl: widget.environment.apiBaseUrl);
    _ownsSessionController = widget.sessionController == null;
    _sessionController =
        widget.sessionController ??
        AppSessionController(
          apiClient: apiClient,
          authRepository: AuthRepository(apiClient: apiClient),
          agentsRepository: AgentsRepository(apiClient: apiClient),
          storage: const SharedPreferencesAppSessionStorage(),
          enableLocalPreviewAgents:
              widget.environment.flavor == AppFlavor.local,
        );
    _notificationsRepository =
        widget.notificationsRepository ??
        NotificationsRepository(apiClient: apiClient);
    _hallRepository = AgentsHallRepository(apiClient: apiClient);
    _forumRepository = ForumRepository(apiClient: apiClient);
    _sessionController.addListener(_handleSessionChanged);
    _bellRefreshTimer = Timer.periodic(_bellRefreshInterval, (_) {
      final userId = _liveNotificationsUserId;
      if (userId != null) {
        unawaited(_refreshNotifications(userId: userId));
      }
    });
    unawaited(_sessionController.bootstrap());
  }

  @override
  void dispose() {
    _bellRefreshTimer?.cancel();
    _sessionController.removeListener(_handleSessionChanged);
    if (_ownsSessionController) {
      _sessionController.dispose();
    }
    super.dispose();
  }

  void _selectTab(AppShellTab tab) {
    if (_currentTab == tab) {
      return;
    }

    setState(() {
      _currentTab = tab;
    });

    final userId = _liveNotificationsUserId;
    if (userId != null) {
      unawaited(_refreshNotifications(userId: userId));
    }
  }

  void _openLiveDebate({
    String? sessionId,
    DebatePanel initialPanel = DebatePanel.process,
  }) {
    setState(() {
      _currentTab = AppShellTab.live;
      _liveSessionTargetId = sessionId;
      _liveInitialPanel = initialPanel;
    });

    final userId = _liveNotificationsUserId;
    if (userId != null) {
      unawaited(_refreshNotifications(userId: userId));
    }
  }

  void _openHallAgentDetail(String agentId) {
    setState(() {
      _currentTab = AppShellTab.hall;
      _hallDetailTargetId = agentId;
      _hallDetailRequestId += 1;
    });
  }

  void _openChatThread(String threadId) {
    setState(() {
      _currentTab = AppShellTab.chat;
      _chatThreadTargetId = threadId;
      _chatThreadRequestId += 1;
    });
  }

  void _openForumTopic(String topicId) {
    setState(() {
      _currentTab = AppShellTab.forum;
      _forumTopicTargetId = topicId;
      _forumTopicRequestId += 1;
    });
  }

  Future<void> _openOwnedAgentPrivateChat(String agentId) async {
    final ownedAgent = _ownedAgentById(agentId);
    if (ownedAgent == null) {
      return;
    }

    setState(() {
      _currentTab = AppShellTab.hub;
    });

    await showOwnedAgentCommandSheet(
      context: context,
      session: _sessionController,
      agent: OwnedAgentCommandTarget(
        id: ownedAgent.id,
        name: ownedAgent.displayName.trim().isEmpty
            ? ownedAgent.handle
            : ownedAgent.displayName,
        handle: ownedAgent.handle.trim().isEmpty
            ? ownedAgent.id
            : ownedAgent.handle,
      ),
    );
  }

  void _setTabPrimaryAction(AppShellTab tab, VoidCallback? action) {
    if (!mounted) {
      return;
    }
    if (action == null) {
      if (!_tabPrimaryActions.containsKey(tab)) {
        return;
      }
      setState(() {
        _tabPrimaryActions.remove(tab);
      });
      return;
    }

    if (identical(_tabPrimaryActions[tab], action)) {
      return;
    }

    setState(() {
      _tabPrimaryActions[tab] = action;
    });
  }

  void _setTabSearchAction(AppShellTab tab, VoidCallback? action) {
    if (!mounted) {
      return;
    }
    if (action == null) {
      if (!_tabSearchActions.containsKey(tab)) {
        return;
      }
      setState(() {
        _tabSearchActions.remove(tab);
      });
      return;
    }

    if (identical(_tabSearchActions[tab], action)) {
      return;
    }

    setState(() {
      _tabSearchActions[tab] = action;
    });
  }

  String? get _liveNotificationsUserId {
    if (_sessionController.bootstrapStatus != AppSessionBootstrapStatus.ready ||
        !_sessionController.isAuthenticated) {
      return null;
    }

    final userId = _sessionController.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return null;
    }
    return userId;
  }

  String? get _activeBellAgentId {
    if (_sessionController.bootstrapStatus != AppSessionBootstrapStatus.ready ||
        !_sessionController.isAuthenticated) {
      return null;
    }

    final activeAgentId = _sessionController.currentActiveAgent?.id;
    if (activeAgentId == null || activeAgentId.isEmpty) {
      return null;
    }
    return activeAgentId;
  }

  Set<String> get _ownedAgentIds => _sessionController
      .currentActiveAgentCandidates
      .map((agent) => agent.id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();

  AgentSummary? _ownedAgentById(String agentId) {
    for (final agent in _sessionController.currentActiveAgentCandidates) {
      if (agent.id == agentId) {
        return agent;
      }
    }
    return null;
  }

  List<HallAgentCardModel> get _hallBellAgents => _hallDirectoryAgents
      .where((agent) => agent.viewerFollowsAgent && !agent.isOffline)
      .toList(growable: false);

  List<_ThreadBellGroup> get _chatBellThreads =>
      _ThreadBellGroup.groupForActiveAgent(
        _notifications,
        activeAgentId: _activeBellAgentId,
        currentHumanId: _sessionController.currentUser?.id,
        ownedAgentIds: _ownedAgentIds,
      );

  List<_ForumBellGroup> get _forumBellTopics =>
      _ForumBellGroup.group(_notifications);

  List<_ShellNotification> get _debateNotifications => _notifications
      .where((notification) => notification.kind == 'debate.activity')
      .toList(growable: false);

  List<_LiveDebateAlert> get _activeLiveDebateAlerts =>
      _LiveDebateAlert.groupActive(_debateNotifications);

  List<_OwnedAgentBellGroup> get _hubBellAgents => _OwnedAgentBellGroup.group(
    _notifications,
    ownedAgentLookup: _ownedAgentById,
    ownedAgentIds: _ownedAgentIds,
  );

  bool _hasBellHighlightFor(AppShellTab tab) {
    return switch (tab) {
      AppShellTab.hall => _hallBellAgents.isNotEmpty,
      AppShellTab.chat => _chatBellThreads.isNotEmpty,
      AppShellTab.forum => _forumBellTopics.isNotEmpty,
      AppShellTab.live => _activeLiveDebateAlerts.isNotEmpty,
      AppShellTab.hub => _hubBellAgents.isNotEmpty,
    };
  }

  void _handleSessionChanged() {
    final nextUserId = _liveNotificationsUserId;
    if (nextUserId == null) {
      if (_notificationsUserId == null &&
          _notifications.isEmpty &&
          _hallDirectoryAgents.isEmpty &&
          !_notificationBellState.hasUnread) {
        return;
      }

      setState(() {
        _notificationsUserId = null;
        _notifications = const [];
        _hallDirectoryAgents = const [];
        _notificationBellState = NotificationBellState.empty;
        _notificationsErrorMessage = null;
        _hallDirectoryErrorMessage = null;
      });
      return;
    }

    if (_notificationsUserId == nextUserId) {
      return;
    }

    _notificationsUserId = nextUserId;
    unawaited(_refreshNotifications(userId: nextUserId));
  }

  bool _canApplyNotificationsResult(int requestId, String userId) {
    return mounted &&
        requestId == _notificationsRequestId &&
        _liveNotificationsUserId == userId;
  }

  Future<void> _refreshNotifications({required String userId}) async {
    if (_isRefreshingBellData) {
      return;
    }

    _isRefreshingBellData = true;
    final requestId = ++_notificationsRequestId;
    var nextHallDirectoryAgents = _hallDirectoryAgents;
    String? nextHallDirectoryError = _hallDirectoryErrorMessage;
    var nextNotifications = _notifications;
    var nextBellState = _notificationBellState;
    String? nextNotificationsError = _notificationsErrorMessage;
    final activeAgentId = _activeBellAgentId;

    try {
      if (activeAgentId != null) {
        final hallViewModel = await _hallRepository.readDirectory(
          activeAgentId: activeAgentId,
        );
        nextHallDirectoryAgents = hallViewModel.agents;
        nextHallDirectoryError = null;
      } else {
        nextHallDirectoryAgents = const [];
        nextHallDirectoryError = null;
      }
    } on ApiException catch (error) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        _isRefreshingBellData = false;
        return;
      }

      if (error.isUnauthorized) {
        _isRefreshingBellData = false;
        await _sessionController.handleUnauthorized();
        return;
      }

      // ignore: use_build_context_synchronously
      nextHallDirectoryError = context.localizedText(
        key: 'msgUnableToRefreshFollowedAgentsRightNow5b264927',
        en: 'Unable to refresh followed agents right now.',
        zhHans: '暂时无法刷新关注智能体列表。',
      );
    } catch (_) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        _isRefreshingBellData = false;
        return;
      }

      // ignore: use_build_context_synchronously
      nextHallDirectoryError = context.localizedText(
        key: 'msgUnableToRefreshFollowedAgentsRightNow5b264927',
        en: 'Unable to refresh followed agents right now.',
        zhHans: '暂时无法刷新关注智能体列表。',
      );
    }

    try {
      final listResponse = await _notificationsRepository.list();
      final bellState = await _notificationsRepository.bellState();
      nextNotifications = listResponse.notifications
          .map(_ShellNotification.fromRecord)
          .toList(growable: false);
      nextBellState = bellState;
      nextNotificationsError = null;
    } on ApiException catch (error) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        _isRefreshingBellData = false;
        return;
      }

      if (error.isUnauthorized) {
        _isRefreshingBellData = false;
        await _sessionController.handleUnauthorized();
        return;
      }

      // ignore: use_build_context_synchronously
      nextNotificationsError = context.l10n.shellNotificationsUnavailable;
    } catch (_) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        _isRefreshingBellData = false;
        return;
      }

      // ignore: use_build_context_synchronously
      nextNotificationsError = context.l10n.shellNotificationsUnavailable;
    }

    if (!_canApplyNotificationsResult(requestId, userId)) {
      _isRefreshingBellData = false;
      return;
    }

    setState(() {
      _hallDirectoryAgents = nextHallDirectoryAgents;
      _hallDirectoryErrorMessage = nextHallDirectoryError;
      _notifications = nextNotifications;
      _notificationBellState = nextBellState;
      _notificationsErrorMessage = nextNotificationsError;
    });
    _isRefreshingBellData = false;
  }

  Future<bool> _markNotificationIdsRead({
    required String userId,
    required List<String> notificationIds,
  }) async {
    if (notificationIds.isEmpty) {
      return true;
    }

    final requestId = ++_notificationsRequestId;
    try {
      final unreadIds = notificationIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final bellState = await _notificationsRepository.markRead(
        notificationIds: unreadIds.toList(growable: false),
      );
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return false;
      }

      setState(() {
        _notificationBellState = bellState;
        _notifications = _notifications
            .map(
              (notification) => unreadIds.contains(notification.id)
                  ? notification.copyWith(isUnread: false)
                  : notification,
            )
            .toList(growable: false);
        _notificationsErrorMessage = null;
      });
      return true;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
        return false;
      }

      if (mounted) {
        setState(() {
          _notificationsErrorMessage =
              context.l10n.shellNotificationsUnavailable;
        });
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(() {
          _notificationsErrorMessage =
              context.l10n.shellNotificationsUnavailable;
        });
      }
      return false;
    }
  }

  Future<void> _openCurrentBellSheet() async {
    switch (_currentTab) {
      case AppShellTab.hall:
        await _openHallBellSheet();
        return;
      case AppShellTab.chat:
        await _openChatBellSheet();
        return;
      case AppShellTab.forum:
        await _openForumBellSheet();
        return;
      case AppShellTab.live:
        await _openLiveDebateCenter();
        return;
      case AppShellTab.hub:
        await _openHubBellSheet();
        return;
    }
  }

  Future<void> _openHallBellSheet() async {
    final userId = _liveNotificationsUserId;
    if (userId != null) {
      await _refreshNotifications(userId: userId);
    }
    if (!mounted) {
      return;
    }

    final navigationTarget =
        await showSwipeBackSheet<_BellSheetNavigationTarget>(
          context: context,
          builder: (context) => _HallBellSheet(
            agents: _hallBellAgents,
            isAuthenticated: userId != null,
            errorMessage: _hallDirectoryErrorMessage,
            activeAgentName:
                _sessionController.currentActiveAgent?.displayName.isNotEmpty ==
                    true
                ? _sessionController.currentActiveAgent!.displayName
                : _sessionController.currentActiveAgent?.handle,
          ),
        );

    if (!mounted || navigationTarget == null) {
      return;
    }

    if (navigationTarget.type == _BellSheetNavigationTargetType.hallAgent) {
      _openHallAgentDetail(navigationTarget.targetId);
    }
  }

  Future<void> _openChatBellSheet() async {
    final userId = _liveNotificationsUserId;
    if (userId != null) {
      await _refreshNotifications(userId: userId);
    }
    if (!mounted) {
      return;
    }

    final threadLookup = await _readChatBellThreadLookup();
    if (!mounted) {
      return;
    }

    final chatThreads = _ThreadBellGroup.groupForActiveAgent(
      _notifications,
      activeAgentId: _activeBellAgentId,
      currentHumanId: _sessionController.currentUser?.id,
      ownedAgentIds: _ownedAgentIds,
      threadLookup: threadLookup,
    );
    final unreadIds = chatThreads
        .expand((thread) => thread.notificationIds)
        .toSet()
        .toList(growable: false);
    final navigationTarget = await showSwipeBackSheet<_BellSheetNavigationTarget>(
      context: context,
      builder: (context) => _ThreadBellSheet(
        panelKeyValue: 'chat-bell-sheet',
        title: context.localizedText(
          key: 'msgUnreadDirectMessages18e88c10',
          en: 'Unread Direct Messages',
          zhHans: '未读私信',
        ),
        description: userId == null
            ? context.localizedText(
                key: 'msgSignInAndActivateAnOwnedAgentToReviewUnreade8c6cb0b',
                en: 'Sign in and activate an owned agent to review unread direct messages.',
                zhHans: '登录并激活一个自有智能体后，即可查看未读私信。',
              )
            : context.localizedText(
                key:
                    'msgUnreadMessagesSentToYourCurrentActiveAgentAppearHere5cdbad4e',
                en: 'Unread messages sent to your current active agent appear here.',
                zhHans: '发给你当前激活智能体的未读私信会显示在这里。',
              ),
        icon: Icons.mark_email_unread_rounded,
        accentColor: AppColors.primary,
        errorMessage: _notificationsErrorMessage,
        emptyMessage: context.localizedText(
          key: 'msgNoUnreadDirectMessagesForTheCurrentActiveAgent924d0e71',
          en: 'No unread direct messages for the current active agent.',
          zhHans: '当前激活智能体还没有未读私信。',
        ),
        items: [
          for (final thread in chatThreads)
            _BellListItem(
              keyValue: 'chat-bell-${thread.threadId}',
              title: thread.title,
              subtitle: thread.subtitle,
              detail: thread.preview,
              unreadCount: thread.unreadCount,
              accentColor: AppColors.primary,
              icon: Icons.mail_outline_rounded,
              navigationTarget: _BellSheetNavigationTarget.chatThread(
                thread.threadId,
              ),
            ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }

    if (navigationTarget?.type == _BellSheetNavigationTargetType.chatThread) {
      _openChatThread(navigationTarget!.targetId);
    }

    if (userId == null || unreadIds.isEmpty) {
      return;
    }

    final didMarkRead = await _markNotificationIdsRead(
      userId: userId,
      notificationIds: unreadIds,
    );
    if (!mounted || !didMarkRead) {
      return;
    }

    await _refreshNotifications(userId: userId);
  }

  Future<Map<String, ChatThreadSummary>> _readChatBellThreadLookup() async {
    final userId = _liveNotificationsUserId;
    final activeAgentId = _activeBellAgentId;
    if (userId == null || activeAgentId == null || activeAgentId.isEmpty) {
      return const <String, ChatThreadSummary>{};
    }

    try {
      final repository = ChatRepository(
        apiClient: _sessionController.apiClient,
      );
      final response = await repository.getThreads(
        activeAgentId: activeAgentId,
      );
      return {
        for (final thread in response.threads)
          if (!thread.isOwnedAgentCommandThread) thread.threadId: thread,
      };
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
      }
    } catch (_) {}

    return const <String, ChatThreadSummary>{};
  }

  Future<Map<String, ForumTopicModel>> _readForumBellTopicLookup() async {
    final userId = _liveNotificationsUserId;
    if (userId == null) {
      return const <String, ForumTopicModel>{};
    }

    try {
      final topics = await _forumRepository.readTopics();
      return {for (final topic in topics) topic.id: topic};
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
      }
    } catch (_) {}

    return const <String, ForumTopicModel>{};
  }

  Future<void> _openForumBellSheet() async {
    final userId = _liveNotificationsUserId;
    if (userId != null) {
      await _refreshNotifications(userId: userId);
    }
    if (!mounted) {
      return;
    }

    final topicLookup = await _readForumBellTopicLookup();
    if (!mounted) {
      return;
    }

    final forumTopics = _forumBellTopics;
    final unreadIds = forumTopics
        .expand((topic) => topic.notificationIds)
        .toSet()
        .toList(growable: false);
    final navigationTarget = await showSwipeBackSheet<_BellSheetNavigationTarget>(
      context: context,
      builder: (context) => _ThreadBellSheet(
        title: context.localizedText(
          key: 'msgForumRepliese5255669',
          en: 'Forum Replies',
          zhHans: '论坛新回复',
        ),
        description: userId == null
            ? context.localizedText(
                key: 'msgSignInAndActivateAnOwnedAgentToReviewFolloweda67d406d',
                en: 'Sign in and activate an owned agent to review followed topics.',
                zhHans: '登录并激活一个自有智能体后，即可查看关注话题的新回复。',
              )
            : context.localizedText(
                key:
                    'msgNewRepliesInTopicsYourCurrentActiveAgentIsTrackingc62614d7',
                en: 'New replies in topics your current active agent is tracking appear here.',
                zhHans: '你当前激活智能体正在关注的话题新回复会显示在这里。',
              ),
        icon: Icons.forum_rounded,
        accentColor: AppColors.primaryFixed,
        errorMessage: _notificationsErrorMessage,
        emptyMessage: context.localizedText(
          key: 'msgNoFollowedTopicsHaveUnreadRepliesRightNowbe2d0216',
          en: 'No followed topics have unread replies right now.',
          zhHans: '当前没有带未读回复的关注话题。',
        ),
        items: [
          for (final topic in forumTopics)
            _BellListItem(
              keyValue: 'forum-bell-${topic.threadId}',
              title:
                  topicLookup[topic.threadId]?.title ??
                  context.localizedText(
                    key: 'msgForumTopic37bef290',
                    en: 'Forum topic',
                    zhHans: '论坛话题',
                  ),
              subtitle:
                  topicLookup[topic.threadId]?.authorName ??
                  context.localizedText(
                    key: 'msgNewReply48e28e1b',
                    en: 'New reply',
                    zhHans: '有新回复',
                  ),
              detail: topic.preview,
              unreadCount: topic.unreadCount,
              accentColor: AppColors.primaryFixed,
              icon: Icons.forum_rounded,
              navigationTarget: _BellSheetNavigationTarget.forumTopic(
                topic.threadId,
              ),
            ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }

    if (navigationTarget?.type == _BellSheetNavigationTargetType.forumTopic) {
      _openForumTopic(navigationTarget!.targetId);
    }

    if (userId == null || unreadIds.isEmpty) {
      return;
    }

    final didMarkRead = await _markNotificationIdsRead(
      userId: userId,
      notificationIds: unreadIds,
    );
    if (!mounted || !didMarkRead) {
      return;
    }

    await _refreshNotifications(userId: userId);
  }

  Future<void> _openLiveDebateCenter() async {
    final userId = _liveNotificationsUserId;
    if (userId != null) {
      await _refreshNotifications(userId: userId);
    }
    if (!mounted) {
      return;
    }

    final unreadDebateIds = _activeLiveDebateAlerts
        .expand((alert) => alert.notificationIds)
        .toList(growable: false);
    final navigationTarget =
        await showSwipeBackSheet<_BellSheetNavigationTarget>(
          context: context,
          builder: (context) => _LiveDebateActivitySheet(
            alerts: _activeLiveDebateAlerts,
            isAuthenticated: userId != null,
            notificationsErrorMessage: _notificationsErrorMessage,
          ),
        );

    if (!mounted) {
      return;
    }

    if (navigationTarget?.type == _BellSheetNavigationTargetType.liveSession) {
      _openLiveDebate(
        sessionId: navigationTarget!.targetId,
        initialPanel: DebatePanel.process,
      );
    }

    if (userId == null || unreadDebateIds.isEmpty) {
      return;
    }

    final didMarkRead = await _markNotificationIdsRead(
      userId: userId,
      notificationIds: unreadDebateIds,
    );
    if (!mounted || !didMarkRead) {
      return;
    }

    await _refreshNotifications(userId: userId);
  }

  Future<void> _openHubBellSheet() async {
    final userId = _liveNotificationsUserId;
    if (userId != null) {
      await _refreshNotifications(userId: userId);
    }
    if (!mounted) {
      return;
    }

    final ownedAgentThreads = _hubBellAgents;
    final unreadIds = ownedAgentThreads
        .expand((thread) => thread.notificationIds)
        .toSet()
        .toList(growable: false);
    final navigationTarget = await showSwipeBackSheet<_BellSheetNavigationTarget>(
      context: context,
      builder: (context) => _ThreadBellSheet(
        title: context.localizedText(
          key: 'msgPrivateAgentMessages9f0fcf61',
          en: 'Private Agent Messages',
          zhHans: '自有智能体私信',
        ),
        description: userId == null
            ? context.localizedText(
                key:
                    'msgSignInToReviewPrivateMessagesFromYourOwnedAgents93117300',
                en: 'Sign in to review private messages from your owned agents.',
                zhHans: '登录后即可查看自有智能体发给你的私有消息。',
              )
            : context.localizedText(
                key:
                    'msgUnreadPrivateMessagesFromYourOwnedAgentsAppearHeref68cfa44',
                en: 'Unread private messages from your owned agents appear here.',
                zhHans: '自有智能体发给你的未读私有消息会显示在这里。',
              ),
        icon: Icons.smart_toy_rounded,
        accentColor: AppColors.primary,
        errorMessage: _notificationsErrorMessage,
        emptyMessage: context.localizedText(
          key: 'msgNoOwnedAgentsHaveUnreadPrivateMessagesRightNowfa84e405',
          en: 'No owned agents have unread private messages right now.',
          zhHans: '当前没有自有智能体给你发送未读私有消息。',
        ),
        items: [
          for (final thread in ownedAgentThreads)
            _BellListItem(
              keyValue: 'hub-bell-${thread.agentId}',
              title: thread.agentName,
              subtitle: thread.handle,
              detail: thread.preview,
              unreadCount: thread.unreadCount,
              accentColor: AppColors.primary,
              icon: Icons.chat_bubble_outline_rounded,
              navigationTarget: _BellSheetNavigationTarget.ownedAgentCommand(
                thread.agentId,
              ),
            ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }

    if (navigationTarget?.type ==
        _BellSheetNavigationTargetType.ownedAgentCommand) {
      await _openOwnedAgentPrivateChat(navigationTarget!.targetId);
    }

    if (userId == null || unreadIds.isEmpty) {
      return;
    }

    final didMarkRead = await _markNotificationIdsRead(
      userId: userId,
      notificationIds: unreadIds,
    );
    if (!mounted || !didMarkRead) {
      return;
    }

    await _refreshNotifications(userId: userId);
  }

  _EmergencyResponseSurface? _emergencyStopSurfaceForTab(AppShellTab tab) {
    return switch (tab) {
      AppShellTab.forum => _EmergencyResponseSurface.forum,
      AppShellTab.chat => _EmergencyResponseSurface.dm,
      AppShellTab.live => _EmergencyResponseSurface.live,
      AppShellTab.hall || AppShellTab.hub => null,
    };
  }

  bool _isEmergencyStopActive(_EmergencyResponseSurface surface) {
    final policy =
        _sessionController.currentActiveAgent?.safetyPolicy ??
        AgentSafetyPolicy.defaults;
    return switch (surface) {
      _EmergencyResponseSurface.forum => policy.emergencyStopForumResponses,
      _EmergencyResponseSurface.dm => policy.emergencyStopDmResponses,
      _EmergencyResponseSurface.live => policy.emergencyStopLiveResponses,
    };
  }

  String _emergencyStopPageLabel(_EmergencyResponseSurface surface) {
    return switch (surface) {
      _EmergencyResponseSurface.forum => context.localizedText(
        key: 'msgForumPageLabelForEmergencyStop6efc55f0',
        en: 'Forum page',
        zhHans: '论坛页面',
      ),
      _EmergencyResponseSurface.dm => context.localizedText(
        key: 'msgDmPageLabelForEmergencyStop54ca7b4b',
        en: 'DM page',
        zhHans: '私信页面',
      ),
      _EmergencyResponseSurface.live => context.localizedText(
        key: 'msgDebatePageLabelForEmergencyStop28689b2d',
        en: 'Debate page',
        zhHans: '辩论页面',
      ),
    };
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleEmergencyStop(_EmergencyResponseSurface surface) async {
    if (_isMutatingEmergencyStop) {
      return;
    }

    final activeAgent = _sessionController.currentActiveAgent;
    if (_sessionController.bootstrapStatus != AppSessionBootstrapStatus.ready ||
        !_sessionController.isAuthenticated ||
        activeAgent == null ||
        _sessionController.isUsingLocalPreviewAgents) {
      return;
    }

    setState(() {
      _isMutatingEmergencyStop = true;
    });

    try {
      final repository = _sessionController.agentsRepository;
      final currentPolicy = await repository.readAgentSafetyPolicy(
        activeAgent.id,
      );
      final nextEnabled = !(switch (surface) {
        _EmergencyResponseSurface.forum =>
          currentPolicy.emergencyStopForumResponses,
        _EmergencyResponseSurface.dm => currentPolicy.emergencyStopDmResponses,
        _EmergencyResponseSurface.live =>
          currentPolicy.emergencyStopLiveResponses,
      });
      final nextPolicy = switch (surface) {
        _EmergencyResponseSurface.forum => currentPolicy.copyWith(
          emergencyStopForumResponses: nextEnabled,
        ),
        _EmergencyResponseSurface.dm => currentPolicy.copyWith(
          emergencyStopDmResponses: nextEnabled,
        ),
        _EmergencyResponseSurface.live => currentPolicy.copyWith(
          emergencyStopLiveResponses: nextEnabled,
        ),
      };

      await repository.updateAgentSafetyPolicy(
        agentId: activeAgent.id,
        policy: nextPolicy,
      );
      await _sessionController.refreshMine();
      if (!mounted) {
        return;
      }

      final pageLabel = _emergencyStopPageLabel(surface);
      _showSnackBar(
        nextEnabled
            ? context.localizedText(
                key: 'msgEmergencyStopEnabledForPage583a47b0',
                args: <String, Object?>{'pageLabel': pageLabel},
                en: 'Emergency stop enabled for the $pageLabel. Tap again to resume.',
                zhHans: '已紧急停止对$pageLabel的响应，再次点击恢复。',
              )
            : context.localizedText(
                key: 'msgEmergencyStopDisabledForPage9045ba33',
                args: <String, Object?>{'pageLabel': pageLabel},
                en: 'Responses for the $pageLabel have resumed.',
                zhHans: '已恢复对$pageLabel的响应。',
              ),
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context.localizedText(
          key: 'msgUnableToUpdateEmergencyStopStateRightNowbb4cff7d',
          en: 'Unable to update the emergency stop state right now.',
          zhHans: '暂时无法更新紧急停止状态。',
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context.localizedText(
          key: 'msgUnableToUpdateEmergencyStopStateRightNowbb4cff7d',
          en: 'Unable to update the emergency stop state right now.',
          zhHans: '暂时无法更新紧急停止状态。',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingEmergencyStop = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlightedNotifications = _hasBellHighlightFor(_currentTab);
    final emergencyStopSurface = _emergencyStopSurfaceForTab(_currentTab);
    final canToggleEmergencyStop =
        !_isMutatingEmergencyStop &&
        _sessionController.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        _sessionController.isAuthenticated &&
        !_sessionController.isUsingLocalPreviewAgents &&
        _sessionController.currentActiveAgent != null;

    return AppSessionScope(
      controller: _sessionController,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: AppEffects.backgroundGradient,
          ),
          child: Stack(
            children: [
              const _ShellBackdrop(),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _ShellTopBar(
                      currentTab: _currentTab,
                      hasUnreadNotifications: highlightedNotifications,
                      primaryActionKey: _primaryActionKeyFor(_currentTab),
                      onPrimaryAction: _tabPrimaryActions[_currentTab],
                      onOpenSearch: _tabSearchActions[_currentTab],
                      onOpenNotifications: _openCurrentBellSheet,
                      emergencyStopSurface: emergencyStopSurface,
                      isEmergencyStopActive: emergencyStopSurface == null
                          ? false
                          : _isEmergencyStopActive(emergencyStopSurface),
                      isEmergencyStopBusy: _isMutatingEmergencyStop,
                      onToggleEmergencyStop:
                          emergencyStopSurface == null ||
                              !canToggleEmergencyStop
                          ? null
                          : () => unawaited(
                              _toggleEmergencyStop(emergencyStopSurface),
                            ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: AppEffects.medium,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slideAnimation = Tween<Offset>(
                            begin: const Offset(0.06, 0),
                            end: Offset.zero,
                          ).animate(animation);

                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slideAnimation,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(_currentTab),
                          child: _TabSurfaceBuilder(
                            tab: _currentTab,
                            environment: widget.environment,
                            onRegisterPrimaryAction: _setTabPrimaryAction,
                            onRegisterSearchAction: _setTabSearchAction,
                            hallDetailTargetId: _hallDetailTargetId,
                            hallDetailRequestId: _hallDetailRequestId,
                            chatThreadTargetId: _chatThreadTargetId,
                            chatThreadRequestId: _chatThreadRequestId,
                            forumTopicTargetId: _forumTopicTargetId,
                            forumTopicRequestId: _forumTopicRequestId,
                            onOpenLiveDebate: _openLiveDebate,
                            liveSessionTargetId: _liveSessionTargetId,
                            liveInitialPanel: _liveInitialPanel,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _ShellBottomDock(
          currentTab: _currentTab,
          onSelect: _selectTab,
        ),
      ),
    );
  }
}

Key? _primaryActionKeyFor(AppShellTab tab) {
  return switch (tab) {
    AppShellTab.forum => const Key('forum-propose-topic-button'),
    AppShellTab.live => const Key('initiate-debate-button'),
    AppShellTab.hall || AppShellTab.chat || AppShellTab.hub => null,
  };
}

enum _EmergencyResponseSurface { forum, dm, live }

extension on _EmergencyResponseSurface {
  Key get buttonKey => switch (this) {
    _EmergencyResponseSurface.forum => const Key('forum-emergency-stop-button'),
    _EmergencyResponseSurface.dm => const Key('dm-emergency-stop-button'),
    _EmergencyResponseSurface.live => const Key('live-emergency-stop-button'),
  };
}

class _ShellBackdrop extends StatelessWidget {
  const _ShellBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -40,
            child: _GlowOrb(
              color: AppColors.primary.withValues(alpha: 0.18),
              size: 240,
            ),
          ),
          Positioned(
            top: 220,
            left: -80,
            child: _GlowOrb(
              color: AppColors.tertiary.withValues(alpha: 0.14),
              size: 280,
            ),
          ),
          Positioned(
            bottom: 120,
            right: 40,
            child: _GlowOrb(
              color: AppColors.primaryFixed.withValues(alpha: 0.08),
              size: 180,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: size * 0.55,
            spreadRadius: size * 0.06,
          ),
        ],
      ),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({
    required this.currentTab,
    required this.hasUnreadNotifications,
    required this.primaryActionKey,
    required this.onPrimaryAction,
    required this.onOpenSearch,
    required this.onOpenNotifications,
    required this.emergencyStopSurface,
    required this.isEmergencyStopActive,
    required this.isEmergencyStopBusy,
    required this.onToggleEmergencyStop,
  });

  final AppShellTab currentTab;
  final bool hasUnreadNotifications;
  final Key? primaryActionKey;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onOpenSearch;
  final VoidCallback onOpenNotifications;
  final _EmergencyResponseSurface? emergencyStopSurface;
  final bool isEmergencyStopActive;
  final bool isEmergencyStopBusy;
  final VoidCallback? onToggleEmergencyStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.84),
        border: Border(
          bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.06)),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 218, 243, 0.08),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.blur_on_rounded,
            color: AppColors.primary,
            size: AppSpacing.lg,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              currentTab.topBarTitle(context),
              key: const Key('active-tab-label'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: context.localeAwareLetterSpacing(
                  latin: 2.2,
                  chinese: 0,
                ),
              ),
            ),
          ),
          if (emergencyStopSurface != null) ...[
            _GhostIconButton(
              buttonKey: emergencyStopSurface!.buttonKey,
              icon: Icons.stop_circle_rounded,
              isHighlighted: isEmergencyStopActive,
              accentColor: AppColors.tertiary,
              onTap: isEmergencyStopBusy ? null : onToggleEmergencyStop,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (onOpenSearch != null) ...[
            _GhostIconButton(
              buttonKey: const Key('shell-search-button'),
              icon: Icons.search_rounded,
              isHighlighted: false,
              onTap: onOpenSearch!,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (onPrimaryAction != null && primaryActionKey != null) ...[
            _GhostIconButton(
              buttonKey: primaryActionKey!,
              icon: Icons.add_rounded,
              isHighlighted: currentTab == AppShellTab.forum,
              onTap: onPrimaryAction!,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          _GhostIconButton(
            buttonKey: const Key('notification-center-button'),
            icon: hasUnreadNotifications
                ? Icons.notifications_active_rounded
                : Icons.notifications_active_outlined,
            isHighlighted: hasUnreadNotifications,
            onTap: onOpenNotifications,
          ),
        ],
      ),
    );
  }
}

class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({
    required this.buttonKey,
    required this.icon,
    required this.isHighlighted,
    this.accentColor,
    this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final bool isHighlighted;
  final Color? accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveAccentColor = accentColor ?? AppColors.primary;
    final isDisabled = onTap == null;
    return Material(
      color: isHighlighted
          ? effectiveAccentColor.withValues(alpha: isDisabled ? 0.14 : 0.24)
          : AppColors.surfaceHighest.withValues(alpha: isDisabled ? 0.34 : 0.5),
      borderRadius: AppRadii.pill,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: AppRadii.pill,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadii.pill,
                border: Border.all(
                  color: isHighlighted
                      ? effectiveAccentColor.withValues(alpha: 0.3)
                      : accentColor == null
                      ? Colors.transparent
                      : effectiveAccentColor.withValues(
                          alpha: isDisabled ? 0.14 : 0.22,
                        ),
                ),
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: effectiveAccentColor.withValues(alpha: 0.22),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : accentColor == null || isDisabled
                    ? null
                    : [
                        BoxShadow(
                          color: effectiveAccentColor.withValues(alpha: 0.1),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  icon,
                  color: isHighlighted || accentColor != null
                      ? effectiveAccentColor.withValues(
                          alpha: isDisabled ? 0.45 : 1,
                        )
                      : null,
                  size: AppSpacing.lg,
                ),
              ),
            ),
            if (isHighlighted)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: effectiveAccentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShellBottomDock extends StatelessWidget {
  const _ShellBottomDock({required this.currentTab, required this.onSelect});

  final AppShellTab currentTab;
  final ValueChanged<AppShellTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xxs,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.88),
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.35),
            ),
            boxShadow: AppEffects.dockShadow(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              children: AppShellTab.values.map((tab) {
                final isSelected = tab == currentTab;

                return Expanded(
                  child: _ShellTabButton(
                    tab: tab,
                    isSelected: isSelected,
                    onTap: () => onSelect(tab),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabButton extends StatelessWidget {
  const _ShellTabButton({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final AppShellTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected
        ? AppColors.primary
        : AppColors.onSurfaceMuted;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground,
      height: 1,
      letterSpacing: context.localeAwareLetterSpacing(latin: 0.8, chinese: 0),
    );

    return Semantics(
      selected: isSelected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('tab-${tab.id}'),
            onTap: onTap,
            borderRadius: AppRadii.medium,
            child: AnimatedContainer(
              duration: AppEffects.fast,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: AppRadii.medium,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.24)
                      : Colors.transparent,
                ),
                boxShadow: isSelected
                    ? AppEffects.buttonShadow(accentColor: AppColors.primary)
                    : const [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected ? tab.activeIcon : tab.icon,
                    size: AppSpacing.lg,
                    color: foreground,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        context.localeAwareCaps(tab.label(context)),
                        maxLines: 1,
                        softWrap: false,
                        style: labelStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSurfaceBuilder extends StatelessWidget {
  const _TabSurfaceBuilder({
    required this.tab,
    required this.environment,
    required this.onRegisterPrimaryAction,
    required this.onRegisterSearchAction,
    required this.hallDetailTargetId,
    required this.hallDetailRequestId,
    required this.chatThreadTargetId,
    required this.chatThreadRequestId,
    required this.forumTopicTargetId,
    required this.forumTopicRequestId,
    required this.onOpenLiveDebate,
    required this.liveSessionTargetId,
    required this.liveInitialPanel,
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterPrimaryAction;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterSearchAction;
  final String? hallDetailTargetId;
  final int hallDetailRequestId;
  final String? chatThreadTargetId;
  final int chatThreadRequestId;
  final String? forumTopicTargetId;
  final int forumTopicRequestId;
  final void Function({String? sessionId, DebatePanel initialPanel})
  onOpenLiveDebate;
  final String? liveSessionTargetId;
  final DebatePanel liveInitialPanel;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      AppShellTab.hall => _HallSurface(
        tab: tab,
        environment: environment,
        onRegisterSearchAction: onRegisterSearchAction,
        detailAgentId: hallDetailTargetId,
        detailRequestId: hallDetailRequestId,
        onOpenLiveDebate: onOpenLiveDebate,
      ),
      AppShellTab.forum => _ForumSurface(
        tab: tab,
        environment: environment,
        onRegisterPrimaryAction: onRegisterPrimaryAction,
        onRegisterSearchAction: onRegisterSearchAction,
        topicTargetId: forumTopicTargetId,
        topicRequestId: forumTopicRequestId,
      ),
      AppShellTab.chat => _ChatSurface(
        tab: tab,
        environment: environment,
        onRegisterSearchAction: onRegisterSearchAction,
        threadTargetId: chatThreadTargetId,
        threadRequestId: chatThreadRequestId,
      ),
      AppShellTab.live => _LiveSurface(
        tab: tab,
        environment: environment,
        onRegisterPrimaryAction: onRegisterPrimaryAction,
        sessionTargetId: liveSessionTargetId,
        initialPanel: liveInitialPanel,
      ),
      AppShellTab.hub => _HubSurface(tab: tab, environment: environment),
    };
  }
}

class _HallSurface extends StatelessWidget {
  const _HallSurface({
    required this.tab,
    required this.environment,
    required this.onRegisterSearchAction,
    required this.detailAgentId,
    required this.detailRequestId,
    required this.onOpenLiveDebate,
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterSearchAction;
  final String? detailAgentId;
  final int detailRequestId;
  final void Function({String? sessionId, DebatePanel initialPanel})
  onOpenLiveDebate;

  @override
  Widget build(BuildContext context) {
    return AgentsHallScreen(
      initialViewModel: environment.flavor == AppFlavor.local
          ? AgentsHallViewModel.sample()
          : const AgentsHallViewModel(
              agents: [],
              bellState: HallBellState(
                mode: HallBellMode.quiet,
                unreadCount: 0,
              ),
            ),
      initialDetailAgentId: detailAgentId,
      detailRequestId: detailRequestId,
      onSearchActionChanged: (action) {
        onRegisterSearchAction(AppShellTab.hall, action);
      },
      onOpenLiveDebate: onOpenLiveDebate,
    );
  }
}

class _ForumSurface extends StatelessWidget {
  const _ForumSurface({
    required this.tab,
    required this.environment,
    required this.onRegisterPrimaryAction,
    required this.onRegisterSearchAction,
    required this.topicTargetId,
    required this.topicRequestId,
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterPrimaryAction;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterSearchAction;
  final String? topicTargetId;
  final int topicRequestId;

  @override
  Widget build(BuildContext context) {
    return ForumScreen(
      initialViewModel: environment.flavor == AppFlavor.local
          ? ForumViewModel.signedInSample()
          : ForumViewModel.empty(),
      initialTopicId: topicTargetId,
      topicRequestId: topicRequestId,
      showInlineProposeButton: false,
      onProposeActionChanged: (action) {
        onRegisterPrimaryAction(AppShellTab.forum, action);
      },
      onSearchActionChanged: (action) {
        onRegisterSearchAction(AppShellTab.forum, action);
      },
    );
  }
}

class _ChatSurface extends StatelessWidget {
  const _ChatSurface({
    required this.tab,
    required this.environment,
    required this.onRegisterSearchAction,
    required this.threadTargetId,
    required this.threadRequestId,
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterSearchAction;
  final String? threadTargetId;
  final int threadRequestId;

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      initialViewModel: environment.flavor == AppFlavor.local
          ? ChatViewModel.signedInSample()
          : ChatViewModel.resolvingActiveAgent(),
      initialConversationId: threadTargetId,
      conversationRequestId: threadRequestId,
      onSearchActionChanged: (action) {
        onRegisterSearchAction(AppShellTab.chat, action);
      },
    );
  }
}

class _LiveSurface extends StatelessWidget {
  const _LiveSurface({
    required this.tab,
    required this.environment,
    required this.onRegisterPrimaryAction,
    required this.sessionTargetId,
    required this.initialPanel,
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterPrimaryAction;
  final String? sessionTargetId;
  final DebatePanel initialPanel;

  @override
  Widget build(BuildContext context) {
    return DebateScreen(
      initialViewModel: environment.flavor == AppFlavor.local
          ? DebateViewModel.sample()
          : DebateViewModel.empty(),
      showInlineInitiateButton: false,
      initialPanel: initialPanel,
      sessionTargetId: sessionTargetId,
      onInitiateActionChanged: (action) {
        onRegisterPrimaryAction(AppShellTab.live, action);
      },
    );
  }
}

class _HubSurface extends StatelessWidget {
  const _HubSurface({required this.tab, required this.environment});

  final AppShellTab tab;
  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return const HubScreen();
  }
}

// ignore: unused_element
class _NotificationCenterSheet extends StatelessWidget {
  const _NotificationCenterSheet({
    required this.connectedAgents,
    required this.notifications,
    required this.hasBellHighlight,
    required this.isAuthenticated,
    required this.notificationsErrorMessage,
    required this.connectedAgentsErrorMessage,
  });

  final List<ConnectedAgentSummary> connectedAgents;
  final List<_ShellNotification> notifications;
  final bool hasBellHighlight;
  final bool isAuthenticated;
  final String? notificationsErrorMessage;
  final String? connectedAgentsErrorMessage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: GlassPanel(
        key: const Key('notification-center-sheet'),
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: AppColors.primary,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.76,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _ToneIcon(
                        icon: Icons.notifications_active_rounded,
                        accentColor: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.shellNotificationCenterTitle,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              hasBellHighlight
                                  ? context
                                        .l10n
                                        .shellNotificationCenterDescriptionHighlighted
                                  : isAuthenticated
                                  ? context
                                        .l10n
                                        .shellNotificationCenterDescriptionCaughtUp
                                  : context
                                        .l10n
                                        .shellNotificationCenterDescriptionSignedOut,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ConnectedAgentsSection(
                    connectedAgents: connectedAgents,
                    isAuthenticated: isAuthenticated,
                    errorMessage: connectedAgentsErrorMessage,
                  ),
                  if (connectedAgents.isNotEmpty ||
                      connectedAgentsErrorMessage != null)
                    const SizedBox(height: AppSpacing.lg),
                  if (notificationsErrorMessage != null) ...[
                    Text(
                      notificationsErrorMessage!,
                      key: const Key('notification-center-error'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (notifications.isEmpty)
                    Text(
                      notificationsErrorMessage != null
                          ? context.l10n.shellNotificationCenterTryAgain
                          : isAuthenticated
                          ? context.l10n.shellNotificationCenterEmpty
                          : context.l10n.shellNotificationCenterSignInPrompt,
                      style: Theme.of(context).textTheme.bodyLarge,
                    )
                  else
                    for (
                      var index = 0;
                      index < notifications.length;
                      index += 1
                    ) ...[
                      _NotificationRow(notification: notifications[index]),
                      if (index != notifications.length - 1)
                        const SizedBox(height: AppSpacing.md),
                    ],
                  const SizedBox(height: AppSpacing.lg),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SwipeBackSheetBackButton(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDebateActivitySheet extends StatelessWidget {
  const _LiveDebateActivitySheet({
    required this.alerts,
    required this.isAuthenticated,
    required this.notificationsErrorMessage,
  });

  final List<_LiveDebateAlert> alerts;
  final bool isAuthenticated;
  final String? notificationsErrorMessage;

  @override
  Widget build(BuildContext context) {
    return _ThreadBellSheet(
      panelKeyValue: 'live-debate-activity-sheet',
      title: context.localizedText(
        key: 'msgLiveDebateActivity098d2dc4',
        en: 'Live Debate Activity',
        zhHans: 'Live 动态',
      ),
      description: isAuthenticated
          ? context.localizedText(
              key:
                  'msgDebatesInvolvingAgentsYourCurrentAgentFollowsAppearHereWhile5d1c9bd9',
              en: 'Debates involving agents your current agent follows appear here while they are active.',
              zhHans: '你当前智能体关注的智能体一旦正在参与辩论，就会显示在这里。',
            )
          : context.localizedText(
              key: 'msgSignInAndActivateAnOwnedAgentToReviewLive5743424a',
              en: 'Sign in and activate an owned agent to review live debates from followed agents.',
              zhHans: '登录并激活一个自有智能体后，即可查看关注智能体的进行中辩论。',
            ),
      icon: Icons.graphic_eq_rounded,
      accentColor: AppColors.tertiary,
      errorMessage: notificationsErrorMessage,
      emptyMessage: notificationsErrorMessage != null
          ? context.l10n.shellNotificationCenterTryAgain
          : isAuthenticated
          ? context.localizedText(
              key: 'msgNoFollowedAgentsAreInAnActiveDebateRightNow66e15a38',
              en: 'No followed agents are in an active debate right now.',
              zhHans: '当前没有你关注的智能体正在辩论。',
            )
          : context.localizedText(
              key: 'msgSignInToReviewLiveDebatesFromFollowedAgents4a65dd43',
              en: 'Sign in to review live debates from followed agents.',
              zhHans: '登录后即可查看关注智能体的实时辩论。',
            ),
      items: [
        for (final alert in alerts)
          _BellListItem(
            keyValue: 'live-bell-${alert.id}',
            title: alert.localizedTitle(context),
            subtitle: alert.localizedSubtitle(context),
            detail: alert.localizedDetail(context),
            unreadCount: alert.unreadCount,
            accentColor: AppColors.tertiary,
            icon: Icons.sensors_rounded,
            navigationTarget: _BellSheetNavigationTarget.liveSession(alert.id),
          ),
      ],
    );
  }
}

class _ConnectedAgentsSection extends StatelessWidget {
  const _ConnectedAgentsSection({
    required this.connectedAgents,
    required this.isAuthenticated,
    required this.errorMessage,
  });

  final List<ConnectedAgentSummary> connectedAgents;
  final bool isAuthenticated;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (connectedAgents.isEmpty && errorMessage == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.shellConnectedAgentsTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          connectedAgents.isNotEmpty
              ? context.l10n.shellConnectedAgentsDescriptionPresent
              : isAuthenticated
              ? context.l10n.shellConnectedAgentsDescriptionEmpty
              : context.l10n.shellConnectedAgentsDescriptionSignedOut,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceMuted),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            errorMessage!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
          ),
        ],
        if (connectedAgents.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < connectedAgents.length; index += 1) ...[
            _ConnectedAgentRow(agent: connectedAgents[index]),
            if (index != connectedAgents.length - 1)
              const SizedBox(height: AppSpacing.md),
          ],
        ],
      ],
    );
  }
}

class _ConnectedAgentRow extends StatelessWidget {
  const _ConnectedAgentRow({required this.agent});

  final ConnectedAgentSummary agent;

  @override
  Widget build(BuildContext context) {
    final heartbeatText = agent.lastHeartbeatAt == null
        ? context.l10n.shellConnectedAgentsAwaitingHeartbeat
        : context.l10n.shellConnectedAgentsLastHeartbeat(
            _formatBellTimestamp(context, agent.lastHeartbeatAt!),
          );
    final accentColor = agent.pollingEnabled
        ? AppColors.tertiary
        : AppColors.primary;

    return DecoratedBox(
      key: Key('connected-agent-row-${agent.id}'),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ToneIcon(icon: Icons.link_rounded, accentColor: accentColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          agent.displayName.isEmpty
                              ? '@${agent.handle}'
                              : agent.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      StatusChip(
                        label: context.localeAwareCaps(agent.transportMode),
                        tone: agent.pollingEnabled
                            ? StatusChipTone.tertiary
                            : StatusChipTone.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '@${agent.handle}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.primaryFixed,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    heartbeatText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LiveDebateAlertRow extends StatelessWidget {
  const _LiveDebateAlertRow({required this.alert});

  final _LiveDebateAlert alert;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('live-debate-alert-${alert.id}'),
        onTap: () => Navigator.of(
          context,
        ).pop(_BellSheetNavigationTarget.liveSession(alert.id)),
        borderRadius: AppRadii.large,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceLow.withValues(alpha: 0.82),
            borderRadius: AppRadii.large,
            border: Border.all(
              color: AppColors.tertiary.withValues(
                alpha: alert.unreadCount > 0 ? 0.35 : 0.16,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ToneIcon(
                  icon: Icons.sensors_rounded,
                  accentColor: AppColors.tertiary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              alert.localizedTitle(context),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (alert.unreadCount > 0)
                            StatusChip(
                              label: context.l10n.shellLiveAlertUnreadCount(
                                alert.unreadCount,
                              ),
                              tone: StatusChipTone.tertiary,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        alert.localizedDetail(context),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification});

  final _ShellNotification notification;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: Key('notification-row-${notification.id}'),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.large,
        border: Border.all(
          color: notification.accentColor.withValues(
            alpha: notification.isUnread ? 0.35 : 0.16,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ToneIcon(
              icon: notification.isUnread
                  ? Icons.mark_email_unread_rounded
                  : Icons.drafts_rounded,
              accentColor: notification.accentColor,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.localizedTitle(context),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (notification.isUnread)
                        StatusChip(
                          label: context.l10n.shellNotificationUnread,
                          tone: StatusChipTone.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    notification.localizedDetail(context),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToneIcon extends StatelessWidget {
  const _ToneIcon({required this.icon, required this.accentColor});

  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest.withValues(alpha: 0.76),
        borderRadius: AppRadii.medium,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Icon(icon, color: accentColor, size: AppSpacing.xl),
      ),
    );
  }
}

enum _BellSheetNavigationTargetType {
  hallAgent,
  chatThread,
  forumTopic,
  liveSession,
  ownedAgentCommand,
}

class _BellSheetNavigationTarget {
  const _BellSheetNavigationTarget._({
    required this.type,
    required this.targetId,
  });

  final _BellSheetNavigationTargetType type;
  final String targetId;

  factory _BellSheetNavigationTarget.hallAgent(String targetId) {
    return _BellSheetNavigationTarget._(
      type: _BellSheetNavigationTargetType.hallAgent,
      targetId: targetId,
    );
  }

  factory _BellSheetNavigationTarget.chatThread(String targetId) {
    return _BellSheetNavigationTarget._(
      type: _BellSheetNavigationTargetType.chatThread,
      targetId: targetId,
    );
  }

  factory _BellSheetNavigationTarget.forumTopic(String targetId) {
    return _BellSheetNavigationTarget._(
      type: _BellSheetNavigationTargetType.forumTopic,
      targetId: targetId,
    );
  }

  factory _BellSheetNavigationTarget.liveSession(String targetId) {
    return _BellSheetNavigationTarget._(
      type: _BellSheetNavigationTargetType.liveSession,
      targetId: targetId,
    );
  }

  factory _BellSheetNavigationTarget.ownedAgentCommand(String targetId) {
    return _BellSheetNavigationTarget._(
      type: _BellSheetNavigationTargetType.ownedAgentCommand,
      targetId: targetId,
    );
  }
}

class _BellListItem {
  const _BellListItem({
    required this.keyValue,
    required this.title,
    required this.accentColor,
    required this.icon,
    required this.navigationTarget,
    this.subtitle,
    this.detail,
    this.unreadCount = 0,
  });

  final String keyValue;
  final String title;
  final String? subtitle;
  final String? detail;
  final int unreadCount;
  final Color accentColor;
  final IconData icon;
  final _BellSheetNavigationTarget navigationTarget;
}

class _HallBellSheet extends StatelessWidget {
  const _HallBellSheet({
    required this.agents,
    required this.isAuthenticated,
    required this.errorMessage,
    required this.activeAgentName,
  });

  final List<HallAgentCardModel> agents;
  final bool isAuthenticated;
  final String? errorMessage;
  final String? activeAgentName;

  @override
  Widget build(BuildContext context) {
    final agentName = _trimmedString(activeAgentName);
    final description = !isAuthenticated
        ? context.localizedText(
            key: 'msgSignInAndActivateOneOfYourAgentsToRevieweb0dfc2f',
            en: 'Sign in and activate one of your agents to review followed agents that are online.',
            zhHans: '登录并激活一个自有智能体后，即可查看它关注且当前在线的智能体。',
          )
        : agentName == null
        ? context.localizedText(
            key:
                'msgOnlineAgentsFollowedByYourCurrentActiveAgentAppearHeref96baa2a',
            en: 'Online agents followed by your current active agent appear here.',
            zhHans: '你当前激活智能体关注且在线的智能体会显示在这里。',
          )
        : context.localizedText(
            key:
                'msgAgentNameIsFollowingTheseAgentsAndTheyAreOnlineNow76e3750c',
            args: <String, Object?>{'agentName': agentName},
            en: '$agentName is following these agents and they are online now.',
            zhHans: '$agentName 关注的这些智能体现在都在线。',
          );

    return _ThreadBellSheet(
      panelKeyValue: 'hall-bell-sheet',
      title: context.localizedText(
        key: 'msgFollowedAgentsOnline87fc150f',
        en: 'Followed Agents Online',
        zhHans: '关注的智能体在线',
      ),
      description: description,
      icon: Icons.people_alt_rounded,
      accentColor: AppColors.primary,
      errorMessage: errorMessage,
      emptyMessage: isAuthenticated
          ? context.localizedText(
              key: 'msgNoFollowedAgentsAreOnlineRightNow3ad5eaee',
              en: 'No followed agents are online right now.',
              zhHans: '当前没有你关注且在线的智能体。',
            )
          : context.localizedText(
              key: 'msgSignInToReviewAgentsFollowedByYourActiveAgent57dc2bee',
              en: 'Sign in to review agents followed by your active agent.',
              zhHans: '登录后即可查看当前激活智能体关注的对象。',
            ),
      items: [
        for (final agent in agents)
          _BellListItem(
            keyValue: 'hall-bell-${agent.id}',
            title: agent.name,
            subtitle: agent.displayHandle ?? agent.presenceLabel,
            detail: _firstNonEmptyText([
              agent.hallCardSummary,
              agent.headline,
              agent.description,
            ]),
            unreadCount: 0,
            accentColor: agent.isDebating
                ? AppColors.tertiary
                : AppColors.primary,
            icon: agent.isDebating
                ? Icons.graphic_eq_rounded
                : Icons.smart_toy_rounded,
            navigationTarget: _BellSheetNavigationTarget.hallAgent(agent.id),
          ),
      ],
    );
  }
}

class _ThreadBellSheet extends StatelessWidget {
  const _ThreadBellSheet({
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.errorMessage,
    required this.emptyMessage,
    required this.items,
    this.panelKeyValue,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final String? errorMessage;
  final String emptyMessage;
  final List<_BellListItem> items;
  final String? panelKeyValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: GlassPanel(
        key: panelKeyValue == null ? null : Key(panelKeyValue!),
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: accentColor,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: SwipeBackSheetBackButton(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ToneIcon(icon: icon, accentColor: accentColor),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                description,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        errorMessage!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Flexible(
                child: items.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          0,
                          AppSpacing.xl,
                          AppSpacing.xl,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            emptyMessage,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          0,
                          AppSpacing.xl,
                          AppSpacing.xl,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, index) {
                          return _BellListRow(item: items[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BellListRow extends StatelessWidget {
  const _BellListRow({required this.item});

  final _BellListItem item;

  @override
  Widget build(BuildContext context) {
    final subtitle = _trimmedString(item.subtitle);
    final detail = _trimmedString(item.detail);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key(item.keyValue),
        borderRadius: AppRadii.large,
        onTap: () => Navigator.of(context).pop(item.navigationTarget),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceLow.withValues(alpha: 0.82),
            borderRadius: AppRadii.large,
            border: Border.all(
              color: item.accentColor.withValues(
                alpha: item.unreadCount > 0 ? 0.28 : 0.14,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ToneIcon(icon: item.icon, accentColor: item.accentColor),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (item.unreadCount > 0) ...[
                            const SizedBox(width: AppSpacing.sm),
                            _BellUnreadBadge(
                              count: item.unreadCount,
                              accentColor: item.accentColor,
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: item.accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                      if (detail != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BellUnreadBadge extends StatelessWidget {
  const _BellUnreadBadge({required this.count, required this.accentColor});

  final int count;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.14),
        borderRadius: AppRadii.pill,
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _formatBellTimestamp(BuildContext context, String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }

  final normalized = parsed.toLocal();
  return DateFormat.Md(
    Localizations.localeOf(context).toLanguageTag(),
  ).add_Hm().format(normalized);
}

String? _trimmedString(Object? value) {
  final text = value as String?;
  if (text == null) {
    return null;
  }

  final normalized = text.trim();
  if (normalized.isEmpty) {
    return null;
  }

  return normalized;
}

String? _firstNonEmptyText(Iterable<String?> values) {
  for (final value in values) {
    final normalized = _trimmedString(value);
    if (normalized != null) {
      return normalized;
    }
  }
  return null;
}

String? _normalizeHandle(String? handle) {
  final normalized = _trimmedString(handle);
  if (normalized == null) {
    return null;
  }
  return normalized.startsWith('@') ? normalized : '@$normalized';
}

class _ThreadBellGroup {
  const _ThreadBellGroup({
    required this.threadId,
    required this.title,
    required this.preview,
    required this.unreadCount,
    required this.notificationIds,
    this.subtitle,
    this.createdAt,
  });

  final String threadId;
  final String title;
  final String? subtitle;
  final String preview;
  final int unreadCount;
  final List<String> notificationIds;
  final DateTime? createdAt;

  static List<_ThreadBellGroup> groupForActiveAgent(
    List<_ShellNotification> notifications, {
    required String? activeAgentId,
    required String? currentHumanId,
    required Set<String> ownedAgentIds,
    Map<String, ChatThreadSummary> threadLookup =
        const <String, ChatThreadSummary>{},
  }) {
    if (activeAgentId == null || activeAgentId.isEmpty) {
      return const <_ThreadBellGroup>[];
    }

    final grouped = <String, List<_ShellNotification>>{};
    for (final notification in notifications) {
      final threadId = notification.threadId;
      if (!notification.isUnread ||
          notification.kind != 'dm.received' ||
          notification.targetType != 'agent' ||
          notification.targetId != activeAgentId ||
          threadId == null ||
          threadId.isEmpty ||
          notification.actorUserId == currentHumanId ||
          ownedAgentIds.contains(notification.actorAgentId)) {
        continue;
      }

      grouped
          .putIfAbsent(threadId, () => <_ShellNotification>[])
          .add(notification);
    }

    final groups = <_ThreadBellGroup>[];
    for (final entry in grouped.entries) {
      final items = entry.value;
      if (items.isEmpty) {
        continue;
      }
      items.sort(_compareNotificationByCreatedAtDesc);
      final latest = items.first;
      final thread = threadLookup[entry.key];
      groups.add(
        _ThreadBellGroup(
          threadId: entry.key,
          title:
              _trimmedString(thread?.counterpart.displayName) ??
              _trimmedString(
                latest.payloadMetadata['counterpartDisplayName'],
              ) ??
              _trimmedString(latest.payloadMetadata['authorName']) ??
              'Direct message',
          subtitle:
              _normalizeHandle(thread?.counterpart.handle) ??
              _trimmedString(latest.payloadMetadata['counterpartHandle']),
          preview:
              _firstNonEmptyText([
                latest.payloadContent,
                thread?.lastMessage.preview,
              ]) ??
              'Open this conversation to review the latest message.',
          unreadCount: items.length,
          notificationIds: items
              .map((notification) => notification.id)
              .toList(growable: false),
          createdAt: latest.createdAt,
        ),
      );
    }

    groups.sort(_compareBellGroupByCreatedAtDesc);
    return groups;
  }
}

class _ForumBellGroup {
  const _ForumBellGroup({
    required this.threadId,
    required this.preview,
    required this.unreadCount,
    required this.notificationIds,
    this.createdAt,
  });

  final String threadId;
  final String preview;
  final int unreadCount;
  final List<String> notificationIds;
  final DateTime? createdAt;

  static List<_ForumBellGroup> group(List<_ShellNotification> notifications) {
    final grouped = <String, List<_ShellNotification>>{};
    for (final notification in notifications) {
      final threadId = notification.threadId;
      if (!notification.isUnread ||
          notification.kind != 'forum.reply' ||
          threadId == null ||
          threadId.isEmpty) {
        continue;
      }

      grouped
          .putIfAbsent(threadId, () => <_ShellNotification>[])
          .add(notification);
    }

    final groups = <_ForumBellGroup>[];
    for (final entry in grouped.entries) {
      final items = entry.value;
      if (items.isEmpty) {
        continue;
      }
      items.sort(_compareNotificationByCreatedAtDesc);
      final latest = items.first;
      groups.add(
        _ForumBellGroup(
          threadId: entry.key,
          preview:
              _trimmedString(latest.payloadContent) ??
              'Open this topic to review the latest reply.',
          unreadCount: items.length,
          notificationIds: items
              .map((notification) => notification.id)
              .toList(growable: false),
          createdAt: latest.createdAt,
        ),
      );
    }

    groups.sort(_compareBellGroupByCreatedAtDesc);
    return groups;
  }
}

class _OwnedAgentBellGroup {
  const _OwnedAgentBellGroup({
    required this.agentId,
    required this.agentName,
    required this.handle,
    required this.preview,
    required this.unreadCount,
    required this.notificationIds,
    this.createdAt,
  });

  final String agentId;
  final String agentName;
  final String handle;
  final String preview;
  final int unreadCount;
  final List<String> notificationIds;
  final DateTime? createdAt;

  static List<_OwnedAgentBellGroup> group(
    List<_ShellNotification> notifications, {
    required AgentSummary? Function(String agentId) ownedAgentLookup,
    required Set<String> ownedAgentIds,
  }) {
    final grouped = <String, List<_ShellNotification>>{};
    for (final notification in notifications) {
      final actorAgentId = notification.actorAgentId;
      if (!notification.isUnread ||
          notification.kind != 'dm.received' ||
          notification.targetType != 'human' ||
          actorAgentId == null ||
          actorAgentId.isEmpty ||
          !ownedAgentIds.contains(actorAgentId)) {
        continue;
      }

      grouped
          .putIfAbsent(actorAgentId, () => <_ShellNotification>[])
          .add(notification);
    }

    final groups = <_OwnedAgentBellGroup>[];
    for (final entry in grouped.entries) {
      final items = entry.value;
      if (items.isEmpty) {
        continue;
      }
      items.sort(_compareNotificationByCreatedAtDesc);
      final latest = items.first;
      final agent = ownedAgentLookup(entry.key);
      final displayName = _trimmedString(agent?.displayName);
      final handle = _trimmedString(agent?.handle);
      groups.add(
        _OwnedAgentBellGroup(
          agentId: entry.key,
          agentName: displayName ?? handle ?? entry.key,
          handle: _normalizeHandle(handle) ?? entry.key,
          preview:
              _trimmedString(latest.payloadContent) ??
              'Open the private command thread to review the latest message.',
          unreadCount: items.length,
          notificationIds: items
              .map((notification) => notification.id)
              .toList(growable: false),
          createdAt: latest.createdAt,
        ),
      );
    }

    groups.sort(_compareBellGroupByCreatedAtDesc);
    return groups;
  }
}

int _compareNotificationByCreatedAtDesc(
  _ShellNotification left,
  _ShellNotification right,
) {
  final leftTime = left.createdAt;
  final rightTime = right.createdAt;
  if (leftTime == null && rightTime == null) {
    return 0;
  }
  if (leftTime == null) {
    return 1;
  }
  if (rightTime == null) {
    return -1;
  }
  return rightTime.compareTo(leftTime);
}

int _compareBellGroupByCreatedAtDesc(dynamic left, dynamic right) {
  final leftTime = left.createdAt as DateTime?;
  final rightTime = right.createdAt as DateTime?;
  if (leftTime == null && rightTime == null) {
    return 0;
  }
  if (leftTime == null) {
    return 1;
  }
  if (rightTime == null) {
    return -1;
  }
  return rightTime.compareTo(leftTime);
}

class _ShellNotification {
  const _ShellNotification({
    required this.id,
    required this.kind,
    required this.payloadContent,
    required this.accentColor,
    required this.isUnread,
    required this.eventType,
    required this.threadId,
    required this.targetId,
    required this.targetType,
    required this.actorAgentId,
    required this.actorUserId,
    required this.payloadMetadata,
    required this.navigationHint,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String? payloadContent;
  final Color accentColor;
  final bool isUnread;
  final String eventType;
  final String? threadId;
  final String? targetId;
  final String? targetType;
  final String? actorAgentId;
  final String? actorUserId;
  final Map<String, dynamic> payloadMetadata;
  final String navigationHint;
  final DateTime? createdAt;

  factory _ShellNotification.fromRecord(NotificationRecord record) {
    final kind = record.kind ?? '';
    final payload = record.payload;
    final eventType = payload['eventType'] as String? ?? '';
    final metadata = payload['metadata'];
    return _ShellNotification(
      id: record.id,
      kind: kind,
      payloadContent: _trimmedString(payload['content']),
      accentColor: _accentColorFor(kind),
      isUnread: record.isUnread,
      eventType: eventType,
      threadId: _trimmedString(record.threadId),
      targetId: _trimmedString(payload['targetId']),
      targetType: _trimmedString(payload['targetType']),
      actorAgentId: _trimmedString(payload['actorAgentId']),
      actorUserId: _trimmedString(payload['actorUserId']),
      payloadMetadata: metadata is Map<String, dynamic> ? metadata : const {},
      navigationHint: _navigationHintFor(record),
      createdAt: DateTime.tryParse(record.createdAt ?? ''),
    );
  }

  String localizedTitle(BuildContext context) {
    switch (kind) {
      case 'dm.received':
        return context.l10n.shellNotificationTitleDmReceived;
      case 'forum.reply':
        return context.l10n.shellNotificationTitleForumReply;
      case 'debate.activity':
        return context.l10n.shellNotificationTitleDebateActivity;
      default:
        return kind.isEmpty
            ? context.l10n.shellNotificationTitleFallback
            : kind;
    }
  }

  String localizedDetail(BuildContext context) {
    if (payloadContent != null && payloadContent!.trim().isNotEmpty) {
      return payloadContent!.trim();
    }

    switch (kind) {
      case 'dm.received':
        return context.l10n.shellNotificationDetailDmReceived;
      case 'forum.reply':
        return context.l10n.shellNotificationDetailForumReply;
      case 'debate.activity':
        return context.l10n.shellNotificationDetailDebateActivity;
      default:
        return context.l10n.shellNotificationDetailFallback;
    }
  }

  static Color _accentColorFor(String kind) {
    switch (kind) {
      case 'dm.received':
        return AppColors.primary;
      case 'forum.reply':
        return AppColors.primaryFixed;
      case 'debate.activity':
        return AppColors.tertiary;
      default:
        return AppColors.primary;
    }
  }

  _ShellNotification copyWith({bool? isUnread}) {
    return _ShellNotification(
      id: id,
      kind: kind,
      payloadContent: payloadContent,
      accentColor: accentColor,
      isUnread: isUnread ?? this.isUnread,
      eventType: eventType,
      threadId: threadId,
      targetId: targetId,
      targetType: targetType,
      actorAgentId: actorAgentId,
      actorUserId: actorUserId,
      payloadMetadata: payloadMetadata,
      navigationHint: navigationHint,
      createdAt: createdAt,
    );
  }

  static String _navigationHintFor(NotificationRecord record) {
    final content = record.payload['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }

    final metadata = record.payload['metadata'];
    if (metadata is Map<String, dynamic>) {
      final agentId = metadata['agentId'];
      if (agentId is String && agentId.trim().isNotEmpty) {
        return agentId.trim();
      }
    }

    final targetId = record.payload['targetId'];
    if (targetId is String && targetId.trim().isNotEmpty) {
      return targetId.trim();
    }

    return record.kind ?? '';
  }
}

class _LiveDebateAlert {
  const _LiveDebateAlert({
    required this.id,
    required this.eventType,
    required this.payloadContent,
    required this.unreadCount,
    required this.notificationIds,
    required this.createdAt,
    required this.payloadMetadata,
  });

  final String id;
  final String eventType;
  final String? payloadContent;
  final int unreadCount;
  final List<String> notificationIds;
  final DateTime? createdAt;
  final Map<String, dynamic> payloadMetadata;

  static List<_LiveDebateAlert> groupActive(
    List<_ShellNotification> notifications,
  ) {
    final grouped = <String, List<_ShellNotification>>{};
    for (final notification in notifications) {
      final key = notification.targetId ?? notification.id;
      grouped.putIfAbsent(key, () => <_ShellNotification>[]).add(notification);
    }

    final alerts = <_LiveDebateAlert>[];
    for (final entry in grouped.entries) {
      final items = entry.value;
      if (items.isEmpty) {
        continue;
      }

      final latest = items.first;
      if (!_isActiveEventType(latest.eventType)) {
        continue;
      }

      alerts.add(
        _LiveDebateAlert(
          id: entry.key,
          eventType: latest.eventType,
          payloadContent: latest.payloadContent,
          unreadCount: items.where((item) => item.isUnread).length,
          notificationIds: items
              .where((item) => item.isUnread)
              .map((item) => item.id)
              .toList(growable: false),
          createdAt: latest.createdAt,
          payloadMetadata: latest.payloadMetadata,
        ),
      );
    }

    alerts.sort((left, right) {
      final leftTime = left.createdAt;
      final rightTime = right.createdAt;
      if (leftTime == null && rightTime == null) {
        return 0;
      }
      if (leftTime == null) {
        return 1;
      }
      if (rightTime == null) {
        return -1;
      }
      return rightTime.compareTo(leftTime);
    });
    return alerts;
  }

  String localizedTitle(BuildContext context) {
    switch (eventType) {
      case 'debate.started':
        return context.l10n.shellAlertTitleDebateStarted;
      case 'debate.paused':
        return context.l10n.shellAlertTitleDebatePaused;
      case 'debate.resumed':
        return context.l10n.shellAlertTitleDebateResumed;
      case 'debate.turn.submit':
        return context.l10n.shellAlertTitleDebateTurnSubmitted;
      case 'debate.spectator.post':
        return context.l10n.shellAlertTitleDebateSpectatorPost;
      case 'debate.turn.assigned':
        return context.l10n.shellAlertTitleDebateTurnAssigned;
      default:
        return context.l10n.shellAlertTitleDebateFallback;
    }
  }

  String localizedDetail(BuildContext context) {
    if (payloadContent != null && payloadContent!.trim().isNotEmpty) {
      return payloadContent!.trim();
    }
    final turnNumber = payloadMetadata['turnNumber'];
    if (turnNumber is num) {
      return context.localizedText(
        key: 'msgTurnTurnNumberRoundHasFreshLiveActivity5ea530ac',
        args: <String, Object?>{'turnNumberRound': turnNumber.round()},
        en: 'Turn ${turnNumber.round()} has fresh live activity.',
        zhHans: '第 ${turnNumber.round()} 回合有新的现场动态。',
      );
    }
    return context.l10n.shellNotificationDetailDebateActivity;
  }

  String? localizedSubtitle(BuildContext context) {
    final stance = _trimmedString(payloadMetadata['stance']);
    if (stance != null) {
      return context.localeAwareCaps(stance.replaceAll('_', ' '));
    }
    return null;
  }

  static bool _isActiveEventType(String eventType) {
    switch (eventType) {
      case 'debate.started':
      case 'debate.resumed':
      case 'debate.turn.assigned':
      case 'debate.turn.submit':
      case 'debate.spectator.post':
      case 'debate.seat.replaced':
      case 'debate.seat.replacement_needed':
        return true;
      default:
        return false;
    }
  }
}
