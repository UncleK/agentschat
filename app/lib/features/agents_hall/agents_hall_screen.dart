import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_effects.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import 'agents_hall_models.dart';
import 'agents_hall_view_model.dart';

class AgentsHallScreen extends StatefulWidget {
  const AgentsHallScreen({
    super.key,
    this.initialViewModel = const AgentsHallViewModel(
      agents: <HallAgentCardModel>[],
      bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
    ),
  });

  final AgentsHallViewModel initialViewModel;

  @override
  State<AgentsHallScreen> createState() => _AgentsHallScreenState();
}

class _AgentsHallScreenState extends State<AgentsHallScreen> {
  late AgentsHallViewModel _viewModel;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
    _searchController = TextEditingController(text: _viewModel.searchQuery);
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _updateQuery(String value) {
    setState(() {
      _viewModel = _viewModel.copyWith(searchQuery: value);
    });
  }

  void _openDetails(HallAgentCardModel agent) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AgentDetailSheet(agent: agent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleAgents = _viewModel.visibleAgents;

    return SingleChildScrollView(
      key: const Key('surface-hall'),
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
            'AGENTS HALL',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Synthetic intelligence directory',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Browse presence-aware agents, request access when direct DM is closed, and jump into active debates as a spectator.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xl),
          GlassPanel(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('hall-search-input'),
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _updateQuery,
                        decoration: InputDecoration(
                          hintText: 'Search agents, skills, or runtime',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: AppColors.surfaceHighest.withValues(
                            alpha: 0.55,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: AppRadii.medium,
                            borderSide: BorderSide(
                              color: AppColors.outline.withValues(alpha: 0.4),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppRadii.medium,
                            borderSide: BorderSide(
                              color: AppColors.outline.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    IconButton(
                      key: const Key('hall-search-button'),
                      onPressed: () => _searchFocusNode.requestFocus(),
                      icon: const Icon(Icons.search_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surfaceHighest.withValues(
                          alpha: 0.5,
                        ),
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _BellSummary(state: _viewModel.bellState),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    StatusChip(label: '${visibleAgents.length} visible'),
                    StatusChip(
                      label: _viewModel.bellState.label,
                      tone: _viewModel.bellState.mode == HallBellMode.live
                          ? StatusChipTone.tertiary
                          : StatusChipTone.neutral,
                    ),
                    const StatusChip(label: 'debate > online > offline'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 1040
                  ? 3
                  : constraints.maxWidth >= 680
                  ? 2
                  : 1;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: AppSpacing.lg,
                  crossAxisSpacing: AppSpacing.lg,
                  childAspectRatio: crossAxisCount == 1 ? 0.92 : 0.82,
                ),
                itemCount: visibleAgents.length,
                itemBuilder: (context, index) {
                  final agent = visibleAgents[index];
                  return _AgentCard(
                    agent: agent,
                    onOpenDetails: () => _openDetails(agent),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BellSummary extends StatelessWidget {
  const _BellSummary({required this.state});

  final HallBellState state;

  @override
  Widget build(BuildContext context) {
    final tone = switch (state.mode) {
      HallBellMode.live => StatusChipTone.tertiary,
      HallBellMode.unread => StatusChipTone.primary,
      HallBellMode.muted || HallBellMode.quiet => StatusChipTone.neutral,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest.withValues(alpha: 0.5),
        borderRadius: AppRadii.medium,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(state.icon, color: AppColors.primary, size: AppSpacing.lg),
            const SizedBox(width: AppSpacing.sm),
            StatusChip(
              label: state.label,
              tone: tone,
              showDot: state.hasUnread,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent, required this.onOpenDetails});

  final HallAgentCardModel agent;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final presenceTone = switch (agent.presence) {
      AgentPresence.debating => StatusChipTone.tertiary,
      AgentPresence.online => StatusChipTone.primary,
      AgentPresence.offline => StatusChipTone.neutral,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('agent-card-${agent.id}'),
        onTap: onOpenDetails,
        borderRadius: AppRadii.large,
        child: GlassPanel(
          padding: const EdgeInsets.all(AppSpacing.lg),
          accentColor: agent.isDebating
              ? AppColors.tertiary
              : AppColors.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighest.withValues(alpha: 0.7),
                      borderRadius: AppRadii.medium,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Icon(
                        agent.isDebating
                            ? Icons.forum_rounded
                            : agent.isOnline
                            ? Icons.smart_toy_rounded
                            : Icons.cloud_off_rounded,
                        color: agent.isDebating
                            ? AppColors.tertiary
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  StatusChip(label: agent.presenceLabel, tone: presenceTone),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                agent.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                agent.headline,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.primaryFixed,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                agent.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: agent.skills
                    .map(
                      (skill) => StatusChip(
                        label: skill,
                        tone: StatusChipTone.neutral,
                        showDot: false,
                      ),
                    )
                    .toList(),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: PrimaryGradientButton(
                      key: Key(
                        'agent-cta-${agent.primaryActionLabel.toLowerCase()}-${agent.id}',
                      ),
                      label: agent.primaryActionLabel,
                      icon: agent.directMessageAllowed
                          ? Icons.chat_bubble_rounded
                          : Icons.key_rounded,
                      onPressed: onOpenDetails,
                    ),
                  ),
                  if (agent.canJoinDebate) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: PrimaryGradientButton(
                        key: Key('agent-cta-join-${agent.id}'),
                        label: 'Join',
                        icon: Icons.forum_rounded,
                        useTertiary: true,
                        onPressed: onOpenDetails,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentDetailSheet extends StatelessWidget {
  const _AgentDetailSheet({required this.agent});

  final HallAgentCardModel agent;

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
        key: const Key('agent-detail-sheet'),
        borderRadius: AppRadii.hero,
        padding: const EdgeInsets.all(AppSpacing.xl),
        accentColor: agent.isDebating ? AppColors.tertiary : AppColors.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                key: const Key('agent-detail-close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: agent.isDebating
                        ? AppEffects.tertiaryGradient
                        : AppEffects.primaryGradient,
                    borderRadius: AppRadii.large,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Icon(Icons.smart_toy_rounded, color: Colors.white),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.name,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        agent.headline,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      StatusChip(
                        label: agent.presenceLabel,
                        tone: agent.isDebating
                            ? StatusChipTone.tertiary
                            : agent.isOnline
                            ? StatusChipTone.primary
                            : StatusChipTone.neutral,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              agent.description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Public metadata'.toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.primaryFixed),
            ),
            const SizedBox(height: AppSpacing.md),
            ...agent.metadata.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        item.label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        item.value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: PrimaryGradientButton(
                    label: agent.primaryActionLabel,
                    icon: agent.directMessageAllowed
                        ? Icons.chat_bubble_rounded
                        : Icons.key_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                if (agent.canJoinDebate) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: PrimaryGradientButton(
                      label: 'Join debate',
                      icon: Icons.forum_rounded,
                      useTertiary: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
