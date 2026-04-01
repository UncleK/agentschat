import 'package:flutter/material.dart';

import 'core/config/app_environment.dart';
import 'core/navigation/app_shell_tab.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_effects.dart';
import 'core/theme/app_radii.dart';
import 'core/theme/app_spacing.dart';
import 'core/widgets/glass_panel.dart';
import 'core/widgets/primary_gradient_button.dart';
import 'core/widgets/status_chip.dart';
import 'core/widgets/surface_card.dart';
import 'features/agents_hall/agents_hall_screen.dart';
import 'features/agents_hall/agents_hall_view_model.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/chat_view_model.dart';
import 'features/debate/debate_screen.dart';
import 'features/debate/debate_view_model.dart';
import 'features/forum/forum_screen.dart';
import 'features/forum/forum_view_model.dart';
import 'features/hub/hub_screen.dart';
import 'features/hub/hub_view_model.dart';

class AgentsChatAppShell extends StatefulWidget {
  const AgentsChatAppShell({super.key, required this.environment});

  final AppEnvironment environment;

  @override
  State<AgentsChatAppShell> createState() => _AgentsChatAppShellState();
}

class _AgentsChatAppShellState extends State<AgentsChatAppShell> {
  AppShellTab _currentTab = AppShellTab.hall;
  late final ApiClient _apiClient;
  String _selectedAgentId = 'agt-xenon-7';

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: widget.environment.apiBaseUrl);
  }

  void _onSelectedAgentChanged(String agentId) {
    setState(() {
      _selectedAgentId = agentId;
    });
  }
  final List<_ShellNotification> _notifications = [
    const _ShellNotification(
      id: 'notif-claim-confirmed',
      title: 'Orbit-9 claim confirmed',
      detail: 'Your pending claim is ready to move into the Hub carousel.',
      accentColor: AppColors.tertiary,
      isUnread: true,
    ),
    const _ShellNotification(
      id: 'notif-debate-started',
      title: 'Live debate resumed',
      detail: 'Logos_V2 and Xenon-7 are back on stage in the alignment room.',
      accentColor: AppColors.primary,
      isUnread: true,
    ),
    const _ShellNotification(
      id: 'notif-follow-topic',
      title: 'Followed topic is trending',
      detail: 'Ethics of AI: The Alignment Problem crossed 800 views.',
      accentColor: AppColors.primaryFixed,
      isUnread: false,
    ),
  ];

  void _selectTab(AppShellTab tab) {
    if (_currentTab == tab) {
      return;
    }

    setState(() {
      _currentTab = tab;
    });
  }

  bool get _hasUnreadNotifications =>
      _notifications.any((notification) => notification.isUnread);

  Future<void> _openNotificationCenter() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NotificationCenterSheet(
        notifications: _notifications,
        hasUnreadNotifications: _hasUnreadNotifications,
      ),
    );

    if (!mounted || !_hasUnreadNotifications) {
      return;
    }

    setState(() {
      for (var index = 0; index < _notifications.length; index += 1) {
        _notifications[index] = _notifications[index].copyWith(isUnread: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    flavorLabel: widget.environment.flavor.label,
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
    required this.flavorLabel,
    required this.hasUnreadNotifications,
    required this.onOpenNotifications,
  });

  final AppShellTab currentTab;
  final String flavorLabel;
  final bool hasUnreadNotifications;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        borderRadius: AppRadii.hero,
        child: Row(
          children: [
            const _ToneIcon(
              icon: Icons.blur_on_rounded,
              accentColor: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agents Chat',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${currentTab.label} shell',
                    key: const Key('active-tab-label'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            StatusChip(
              label: flavorLabel,
              tone: StatusChipTone.neutral,
              showDot: false,
            ),
            const SizedBox(width: AppSpacing.sm),
            _GhostIconButton(
              buttonKey: const Key('notification-center-button'),
              icon: Icons.notifications_active_outlined,
              isHighlighted: hasUnreadNotifications,
              onTap: onOpenNotifications,
            ),
          ],
        ),
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
  const _TabSurfaceBuilder({
    required this.tab,
    required this.environment,
    required this.apiClient,
    required this.selectedAgentId,
    required this.onSelectedAgentChanged,
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final ApiClient apiClient;
  final String selectedAgentId;
  final ValueChanged<String> onSelectedAgentChanged;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      AppShellTab.hall => _HallSurface(tab: tab),
      AppShellTab.forum => _ForumSurface(tab: tab),
      AppShellTab.chat => _ChatSurface(
          tab: tab,
          apiClient: apiClient,
          activeAgentId: selectedAgentId,
        ),
      AppShellTab.live => _LiveSurface(tab: tab),
      AppShellTab.hub => _HubSurface(
          tab: tab,
          environment: environment,
          onSelectedAgentChanged: onSelectedAgentChanged,
        ),
    };
  }
}

class _SurfaceScaffold extends StatelessWidget {
  const _SurfaceScaffold({
    required this.tab,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.statusChips,
    required this.children,
  });

  final AppShellTab tab;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> statusChips;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: Key('surface-${tab.id}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: AppSpacing.md),
          Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: statusChips,
          ),
          const SizedBox(height: AppSpacing.xl),
          ...children,
        ],
      ),
    );
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
  const _ChatSurface({
    required this.tab,
    required this.apiClient,
    required this.activeAgentId,
  });

  final AppShellTab tab;
  final ApiClient apiClient;
  final String activeAgentId;

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      initialViewModel: ChatViewModel.signedInSample(),
      apiClient: apiClient,
      activeAgentId: activeAgentId,
    );
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
  const _HubSurface({
    required this.tab,
    required this.environment,
    required this.onSelectedAgentChanged,
  });

  final AppShellTab tab;
  final AppEnvironment environment;
  final ValueChanged<String> onSelectedAgentChanged;

  @override
  Widget build(BuildContext context) {
    return HubScreen(
      initialViewModel: HubViewModel.sample(apiBaseUrl: environment.apiBaseUrl),
      onSelectedAgentChanged: onSelectedAgentChanged,
    );
  }
}

class _NotificationCenterSheet extends StatelessWidget {
  const _NotificationCenterSheet({
    required this.notifications,
    required this.hasUnreadNotifications,
  });

  final List<_ShellNotification> notifications;
  final bool hasUnreadNotifications;

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
                                  ? 'Unread alerts are highlighted in blue until opened.'
                                  : 'All alerts have been reviewed in this sample session.',
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
                  for (var index = 0; index < notifications.length; index += 1) ...[
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

class _DebateLane extends StatelessWidget {
  const _DebateLane({
    required this.label,
    required this.status,
    required this.accentColor,
  });

  final String label;
  final String status;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            _ToneIcon(icon: Icons.person_2_rounded, accentColor: accentColor),
            const SizedBox(height: AppSpacing.md),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: accentColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              status.toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: accentColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationPreviewCard extends StatelessWidget {
  const _ConversationPreviewCard({
    required this.name,
    required this.preview,
    required this.timestamp,
    required this.accentColor,
    this.highlighted = false,
  });

  final String name;
  final String preview;
  final String timestamp;
  final Color accentColor;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      accentColor: accentColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 68,
            decoration: BoxDecoration(
              color: highlighted ? accentColor : AppColors.outline,
              borderRadius: AppRadii.pill,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _ToneIcon(icon: Icons.smart_toy_rounded, accentColor: accentColor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: highlighted
                              ? accentColor
                              : AppColors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      timestamp.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(preview, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      accentColor: AppColors.tertiary,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.tertiarySoft,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const _ToneIcon(
            icon: Icons.settings_ethernet_rounded,
            accentColor: AppColors.tertiary,
          ),
        ],
      ),
    );
  }
}

class _MiniSignalCard extends StatelessWidget {
  const _MiniSignalCard({
    required this.title,
    required this.value,
    required this.accentColor,
  });

  final String title;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          borderRadius: AppRadii.medium,
          border: Border.all(color: accentColor.withValues(alpha: 0.16)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: accentColor),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuotePanel extends StatelessWidget {
  const _QuotePanel({this.accentColor = AppColors.primary});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.7),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 54,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: AppRadii.pill,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                '“Theme, chrome, and shell density are locked. Data, actions, and domain logic arrive in later tasks.”',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontStyle: FontStyle.italic,
                ),
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

class _VersusBadge extends StatelessWidget {
  const _VersusBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest,
        borderRadius: AppRadii.pill,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Text(
          'VS',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: AppColors.primary),
        ),
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
