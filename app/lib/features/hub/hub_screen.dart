import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/session/app_session_scope.dart';
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
  const HubScreen({super.key});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  static const HubSafetySettings _defaultHumanSafety = HubSafetySettings(
    allowUnknownHumans: false,
    allowUnknownAgents: true,
  );
  static const HubSafetySettings _defaultAgentSafety = HubSafetySettings(
    allowUnknownHumans: false,
    allowUnknownAgents: false,
  );

  late final PageController _agentPageController;
  HubSafetySettings _humanSafety = _defaultHumanSafety;
  final Map<String, HubSafetySettings> _agentSafetyOverrides =
      <String, HubSafetySettings>{};
  String? _lastCarouselAgentId;

  @override
  void initState() {
    super.initState();
    _agentPageController = PageController(viewportFraction: 0.8);
  }

  @override
  void dispose() {
    _agentPageController.dispose();
    super.dispose();
  }

  Future<void> _refreshMine() async {
    final session = AppSessionScope.read(context);
    try {
      await session.refreshMine();
      if (!mounted) {
        return;
      }
      _showSnackBar('Hub partitions refreshed');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Unable to refresh Hub right now');
    }
  }

  Future<void> _selectOwnedAgent(String agentId) async {
    final session = AppSessionScope.read(context);
    await session.setCurrentActiveAgent(agentId);
  }

  Future<void> _claimAgent(HubClaimableAgentModel agent) async {
    final session = AppSessionScope.read(context);
    try {
      final resolvedAgent = await session.claimAgent(agent.id);
      if (!mounted) {
        return;
      }

      final displayName = resolvedAgent?.displayName ?? agent.name;
      _showSnackBar('Claimed $displayName');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Unable to claim ${agent.name}');
    }
  }

  Future<void> _openAddAgentSheet(bool isSignedIn) async {
    final result = await showModalBottomSheet<_AddAgentSheetResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddAgentSheet(isSignedIn: isSignedIn),
    );

    if (!mounted || result == null) {
      return;
    }

    final session = AppSessionScope.read(context);
    try {
      final resolvedAgent = await session.importHumanOwnedAgent(
        handle: result.handle,
        displayName: result.displayName,
        bio: result.bio,
      );
      if (!mounted) {
        return;
      }

      final displayName = resolvedAgent?.displayName ?? result.displayName;
      _showSnackBar('Imported $displayName');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Unable to import ${result.displayName}');
    }
  }

  Future<String> _submitHumanAuth({
    required _HumanAuthMode mode,
    required String email,
    required String displayName,
    required String password,
  }) async {
    final session = AppSessionScope.read(context);
    final authRepository = session.authRepository;
    final authState = switch (mode) {
      _HumanAuthMode.signIn => await authRepository.loginWithEmail(
        email: email,
        password: password,
      ),
      _HumanAuthMode.register => await authRepository.registerWithEmail(
        email: email,
        displayName: displayName,
        password: password,
      ),
    };

    await session.authenticate(authState);

    return switch (mode) {
      _HumanAuthMode.signIn => 'Signed in as ${authState.displayName}',
      _HumanAuthMode.register => 'Created account for ${authState.displayName}',
    };
  }

  Future<void> _openHumanAuthSheet(_HumanAuthMode mode) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _HumanAuthSheet(initialMode: mode, onSubmit: _submitHumanAuth),
    );

    if (!mounted || message == null) {
      return;
    }

    _showSnackBar(message);
  }

  Future<void> _disconnectHumanSession() async {
    final session = AppSessionScope.read(context);
    await session.logout();
    if (!mounted) {
      return;
    }
    _showSnackBar('Signed out of the current human session');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleHumanUnknownHumans() {
    setState(() {
      _humanSafety = _humanSafety.copyWith(
        allowUnknownHumans: !_humanSafety.allowUnknownHumans,
      );
    });
  }

  void _toggleHumanUnknownAgents() {
    setState(() {
      _humanSafety = _humanSafety.copyWith(
        allowUnknownAgents: !_humanSafety.allowUnknownAgents,
      );
    });
  }

  void _toggleSelectedAgentUnknownHumans(String agentId) {
    final current = _agentSafetyOverrides[agentId] ?? _defaultAgentSafety;
    setState(() {
      _agentSafetyOverrides[agentId] = current.copyWith(
        allowUnknownHumans: !current.allowUnknownHumans,
      );
    });
  }

  void _toggleSelectedAgentUnknownAgents(String agentId) {
    final current = _agentSafetyOverrides[agentId] ?? _defaultAgentSafety;
    setState(() {
      _agentSafetyOverrides[agentId] = current.copyWith(
        allowUnknownAgents: !current.allowUnknownAgents,
      );
    });
  }

  HubViewModel _buildViewModel() {
    final session = AppSessionScope.of(context);
    return HubViewModel.fromSession(
      authState: session.authState,
      ownedAgents: session.currentActiveAgentCandidates,
      claimableAgents: session.claimableAgents,
      pendingClaims: session.pendingClaims,
      selectedAgentId: session.currentActiveAgent?.id,
      humanSafety: _humanSafety,
      agentSafetyOverrides: _agentSafetyOverrides,
    );
  }

  void _scheduleCarouselSync(HubViewModel viewModel) {
    final selectedAgentId = viewModel.selectedAgentOrNull?.id;
    if (selectedAgentId == null) {
      _lastCarouselAgentId = null;
      return;
    }

    if (_lastCarouselAgentId == selectedAgentId) {
      return;
    }
    _lastCarouselAgentId = selectedAgentId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_agentPageController.hasClients) {
        return;
      }

      final targetIndex = viewModel.selectedAgentIndex;
      final activePage = _agentPageController.page?.round();
      if (activePage == targetIndex) {
        return;
      }

      if (activePage == null || (activePage - targetIndex).abs() > 1) {
        _agentPageController.jumpToPage(targetIndex);
        return;
      }

      _agentPageController.animateToPage(
        targetIndex,
        duration: AppEffects.medium,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    final viewModel = _buildViewModel();
    _scheduleCarouselSync(viewModel);

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
          Text('My Hub', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Owned agents, followed graphs, human access, and security controls now live in one session-driven surface.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          _buildOwnedAgentsSection(viewModel, session.isRefreshingMine),
          const SizedBox(height: AppSpacing.xl),
          _buildRelationshipSections(viewModel),
          const SizedBox(height: AppSpacing.xl),
          _buildClaimableAgentsSection(viewModel, session.isRefreshingMine),
          const SizedBox(height: AppSpacing.xl),
          _buildPendingClaimsSection(viewModel),
          const SizedBox(height: AppSpacing.xl),
          _buildHumanAuthSection(viewModel, session.isRefreshingMine),
          const SizedBox(height: AppSpacing.xl),
          _buildHumanSafetySection(viewModel),
          const SizedBox(height: AppSpacing.xl),
          _buildAgentSafetySection(viewModel),
        ],
      ),
    );
  }

  Widget _buildOwnedAgentsSection(
    HubViewModel viewModel,
    bool isRefreshingMine,
  ) {
    final selectedAgent = viewModel.selectedAgentOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'My Agent Profile'.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  letterSpacing: 2.2,
                ),
              ),
            ),
            IconButton(
              key: const Key('refresh-hub-button'),
              onPressed: isRefreshingMine ? null : _refreshMine,
              icon: isRefreshingMine
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceHighest.withValues(
                  alpha: 0.36,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              key: const Key('add-agent-button'),
              onPressed: isRefreshingMine || !viewModel.humanAuth.isSignedIn
                  ? null
                  : () => _openAddAgentSheet(viewModel.humanAuth.isSignedIn),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.78),
            borderRadius: const BorderRadius.all(Radius.circular(32)),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.14),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: viewModel.hasOwnedAgents
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 236,
                        child: PageView.builder(
                          key: const Key('owned-agent-carousel'),
                          controller: _agentPageController,
                          itemCount: viewModel.carouselAgents.length,
                          onPageChanged: (index) {
                            unawaited(
                              _selectOwnedAgent(
                                viewModel.carouselAgents[index].id,
                              ),
                            );
                          },
                          itemBuilder: (context, index) {
                            final agent = viewModel.carouselAgents[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                              ),
                              child: _OwnedAgentCard(
                                agent: agent,
                                isSelected: agent.id == selectedAgent?.id,
                                onTap: () {
                                  unawaited(_selectOwnedAgent(agent.id));
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: Text(
                          'Swipe or tap to change the current active agent. DM follows this selection.',
                          key: const Key('active-agent-carousel-hint'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.onSurfaceMuted),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          IconButton(
                            key: const Key('hub-agent-previous'),
                            onPressed: viewModel.canSelectPreviousAgent
                                ? () {
                                    unawaited(
                                      _selectOwnedAgent(
                                        viewModel
                                            .carouselAgents[viewModel
                                                    .selectedAgentIndex -
                                                1]
                                            .id,
                                      ),
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  viewModel.carouselAgents.length,
                                  (index) {
                                    final isSelected =
                                        index == viewModel.selectedAgentIndex;
                                    return AnimatedContainer(
                                      duration: AppEffects.fast,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xxs,
                                      ),
                                      width: isSelected
                                          ? AppSpacing.lg
                                          : AppSpacing.xs,
                                      height: AppSpacing.xs,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.outline.withValues(
                                                alpha: 0.45,
                                              ),
                                        borderRadius: AppRadii.pill,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('hub-agent-next'),
                            onPressed: viewModel.canSelectNextAgent
                                ? () {
                                    unawaited(
                                      _selectOwnedAgent(
                                        viewModel
                                            .carouselAgents[viewModel
                                                    .selectedAgentIndex +
                                                1]
                                            .id,
                                      ),
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (selectedAgent != null)
                        _SelectedAgentSignals(agent: selectedAgent),
                    ],
                  )
                : const _EmptyStatePanel(
                    icon: Icons.lock_person_rounded,
                    title: 'No directly usable owned agents yet',
                    body:
                        'Import a human-owned agent or finish a claim. Claimable and pending records stay visible below, but they never become active until they move into the owned partition.',
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildClaimableAgentsSection(
    HubViewModel viewModel,
    bool isRefreshingMine,
  ) {
    return SurfaceCard(
      key: const Key('claimable-agents-section'),
      eyebrow: 'Claimable agents',
      title: 'Self-owned inventory waiting for claim',
      subtitle:
          'These agents are visible to the current human, but they cannot become active until the claim flow refreshes them into the owned partition.',
      leading: const _HubToneIcon(
        icon: Icons.verified_user_rounded,
        accentColor: AppColors.tertiary,
      ),
      accentColor: AppColors.tertiary,
      child: viewModel.hasClaimableAgents
          ? Column(
              children: [
                for (
                  var index = 0;
                  index < viewModel.claimableAgents.length;
                  index++
                ) ...[
                  _ClaimableAgentRow(
                    agent: viewModel.claimableAgents[index],
                    isBusy: isRefreshingMine,
                    canClaim: viewModel.humanAuth.isSignedIn,
                    onClaim: () =>
                        _claimAgent(viewModel.claimableAgents[index]),
                  ),
                  if (index != viewModel.claimableAgents.length - 1)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            )
          : const _EmptyStatePanel(
              icon: Icons.inventory_2_outlined,
              title: 'No claimable agents right now',
              body:
                  'Any self-owned agents that the current human can claim will appear here until the claim completes.',
            ),
    );
  }

  Widget _buildPendingClaimsSection(HubViewModel viewModel) {
    return SurfaceCard(
      key: const Key('pending-claims-section'),
      eyebrow: 'Pending claims',
      title: 'Requests waiting for confirmation',
      subtitle:
          'Pending claims remain visible but inactive so Hub never promotes them into the global session before they are fully usable.',
      leading: const _HubToneIcon(
        icon: Icons.hourglass_top_rounded,
        accentColor: AppColors.primaryFixed,
      ),
      child: viewModel.hasPendingClaims
          ? Column(
              children: [
                for (
                  var index = 0;
                  index < viewModel.pendingClaims.length;
                  index++
                ) ...[
                  _PendingClaimRow(claim: viewModel.pendingClaims[index]),
                  if (index != viewModel.pendingClaims.length - 1)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            )
          : const _EmptyStatePanel(
              icon: Icons.pending_actions_rounded,
              title: 'No pending claims',
              body:
                  'Claim requests that are still waiting on confirmation will stay here until they either expire or become owned agents.',
            ),
    );
  }

  Widget _buildHumanAuthSection(HubViewModel viewModel, bool isRefreshingMine) {
    return SurfaceCard(
      key: const Key('human-access-section'),
      eyebrow: 'Human access',
      title: 'Human Access',
      subtitle: viewModel.humanAuth.isSignedIn
          ? 'Manage the live human session that owns and operates this Hub.'
          : 'Sign in, create an account, or review external provider availability.',
      leading: const _HubToneIcon(
        icon: Icons.shield_rounded,
        accentColor: AppColors.primary,
      ),
      trailing: StatusChip(
        label: viewModel.humanAuth.providerLabel,
        tone: viewModel.humanAuth.isSignedIn
            ? StatusChipTone.tertiary
            : StatusChipTone.neutral,
        showDot: viewModel.humanAuth.isSignedIn,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewModel.humanAuth.isSignedIn) ...[
            _HumanSessionSummaryCard(model: viewModel.humanAuth),
            const SizedBox(height: AppSpacing.md),
            _HubActionRow(
              rowKey: const Key('hub-refresh-button'),
              accentColor: AppColors.primary,
              icon: Icons.refresh_rounded,
              title: isRefreshingMine
                  ? 'Refreshing owned partitions'
                  : 'Refresh owned partitions',
              subtitle:
                  'Sync live owned, claimable, and pending partitions from the current authenticated session.',
              enabled: !isRefreshingMine,
              onTap: isRefreshingMine
                  ? null
                  : () {
                      unawaited(_refreshMine());
                    },
            ),
            const SizedBox(height: AppSpacing.md),
            _HubActionRow(
              rowKey: const Key('human-auth-logout-button'),
              accentColor: AppColors.error,
              icon: Icons.logout_rounded,
              title: 'Disconnect all sessions',
              subtitle:
                  'Clear the current human session from this device and return Hub to signed-out mode.',
              enabled: true,
              onTap: () {
                unawaited(_disconnectHumanSession());
              },
            ),
          ] else ...[
            _HubActionRow(
              rowKey: const Key('human-auth-email-button'),
              accentColor: AppColors.primary,
              icon: Icons.person_rounded,
              title: 'Sign in as human',
              subtitle: 'Biometric or passkey later. Email + password now.',
              enabled: true,
              onTap: () {
                unawaited(_openHumanAuthSheet(_HumanAuthMode.signIn));
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _HubActionRow(
              rowKey: const Key('human-auth-register-button'),
              accentColor: AppColors.outlineBright,
              icon: Icons.person_add_rounded,
              title: 'Create new human account',
              subtitle:
                  'Register a live account and immediately bootstrap the owned-agent session.',
              enabled: true,
              onTap: () {
                unawaited(_openHumanAuthSheet(_HumanAuthMode.register));
              },
            ),
            const SizedBox(height: AppSpacing.md),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceLow.withValues(alpha: 0.82),
                borderRadius: AppRadii.large,
                border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.16),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'External Identity Providers'.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _ProviderActionButton(
                            buttonKey: const Key('human-auth-google-button'),
                            label: 'Google',
                            icon: Icons.account_circle_outlined,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _ProviderActionButton(
                            buttonKey: const Key('human-auth-github-button'),
                            label: 'GitHub',
                            icon: Icons.code_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'External-provider login is intentionally disabled in this release until provider token verification is fully implemented.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHumanSafetySection(HubViewModel viewModel) {
    return SurfaceCard(
      key: const Key('human-safety-section'),
      eyebrow: 'Human safety',
      title: 'Human inbound controls',
      subtitle:
          'These toggles describe what the signed-in human accepts. They remain separate from every owned-agent rule.',
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
            value: viewModel.humanSafety.allowUnknownHumans,
            onChanged: (_) => _toggleHumanUnknownHumans(),
          ),
          const SizedBox(height: AppSpacing.md),
          _SafetyToggleRow(
            switchKey: const Key('human-safety-unknown-agents'),
            accentColor: AppColors.primary,
            icon: Icons.smart_toy_outlined,
            title: 'Allow DMs from unknown agents',
            subtitle:
                'Keeps human-level stranger filtering distinct from any agent-owned moderation rule.',
            value: viewModel.humanSafety.allowUnknownAgents,
            onChanged: (_) => _toggleHumanUnknownAgents(),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentSafetySection(HubViewModel viewModel) {
    final agent = viewModel.selectedAgentOrNull;
    if (agent == null) {
      return const SurfaceCard(
        key: Key('agent-safety-empty'),
        eyebrow: 'Agent safety',
        title: 'No active owned agent selected',
        subtitle:
            'Agent-specific safety controls unlock only after an owned agent becomes the active session agent.',
        leading: _HubToneIcon(
          icon: Icons.admin_panel_settings_rounded,
          accentColor: AppColors.tertiary,
        ),
        accentColor: AppColors.tertiary,
        child: _EmptyStatePanel(
          icon: Icons.smart_toy_outlined,
          title: 'No active agent',
          body:
              'Claimable and pending entries never receive active-agent controls until they refresh into the owned partition.',
        ),
      );
    }

    return SurfaceCard(
      key: Key('agent-safety-section-${agent.id}'),
      eyebrow: 'Agent safety',
      title: '${agent.name} safety rail',
      subtitle:
          'These controls belong only to the selected owned agent, so active-agent changes update this panel without touching human safety.',
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
                'Updates only the selected agent policy so global human safety stays separate.',
            value: agent.safety.allowUnknownHumans,
            onChanged: (_) => _toggleSelectedAgentUnknownHumans(agent.id),
          ),
          const SizedBox(height: AppSpacing.md),
          _SafetyToggleRow(
            switchKey: Key('agent-safety-unknown-agents-${agent.id}'),
            accentColor: AppColors.tertiary,
            icon: Icons.hub_rounded,
            title: 'Allow unknown agents to DM ${agent.name}',
            subtitle:
                'Leaves human inbox safety untouched while letting each active owned agent keep its own threshold.',
            value: agent.safety.allowUnknownAgents,
            onChanged: (_) => _toggleSelectedAgentUnknownAgents(agent.id),
          ),
        ],
      ),
    );
  }

  Widget _buildRelationshipSections(HubViewModel viewModel) {
    final agent = viewModel.selectedAgentOrNull;
    if (agent == null) {
      return const SurfaceCard(
        eyebrow: 'Relationships',
        title: 'No active owned graph',
        subtitle:
            'Relationship views stay bound to the active owned agent so claimable and pending entries never masquerade as live graph owners.',
        leading: _HubToneIcon(
          icon: Icons.account_tree_rounded,
          accentColor: AppColors.primary,
        ),
        child: _EmptyStatePanel(
          icon: Icons.share_outlined,
          title: 'No selected owned agent',
          body:
              'Select or create an owned agent first to inspect its following and follower surfaces.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RelationshipSectionCard(
          cardKey: Key('following-section-${agent.id}'),
          eyebrow: 'Followed Agents',
          title: '${agent.name} follows these agents',
          subtitle:
              'Follow relationships remain separate from ownership and selection, but they surface here in the same visual lane as the original Hub concept.',
          accentColor: AppColors.primary,
          emptyLabel: 'No followed agents are available in this Hub slice yet.',
          relationships: agent.following,
          itemPrefix: 'following-item-${agent.id}',
        ),
        const SizedBox(height: AppSpacing.xl),
        _RelationshipSectionCard(
          cardKey: Key('followed-section-${agent.id}'),
          eyebrow: 'Following Agents',
          title: '${agent.name} is followed by these agents',
          subtitle:
              'Inbound follows stay distinct from active-agent ownership, but they are still part of the same social graph view.',
          accentColor: AppColors.tertiary,
          emptyLabel:
              'No following agents are available in this Hub slice yet.',
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
      scale: isSelected ? 1 : 0.88,
      duration: AppEffects.fast,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: isSelected ? 1 : 0.42,
        duration: AppEffects.fast,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('owned-agent-card-${agent.id}'),
            onTap: onTap,
            borderRadius: AppRadii.hero,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.66),
                borderRadius: const BorderRadius.all(Radius.circular(24)),
                border: Border.all(
                  color: accentColor.withValues(
                    alpha: isSelected ? 0.36 : 0.12,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: isSelected ? 92 : 74,
                          height: isSelected ? 92 : 74,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLow,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(22),
                            ),
                            border: Border.all(
                              color: accentColor.withValues(
                                alpha: isSelected ? 0.36 : 0.16,
                              ),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            agent.isPrimary
                                ? Icons.stars_rounded
                                : Icons.smart_toy_rounded,
                            color: accentColor,
                            size: isSelected ? 36 : 28,
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            bottom: -10,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.xxs,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: AppRadii.pill,
                                ),
                                child: Text(
                                  'ACTIVE',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: AppColors.onPrimary,
                                        letterSpacing: 1.3,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      agent.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: isSelected
                            ? accentColor
                            : AppColors.onSurfaceMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      agent.handle.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.onSurfaceMuted,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (isSelected) ...[
                      StatusChip(
                        label: agent.origin.label,
                        tone: _originToneFor(agent.origin),
                      ),
                    ] else ...[
                      Text(
                        agent.statusLabel.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                    ],
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
        Align(
          alignment: Alignment.center,
          child: Text(
            'Connection Endpoint'.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onSurfaceMuted,
              letterSpacing: 1.6,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceLow.withValues(alpha: 0.68),
            borderRadius: AppRadii.large,
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.14),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    agent.endpointLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.tertiarySoft,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.content_copy_rounded,
                  color: AppColors.primary,
                  size: AppSpacing.lg,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
            StatusChip(
              label: agent.runtimeLabel,
              tone: StatusChipTone.neutral,
              showDot: false,
            ),
            StatusChip(
              label:
                  'H ${agent.safety.allowUnknownHumans ? 'open' : 'filtered'} / A ${agent.safety.allowUnknownAgents ? 'open' : 'filtered'}',
              tone: StatusChipTone.neutral,
              showDot: false,
            ),
          ],
        ),
      ],
    );
  }
}

class _ClaimableAgentRow extends StatelessWidget {
  const _ClaimableAgentRow({
    required this.agent,
    required this.isBusy,
    required this.canClaim,
    required this.onClaim,
  });

  final HubClaimableAgentModel agent;
  final bool isBusy;
  final bool canClaim;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: Key('claimable-agent-card-${agent.id}'),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HubToneIcon(
              icon: Icons.inventory_2_rounded,
              accentColor: AppColors.tertiary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    agent.handle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    agent.headline,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(
                  label: agent.statusLabel,
                  tone: StatusChipTone.neutral,
                  showDot: false,
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: Key('claim-agent-button-${agent.id}'),
                  onPressed: canClaim && !isBusy ? onClaim : null,
                  icon: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_rounded),
                  label: const Text('Claim'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingClaimRow extends StatelessWidget {
  const _PendingClaimRow({required this.claim});

  final HubPendingClaimModel claim;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: Key('pending-claim-card-${claim.claimRequestId}'),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.large,
        border: Border.all(
          color: AppColors.primaryFixed.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HubToneIcon(
              icon: Icons.hourglass_top_rounded,
              accentColor: AppColors.primaryFixed,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    claim.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    claim.handle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Requested ${claim.requestedAtLabel}  |  Expires ${claim.expiresAtLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            StatusChip(
              label: claim.statusLabel,
              tone: StatusChipTone.neutral,
              showDot: false,
            ),
          ],
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
    return Column(
      key: cardKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                eyebrow.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  letterSpacing: 2.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (relationships.isEmpty)
          _EmptyStatePanel(
            icon: Icons.share_outlined,
            title: 'Nothing to show yet',
            body: emptyLabel,
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < relationships.length; index++) ...[
                  _RelationshipTile(
                    tileKey: Key('$itemPrefix-${relationships[index].id}'),
                    relationship: relationships[index],
                    accentColor: accentColor,
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
              ],
            ),
          ),
      ],
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
        child: SizedBox(
          width: 132,
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighest.withValues(alpha: 0.74),
                  borderRadius: AppRadii.medium,
                ),
                child: Icon(relationship.kind.icon, color: accentColor),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                relationship.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                relationship.statusLabel.toUpperCase(),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: accentColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStatePanel extends StatelessWidget {
  const _EmptyStatePanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.72),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HubToneIcon(icon: icon, accentColor: AppColors.primaryFixed),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(body, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
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
  const _AddAgentSheet({required this.isSignedIn});

  final bool isSignedIn;

  @override
  State<_AddAgentSheet> createState() => _AddAgentSheetState();
}

class _AddAgentSheetState extends State<_AddAgentSheet> {
  late final TextEditingController _handleController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    _handleController = TextEditingController();
    _displayNameController = TextEditingController();
    _bioController = TextEditingController();
  }

  @override
  void dispose() {
    _handleController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        widget.isSignedIn &&
        _handleController.text.trim().isNotEmpty &&
        _displayNameController.text.trim().isNotEmpty;

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
                            'Import a human-owned agent',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            widget.isSignedIn
                                ? 'Import writes through the live controller, refreshes `/agents/mine`, and promotes the new agent into the owned partition.'
                                : 'A signed-in human session is required before Hub can import a new owned agent.',
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
                  title: 'Human-owned import',
                  subtitle:
                      'Create a live owned agent for the authenticated human using the backend import endpoint.',
                  enabled: widget.isSignedIn,
                  onTap: null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('import-handle-field'),
                  controller: _handleController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Agent handle',
                    hintText: 'xenon-7',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('import-display-name-field'),
                  controller: _displayNameController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'Xenon-7',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('import-bio-field'),
                  controller: _bioController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Bio (optional)',
                    hintText: 'Short headline for Hub cards',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: Opacity(
                    opacity: canSubmit ? 1 : 0.5,
                    child: IgnorePointer(
                      ignoring: !canSubmit,
                      child: PrimaryGradientButton(
                        key: const Key('complete-import-button'),
                        label: 'Import owned agent',
                        icon: Icons.done_all_rounded,
                        onPressed: () {
                          Navigator.of(context).pop(
                            _AddAgentSheetResult(
                              handle: _handleController.text.trim(),
                              displayName: _displayNameController.text.trim(),
                              bio: _bioController.text.trim().isEmpty
                                  ? null
                                  : _bioController.text.trim(),
                            ),
                          );
                        },
                      ),
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
  const _HubToneIcon({required this.icon, required this.accentColor});

  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: AppRadii.medium,
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Icon(icon, color: accentColor),
      ),
    );
  }
}

class _AddAgentSheetResult {
  const _AddAgentSheetResult({
    required this.handle,
    required this.displayName,
    this.bio,
  });

  final String handle;
  final String displayName;
  final String? bio;
}

enum _HumanAuthMode { signIn, register }

class _HumanSessionSummaryCard extends StatelessWidget {
  const _HumanSessionSummaryCard({required this.model});

  final HubHumanAuthModel model;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HubToneIcon(
              icon: Icons.person_rounded,
              accentColor: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    model.handle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    model.statusLine,
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

class _HubActionRow extends StatelessWidget {
  const _HubActionRow({
    required this.rowKey,
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final Key rowKey;
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: rowKey,
          onTap: enabled ? onTap : null,
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
                children: [
                  _HubToneIcon(icon: icon, accentColor: accentColor),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    enabled ? Icons.arrow_forward_rounded : Icons.lock_rounded,
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

class _ProviderActionButton extends StatelessWidget {
  const _ProviderActionButton({
    required this.buttonKey,
    required this.label,
    required this.icon,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Column(
        key: buttonKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceHighest.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Icon(
                icon,
                size: AppSpacing.xl,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppColors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

class _AuthFooterChip extends StatelessWidget {
  const _AuthFooterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
      ),
    );
  }
}

class _HumanAuthSheet extends StatefulWidget {
  const _HumanAuthSheet({required this.initialMode, required this.onSubmit});

  final _HumanAuthMode initialMode;
  final Future<String> Function({
    required _HumanAuthMode mode,
    required String email,
    required String displayName,
    required String password,
  })
  onSubmit;

  @override
  State<_HumanAuthSheet> createState() => _HumanAuthSheetState();
}

class _HumanAuthSheetState extends State<_HumanAuthSheet> {
  late _HumanAuthMode _mode;
  late final TextEditingController _emailController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _passwordController;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _emailController = TextEditingController();
    _displayNameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final message = await widget.onSubmit(
        mode: _mode,
        email: _emailController.text.trim(),
        displayName: _displayNameController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(message);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _isSubmitting = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to complete authentication right now.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == _HumanAuthMode.register;
    final canSubmit =
        !_isSubmitting &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        (!isRegister || _displayNameController.text.trim().isNotEmpty);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        right: AppSpacing.sm,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm,
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
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Center(
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: AppRadii.large,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Icon(
                            Icons.shield_rounded,
                            color: AppColors.primary,
                            size: AppSpacing.xxl,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Human Authentication',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isRegister
                            ? 'Create a live human account for Agents Chat.'
                            : 'Sign in to manage owned agents and claims.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SegmentedButton<_HumanAuthMode>(
                  segments: const [
                    ButtonSegment<_HumanAuthMode>(
                      value: _HumanAuthMode.signIn,
                      label: Text('Sign in'),
                      icon: Icon(Icons.login_rounded),
                    ),
                    ButtonSegment<_HumanAuthMode>(
                      value: _HumanAuthMode.register,
                      label: Text('Create'),
                      icon: Icon(Icons.person_add_rounded),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _mode = selection.first;
                      _errorMessage = null;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow.withValues(alpha: 0.72),
                    borderRadius: AppRadii.large,
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        TextField(
                          key: const Key('human-auth-email-field'),
                          controller: _emailController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'owner@example.com',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                        ),
                        if (isRegister) ...[
                          const SizedBox(height: AppSpacing.md),
                          TextField(
                            key: const Key('human-auth-display-name-field'),
                            controller: _displayNameController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Display name',
                              hintText: 'Neural Node',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          key: const Key('human-auth-password-field'),
                          controller: _passwordController,
                          onChanged: (_) => setState(() {}),
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            hintText: 'password123',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _errorMessage!,
                    key: const Key('human-auth-error'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: Opacity(
                    opacity: canSubmit ? 1 : 0.5,
                    child: IgnorePointer(
                      ignoring: !canSubmit,
                      child: PrimaryGradientButton(
                        key: const Key('human-auth-submit-button'),
                        label: _isSubmitting
                            ? 'Initializing session'
                            : isRegister
                            ? 'Create identity'
                            : 'Initialize session',
                        icon: _isSubmitting
                            ? Icons.sync_rounded
                            : Icons.shield_rounded,
                        onPressed: () {
                          unawaited(_submit());
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow.withValues(alpha: 0.82),
                    borderRadius: AppRadii.large,
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'External Identity Providers'.toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            _ProviderActionButton(
                              buttonKey: Key('human-auth-modal-google-button'),
                              label: 'Google',
                              icon: Icons.account_circle_outlined,
                            ),
                            SizedBox(width: AppSpacing.md),
                            _ProviderActionButton(
                              buttonKey: Key('human-auth-modal-github-button'),
                              label: 'GitHub',
                              icon: Icons.code_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Center(
                          child: Text(
                            'New to the synapse? Create identity from the segmented control above.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: const [
                      _AuthFooterChip(label: 'Encryption v4.2'),
                      _AuthFooterChip(label: 'Secure Node'),
                      _AuthFooterChip(label: 'Auth Level 7'),
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
