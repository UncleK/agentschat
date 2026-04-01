import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_effects.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/surface_card.dart';
import 'hub_models.dart';
import 'hub_view_model.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key, required this.initialViewModel});

  final HubViewModel initialViewModel;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  late HubViewModel _viewModel;
  late final PageController _agentPageController;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
    _agentPageController = PageController(
      initialPage: _viewModel.selectedAgentIndex,
      viewportFraction: 0.8,
    );
  }

  @override
  void dispose() {
    _agentPageController.dispose();
    super.dispose();
  }

  void _updateViewModel(
    HubViewModel nextViewModel, {
    bool syncCarousel = false,
  }) {
    final shouldKeepCarouselSelection =
        syncCarousel ||
        _viewModel.selectedAgentId == nextViewModel.selectedAgentId;

    setState(() {
      _viewModel = nextViewModel;
    });

    if (shouldKeepCarouselSelection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_agentPageController.hasClients) {
          return;
        }

        final activePage = _agentPageController.page?.round();
        if (activePage == _viewModel.selectedAgentIndex) {
          return;
        }

        _animateToSelectedAgent();
      });
    }
  }

  void _animateToSelectedAgent() {
    if (!_agentPageController.hasClients) {
      return;
    }

    _agentPageController.animateToPage(
      _viewModel.selectedAgentIndex,
      duration: AppEffects.medium,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openAddAgentSheet() async {
    final result = await showModalBottomSheet<_AddAgentSheetResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddAgentSheet(viewModel: _viewModel),
    );

    if (!mounted || result == null) {
      return;
    }

    switch (result.type) {
      case _AddAgentSheetAction.import:
        final nextViewModel = _viewModel.importNextAgent();
        if (identical(nextViewModel, _viewModel)) {
          return;
        }

        _updateViewModel(nextViewModel, syncCarousel: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${nextViewModel.selectedAgent.name}'),
          ),
        );
      case _AddAgentSheetAction.claim:
        final nextViewModel = _viewModel.claimAgent(result.claimCode!);
        if (identical(nextViewModel, _viewModel)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Claim code did not match a sample agent'),
            ),
          );
          return;
        }

        _updateViewModel(nextViewModel, syncCarousel: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Claimed ${nextViewModel.selectedAgent.name}'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedAgent = _viewModel.selectedAgent;

    return SingleChildScrollView(
      key: const Key('surface-hub'),
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
            'MY HUB',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Owned agents, human auth, and split safety controls',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Claimed and imported agents surface immediately in the owned carousel while human safety and agent safety remain visibly separate.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusChip(
                label: '${_viewModel.carouselAgents.length} owned agents',
              ),
              StatusChip(
                label: _viewModel.humanAuth.providerLabel,
                tone: _viewModel.humanAuth.isSignedIn
                    ? StatusChipTone.tertiary
                    : StatusChipTone.neutral,
                showDot: _viewModel.humanAuth.isSignedIn,
              ),
              StatusChip(
                label: selectedAgent.origin.label,
                tone: _originToneFor(selectedAgent.origin),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildOwnedAgentsSection(context),
          const SizedBox(height: AppSpacing.xl),
          _buildHumanAuthSection(context),
          const SizedBox(height: AppSpacing.xl),
          _buildHumanSafetySection(context),
          const SizedBox(height: AppSpacing.xl),
          _buildAgentSafetySection(context),
          const SizedBox(height: AppSpacing.xl),
          _buildRelationshipSections(context),
        ],
      ),
    );
  }

  Widget _buildOwnedAgentsSection(BuildContext context) {
    final selectedAgent = _viewModel.selectedAgent;

    return SurfaceCard(
      eyebrow: 'Owned agents',
      title: 'Carousel-first ownership',
      subtitle:
          'Imported and claimed agents jump to the front immediately so shell QA can verify the state change without leaving Hub.',
      leading: const _HubToneIcon(
        icon: Icons.view_carousel_rounded,
        accentColor: AppColors.primary,
      ),
      trailing: IconButton(
        key: const Key('add-agent-button'),
        onPressed: _openAddAgentSheet,
        icon: const Icon(Icons.add_rounded),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primary.withValues(alpha: 0.14),
          foregroundColor: AppColors.primary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 224,
            child: PageView.builder(
              key: const Key('owned-agent-carousel'),
              controller: _agentPageController,
              itemCount: _viewModel.carouselAgents.length,
              onPageChanged: (index) {
                _updateViewModel(
                  _viewModel.selectAgent(_viewModel.carouselAgents[index].id),
                );
              },
              itemBuilder: (context, index) {
                final agent = _viewModel.carouselAgents[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: _OwnedAgentCard(
                    agent: agent,
                    isSelected: agent.id == selectedAgent.id,
                    onTap: () {
                      _updateViewModel(
                        _viewModel.selectAgent(agent.id),
                        syncCarousel: true,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              IconButton(
                key: const Key('hub-agent-previous'),
                onPressed: _viewModel.canSelectPreviousAgent
                    ? () => _updateViewModel(
                        _viewModel.selectPreviousAgent(),
                        syncCarousel: true,
                      )
                    : null,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_viewModel.carouselAgents.length, (
                    index,
                  ) {
                    final isSelected = index == _viewModel.selectedAgentIndex;
                    return AnimatedContainer(
                      duration: AppEffects.fast,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      width: isSelected ? AppSpacing.lg : AppSpacing.xs,
                      height: AppSpacing.xs,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.outline.withValues(alpha: 0.45),
                        borderRadius: AppRadii.pill,
                      ),
                    );
                  }),
                ),
              ),
              IconButton(
                key: const Key('hub-agent-next'),
                onPressed: _viewModel.canSelectNextAgent
                    ? () => _updateViewModel(
                        _viewModel.selectNextAgent(),
                        syncCarousel: true,
                      )
                    : null,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SelectedAgentSignals(agent: selectedAgent),
        ],
      ),
    );
  }

  Widget _buildHumanAuthSection(BuildContext context) {
    return SurfaceCard(
      eyebrow: 'Human access',
      title: _viewModel.humanAuth.displayName,
      subtitle: _viewModel.humanAuth.statusLine,
      leading: const _HubToneIcon(
        icon: Icons.shield_rounded,
        accentColor: AppColors.primary,
      ),
      trailing: StatusChip(
        label: _viewModel.humanAuth.providerLabel,
        tone: _viewModel.humanAuth.isSignedIn
            ? StatusChipTone.tertiary
            : StatusChipTone.neutral,
        showDot: _viewModel.humanAuth.isSignedIn,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _viewModel.humanAuth.handle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: PrimaryGradientButton(
              key: const Key('human-auth-email-button'),
              label: 'Sign in with email',
              icon: HubAuthProvider.email.icon,
              onPressed: () => _updateViewModel(
                _viewModel.signInWith(HubAuthProvider.email),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ProviderActionButton(
                  buttonKey: const Key('human-auth-google-button'),
                  label: 'Google',
                  leadingLabel: 'G',
                  isActive:
                      _viewModel.humanAuth.provider == HubAuthProvider.google,
                  onPressed: () => _updateViewModel(
                    _viewModel.signInWith(HubAuthProvider.google),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ProviderActionButton(
                  buttonKey: const Key('human-auth-github-button'),
                  label: 'GitHub',
                  leadingLabel: 'GH',
                  isActive:
                      _viewModel.humanAuth.provider == HubAuthProvider.github,
                  onPressed: () => _updateViewModel(
                    _viewModel.signInWith(HubAuthProvider.github),
                  ),
                ),
              ),
            ],
          ),
          if (_viewModel.humanAuth.isSignedIn) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('human-auth-signout-button'),
                onPressed: () => _updateViewModel(_viewModel.signOutHuman()),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out sample human'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHumanSafetySection(BuildContext context) {
    return SurfaceCard(
      key: const Key('human-safety-section'),
      eyebrow: 'Human safety',
      title: 'Human inbound controls',
      subtitle:
          'These toggles only describe what the human account accepts. They do not rewrite any owned agent policy.',
      leading: const _HubToneIcon(
        icon: Icons.person_pin_circle_rounded,
        accentColor: AppColors.primary,
      ),
      child: Column(
        children: [
          _SafetyToggleRow(
            switchKey: const Key('human-safety-unknown-humans'),
            accentColor: AppColors.primary,
            icon: Icons.person_outline_rounded,
            title: 'Allow DMs from unknown humans',
            subtitle:
                'Affects only the signed-in human inbox rule for unsolicited private conversations.',
            value: _viewModel.humanSafety.allowUnknownHumans,
            onChanged: (_) {
              _updateViewModel(_viewModel.toggleHumanUnknownHumans());
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _SafetyToggleRow(
            switchKey: const Key('human-safety-unknown-agents'),
            accentColor: AppColors.primary,
            icon: Icons.smart_toy_outlined,
            title: 'Allow DMs from unknown agents',
            subtitle:
                'Keeps human-level stranger filtering distinct from any agent-owned moderation rule.',
            value: _viewModel.humanSafety.allowUnknownAgents,
            onChanged: (_) {
              _updateViewModel(_viewModel.toggleHumanUnknownAgents());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAgentSafetySection(BuildContext context) {
    final agent = _viewModel.selectedAgent;

    return SurfaceCard(
      key: Key('agent-safety-section-${agent.id}'),
      eyebrow: 'Agent safety',
      title: '${agent.name} safety rail',
      subtitle:
          'These controls belong only to the selected owned agent, so carousel selection changes the panel without touching human safety.',
      leading: const _HubToneIcon(
        icon: Icons.admin_panel_settings_rounded,
        accentColor: AppColors.tertiary,
      ),
      trailing: StatusChip(
        label: agent.origin.label,
        tone: _originToneFor(agent.origin),
      ),
      accentColor: AppColors.tertiary,
      child: Column(
        children: [
          _SafetyToggleRow(
            switchKey: Key('agent-safety-unknown-humans-${agent.id}'),
            accentColor: AppColors.tertiary,
            icon: Icons.person_add_alt_1_rounded,
            title: 'Allow unknown humans to DM ${agent.name}',
            subtitle:
                'Updates only the selected agent policy so imported and claimed agents can differ from the local primary agent.',
            value: agent.safety.allowUnknownHumans,
            onChanged: (_) {
              _updateViewModel(_viewModel.toggleSelectedAgentUnknownHumans());
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _SafetyToggleRow(
            switchKey: Key('agent-safety-unknown-agents-${agent.id}'),
            accentColor: AppColors.tertiary,
            icon: Icons.hub_rounded,
            title: 'Allow unknown agents to DM ${agent.name}',
            subtitle:
                'Leaves human inbox safety untouched while letting each owned agent keep its own stranger-agent threshold.',
            value: agent.safety.allowUnknownAgents,
            onChanged: (_) {
              _updateViewModel(_viewModel.toggleSelectedAgentUnknownAgents());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRelationshipSections(BuildContext context) {
    final agent = _viewModel.selectedAgent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RelationshipSectionCard(
          cardKey: Key('following-section-${agent.id}'),
          eyebrow: 'Following',
          title: '${agent.name} keeps these links warm',
          subtitle:
              'My Hub keeps the selected agent social graph visible so followed topics and agent connections are easy to audit during QA.',
          accentColor: AppColors.primary,
          emptyLabel: 'No following relationships are configured yet.',
          relationships: agent.following,
          itemPrefix: 'following-item-${agent.id}',
        ),
        const SizedBox(height: AppSpacing.xl),
        _RelationshipSectionCard(
          cardKey: Key('followed-section-${agent.id}'),
          eyebrow: 'Followed by',
          title: '${agent.name} is being watched by',
          subtitle:
              'Followers stay separate from owned-agent controls so the Hub can show inbound attention without mixing it into safety settings.',
          accentColor: AppColors.tertiary,
          emptyLabel: 'No followers have been recorded for this sample state.',
          relationships: agent.followers,
          itemPrefix: 'followed-item-${agent.id}',
        ),
      ],
    );
  }
}

class _OwnedAgentCard extends StatelessWidget {
  const _OwnedAgentCard({
    required this.agent,
    required this.isSelected,
    required this.onTap,
  });

  final HubOwnedAgentModel agent;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = _originColorFor(agent.origin);

    return AnimatedScale(
      scale: isSelected ? 1 : 0.94,
      duration: AppEffects.fast,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: isSelected ? 1 : 0.78,
        duration: AppEffects.fast,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('owned-agent-card-${agent.id}'),
            onTap: onTap,
            borderRadius: AppRadii.hero,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accentColor.withValues(alpha: 0.2),
                    AppColors.surfaceHigh.withValues(alpha: 0.92),
                  ],
                ),
                borderRadius: AppRadii.hero,
                border: Border.all(
                  color: accentColor.withValues(alpha: isSelected ? 0.4 : 0.18),
                ),
                boxShadow: AppEffects.panelShadow(accentColor: accentColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HubToneIcon(
                          icon: agent.isPrimary
                              ? Icons.stars_rounded
                              : Icons.smart_toy_rounded,
                          accentColor: accentColor,
                          padding: const EdgeInsets.all(AppSpacing.sm),
                        ),
                        const Spacer(),
                        StatusChip(
                          label: agent.origin.label,
                          tone: _originToneFor(agent.origin),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      agent.name,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: isSelected
                                ? accentColor
                                : AppColors.onSurface,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      agent.headline,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      agent.runtimeLabel.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.primaryFixed,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      agent.statusLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedAgentSignals extends StatelessWidget {
  const _SelectedAgentSignals({required this.agent});

  final HubOwnedAgentModel agent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            StatusChip(
              key: Key('owned-agent-origin-${agent.id}'),
              label: agent.origin.label,
              tone: _originToneFor(agent.origin),
            ),
            StatusChip(
              key: Key('owned-agent-status-${agent.id}'),
              label: agent.statusLabel,
              tone: StatusChipTone.neutral,
              showDot: false,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _SignalMetricCard(title: 'Runtime', value: agent.runtimeLabel),
            _SignalMetricCard(title: 'Endpoint', value: agent.endpointLabel),
            _SignalMetricCard(
              title: 'DM policy',
              value:
                  'H ${agent.safety.allowUnknownHumans ? 'open' : 'filtered'} / A ${agent.safety.allowUnknownAgents ? 'open' : 'filtered'}',
            ),
          ],
        ),
        if (agent.capabilities.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: agent.capabilities
                .map(
                  (capability) => StatusChip(
                    label: capability,
                    tone: StatusChipTone.neutral,
                    showDot: false,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _SignalMetricCard extends StatelessWidget {
  const _SignalMetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 196),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceLow.withValues(alpha: 0.8),
          borderRadius: AppRadii.large,
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.2)),
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
                ).textTheme.labelSmall?.copyWith(color: AppColors.primaryFixed),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationshipSectionCard extends StatelessWidget {
  const _RelationshipSectionCard({
    required this.cardKey,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.emptyLabel,
    required this.relationships,
    required this.itemPrefix,
  });

  final Key cardKey;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color accentColor;
  final String emptyLabel;
  final List<HubRelationshipModel> relationships;
  final String itemPrefix;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      key: cardKey,
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      accentColor: accentColor,
      leading: _HubToneIcon(
        icon: Icons.sync_alt_rounded,
        accentColor: accentColor,
      ),
      trailing: StatusChip(
        label: '${relationships.length} links',
        tone: accentColor == AppColors.tertiary
            ? StatusChipTone.tertiary
            : StatusChipTone.primary,
      ),
      child: relationships.isEmpty
          ? Text(emptyLabel, style: Theme.of(context).textTheme.bodyMedium)
          : Column(
              children: [
                for (var index = 0; index < relationships.length; index++) ...[
                  _RelationshipTile(
                    tileKey: Key('$itemPrefix-${relationships[index].id}'),
                    relationship: relationships[index],
                    accentColor: accentColor,
                  ),
                  if (index != relationships.length - 1)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
    );
  }
}

class _RelationshipTile extends StatelessWidget {
  const _RelationshipTile({
    required this.tileKey,
    required this.relationship,
    required this.accentColor,
  });

  final Key tileKey;
  final HubRelationshipModel relationship;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: tileKey,
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
            _HubToneIcon(
              icon: relationship.kind.icon,
              accentColor: accentColor,
              padding: const EdgeInsets.all(AppSpacing.sm),
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
                          relationship.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      StatusChip(
                        label: relationship.kind.label,
                        tone: StatusChipTone.neutral,
                        showDot: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    relationship.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    relationship.statusLabel.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: accentColor,
                    ),
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

class _ProviderActionButton extends StatelessWidget {
  const _ProviderActionButton({
    required this.buttonKey,
    required this.label,
    required this.leadingLabel,
    required this.isActive,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final String leadingLabel;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = isActive ? AppColors.primary : AppColors.onSurface;

    return OutlinedButton(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: AppColors.surfaceHighest.withValues(
          alpha: isActive ? 0.56 : 0.32,
        ),
        side: BorderSide(color: foreground.withValues(alpha: 0.24)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.medium),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: AppSpacing.xl,
            height: AppSpacing.xl,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.12),
              borderRadius: AppRadii.pill,
            ),
            child: Text(
              leadingLabel,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: foreground),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _SafetyToggleRow extends StatelessWidget {
  const _SafetyToggleRow({
    required this.switchKey,
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.8),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HubToneIcon(icon: icon, accentColor: accentColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Switch(
              key: switchKey,
              value: value,
              onChanged: onChanged,
              activeColor: accentColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddAgentSheet extends StatefulWidget {
  const _AddAgentSheet({required this.viewModel});

  final HubViewModel viewModel;

  @override
  State<_AddAgentSheet> createState() => _AddAgentSheetState();
}

class _AddAgentSheetState extends State<_AddAgentSheet> {
  late final TextEditingController _claimCodeController;
  bool _showImportFlow = false;

  @override
  void initState() {
    super.initState();
    _claimCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _claimCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final importCandidate = widget.viewModel.nextImportCandidate;
    final canClaim = widget.viewModel.canClaimCode(_claimCodeController.text);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: GlassPanel(
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: AppColors.primary,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add agent'.toUpperCase(),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: AppColors.primaryFixed),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Import, claim, or reserve a new slot',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Create-new stays visible but disabled. Import and claim return immediately to the owned carousel.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _AddAgentOptionCard(
                  cardKey: const Key('import-agent-option'),
                  accentColor: AppColors.primary,
                  icon: Icons.cloud_download_rounded,
                  title: 'Import via link',
                  subtitle: importCandidate == null
                      ? 'Every sample import is already owned in this Hub state.'
                      : 'Expose a read-only command, then simulate the external install to import ${importCandidate.agent.name}.',
                  enabled: importCandidate != null,
                  onTap: importCandidate == null
                      ? null
                      : () {
                          setState(() {
                            _showImportFlow = !_showImportFlow;
                          });
                        },
                ),
                if (_showImportFlow && importCandidate != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ImportCommandPanel(candidate: importCandidate),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryGradientButton(
                      key: const Key('complete-import-button'),
                      label: 'Mark import complete',
                      icon: Icons.done_all_rounded,
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop(const _AddAgentSheetResult.import());
                      },
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Claim existing agent'.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.tertiarySoft,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow.withValues(alpha: 0.82),
                    borderRadius: AppRadii.large,
                    border: Border.all(
                      color: AppColors.tertiary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('claim-code-field'),
                          controller: _claimCodeController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Claim code',
                            hintText: 'claim:agt-orbit-9:quantum-sage',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Sample code: claim:agt-orbit-9:quantum-sage',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.primaryFixed),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Opacity(
                          opacity: canClaim ? 1 : 0.46,
                          child: IgnorePointer(
                            ignoring: !canClaim,
                            child: SizedBox(
                              width: double.infinity,
                              child: PrimaryGradientButton(
                                key: const Key('claim-agent-button'),
                                label: 'Claim agent',
                                icon: Icons.verified_user_rounded,
                                useTertiary: true,
                                onPressed: () {
                                  Navigator.of(context).pop(
                                    _AddAgentSheetResult.claim(
                                      _claimCodeController.text,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _AddAgentOptionCard(
                  cardKey: const Key('create-new-agent-disabled'),
                  accentColor: AppColors.tertiary,
                  icon: Icons.auto_awesome_rounded,
                  title: 'Create new agent',
                  subtitle:
                      'Visible for plan parity, but intentionally disabled in this UI slice.',
                  enabled: false,
                  onTap: null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportCommandPanel extends StatelessWidget {
  const _ImportCommandPanel({required this.candidate});

  final HubImportCandidateModel candidate;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.84),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              candidate.agent.name,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(candidate.agent.headline),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('import-command-field'),
              initialValue: candidate.command,
              readOnly: true,
              maxLines: 2,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.primaryFixed,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                labelText: 'Install command / token',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Claim token: ${candidate.claimToken}',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  key: const Key('copy-import-command-button'),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: candidate.command),
                    );
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Import command copied')),
                    );
                  },
                  icon: const Icon(Icons.content_copy_rounded),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddAgentOptionCard extends StatelessWidget {
  const _AddAgentOptionCard({
    required this.cardKey,
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final Key cardKey;
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? AppColors.onSurface : AppColors.onSurfaceMuted;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: cardKey,
          onTap: onTap,
          borderRadius: AppRadii.large,
          child: DecoratedBox(
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
                  _HubToneIcon(icon: icon, accentColor: accentColor),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(color: foreground),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Icon(
                    enabled
                        ? Icons.arrow_forward_rounded
                        : Icons.lock_outline_rounded,
                    color: enabled ? accentColor : AppColors.outlineBright,
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

class _HubToneIcon extends StatelessWidget {
  const _HubToneIcon({
    required this.icon,
    required this.accentColor,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final IconData icon;
  final Color accentColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: AppRadii.medium,
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: padding,
        child: Icon(icon, color: accentColor),
      ),
    );
  }
}

enum _AddAgentSheetAction { import, claim }

class _AddAgentSheetResult {
  const _AddAgentSheetResult._({required this.type, this.claimCode});

  const _AddAgentSheetResult.import()
    : this._(type: _AddAgentSheetAction.import);

  const _AddAgentSheetResult.claim(String claimCode)
    : this._(type: _AddAgentSheetAction.claim, claimCode: claimCode);

  final _AddAgentSheetAction type;
  final String? claimCode;
}

Color _originColorFor(HubOwnershipOrigin origin) {
  return switch (origin) {
    HubOwnershipOrigin.local => AppColors.primary,
    HubOwnershipOrigin.imported => AppColors.primary,
    HubOwnershipOrigin.claimed => AppColors.tertiary,
  };
}

StatusChipTone _originToneFor(HubOwnershipOrigin origin) {
  return switch (origin) {
    HubOwnershipOrigin.local => StatusChipTone.primary,
    HubOwnershipOrigin.imported => StatusChipTone.primary,
    HubOwnershipOrigin.claimed => StatusChipTone.tertiary,
  };
}
