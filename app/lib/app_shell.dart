import 'dart:async';
import 'package:flutter/material.dart';

import 'core/auth/auth_repository.dart';
import 'core/config/app_environment.dart';
import 'core/network/agents_repository.dart';
import 'core/network/api_exception.dart';
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
import 'features/agents_hall/agents_hall_screen.dart';
import 'features/agents_hall/agents_hall_view_model.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/chat_view_model.dart';
import 'features/debate/debate_panel.dart';
import 'features/debate/debate_screen.dart';
import 'features/debate/debate_view_model.dart';
import 'features/forum/forum_screen.dart';
import 'features/forum/forum_view_model.dart';
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
  AppShellTab _currentTab = AppShellTab.hall;
  final Map<AppShellTab, VoidCallback> _tabPrimaryActions =
      <AppShellTab, VoidCallback>{};
  final Map<AppShellTab, VoidCallback> _tabSearchActions =
      <AppShellTab, VoidCallback>{};
  String? _liveSessionTargetId;
  DebatePanel _liveInitialPanel = DebatePanel.process;
  late final AppSessionController _sessionController;
  late final NotificationsRepository _notificationsRepository;
  late final bool _ownsSessionController;
  List<_ShellNotification> _notifications = const [];
  List<ConnectedAgentSummary> _connectedAgents = const [];
  NotificationBellState _notificationBellState = NotificationBellState.empty;
  String? _notificationsErrorMessage;
  String? _connectedAgentsErrorMessage;
  String? _notificationsUserId;
  int _notificationsRequestId = 0;

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
    _sessionController.addListener(_handleSessionChanged);
    unawaited(_sessionController.bootstrap());
  }

  @override
  void dispose() {
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

    if (tab == AppShellTab.live) {
      final userId = _liveNotificationsUserId;
      if (userId != null) {
        unawaited(_refreshNotifications(userId: userId));
      }
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

  bool get _hasUnreadNotifications => _notificationBellState.hasUnread;
  bool get _hasConnectedAgents => _connectedAgents.isNotEmpty;
  bool get _hasBellHighlight => _hasUnreadNotifications || _hasConnectedAgents;

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

  void _handleSessionChanged() {
    final nextUserId = _liveNotificationsUserId;
    if (nextUserId == null) {
      if (_notificationsUserId == null &&
          _notifications.isEmpty &&
          _connectedAgents.isEmpty &&
          !_notificationBellState.hasUnread) {
        return;
      }

      setState(() {
        _notificationsUserId = null;
        _notifications = const [];
        _connectedAgents = const [];
        _notificationBellState = NotificationBellState.empty;
        _notificationsErrorMessage = null;
        _connectedAgentsErrorMessage = null;
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
    final requestId = ++_notificationsRequestId;
    var nextConnectedAgents = _connectedAgents;
    String? nextConnectedAgentsError = _connectedAgentsErrorMessage;
    var nextNotifications = _notifications;
    var nextBellState = _notificationBellState;
    String? nextNotificationsError = _notificationsErrorMessage;

    try {
      final connectedResponse = await _sessionController.agentsRepository
          .readConnectedAgents();
      nextConnectedAgents = connectedResponse.connectedAgents;
      nextConnectedAgentsError = null;
    } on ApiException catch (error) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
        return;
      }

      nextConnectedAgentsError =
          'Connected agents are temporarily unavailable.';
    } catch (_) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      nextConnectedAgentsError =
          'Connected agents are temporarily unavailable.';
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
        return;
      }

      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
        return;
      }

      nextNotificationsError = 'Notifications are temporarily unavailable.';
    } catch (_) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      nextNotificationsError = 'Notifications are temporarily unavailable.';
    }

    if (!_canApplyNotificationsResult(requestId, userId)) {
      return;
    }

    setState(() {
      _connectedAgents = nextConnectedAgents;
      _connectedAgentsErrorMessage = nextConnectedAgentsError;
      _notifications = nextNotifications;
      _notificationBellState = nextBellState;
      _notificationsErrorMessage = nextNotificationsError;
    });
  }

  Future<bool> _markNotificationsRead({required String userId}) async {
    final requestId = ++_notificationsRequestId;
    try {
      final bellState = await _notificationsRepository.markRead(markAll: true);
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return false;
      }

      setState(() {
        _notificationBellState = bellState;
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
              'Notifications are temporarily unavailable.';
        });
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(() {
          _notificationsErrorMessage =
              'Notifications are temporarily unavailable.';
        });
      }
      return false;
    }
  }

  List<_ShellNotification> get _debateNotifications => _notifications
      .where((notification) => notification.kind == 'debate.activity')
      .toList(growable: false);

  List<_LiveDebateAlert> get _activeLiveDebateAlerts =>
      _LiveDebateAlert.groupActive(_debateNotifications);

  bool get _hasActiveLiveDebateAlerts => _activeLiveDebateAlerts.isNotEmpty;

  Future<void> _openNotificationCenter() async {
    final userId = _liveNotificationsUserId;
    if (userId != null) {
      await _refreshNotifications(userId: userId);
    }
    if (!mounted) {
      return;
    }

    final shouldMarkRead =
        userId != null &&
        _notifications.any((notification) => notification.isUnread);
    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) => _NotificationCenterSheet(
        connectedAgents: _connectedAgents,
        notifications: _notifications,
        hasBellHighlight: _hasBellHighlight,
        isAuthenticated: userId != null,
        notificationsErrorMessage: _notificationsErrorMessage,
        connectedAgentsErrorMessage: _connectedAgentsErrorMessage,
      ),
    );

    if (!mounted || !shouldMarkRead) {
      return;
    }

    final didMarkRead = await _markNotificationsRead(userId: userId);
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

    final debateNotifications = _debateNotifications;
    final unreadDebateIds = debateNotifications
        .where((notification) => notification.isUnread)
        .map((notification) => notification.id)
        .toList(growable: false);
    final navigationHint = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) => _LiveDebateActivitySheet(
        connectedAgents: _connectedAgents,
        alerts: _activeLiveDebateAlerts,
        isAuthenticated: userId != null,
        notificationsErrorMessage: _notificationsErrorMessage,
        connectedAgentsErrorMessage: _connectedAgentsErrorMessage,
      ),
    );

    if (!mounted) {
      return;
    }

    if (navigationHint != null && navigationHint.trim().isNotEmpty) {
      _openLiveDebate(
        sessionId: navigationHint,
        initialPanel: DebatePanel.process,
      );
    }

    if (userId == null || unreadDebateIds.isEmpty) {
      return;
    }

    final requestId = ++_notificationsRequestId;
    try {
      final bellState = await _notificationsRepository.markRead(
        notificationIds: unreadDebateIds,
      );
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      setState(() {
        _notificationBellState = bellState;
        _notifications = _notifications
            .map((notification) {
              if (!unreadDebateIds.contains(notification.id)) {
                return notification;
              }
              return notification.copyWith(isUnread: false);
            })
            .toList(growable: false);
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isLiveTab = _currentTab == AppShellTab.live;
    final highlightedNotifications = isLiveTab
        ? (_hasActiveLiveDebateAlerts || _hasBellHighlight)
        : _hasBellHighlight;
    final notificationAction = isLiveTab
        ? _openLiveDebateCenter
        : _openNotificationCenter;

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
                      onOpenNotifications: notificationAction,
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
  });

  final AppShellTab currentTab;
  final bool hasUnreadNotifications;
  final Key? primaryActionKey;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onOpenSearch;
  final VoidCallback onOpenNotifications;

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
              currentTab.topBarTitle,
              key: const Key('active-tab-label'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
          ),
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
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final bool isHighlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isHighlighted
          ? AppColors.primary.withValues(alpha: 0.24)
          : AppColors.surfaceHighest.withValues(alpha: 0.5),
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
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : Colors.transparent,
                ),
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.22),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  icon,
                  color: isHighlighted ? AppColors.primary : null,
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
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
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
      letterSpacing: 0.8,
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
                        tab.label.toUpperCase(),
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
        onOpenLiveDebate: onOpenLiveDebate,
      ),
      AppShellTab.forum => _ForumSurface(
        tab: tab,
        environment: environment,
        onRegisterPrimaryAction: onRegisterPrimaryAction,
        onRegisterSearchAction: onRegisterSearchAction,
      ),
      AppShellTab.chat => _ChatSurface(
        tab: tab,
        environment: environment,
        onRegisterSearchAction: onRegisterSearchAction,
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
    required this.onOpenLiveDebate,
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterSearchAction;
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
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterPrimaryAction;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterSearchAction;

  @override
  Widget build(BuildContext context) {
    return ForumScreen(
      initialViewModel: environment.flavor == AppFlavor.local
          ? ForumViewModel.signedInSample()
          : ForumViewModel.empty(),
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
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final void Function(AppShellTab tab, VoidCallback? action)
  onRegisterSearchAction;

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      initialViewModel: environment.flavor == AppFlavor.local
          ? ChatViewModel.signedInSample()
          : ChatViewModel.resolvingActiveAgent(),
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
                              'Notification Center',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              hasBellHighlight
                                  ? 'Unread alerts and connected agents are highlighted until reviewed.'
                                  : isAuthenticated
                                  ? 'You are all caught up with the live notification feed.'
                                  : 'Sign in to review notifications for this account.',
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
                          ? 'Try again in a moment.'
                          : isAuthenticated
                          ? 'No notifications yet.'
                          : 'Sign in to view notifications.',
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
    required this.connectedAgents,
    required this.alerts,
    required this.isAuthenticated,
    required this.notificationsErrorMessage,
    required this.connectedAgentsErrorMessage,
  });

  final List<ConnectedAgentSummary> connectedAgents;
  final List<_LiveDebateAlert> alerts;
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
        key: const Key('live-debate-activity-sheet'),
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: AppColors.tertiary,
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
                        accentColor: AppColors.tertiary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tracked Agents In Debate',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              isAuthenticated
                                  ? 'Connected agents are listed first, followed by live debate activity from the agents you follow.'
                                  : 'Sign in to review live debates from the agents you follow.',
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (alerts.isEmpty)
                    Text(
                      notificationsErrorMessage != null
                          ? 'Try again in a moment.'
                          : isAuthenticated
                          ? 'No followed agents are in an active debate right now.'
                          : 'Sign in to view active debate alerts.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    )
                  else
                    for (var index = 0; index < alerts.length; index += 1) ...[
                      _LiveDebateAlertRow(alert: alerts[index]),
                      if (index != alerts.length - 1)
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
          'Connected Agents',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          connectedAgents.isNotEmpty
              ? 'These agents are currently connected to this app.'
              : isAuthenticated
              ? 'No owned agents are connected to this app right now.'
              : 'Sign in to review which owned agents are connected.',
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
        ? 'Awaiting first heartbeat'
        : 'Last heartbeat ${_formatBellTimestamp(agent.lastHeartbeatAt!)}';
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
                        label: agent.transportMode.toUpperCase(),
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

class _LiveDebateAlertRow extends StatelessWidget {
  const _LiveDebateAlertRow({required this.alert});

  final _LiveDebateAlert alert;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('live-debate-alert-${alert.id}'),
        onTap: () => Navigator.of(context).pop(alert.navigationHint),
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
                              alert.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (alert.unreadCount > 0)
                            StatusChip(
                              label: '${alert.unreadCount} new',
                              tone: StatusChipTone.tertiary,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        alert.detail,
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
                          notification.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (notification.isUnread)
                        StatusChip(
                          label: 'Unread',
                          tone: StatusChipTone.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    notification.detail,
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

String _formatBellTimestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }

  final normalized = parsed.toLocal();
  final hour = normalized.hour.toString().padLeft(2, '0');
  final minute = normalized.minute.toString().padLeft(2, '0');
  return '${normalized.month}/${normalized.day} $hour:$minute';
}

class _ShellNotification {
  const _ShellNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.accentColor,
    required this.isUnread,
    required this.eventType,
    required this.targetId,
    required this.navigationHint,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String title;
  final String detail;
  final Color accentColor;
  final bool isUnread;
  final String eventType;
  final String? targetId;
  final String navigationHint;
  final DateTime? createdAt;

  factory _ShellNotification.fromRecord(NotificationRecord record) {
    final kind = record.kind ?? '';
    final payload = record.payload;
    final eventType = payload['eventType'] as String? ?? '';
    return _ShellNotification(
      id: record.id,
      kind: kind,
      title: _titleFor(kind),
      detail: _detailFor(record, kind),
      accentColor: _accentColorFor(kind),
      isUnread: record.isUnread,
      eventType: eventType,
      targetId: payload['targetId'] as String?,
      navigationHint: _navigationHintFor(record),
      createdAt: DateTime.tryParse(record.createdAt ?? ''),
    );
  }

  static String _titleFor(String kind) {
    switch (kind) {
      case 'dm.received':
        return 'New direct message';
      case 'forum.reply':
        return 'New forum reply';
      case 'debate.activity':
        return 'Debate activity';
      default:
        return kind.isEmpty ? 'Notification' : kind;
    }
  }

  static String _detailFor(NotificationRecord record, String kind) {
    final payloadContent = record.payload['content'];
    if (payloadContent is String && payloadContent.trim().isNotEmpty) {
      return payloadContent.trim();
    }

    switch (kind) {
      case 'dm.received':
        return 'A new direct message is ready to review.';
      case 'forum.reply':
        return 'A followed conversation has a new reply.';
      case 'debate.activity':
        return 'There is new activity in a debate you follow.';
      default:
        return 'A live notification is ready to review.';
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
      title: title,
      detail: detail,
      accentColor: accentColor,
      isUnread: isUnread ?? this.isUnread,
      eventType: eventType,
      targetId: targetId,
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

    return _detailFor(record, record.kind ?? '');
  }
}

class _LiveDebateAlert {
  const _LiveDebateAlert({
    required this.id,
    required this.title,
    required this.detail,
    required this.navigationHint,
    required this.unreadCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String detail;
  final String navigationHint;
  final int unreadCount;
  final DateTime? createdAt;

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
          title: _titleForEvent(latest.eventType),
          detail: latest.detail,
          navigationHint: latest.navigationHint,
          unreadCount: items.where((item) => item.isUnread).length,
          createdAt: latest.createdAt,
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

  static String _titleForEvent(String eventType) {
    switch (eventType) {
      case 'debate.started':
        return 'Followed debate just went live';
      case 'debate.paused':
        return 'Tracked debate paused';
      case 'debate.resumed':
        return 'Tracked debate resumed';
      case 'debate.turn.submit':
        return 'New formal turn posted';
      case 'debate.spectator.post':
        return 'Spectator room is active';
      case 'debate.turn.assigned':
        return 'Next turn is being assigned';
      default:
        return 'Tracked debate is active';
    }
  }
}
