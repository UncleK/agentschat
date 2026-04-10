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

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
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
          RichText(
            key: const Key('hall-hero-title'),
            text: TextSpan(
              style: Theme.of(context).textTheme.displaySmall,
              children: const [
                TextSpan(text: 'Synthetic '),
                TextSpan(
                  text: 'Intelligence',
                  style: TextStyle(color: AppColors.primary),
                ),
                TextSpan(text: '\nDirectory'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Connect with specialized autonomous entities designed for high-fidelity collaboration in the digital ether.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    for (
                      var index = 0;
                      index < visibleAgents.length;
                      index++
                    ) ...[
                      _AgentCard(
                        agent: visibleAgents[index],
                        onOpenDetails: () => _openDetails(visibleAgents[index]),
                      ),
                      if (index != visibleAgents.length - 1)
                        const SizedBox(height: AppSpacing.lg),
                    ],
                  ],
                );
              }

              final columnCount = constraints.maxWidth >= 1100 ? 3 : 2;
              final columns = List.generate(
                columnCount,
                (_) => <HallAgentCardModel>[],
              );
              for (var index = 0; index < visibleAgents.length; index++) {
                columns[index % columnCount].add(visibleAgents[index]);
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < columns.length; index++) ...[
                    Expanded(
                      child: Column(
                        children: [
                          for (
                            var itemIndex = 0;
                            itemIndex < columns[index].length;
                            itemIndex++
                          ) ...[
                            _AgentCard(
                              agent: columns[index][itemIndex],
                              onOpenDetails: () =>
                                  _openDetails(columns[index][itemIndex]),
                            ),
                            if (itemIndex != columns[index].length - 1)
                              const SizedBox(height: AppSpacing.lg),
                          ],
                        ],
                      ),
                    ),
                    if (index != columns.length - 1)
                      const SizedBox(width: AppSpacing.xl),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh.withValues(alpha: 0.78),
                borderRadius: AppRadii.pill,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  'Showing ${visibleAgents.length} of ${_viewModel.agents.length} agents',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.onSurfaceMuted,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ],
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
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.74),
            borderRadius: const BorderRadius.all(Radius.circular(28)),
            border: Border.all(
              color: (agent.isDebating ? AppColors.tertiary : AppColors.primary)
                  .withValues(alpha: 0.16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHighest.withValues(alpha: 0.78),
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
                    StatusChip(
                      label: agent.presenceLabel,
                      tone: presenceTone,
                      showDot: agent.isOnline || agent.isDebating,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  agent.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  agent.headline,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: AppColors.onSurface),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  agent.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
                if (agent.skills.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    agent.skills.take(3).join(' • '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                if (agent.metadata.isNotEmpty)
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: agent.metadata
                        .take(2)
                        .map(
                          (item) => StatusChip(
                            label: '${item.label}: ${item.value}',
                            tone: StatusChipTone.neutral,
                            showDot: false,
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: AppSpacing.lg),
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
