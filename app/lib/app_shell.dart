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
import 'features/agents_hall/agents_hall_screen.dart';
import 'features/agents_hall/agents_hall_view_model.dart';
import 'features/chat/chat_screen.dart';
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
  late final AppSessionController _sessionController;
  late final NotificationsRepository _notificationsRepository;
  late final bool _ownsSessionController;
  List<_ShellNotification> _notifications = const [];
  NotificationBellState _notificationBellState = NotificationBellState.empty;
  String? _notificationsErrorMessage;
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
  }

  bool get _hasUnreadNotifications => _notificationBellState.hasUnread;

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
          !_notificationBellState.hasUnread) {
        return;
      }

      setState(() {
        _notificationsUserId = null;
        _notifications = const [];
        _notificationBellState = NotificationBellState.empty;
        _notificationsErrorMessage = null;
      });
      return;
    }

    if (_notificationsUserId == nextUserId) {
      return;
    }

    _notificationsUserId = nextUserId;
    unawaited(_refreshNotificationBellState(userId: nextUserId));
  }

  bool _canApplyNotificationsResult(int requestId, String userId) {
    return mounted &&
        requestId == _notificationsRequestId &&
        _liveNotificationsUserId == userId;
  }

  Future<void> _refreshNotificationBellState({required String userId}) async {
    final requestId = ++_notificationsRequestId;
    try {
      final bellState = await _notificationsRepository.bellState();
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      setState(() {
        _notificationBellState = bellState;
        _notificationsErrorMessage = null;
      });
    } on ApiException catch (error) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
        return;
      }

      setState(() {
        _notificationsErrorMessage =
            'Notifications are temporarily unavailable.';
      });
    } catch (_) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      setState(() {
        _notificationsErrorMessage =
            'Notifications are temporarily unavailable.';
      });
    }
  }

  Future<void> _refreshNotifications({required String userId}) async {
    final requestId = ++_notificationsRequestId;
    try {
      final listResponse = await _notificationsRepository.list();
      final bellState = await _notificationsRepository.bellState();
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      setState(() {
        _notifications = listResponse.notifications
            .map(_ShellNotification.fromRecord)
            .toList(growable: false);
        _notificationBellState = bellState;
        _notificationsErrorMessage = null;
      });
    } on ApiException catch (error) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      if (error.isUnauthorized) {
        await _sessionController.handleUnauthorized();
        return;
      }

      setState(() {
        _notificationsErrorMessage =
            'Notifications are temporarily unavailable.';
      });
    } catch (_) {
      if (!_canApplyNotificationsResult(requestId, userId)) {
        return;
      }

      setState(() {
        _notificationsErrorMessage =
            'Notifications are temporarily unavailable.';
      });
    }
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
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NotificationCenterSheet(
        notifications: _notifications,
        hasUnreadNotifications: _hasUnreadNotifications,
        isAuthenticated: userId != null,
        errorMessage: _notificationsErrorMessage,
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

  @override
  Widget build(BuildContext context) {
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
                      hasUnreadNotifications: _hasUnreadNotifications,
                      onOpenNotifications: _openNotificationCenter,
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
    required this.onOpenNotifications,
  });

  final AppShellTab currentTab;
  final bool hasUnreadNotifications;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
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
            size: AppSpacing.xl,
          ),
          const SizedBox(width: AppSpacing.md),
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
          if (currentTab.showsSearchAction) ...[
            _GhostIconButton(
              buttonKey: const Key('shell-search-button'),
              icon: Icons.search_rounded,
              isHighlighted: false,
              onTap: () {},
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          _GhostIconButton(
            buttonKey: const Key('notification-center-button'),
            icon: Icons.notifications_active_outlined,
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
          ? AppColors.primary.withValues(alpha: 0.14)
          : AppColors.surfaceHighest.withValues(alpha: 0.5),
      borderRadius: AppRadii.pill,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: AppRadii.pill,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(
                icon,
                color: isHighlighted ? AppColors.primary : null,
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
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.88),
            borderRadius: AppRadii.dock,
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.35),
            ),
            boxShadow: AppEffects.dockShadow(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
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
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
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
                    size: AppSpacing.xl,
                    color: foreground,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    tab.label.toUpperCase(),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: foreground),
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
  const _TabSurfaceBuilder({required this.tab, required this.environment});

  final AppShellTab tab;
  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      AppShellTab.hall => _HallSurface(tab: tab),
      AppShellTab.forum => _ForumSurface(tab: tab),
      AppShellTab.chat => _ChatSurface(tab: tab),
      AppShellTab.live => _LiveSurface(tab: tab),
      AppShellTab.hub => _HubSurface(tab: tab, environment: environment),
    };
  }
}

class _HallSurface extends StatelessWidget {
  const _HallSurface({required this.tab});

  final AppShellTab tab;

  @override
  Widget build(BuildContext context) {
    return AgentsHallScreen(initialViewModel: AgentsHallViewModel.sample());
  }
}

class _ForumSurface extends StatelessWidget {
  const _ForumSurface({required this.tab});

  final AppShellTab tab;

  @override
  Widget build(BuildContext context) {
    return ForumScreen(initialViewModel: ForumViewModel.signedInSample());
  }
}

class _ChatSurface extends StatelessWidget {
  const _ChatSurface({required this.tab});

  final AppShellTab tab;

  @override
  Widget build(BuildContext context) {
    return const ChatScreen();
  }
}

class _LiveSurface extends StatelessWidget {
  const _LiveSurface({required this.tab});

  final AppShellTab tab;

  @override
  Widget build(BuildContext context) {
    return DebateScreen(initialViewModel: DebateViewModel.sample());
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
    required this.notifications,
    required this.hasUnreadNotifications,
    required this.isAuthenticated,
    required this.errorMessage,
  });

  final List<_ShellNotification> notifications;
  final bool hasUnreadNotifications;
  final bool isAuthenticated;
  final String? errorMessage;

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
                              hasUnreadNotifications
                                  ? 'Unread alerts are highlighted in blue until reviewed.'
                                  : isAuthenticated
                                  ? 'You are all caught up with the live notification feed.'
                                  : 'Sign in to review notifications for this account.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('notification-center-close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (errorMessage != null) ...[
                    Text(
                      errorMessage!,
                      key: const Key('notification-center-error'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (notifications.isEmpty)
                    Text(
                      errorMessage != null
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
                ],
              ),
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

class _ShellNotification {
  const _ShellNotification({
    required this.id,
    required this.title,
    required this.detail,
    required this.accentColor,
    required this.isUnread,
  });

  final String id;
  final String title;
  final String detail;
  final Color accentColor;
  final bool isUnread;

  factory _ShellNotification.fromRecord(NotificationRecord record) {
    final kind = record.kind ?? '';
    return _ShellNotification(
      id: record.id,
      title: _titleFor(kind),
      detail: _detailFor(record, kind),
      accentColor: _accentColorFor(kind),
      isUnread: record.isUnread,
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
      title: title,
      detail: detail,
      accentColor: accentColor,
      isUnread: isUnread ?? this.isUnread,
    );
  }
}
