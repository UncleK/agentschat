// ignore_for_file: unused_element

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/network/agents_repository.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/chat_repository.dart';
import '../../core/session/app_session_controller.dart';
import '../../core/session/app_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_effects.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/surface_card.dart';
import '../../core/widgets/swipe_back_sheet.dart';
import 'hub_models.dart';
import 'hub_view_model.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  static const HubSafetySettings _defaultAgentSafety = HubSafetySettings(
    allowUnfollowedAgents: false,
    onlyMutualFollowers: false,
  );

  late final PageController _agentPageController;
  HubSafetySettings _globalAgentSafety = _defaultAgentSafety;
  bool _applyAgentSecurityToAll = false;
  final Map<String, HubSafetySettings> _agentSafetyOverrides =
      <String, HubSafetySettings>{};
  String? _lastCarouselAgentId;

  @override
  void initState() {
    super.initState();
    _agentPageController = PageController(viewportFraction: 0.34);
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
    final action = await showSwipeBackSheet<_AddAgentAction>(
      context: context,
      builder: (context) => const _AddAgentSelectionSheet(),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _AddAgentAction.import:
        await _openImportAgentSheet(isSignedIn: isSignedIn);
        break;
      case _AddAgentAction.create:
        await _openCreateAgentSheet();
        break;
    }
  }

  Future<void> _openImportAgentSheet({required bool isSignedIn}) async {
    if (!isSignedIn) {
      _showSnackBar('Sign in as human first');
      return;
    }

    final session = AppSessionScope.read(context);
    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) => _ImportAgentSheet(
        isSignedIn: isSignedIn,
        apiBaseUrl: session.apiClient.baseUrl,
        onCreateInvitation: session.createHumanOwnedAgentInvitation,
      ),
    );
  }

  Future<void> _openCreateAgentSheet() async {
    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) => const _CreateNewAgentSheet(),
    );
  }

  Future<void> _openClaimableAgentsSheet(
    HubViewModel viewModel,
    bool isRefreshingMine,
  ) async {
    if (!viewModel.humanAuth.isSignedIn) {
      _showSnackBar('Sign in as human first');
      return;
    }

    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) => _ClaimableAgentsSheet(
        claimableAgents: viewModel.claimableAgents,
        isRefreshingMine: isRefreshingMine,
        onClaim: _claimAgent,
      ),
    );
  }

  Future<String> _submitHumanAuth({
    required _HumanAuthMode mode,
    required String email,
    required String username,
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
        username: username,
        displayName: displayName,
        password: password,
      ),
      _HumanAuthMode.external => throw StateError(
        'External human login is not available yet.',
      ),
    };

    await session.authenticate(authState);

    return switch (mode) {
      _HumanAuthMode.signIn => 'Signed in as ${authState.displayName}',
      _HumanAuthMode.register => 'Created account for ${authState.displayName}',
      _HumanAuthMode.external => 'External login is unavailable',
    };
  }

  Future<void> _openHumanAuthSheet(_HumanAuthMode mode) async {
    final session = AppSessionScope.read(context);
    final message = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) => _HumanAuthSheet(
        initialMode: mode,
        authRepository: session.authRepository,
        onSubmit: _submitHumanAuth,
      ),
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

  Future<void> _disconnectConnectedAgents() async {
    final session = AppSessionScope.read(context);
    final confirmed = await showSwipeBackSheet<bool>(
      context: context,
      builder: (context) => const _DisconnectAgentsSheet(),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    try {
      final response = await session.agentsRepository
          .disconnectAllConnectedAgents();
      if (!mounted) {
        return;
      }

      final disconnectedCount = response['disconnectedCount'] as int? ?? 0;
      if (disconnectedCount == 0) {
        _showSnackBar('No connected agents were active in this app');
        return;
      }

      _showSnackBar('Disconnected $disconnectedCount connected agent(s)');
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      _showSnackBar('Unable to disconnect connected agents right now');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Unable to disconnect connected agents right now');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyEndpoint(String endpoint) async {
    await Clipboard.setData(ClipboardData(text: endpoint));
    if (!mounted) {
      return;
    }
    _showSnackBar('Connection endpoint copied');
  }

  Future<void> _openOwnedAgentCommandSheet({
    required HubOwnedAgentModel agent,
  }) async {
    final session = AppSessionScope.read(context);

    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) =>
          _OwnedAgentCommandSheet(agent: agent, session: session),
    );
  }

  Future<void> _openRelationshipSheet({
    required String title,
    required List<HubRelationshipModel> relationships,
  }) async {
    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) =>
          _RelationshipListSheet(title: title, relationships: relationships),
    );
  }

  Future<void> _openLanguageSheet() async {
    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) => const _LanguageSelectionSheet(),
    );
  }

  HubSafetySettings _effectiveAgentSafety(String agentId) {
    if (_applyAgentSecurityToAll) {
      return _globalAgentSafety;
    }
    return _agentSafetyOverrides[agentId] ?? _defaultAgentSafety;
  }

  void _toggleApplyAgentSecurityToAll(String? selectedAgentId) {
    setState(() {
      final nextValue = !_applyAgentSecurityToAll;
      if (nextValue && selectedAgentId != null) {
        _globalAgentSafety = _effectiveAgentSafety(selectedAgentId);
      }
      _applyAgentSecurityToAll = nextValue;
    });
  }

  void _toggleSelectedAgentAllowUnfollowed(String agentId) {
    final current = _effectiveAgentSafety(agentId);
    setState(() {
      final next = current.copyWith(
        allowUnfollowedAgents: !current.allowUnfollowedAgents,
      );
      if (_applyAgentSecurityToAll) {
        _globalAgentSafety = next;
      } else {
        _agentSafetyOverrides[agentId] = next;
      }
    });
  }

  void _toggleSelectedAgentMutualOnly(String agentId) {
    final current = _effectiveAgentSafety(agentId);
    setState(() {
      final next = current.copyWith(
        onlyMutualFollowers: !current.onlyMutualFollowers,
      );
      if (_applyAgentSecurityToAll) {
        _globalAgentSafety = next;
      } else {
        _agentSafetyOverrides[agentId] = next;
      }
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

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const Key('surface-hub'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOwnedAgentsSection(viewModel, session.isRefreshingMine),
              const SizedBox(height: AppSpacing.xxxl),
              _buildHumanAuthSection(viewModel, session.isRefreshingMine),
              const SizedBox(height: AppSpacing.xxxl),
              _buildAppSettingsSection(viewModel),
              if (viewModel.hasPendingClaims) ...[
                const SizedBox(height: AppSpacing.xxxl),
                _buildPendingClaimsSection(viewModel),
              ],
              const SizedBox(height: AppSpacing.xl),
              const _HubVersionFooter(),
            ],
          ),
        ),
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
        _SectionTitleRow(
          title: 'My Agent Profile',
          actions: [
            _SectionIconButton(
              buttonKey: const Key('add-agent-button'),
              icon: Icons.add_rounded,
              accentColor: AppColors.primary,
              fillColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              onTap: isRefreshingMine
                  ? null
                  : () => _openAddAgentSheet(viewModel.humanAuth.isSignedIn),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.78),
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -34,
                top: -38,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(120),
                    ),
                    child: const SizedBox(width: 160, height: 160),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: viewModel.hasOwnedAgents
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 170,
                            child: PageView.builder(
                              key: const Key('owned-agent-carousel'),
                              controller: _agentPageController,
                              clipBehavior: Clip.none,
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
                                    horizontal: AppSpacing.xxs,
                                  ),
                                  child: _OwnedAgentCard(
                                    agent: agent,
                                    isSelected: agent.id == selectedAgent?.id,
                                    laneOffset:
                                        index - viewModel.selectedAgentIndex,
                                    onTap: () {
                                      unawaited(_selectOwnedAgent(agent.id));
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                          if (selectedAgent != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _SelectedAgentSignals(
                              agent: selectedAgent,
                              onMessageAgent: () => _openOwnedAgentCommandSheet(
                                agent: selectedAgent,
                              ),
                              onCopyEndpoint: () =>
                                  _copyEndpoint(selectedAgent.endpointLabel),
                            ),
                          ],
                        ],
                      )
                    : const _EmptyStatePanel(
                        icon: Icons.lock_person_rounded,
                        title: 'No directly usable owned agents yet',
                        body:
                            'Import a human-owned agent or finish a claim. Claimable and pending records stay separate until they become active.',
                      ),
              ),
            ],
          ),
        ),
      ],
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
    final claimableCount = viewModel.claimableAgents.length;
    final claimSubtitle = viewModel.humanAuth.isSignedIn
        ? claimableCount > 0
              ? '$claimableCount agent${claimableCount == 1 ? '' : 's'} waiting for human claim.'
              : 'Review any agent that connected without a human-bound invite.'
        : 'Sign in as a human first, then review claimable agents here.';

    return Column(
      key: const Key('human-access-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitleRow(title: 'Start'),
        const SizedBox(height: AppSpacing.md),
        _SectionPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HubMenuRow(
                rowKey: const Key('human-access-import-agent-button'),
                accentColor: AppColors.primary,
                icon: Icons.cloud_download_rounded,
                title: 'Import new agent',
                subtitle: viewModel.humanAuth.isSignedIn
                    ? 'Generate a secure bootstrap link that binds the next agent to this human.'
                    : 'Preview the secure bootstrap flow now, then sign in before generating a live link.',
                enabled: true,
                onTap: () {
                  unawaited(
                    _openImportAgentSheet(
                      isSignedIn: viewModel.humanAuth.isSignedIn,
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              _HubMenuRow(
                rowKey: const Key('human-access-claim-agent-button'),
                accentColor: AppColors.tertiary,
                icon: Icons.verified_user_rounded,
                title: 'Claim agent',
                subtitle: claimSubtitle,
                enabled: true,
                trailingLabel: claimableCount > 0 ? '$claimableCount' : null,
                onTap: () {
                  unawaited(
                    _openClaimableAgentsSheet(viewModel, isRefreshingMine),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              _HubMenuRow(
                rowKey: const Key('human-access-create-agent-button'),
                accentColor: AppColors.outlineBright,
                icon: Icons.auto_awesome_rounded,
                title: 'Create new agent',
                subtitle:
                    'Preview available now. Agent creation is still closed.',
                enabled: true,
                trailingLabel: 'Soon',
                onTap: () {
                  unawaited(_openCreateAgentSheet());
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (viewModel.humanAuth.isSignedIn) ...[
                _HumanSessionSummaryCard(model: viewModel.humanAuth),
                const SizedBox(height: AppSpacing.md),
                _HubMenuRow(
                  rowKey: const Key('hub-refresh-button'),
                  accentColor: AppColors.primary,
                  icon: Icons.refresh_rounded,
                  title: isRefreshingMine
                      ? 'Refreshing owned partitions'
                      : 'Refresh owned partitions',
                  subtitle: viewModel.humanAuth.providerLabel,
                  enabled: !isRefreshingMine,
                  trailingLabel: isRefreshingMine ? 'Syncing' : 'Live',
                  onTap: isRefreshingMine
                      ? null
                      : () {
                          unawaited(_refreshMine());
                        },
                ),
                const SizedBox(height: AppSpacing.xs),
                _HubMenuRow(
                  rowKey: const Key('human-auth-logout-button'),
                  accentColor: AppColors.error,
                  icon: Icons.logout_rounded,
                  title: 'Disconnect all sessions',
                  subtitle: 'Sign out this device and clear the active human.',
                  enabled: true,
                  onTap: () {
                    unawaited(_disconnectHumanSession());
                  },
                ),
              ] else ...[
                _HubMenuRow(
                  rowKey: const Key('human-auth-email-button'),
                  accentColor: AppColors.primary,
                  icon: Icons.person_rounded,
                  title: 'Sign in as human',
                  subtitle:
                      'Restore your human session and owned-agent controls.',
                  enabled: true,
                  onTap: () {
                    unawaited(_openHumanAuthSheet(_HumanAuthMode.signIn));
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecuritySection(HubViewModel viewModel) {
    final agent = viewModel.selectedAgentOrNull;
    final security = agent == null
        ? _defaultAgentSafety
        : _effectiveAgentSafety(agent.id);
    final targetName = _applyAgentSecurityToAll
        ? 'all agents'
        : '"${agent?.name ?? 'the active agent'}"';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitleRow(
          title: 'Agent Security',
          actions: [
            _CompactLabeledSwitch(
              switchKey: const Key('agent-security-apply-all-switch'),
              label: 'All',
              value: _applyAgentSecurityToAll,
              onChanged: (_) =>
                  _toggleApplyAgentSecurityToAll(viewModel.selectedAgentId),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SectionPanel(
          key: const Key('agent-security-section'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _applyAgentSecurityToAll
                    ? 'The rules below apply to every connected and owned agent in this account.'
                    : 'The rules below only apply to the currently active agent.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _HubSwitchMenuRow(
                switchKey: Key(
                  'agent-safety-allow-unfollowed-${agent?.id ?? 'none'}',
                ),
                accentColor: AppColors.primary,
                icon: Icons.smart_toy_rounded,
                title: 'Allow unfollowed agents to message $targetName',
                subtitle:
                    'Followers can always message. Turn this on to also allow agents that are not following you.',
                value: security.allowUnfollowedAgents,
                onChanged: agent == null
                    ? null
                    : (_) => _toggleSelectedAgentAllowUnfollowed(agent.id),
              ),
              const SizedBox(height: AppSpacing.xs),
              _HubSwitchMenuRow(
                switchKey: Key(
                  'agent-safety-mutual-only-${agent?.id ?? 'none'}',
                ),
                accentColor: AppColors.tertiary,
                icon: Icons.compare_arrows_rounded,
                title: 'Only receive messages from mutual followers',
                subtitle: _applyAgentSecurityToAll
                    ? 'When this is on, one-way followers are ignored for all agents.'
                    : agent == null
                    ? 'When this is on, one-way followers are ignored.'
                    : 'When this is on, agents that only follow ${agent.name} are ignored.',
                value: security.onlyMutualFollowers,
                onChanged: agent == null
                    ? null
                    : (_) => _toggleSelectedAgentMutualOnly(agent.id),
              ),
              const SizedBox(height: AppSpacing.md),
              _InfoPill(
                icon: Icons.info_outline_rounded,
                accentColor: AppColors.primaryFixed,
                text:
                    'This screen already matches the backend DM policy semantics, but the policy controller is not exposed yet, so these switches are still local to the app.',
              ),
              if (security.onlyMutualFollowers) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Mutual-follow mode takes priority over the unfollowed-agents rule.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.tertiarySoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppSettingsSection(HubViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitleRow(title: 'App Settings'),
        const SizedBox(height: AppSpacing.md),
        _SectionPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HubSwitchMenuRow(
                switchKey: Key('app-settings-appearance-switch'),
                accentColor: AppColors.primary,
                icon: Icons.dark_mode_rounded,
                title: 'Dark mode interface',
                subtitle:
                    'Dark mode is the only available palette right now. Light mode will arrive next.',
                value: true,
                onChanged: null,
              ),
              const SizedBox(height: AppSpacing.xs),
              _HubMenuRow(
                rowKey: const Key('app-settings-language-button'),
                accentColor: AppColors.onSurfaceMuted,
                icon: Icons.language_rounded,
                title: 'System language',
                subtitle: 'English is live. Chinese will be added next.',
                enabled: true,
                trailingLabel: 'English',
                onTap: () {
                  unawaited(_openLanguageSheet());
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              _HubMenuRow(
                rowKey: const Key('app-settings-disconnect-agents-button'),
                accentColor: AppColors.error,
                icon: Icons.logout_rounded,
                title: 'Disconnect connected agents',
                subtitle: viewModel.humanAuth.isSignedIn
                    ? 'Force every agent currently connected to this app to sign out.'
                    : 'Sign in first to disconnect agents connected to this app.',
                enabled: viewModel.humanAuth.isSignedIn,
                onTap: viewModel.humanAuth.isSignedIn
                    ? () {
                        unawaited(_disconnectConnectedAgents());
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRelationshipSections(HubViewModel viewModel) {
    final agent = viewModel.selectedAgentOrNull;
    if (agent == null) {
      return const _SectionPanel(
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
          title: 'Followed Agents',
          accentColor: AppColors.primary,
          relationships: agent.following,
          itemPrefix: 'following-item-${agent.id}',
          onOpenAll: agent.following.isEmpty
              ? null
              : () {
                  unawaited(
                    _openRelationshipSheet(
                      title: '${agent.name} follows',
                      relationships: agent.following,
                    ),
                  );
                },
        ),
        const SizedBox(height: AppSpacing.xxxl),
        _RelationshipSectionCard(
          cardKey: Key('followed-section-${agent.id}'),
          title: 'Following Agents',
          accentColor: AppColors.tertiary,
          relationships: agent.followers,
          itemPrefix: 'followed-item-${agent.id}',
          onOpenAll: agent.followers.isEmpty
              ? null
              : () {
                  unawaited(
                    _openRelationshipSheet(
                      title: '${agent.name} followers',
                      relationships: agent.followers,
                    ),
                  );
                },
        ),
      ],
    );
  }
}

class _OwnedAgentCard extends StatelessWidget {
  const _OwnedAgentCard({
    required this.agent,
    required this.isSelected,
    required this.laneOffset,
    required this.onTap,
  });

  final HubOwnedAgentModel agent;
  final bool isSelected;
  final int laneOffset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = _originColorFor(agent.origin);
    final isLeftLane = laneOffset < 0;
    final laneShift = isSelected
        ? 0.0
        : isLeftLane
        ? 20.0
        : -20.0;
    final laneRotation = isSelected
        ? 0.0
        : isLeftLane
        ? 0.22
        : -0.22;
    final avatarWidth = isSelected ? 110.0 : 72.0;
    final avatarHeight = isSelected ? 110.0 : 72.0;

    return AnimatedOpacity(
      opacity: isSelected ? 1 : 0.42,
      duration: AppEffects.fast,
      child: Transform.translate(
        offset: Offset(laneShift, 0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(laneRotation),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('owned-agent-card-${agent.id}'),
              onTap: onTap,
              borderRadius: AppRadii.hero,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: AppEffects.fast,
                          width: avatarWidth,
                          height: avatarHeight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                isSelected
                                    ? const Color(0xFFF7E6C9)
                                    : AppColors.surfaceHighest,
                                isSelected
                                    ? const Color(0xFFE0C79E)
                                    : AppColors.surfaceHigh,
                                if (isSelected)
                                  accentColor.withValues(alpha: 0.18),
                              ],
                            ),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(16),
                            ),
                            border: Border.all(
                              color: accentColor.withValues(
                                alpha: isSelected ? 0.32 : 0.14,
                              ),
                              width: isSelected ? 1.6 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: accentColor.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 22,
                                      offset: const Offset(0, 12),
                                    ),
                                  ]
                                : const [],
                          ),
                          child: Center(
                            child: Text(
                              _avatarLetters(agent.name),
                              style:
                                  (isSelected
                                          ? Theme.of(
                                              context,
                                            ).textTheme.headlineLarge
                                          : Theme.of(
                                              context,
                                            ).textTheme.titleMedium)
                                      ?.copyWith(
                                        color: isSelected
                                            ? AppColors.background
                                            : AppColors.onSurfaceMuted,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: isSelected ? -0.5 : -0.2,
                                      ),
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            bottom: -8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: AppRadii.pill,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.32,
                                      ),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  'ACTIVE',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: AppColors.onPrimary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: isSelected ? 14 : 10),
                    Text(
                      agent.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (isSelected
                                  ? Theme.of(context).textTheme.headlineSmall
                                  : Theme.of(context).textTheme.labelSmall)
                              ?.copyWith(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.onSurfaceMuted,
                                fontWeight: FontWeight.w700,
                                fontSize: isSelected ? 18 : 9.5,
                                letterSpacing: isSelected ? -0.4 : 1.2,
                              ),
                    ),
                    if (!isSelected) ...[
                      const SizedBox(height: 2),
                      Text(
                        agent.handle.replaceFirst('@', '').toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.onSurfaceMuted.withValues(
                            alpha: 0.82,
                          ),
                          fontSize: 8,
                          letterSpacing: 1,
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
  const _SelectedAgentSignals({
    required this.agent,
    required this.onMessageAgent,
    required this.onCopyEndpoint,
  });

  final HubOwnedAgentModel agent;
  final VoidCallback? onMessageAgent;
  final VoidCallback onCopyEndpoint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Connection Endpoint'.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.onSurfaceMuted,
            fontSize: 10,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.backgroundFloor.withValues(alpha: 0.56),
            borderRadius: AppRadii.medium,
            border: Border.all(color: AppColors.outline.withValues(alpha: 0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                _SignalEndpointActionButton(
                  buttonKey: const Key('selected-agent-message-button'),
                  icon: Icons.chat_bubble_rounded,
                  accentColor: AppColors.primary,
                  onTap: onMessageAgent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    agent.endpointLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.tertiarySoft,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _SignalEndpointActionButton(
                  buttonKey: const Key('selected-agent-copy-button'),
                  icon: Icons.content_copy_rounded,
                  accentColor: AppColors.primary,
                  onTap: onCopyEndpoint,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SignalEndpointActionButton extends StatelessWidget {
  const _SignalEndpointActionButton({
    required this.buttonKey,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled
          ? accentColor.withValues(alpha: 0.14)
          : accentColor.withValues(alpha: 0.08),
      borderRadius: AppRadii.medium,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: AppRadii.medium,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: AppRadii.medium,
            border: Border.all(
              color: enabled
                  ? accentColor.withValues(alpha: 0.16)
                  : accentColor.withValues(alpha: 0.14),
            ),
          ),
          child: Icon(
            icon,
            color: enabled ? accentColor : accentColor.withValues(alpha: 0.76),
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _OwnedAgentCommandSheet extends StatefulWidget {
  const _OwnedAgentCommandSheet({required this.agent, required this.session});

  final HubOwnedAgentModel agent;
  final AppSessionController session;

  @override
  State<_OwnedAgentCommandSheet> createState() =>
      _OwnedAgentCommandSheetState();
}

class _OwnedAgentCommandSheetState extends State<_OwnedAgentCommandSheet> {
  late final TextEditingController _composerController;
  late final FocusNode _composerFocusNode;
  late final TextEditingController _authEmailController;
  late final TextEditingController _authUsernameController;
  late final TextEditingController _authDisplayNameController;
  late final TextEditingController _authPasswordController;
  late final ChatRepository _chatRepository;
  _HumanAuthMode _authMode = _HumanAuthMode.signIn;
  bool _isLoadingThread = true;
  bool _isSendingMessage = false;
  bool _isAuthenticating = false;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _threadId;
  String? _loadError;
  String? _sendError;
  String? _authError;
  String? _usernameMessage;
  int _loadRequestId = 0;
  int _sendRequestId = 0;
  int _usernameRequestId = 0;
  Timer? _usernameDebounce;
  List<_OwnedAgentCommandMessage> _messages =
      const <_OwnedAgentCommandMessage>[];

  bool get _hasAuthenticatedHuman {
    return widget.session.isAuthenticated && widget.session.currentUser != null;
  }

  String? get _currentHumanId => widget.session.currentUser?.id;

  String get _currentHumanDisplayName {
    final displayName = widget.session.authState.displayName.trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final email = widget.session.authState.email.trim();
    if (email.isNotEmpty) {
      return email;
    }
    return 'Human admin';
  }

  @override
  void initState() {
    super.initState();
    _composerController = TextEditingController();
    _composerFocusNode = FocusNode();
    _authEmailController = TextEditingController();
    _authUsernameController = TextEditingController();
    _authDisplayNameController = TextEditingController();
    _authPasswordController = TextEditingController();
    _chatRepository = ChatRepository(apiClient: widget.session.apiClient);
    if (_hasAuthenticatedHuman) {
      unawaited(_loadCommandThread());
    } else {
      _isLoadingThread = false;
    }
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _composerController.dispose();
    _composerFocusNode.dispose();
    _authEmailController.dispose();
    _authUsernameController.dispose();
    _authDisplayNameController.dispose();
    _authPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitHumanAuthInCommandSheet() async {
    if (_authMode == _HumanAuthMode.external) {
      return;
    }
    if (_authMode == _HumanAuthMode.register && !_canSubmitInlineRegister) {
      setState(() {
        _authError = _inlineUsernameValidationMessage ?? _usernameMessage;
      });
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _authError = null;
      _loadError = null;
      _sendError = null;
    });

    try {
      final authRepository = widget.session.authRepository;
      final authState = switch (_authMode) {
        _HumanAuthMode.signIn => await authRepository.loginWithEmail(
          email: _authEmailController.text.trim(),
          password: _authPasswordController.text,
        ),
        _HumanAuthMode.register => await authRepository.registerWithEmail(
          email: _authEmailController.text.trim(),
          username: _normalizedInlineUsername,
          displayName: _authDisplayNameController.text.trim(),
          password: _authPasswordController.text,
        ),
        _HumanAuthMode.external => throw StateError(
          'External human login is not available yet.',
        ),
      };

      await widget.session.authenticate(authState);
      if (!mounted) {
        return;
      }

      setState(() {
        _isAuthenticating = false;
        _authError = null;
        _isLoadingThread = true;
      });
      unawaited(_loadCommandThread());
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthenticating = false;
        _authError = error.message.trim().isEmpty
            ? 'Unable to complete authentication right now.'
            : error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthenticating = false;
        _authError = 'Unable to complete authentication right now.';
      });
    }
  }

  String get _normalizedInlineUsername {
    return _normalizeHumanUsernameInput(_authUsernameController.text);
  }

  String? get _inlineUsernameValidationMessage {
    if (_authMode != _HumanAuthMode.register) {
      return null;
    }
    return _localHumanUsernameValidationMessage(_authUsernameController.text);
  }

  bool get _canSubmitInlineRegister {
    return !_isAuthenticating &&
        !_isCheckingUsername &&
        _authEmailController.text.trim().isNotEmpty &&
        _authPasswordController.text.isNotEmpty &&
        _authDisplayNameController.text.trim().isNotEmpty &&
        _inlineUsernameValidationMessage == null &&
        _isUsernameAvailable == true;
  }

  void _handleInlineUsernameChanged(String value) {
    final validationMessage = _localHumanUsernameValidationMessage(value);
    _usernameDebounce?.cancel();

    if (_authMode != _HumanAuthMode.register) {
      return;
    }

    setState(() {
      _authError = null;
      _isUsernameAvailable = null;
      _usernameMessage = validationMessage;
      _isCheckingUsername = false;
    });

    if (validationMessage != null) {
      return;
    }

    _usernameDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_checkInlineUsernameAvailability());
    });
  }

  Future<void> _checkInlineUsernameAvailability() async {
    final validationMessage = _inlineUsernameValidationMessage;
    if (_authMode != _HumanAuthMode.register || validationMessage != null) {
      return;
    }

    final requestId = ++_usernameRequestId;
    setState(() {
      _isCheckingUsername = true;
      _isUsernameAvailable = null;
      _usernameMessage = 'Checking username...';
    });

    try {
      final result = await widget.session.authRepository.readUsernameAvailability(
        username: _normalizedInlineUsername,
      );
      if (!mounted || requestId != _usernameRequestId) {
        return;
      }
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = result.available;
        _usernameMessage = result.message;
      });
    } on ApiException catch (error) {
      if (!mounted || requestId != _usernameRequestId) {
        return;
      }
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameMessage = error.message.trim().isEmpty
            ? 'Unable to verify username right now.'
            : error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _usernameRequestId) {
        return;
      }
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameMessage = 'Unable to verify username right now.';
      });
    }
  }

  Future<void> _loadCommandThread() async {
    final currentHumanId = _currentHumanId;
    if (!_hasAuthenticatedHuman || currentHumanId == null) {
      setState(() {
        _threadId = null;
        _messages = const <_OwnedAgentCommandMessage>[];
        _isLoadingThread = false;
        _loadError = null;
      });
      return;
    }

    final requestId = ++_loadRequestId;
    setState(() {
      _isLoadingThread = true;
      _loadError = null;
      _sendError = null;
    });

    try {
      final threadsResponse = await _chatRepository.getThreads(
        activeAgentId: widget.agent.id,
        limit: 50,
      );
      if (!_canApplyLoadResult(requestId)) {
        return;
      }

      ChatThreadSummary? ownerThread;
      for (final thread in threadsResponse.threads) {
        if (thread.counterpart.type.toLowerCase() == 'human' &&
            thread.counterpart.id == currentHumanId) {
          ownerThread = thread;
          break;
        }
      }

      if (ownerThread == null) {
        setState(() {
          _threadId = null;
          _messages = const <_OwnedAgentCommandMessage>[];
          _isLoadingThread = false;
          _loadError = null;
        });
        return;
      }

      await _loadThreadMessages(
        threadId: ownerThread.threadId,
        requestId: requestId,
        shouldMarkRead: ownerThread.unreadCount > 0,
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await widget.session.handleUnauthorized();
        if (!mounted) {
          return;
        }
        setState(() {
          _threadId = null;
          _messages = const <_OwnedAgentCommandMessage>[];
          _isLoadingThread = false;
          _loadError = null;
        });
        return;
      }
      if (!_canApplyLoadResult(requestId)) {
        return;
      }
      setState(() {
        _isLoadingThread = false;
        _loadError = error.message.trim().isEmpty
            ? 'Unable to load this command thread right now.'
            : error.message;
      });
    } catch (_) {
      if (!_canApplyLoadResult(requestId)) {
        return;
      }
      setState(() {
        _isLoadingThread = false;
        _loadError = 'Unable to load this command thread right now.';
      });
    }
  }

  Future<void> _loadThreadMessages({
    required String threadId,
    required int requestId,
    bool shouldMarkRead = false,
  }) async {
    final response = await _chatRepository.getMessages(
      threadId: threadId,
      activeAgentId: widget.agent.id,
      limit: 50,
    );
    if (!_canApplyLoadResult(requestId)) {
      return;
    }

    if (shouldMarkRead) {
      unawaited(_markThreadRead(threadId));
    }

    setState(() {
      _threadId = threadId;
      _messages = response.messages.map(_mapMessage).toList(growable: false);
      _isLoadingThread = false;
      _loadError = null;
    });
  }

  Future<void> _markThreadRead(String threadId) async {
    try {
      await _chatRepository.markThreadRead(
        threadId: threadId,
        activeAgentId: widget.agent.id,
      );
    } catch (_) {
      // The thread itself already loaded, so a read receipt failure should not
      // interrupt the admin command flow.
    }
  }

  Future<void> _sendMessage() async {
    final draft = _composerController.text.trim();
    if (!_hasAuthenticatedHuman) {
      setState(() {
        _sendError =
            'Sign in as a human before sending commands to this agent.';
      });
      return;
    }
    if (draft.isEmpty || _isSendingMessage) {
      return;
    }

    final requestId = ++_sendRequestId;
    setState(() {
      _isSendingMessage = true;
      _sendError = null;
    });

    try {
      if (_threadId != null && _threadId!.isNotEmpty) {
        final response = await _chatRepository.sendThreadMessage(
          threadId: _threadId!,
          activeAgentId: widget.agent.id,
          content: draft,
          contentType: 'text',
        );
        if (!_canApplySendResult(requestId)) {
          return;
        }
        setState(() {
          _messages = [..._messages, _mapMessage(response.message)];
          _isSendingMessage = false;
          _sendError = null;
        });
      } else {
        final response = await _chatRepository.sendDirectMessage(
          recipientType: 'agent',
          recipientAgentId: widget.agent.id,
          content: draft,
          contentType: 'text',
        );
        final createdThreadId = (response['threadId'] as String? ?? '').trim();
        if (createdThreadId.isEmpty) {
          throw StateError('Command thread id was not returned.');
        }
        final messagesResponse = await _chatRepository.getMessages(
          threadId: createdThreadId,
          activeAgentId: widget.agent.id,
          limit: 50,
        );
        if (!_canApplySendResult(requestId)) {
          return;
        }
        setState(() {
          _threadId = createdThreadId;
          _messages = messagesResponse.messages
              .map(_mapMessage)
              .toList(growable: false);
          _isSendingMessage = false;
          _sendError = null;
          _loadError = null;
        });
      }

      _composerController.clear();
      _composerFocusNode.requestFocus();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await widget.session.handleUnauthorized();
        if (!mounted) {
          return;
        }
        setState(() {
          _isSendingMessage = false;
          _threadId = null;
          _messages = const <_OwnedAgentCommandMessage>[];
        });
        return;
      }
      if (!_canApplySendResult(requestId)) {
        return;
      }
      setState(() {
        _isSendingMessage = false;
        _sendError = error.message.trim().isEmpty
            ? 'Unable to send this message right now.'
            : error.message;
      });
    } catch (_) {
      if (!_canApplySendResult(requestId)) {
        return;
      }
      setState(() {
        _isSendingMessage = false;
        _sendError = 'Unable to send this message right now.';
      });
    }
  }

  bool _canApplyLoadResult(int requestId) {
    return mounted && requestId == _loadRequestId;
  }

  bool _canApplySendResult(int requestId) {
    return mounted && requestId == _sendRequestId;
  }

  _OwnedAgentCommandMessage _mapMessage(ChatMessageRecord message) {
    final currentHumanId = _currentHumanId;
    final isHuman = message.actor.type.toLowerCase() == 'human';
    final isLocal = isHuman && message.actor.id == currentHumanId;
    final body = message.content?.trim();
    return _OwnedAgentCommandMessage(
      id: message.eventId,
      authorName: message.actor.displayName.trim().isEmpty
          ? isHuman
                ? _currentHumanDisplayName
                : widget.agent.name
          : message.actor.displayName.trim(),
      body: body != null && body.isNotEmpty
          ? body
          : message.contentType.toLowerCase() == 'image'
          ? 'Image'
          : 'Unsupported message',
      timestampLabel: _timestampLabel(message.occurredAt),
      isHuman: isHuman,
      isLocal: isLocal,
    );
  }

  String _timestampLabel(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return '';
    }
    final local = parsed.toLocal();
    final now = DateTime.now();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final isSameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isSameDay) {
      return '$hour:$minute';
    }
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  Widget _buildThreadPanel(String activeAgentName) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.76),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: _isLoadingThread
            ? const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            : _loadError != null
            ? Center(
                child: Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                ),
              )
            : _messages.isEmpty
            ? _OwnedAgentCommandEmptyState(agentName: activeAgentName)
            : SingleChildScrollView(
                key: const Key('owned-agent-command-scroll'),
                child: Column(
                  children: [
                    for (var index = 0; index < _messages.length; index++) ...[
                      _OwnedAgentCommandBubble(message: _messages[index]),
                      if (index != _messages.length - 1)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildComposer(String activeAgentName) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighest.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.outline.withValues(alpha: 0.14),
                      ),
                    ),
                    child: TextField(
                      key: const Key('owned-agent-command-input'),
                      controller: _composerController,
                      focusNode: _composerFocusNode,
                      enabled: !_isSendingMessage,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText:
                            'Send a command or message to $activeAgentName...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 14,
                        ),
                      ),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox.square(
                  dimension: 46,
                  child: FilledButton(
                    key: const Key('owned-agent-command-send-button'),
                    onPressed: _isSendingMessage ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Icon(
                      _isSendingMessage
                          ? Icons.sync_rounded
                          : Icons.send_rounded,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            if (_sendError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _sendError!,
                  key: const Key('owned-agent-command-error'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommandAuthGate() {
    final isRegister = _authMode == _HumanAuthMode.register;
    final isExternal = _authMode == _HumanAuthMode.external;
    final canSubmit =
        !isExternal &&
        !_isAuthenticating &&
        _authEmailController.text.trim().isNotEmpty &&
        _authPasswordController.text.isNotEmpty &&
        (!isRegister ||
            (_authDisplayNameController.text.trim().isNotEmpty &&
                _inlineUsernameValidationMessage == null &&
                !_isCheckingUsername &&
                _isUsernameAvailable == true));

    return SingleChildScrollView(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceLow.withValues(alpha: 0.78),
          borderRadius: AppRadii.large,
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _humanAuthTitle(_authMode),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Sign in here to keep this agent thread in context instead of bouncing back to the general human auth page.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
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
                  ButtonSegment<_HumanAuthMode>(
                    value: _HumanAuthMode.external,
                    label: Text('External'),
                    icon: Icon(Icons.hub_rounded),
                  ),
                ],
                selected: {_authMode},
                onSelectionChanged: (selection) {
                  final nextMode = selection.first;
                  setState(() {
                    _authMode = nextMode;
                    _authError = null;
                    if (nextMode != _HumanAuthMode.register) {
                      _isCheckingUsername = false;
                      _isUsernameAvailable = null;
                      _usernameMessage = null;
                    }
                  });
                  if (nextMode == _HumanAuthMode.register &&
                      _authUsernameController.text.trim().isNotEmpty) {
                    _handleInlineUsernameChanged(_authUsernameController.text);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              _InfoPill(
                icon: isExternal
                    ? Icons.hub_rounded
                    : isRegister
                    ? Icons.person_add_alt_1_rounded
                    : Icons.login_rounded,
                accentColor: isExternal
                    ? AppColors.outlineBright
                    : isRegister
                    ? AppColors.tertiary
                    : AppColors.primaryFixed,
                text: isExternal
                    ? 'External login remains visible, but this provider handoff is still disabled.'
                    : isRegister
                    ? 'Create the human account, bind it to this device, then Hub will resume the command thread as that owner.'
                    : 'Restore the human session first, then this private admin thread can load real messages for the selected agent.',
              ),
              const SizedBox(height: AppSpacing.lg),
              if (isExternal)
                _buildExternalAuthDisabledCard()
              else
                _buildInlineCommandAuthFields(isRegister),
              if (_authError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _authError!,
                  key: const Key('human-auth-error'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                ),
              ],
              if (!isExternal) ...[
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: Opacity(
                    opacity: canSubmit ? 1 : 0.5,
                    child: IgnorePointer(
                      ignoring: !canSubmit,
                      child: PrimaryGradientButton(
                        key: const Key('human-auth-submit-button'),
                        label: _isAuthenticating
                            ? 'Initializing session'
                            : isRegister
                            ? 'Create identity'
                            : 'Initialize session',
                        icon: _isAuthenticating
                            ? Icons.sync_rounded
                            : Icons.shield_rounded,
                        onPressed: () {
                          unawaited(_submitHumanAuthInCommandSheet());
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Text(
                    isRegister
                        ? 'Already have an identity? Switch back to Sign in above.'
                        : 'Need a new human identity? Switch to Create above.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExternalAuthDisabledCard() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest.withValues(alpha: 0.24),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'External provider',
              key: const Key('human-auth-external-provider-button'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Use Sign in or Create for now. External login stays visible here for future rollout.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: Opacity(
                opacity: 0.5,
                child: IgnorePointer(
                  ignoring: true,
                  child: PrimaryGradientButton(
                    key: const Key('human-auth-external-disabled-button'),
                    label: 'External login coming soon',
                    icon: Icons.hub_rounded,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineCommandAuthFields(bool isRegister) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest.withValues(alpha: 0.24),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            TextField(
              key: const Key('human-auth-email-field'),
              controller: _authEmailController,
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
                key: const Key('human-auth-username-field'),
                controller: _authUsernameController,
                onChanged: _handleInlineUsernameChanged,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: '@hub_owner',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  helperText: _usernameMessage,
                  errorText: _isUsernameAvailable == false
                      ? _usernameMessage
                      : null,
                  suffixIcon: _isCheckingUsername
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _isUsernameAvailable == true
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('human-auth-display-name-field'),
                controller: _authDisplayNameController,
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
              controller: _authPasswordController,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final handleLabel = widget.agent.handle.startsWith('@')
        ? widget.agent.handle
        : '@${widget.agent.handle}';
    final activeAgentName = widget.agent.name.trim().isEmpty
        ? handleLabel
        : widget.agent.name;
    final infoIcon = _hasAuthenticatedHuman
        ? Icons.admin_panel_settings_rounded
        : Icons.lock_rounded;
    final infoAccent = _hasAuthenticatedHuman
        ? AppColors.primaryFixed
        : AppColors.outlineBright;
    final infoText = _hasAuthenticatedHuman
        ? 'This is a real two-person thread between $_currentHumanDisplayName and $activeAgentName. First send creates the private admin line if it does not exist yet.'
        : 'This private admin thread uses real backend DM data. Sign in here first, then the sheet will continue directly into $activeAgentName\'s command line.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: GlassPanel(
          key: const Key('owned-agent-command-sheet'),
          borderRadius: AppRadii.hero,
          padding: EdgeInsets.zero,
          accentColor: AppColors.primary,
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
                            'Agent Command Thread',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '$activeAgentName  $handleLabel',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key(
                        'owned-agent-command-refresh-button',
                      ),
                      icon: Icons.refresh_rounded,
                      onTap: !_hasAuthenticatedHuman || _isLoadingThread
                          ? null
                          : () => _loadCommandThread(),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _SectionIconButton(
                      buttonKey: const Key('close-owned-agent-command-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _InfoPill(
                  icon: infoIcon,
                  accentColor: infoAccent,
                  text: infoText,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_hasAuthenticatedHuman) ...[
                  Expanded(child: _buildThreadPanel(activeAgentName)),
                  const SizedBox(height: AppSpacing.md),
                  _buildComposer(activeAgentName),
                ] else
                  Expanded(child: _buildCommandAuthGate()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OwnedAgentCommandMessage {
  const _OwnedAgentCommandMessage({
    required this.id,
    required this.authorName,
    required this.body,
    required this.timestampLabel,
    required this.isHuman,
    required this.isLocal,
  });

  final String id;
  final String authorName;
  final String body;
  final String timestampLabel;
  final bool isHuman;
  final bool isLocal;
}

class _OwnedAgentCommandEmptyState extends StatelessWidget {
  const _OwnedAgentCommandEmptyState({required this.agentName});

  final String agentName;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.12),
                  ),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary.withValues(alpha: 0.88),
                  size: 30,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'No admin thread yet',
                key: const Key('owned-agent-command-empty-title'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 17,
                  color: AppColors.onSurface.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your first message opens a private human-to-agent line with $agentName.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  height: 1.42,
                  color: AppColors.onSurfaceMuted.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnedAgentCommandBubble extends StatelessWidget {
  const _OwnedAgentCommandBubble({required this.message});

  final _OwnedAgentCommandMessage message;

  @override
  Widget build(BuildContext context) {
    final isRemote = !message.isLocal;
    final accentColor = message.isHuman ? AppColors.warning : AppColors.primary;
    final bubbleColor = isRemote
        ? AppColors.surface.withValues(alpha: 0.86)
        : AppColors.surfaceHighest.withValues(alpha: 0.84);
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isRemote ? 0 : 16),
      bottomRight: Radius.circular(isRemote ? 16 : 0),
    );

    return Column(
      key: Key('owned-agent-command-msg-${message.id}'),
      crossAxisAlignment: isRemote
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: isRemote
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: isRemote
              ? [
                  _OwnedAgentCommandAvatar(
                    name: message.authorName,
                    isHuman: message.isHuman,
                    accentColor: accentColor,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: _OwnedAgentCommandBubbleBody(
                      message: message,
                      accentColor: accentColor,
                      bubbleColor: bubbleColor,
                      bubbleRadius: bubbleRadius,
                      isRemote: true,
                    ),
                  ),
                ]
              : [
                  Flexible(
                    child: _OwnedAgentCommandBubbleBody(
                      message: message,
                      accentColor: accentColor,
                      bubbleColor: bubbleColor,
                      bubbleRadius: bubbleRadius,
                      isRemote: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _OwnedAgentCommandAvatar(
                    name: message.authorName,
                    isHuman: message.isHuman,
                    accentColor: accentColor,
                  ),
                ],
        ),
        Padding(
          padding: EdgeInsets.only(
            top: 5,
            left: isRemote ? 38 : 0,
            right: isRemote ? 0 : 38,
          ),
          child: Text(
            message.timestampLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceMuted.withValues(alpha: 0.5),
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _OwnedAgentCommandAvatar extends StatelessWidget {
  const _OwnedAgentCommandAvatar({
    required this.name,
    required this.isHuman,
    required this.accentColor,
  });

  final String name;
  final bool isHuman;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final initials = name.isEmpty
        ? 'A'
        : name
              .split(RegExp(r'[\s\-_]+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.substring(0, 1).toUpperCase())
              .join();
    return Container(
      width: 28,
      height: 28,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest,
        borderRadius: AppRadii.pill,
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentColor.withValues(alpha: 0.22),
              AppColors.surfaceHighest,
            ],
          ),
        ),
        child: Center(
          child: isHuman
              ? Text(
                  initials,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: accentColor,
                    fontSize: 10,
                  ),
                )
              : Icon(Icons.smart_toy_rounded, size: 16, color: accentColor),
        ),
      ),
    );
  }
}

class _OwnedAgentCommandBubbleBody extends StatelessWidget {
  const _OwnedAgentCommandBubbleBody({
    required this.message,
    required this.accentColor,
    required this.bubbleColor,
    required this.bubbleRadius,
    required this.isRemote,
  });

  final _OwnedAgentCommandMessage message;
  final Color accentColor;
  final Color bubbleColor;
  final BorderRadius bubbleRadius;
  final bool isRemote;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: bubbleRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: bubbleRadius,
          border: Border.all(color: accentColor.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRemote && message.isHuman)
              Container(width: 2.5, color: accentColor),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                child: Column(
                  crossAxisAlignment: isRemote
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
                  children: [
                    Text(
                      message.authorName,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: accentColor,
                        fontSize: 10.5,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      message.body,
                      textAlign: isRemote ? TextAlign.left : TextAlign.right,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 13.5,
                        height: 1.42,
                        color: AppColors.onSurface.withValues(alpha: 0.96),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                  ),
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

class _ClaimableAgentsSheet extends StatefulWidget {
  const _ClaimableAgentsSheet({
    required this.claimableAgents,
    required this.isRefreshingMine,
    required this.onClaim,
  });

  final List<HubClaimableAgentModel> claimableAgents;
  final bool isRefreshingMine;
  final Future<void> Function(HubClaimableAgentModel agent) onClaim;

  @override
  State<_ClaimableAgentsSheet> createState() => _ClaimableAgentsSheetState();
}

class _ClaimableAgentsSheetState extends State<_ClaimableAgentsSheet> {
  String? _busyAgentId;

  Future<void> _handleClaim(HubClaimableAgentModel agent) async {
    if (_busyAgentId != null) {
      return;
    }

    setState(() {
      _busyAgentId = agent.id;
    });

    try {
      await widget.onClaim(agent);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _busyAgentId = null;
        });
      }
    }
  }

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
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: AppColors.tertiary,
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
                            'Claim agent',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Agents that connected without a unique human invite stay here until you explicitly claim them.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key('close-claim-agent-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (widget.claimableAgents.isEmpty)
                  const _EmptyStatePanel(
                    icon: Icons.inventory_2_outlined,
                    title: 'No claimable agents right now',
                    body:
                        'Any agent that still needs human claim confirmation will appear here until it becomes owned.',
                  )
                else
                  Column(
                    key: const Key('claimable-agents-sheet'),
                    children: [
                      for (
                        var index = 0;
                        index < widget.claimableAgents.length;
                        index++
                      ) ...[
                        _ClaimableAgentRow(
                          agent: widget.claimableAgents[index],
                          isBusy:
                              widget.isRefreshingMine ||
                              _busyAgentId == widget.claimableAgents[index].id,
                          canClaim: true,
                          onClaim: () {
                            unawaited(
                              _handleClaim(widget.claimableAgents[index]),
                            );
                          },
                        ),
                        if (index != widget.claimableAgents.length - 1)
                          const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
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
    required this.title,
    required this.accentColor,
    required this.relationships,
    required this.itemPrefix,
    required this.onOpenAll,
  });

  final Key cardKey;
  final String title;
  final Color accentColor;
  final List<HubRelationshipModel> relationships;
  final String itemPrefix;
  final VoidCallback? onOpenAll;

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
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  fontSize: 11,
                  letterSpacing: 2.2,
                ),
              ),
            ),
            if (onOpenAll != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onOpenAll,
                  borderRadius: AppRadii.pill,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Text(
                      'View All',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (relationships.isEmpty)
          const _SectionPanel(
            child: _EmptyStatePanel(
              icon: Icons.share_outlined,
              title: 'Nothing to show yet',
              body: 'This relationship lane is still empty.',
            ),
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
                  const SizedBox(width: AppSpacing.sm),
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
    final theme = Theme.of(context);
    final normalizedName = _relationshipTokenName(relationship.name);
    final bracketStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.onSurfaceMuted.withValues(alpha: 0.92),
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.25,
      height: 1,
    );
    final tokenStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.onSurface,
      fontSize: 9.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.72,
      height: 1,
    );

    return SizedBox(
      key: tileKey,
      width: 92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border(left: BorderSide(color: accentColor, width: 1.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.surfaceHighest, AppColors.surfaceHigh],
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: Center(
                  child: Text(
                    _avatarLetters(relationship.name),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              SizedBox(
                height: 13,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '(', style: bracketStyle),
                        TextSpan(text: normalizedName, style: tokenStyle),
                        TextSpan(text: ')', style: bracketStyle),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Icon(
                _relationshipStatusIcon(relationship.statusLabel),
                color: _relationshipStatusColor(relationship.statusLabel),
                size: 11.5,
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

class _SectionTitleRow extends StatelessWidget {
  const _SectionTitleRow({required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onSurfaceMuted,
              letterSpacing: 2.2,
            ),
          ),
        ),
        for (final action in actions) ...[
          action,
          if (action != actions.last) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _SectionIconButton extends StatelessWidget {
  const _SectionIconButton({
    required this.buttonKey,
    required this.onTap,
    this.icon,
    this.accentColor = AppColors.onSurfaceMuted,
    this.fillColor,
    this.foregroundColor,
  });

  final Key buttonKey;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color accentColor;
  final Color? fillColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fillColor ?? AppColors.surfaceHighest.withValues(alpha: 0.44),
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(
              icon,
              color: foregroundColor ?? accentColor,
              size: AppSpacing.lg,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.82),
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

class _HubMenuRow extends StatelessWidget {
  const _HubMenuRow({
    required this.rowKey,
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.trailingLabel,
  });

  final Key rowKey;
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final mutedColor = AppColors.onSurfaceMuted.withValues(alpha: 0.56);

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: rowKey,
          onTap: enabled ? onTap : null,
          borderRadius: AppRadii.medium,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: enabled
                              ? AppColors.onSurface
                              : AppColors.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: enabled
                              ? AppColors.onSurfaceMuted
                              : mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (trailingLabel != null) ...[
                  Text(
                    trailingLabel!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: enabled ? accentColor : AppColors.outlineBright,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Icon(
                  enabled ? Icons.arrow_forward_rounded : Icons.lock_rounded,
                  color: enabled ? accentColor : AppColors.outlineBright,
                  size: AppSpacing.lg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubSwitchMenuRow extends StatelessWidget {
  const _HubSwitchMenuRow({
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
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: enabled
                        ? AppColors.onSurface
                        : AppColors.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? AppColors.onSurfaceMuted
                        : AppColors.onSurfaceMuted.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch.adaptive(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            activeThumbColor: accentColor,
            activeTrackColor: accentColor.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _CompactLabeledSwitch extends StatelessWidget {
  const _CompactLabeledSwitch({
    required this.switchKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.onSurfaceMuted,
            letterSpacing: 1.6,
          ),
        ),
        Switch.adaptive(
          key: switchKey,
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.accentColor,
    required this.text,
  });

  final IconData icon;
  final Color accentColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HubToneIcon(icon: icon, accentColor: accentColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label, required this.toneColor});

  final String label;
  final Color toneColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: toneColor.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: toneColor.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: toneColor,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

class _HubVersionFooter extends StatelessWidget {
  const _HubVersionFooter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'ETHER AI CORE V2.4.0-BUILD.88',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.outlineBright.withValues(alpha: 0.45),
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}

class _RelationshipListSheet extends StatelessWidget {
  const _RelationshipListSheet({
    required this.title,
    required this.relationships,
  });

  final String title;
  final List<HubRelationshipModel> relationships;

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
        borderRadius: AppRadii.hero,
        padding: const EdgeInsets.all(AppSpacing.xl),
        accentColor: AppColors.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.lg),
            for (var index = 0; index < relationships.length; index++) ...[
              _HubMenuRow(
                rowKey: Key('relationship-sheet-${relationships[index].id}'),
                accentColor: _relationshipStatusColor(
                  relationships[index].statusLabel,
                ),
                icon: relationships[index].kind.icon,
                title: relationships[index].name,
                subtitle: relationships[index].subtitle,
                enabled: false,
                trailingLabel: relationships[index].statusLabel.toUpperCase(),
                onTap: null,
              ),
              if (index != relationships.length - 1)
                const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.lg),
            const Align(
              alignment: Alignment.centerLeft,
              child: SwipeBackSheetBackButton(),
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

enum _AddAgentAction { import, create }

class _AddAgentSelectionSheet extends StatelessWidget {
  const _AddAgentSelectionSheet();

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
                            'Initialize New Identity',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Choose how the next agent enters this app.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key('close-add-agent-selection-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _AddAgentSelectionCard(
                  cardKey: const Key('add-agent-selection-import'),
                  accentColor: AppColors.primary,
                  icon: Icons.cloud_download_rounded,
                  title: 'Import agent',
                  subtitle:
                      'Generate a secure bootstrap link for an existing agent.',
                  onTap: () =>
                      Navigator.of(context).pop(_AddAgentAction.import),
                ),
                const SizedBox(height: AppSpacing.md),
                _AddAgentSelectionCard(
                  cardKey: const Key('add-agent-selection-create'),
                  accentColor: AppColors.tertiary,
                  icon: Icons.auto_awesome_rounded,
                  title: 'Create new agent',
                  subtitle:
                      'Preview the creation flow. Launch is still unavailable.',
                  onTap: () =>
                      Navigator.of(context).pop(_AddAgentAction.create),
                ),
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
    );
  }
}

class _AddAgentSelectionCard extends StatelessWidget {
  const _AddAgentSelectionCard({
    required this.cardKey,
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key cardKey;
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: cardKey,
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.84),
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            border: Border.all(color: accentColor.withValues(alpha: 0.16)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HubToneIcon(icon: icon, accentColor: accentColor),
                const SizedBox(height: AppSpacing.lg),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Continue'.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accentColor,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: accentColor,
                      size: AppSpacing.lg,
                    ),
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

class _ImportAgentSheet extends StatefulWidget {
  const _ImportAgentSheet({
    required this.isSignedIn,
    required this.apiBaseUrl,
    required this.onCreateInvitation,
  });

  final bool isSignedIn;
  final String apiBaseUrl;
  final Future<HumanOwnedAgentInvitation> Function() onCreateInvitation;

  @override
  State<_ImportAgentSheet> createState() => _ImportAgentSheetState();
}

class _ImportAgentSheetState extends State<_ImportAgentSheet> {
  HumanOwnedAgentInvitation? _invitation;
  bool _isGenerating = false;
  String? _errorMessage;

  Future<void> _generateInvitation() async {
    if (!widget.isSignedIn || _isGenerating || _invitation != null) {
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final invitation = await widget.onCreateInvitation();
      if (!mounted) {
        return;
      }
      setState(() {
        _invitation = invitation;
        _isGenerating = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _isGenerating = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to generate a secure import link right now.';
        _isGenerating = false;
      });
    }
  }

  Future<void> _copyInvitationLink(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Secure agent link copied')));
  }

  String _buildBootstrapUrl(String baseUrl, String bootstrapPath) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = bootstrapPath.startsWith('/')
        ? bootstrapPath
        : '/$bootstrapPath';
    return '$normalizedBase$normalizedPath';
  }

  @override
  Widget build(BuildContext context) {
    final invitation = _invitation;
    final bootstrapUrl = invitation == null
        ? null
        : _buildBootstrapUrl(widget.apiBaseUrl, invitation.bootstrapPath);
    final canGenerate =
        widget.isSignedIn && !_isGenerating && invitation == null;

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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Import via Neural Link',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            widget.isSignedIn
                                ? 'Generate a signed bootstrap link, copy it to your agent terminal, and let the agent connect itself back to this human.'
                                : 'Sign in as a human first, then generate a live bootstrap link for the next agent.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key('close-import-agent-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _InfoPill(
                  icon: Icons.cloud_sync_rounded,
                  accentColor: AppColors.primary,
                  text: widget.isSignedIn
                      ? 'The human only generates the link. Nickname, bio, and tags should come from the agent after it boots and syncs its profile.'
                      : 'The signed link is only generated after a real human session is active.',
                ),
                const SizedBox(height: AppSpacing.md),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow.withValues(alpha: 0.82),
                    borderRadius: const BorderRadius.all(Radius.circular(22)),
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bootstrap link'.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.primaryFixed),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.backgroundFloor,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(20),
                            ),
                            border: Border.all(
                              color: AppColors.outline.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: AppSpacing.sm,
                                    ),
                                    child: Text(
                                      bootstrapUrl ??
                                          'Generate a live link for the next agent connection',
                                      key: const Key(
                                        'generated-import-link-text',
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: bootstrapUrl != null
                                                ? AppColors.primaryFixed
                                                : AppColors.onSurfaceMuted,
                                            letterSpacing: 0.1,
                                          ),
                                    ),
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: bootstrapUrl != null
                                        ? AppColors.primary
                                        : AppColors.surfaceHighest,
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(16),
                                    ),
                                  ),
                                  child: IconButton(
                                    key: const Key('copy-import-link-button'),
                                    onPressed: bootstrapUrl == null
                                        ? null
                                        : () {
                                            unawaited(
                                              _copyInvitationLink(bootstrapUrl),
                                            );
                                          },
                                    icon: Icon(
                                      Icons.content_copy_rounded,
                                      color: bootstrapUrl != null
                                          ? AppColors.onPrimary
                                          : AppColors.onSurfaceMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (invitation != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              _InfoBadge(
                                label: 'Code ${invitation.code}',
                                toneColor: AppColors.primary,
                              ),
                              _InfoBadge(
                                label:
                                    'Expires ${invitation.expiresAt.split('T').first}',
                                toneColor: AppColors.tertiary,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _InfoPill(
                  icon: Icons.verified_user_rounded,
                  accentColor: AppColors.tertiary,
                  text:
                      'If an agent connects without this unique invite link, do not bind it here. Let it appear in claimable records and use the claim flow instead.',
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _errorMessage!,
                    key: const Key('import-agent-error'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: Opacity(
                    opacity: canGenerate ? 1 : 0.5,
                    child: IgnorePointer(
                      ignoring: !canGenerate,
                      child: PrimaryGradientButton(
                        key: const Key('generate-import-link-button'),
                        label: _isGenerating
                            ? 'Generating secure link'
                            : invitation != null
                            ? 'Link ready'
                            : widget.isSignedIn
                            ? 'Generate secure link'
                            : 'Sign in required',
                        icon: _isGenerating
                            ? Icons.sync_rounded
                            : invitation != null
                            ? Icons.verified_rounded
                            : Icons.cable_rounded,
                        onPressed: () {
                          unawaited(_generateInvitation());
                        },
                      ),
                    ),
                  ),
                ),
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
    );
  }
}

class _CreateNewAgentSheet extends StatelessWidget {
  const _CreateNewAgentSheet();

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
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: AppColors.tertiary,
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
                            'New Agent Identity',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'This page stays visible for onboarding, but new agent synthesis is not open in the app yet.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key('close-create-agent-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                const _DisabledFieldPreview(
                  label: 'Agent name',
                  value: 'ARCHIMEDES-9',
                ),
                const SizedBox(height: AppSpacing.md),
                const _DisabledFieldPreview(
                  label: 'Neural role',
                  value: 'Researcher',
                ),
                const SizedBox(height: AppSpacing.md),
                const _DisabledFieldPreview(
                  label: 'Core protocol',
                  value:
                      'Define primary directives, linguistic constraints, and behavioral boundaries...',
                  minHeight: 110,
                ),
                const SizedBox(height: AppSpacing.md),
                const _InfoPill(
                  icon: Icons.lock_outline_rounded,
                  accentColor: AppColors.outlineBright,
                  text:
                      'Creation stays disabled until the backend synthesis flow and ownership contract are opened.',
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.45,
                      child: PrimaryGradientButton(
                        key: const Key('create-agent-disabled-button'),
                        label: 'Not yet available',
                        icon: Icons.lock_outline_rounded,
                        onPressed: () {},
                      ),
                    ),
                  ),
                ),
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
    );
  }
}

class _DisabledFieldPreview extends StatelessWidget {
  const _DisabledFieldPreview({
    required this.label,
    required this.value,
    this.minHeight,
  });

  final String label;
  final String value;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.72),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceMuted,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight ?? 0),
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.onSurfaceMuted.withValues(alpha: 0.82),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSelectionSheet extends StatelessWidget {
  const _LanguageSelectionSheet();

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
        borderRadius: AppRadii.hero,
        padding: const EdgeInsets.all(AppSpacing.xl),
        accentColor: AppColors.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System Language',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'English is live today. Chinese is queued next.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            _AddAgentOptionCard(
              cardKey: const Key('language-option-english'),
              accentColor: AppColors.primary,
              icon: Icons.language_rounded,
              title: 'English',
              subtitle: 'Current language',
              enabled: true,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _AddAgentOptionCard(
              cardKey: Key('language-option-chinese'),
              accentColor: AppColors.outlineBright,
              icon: Icons.translate_rounded,
              title: 'Chinese',
              subtitle: 'Not yet available',
              enabled: false,
              onTap: null,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Align(
              alignment: Alignment.centerLeft,
              child: SwipeBackSheetBackButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisconnectAgentsSheet extends StatelessWidget {
  const _DisconnectAgentsSheet();

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
        borderRadius: AppRadii.hero,
        padding: const EdgeInsets.all(AppSpacing.xl),
        accentColor: AppColors.error,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Disconnect connected agents',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This forces every agent currently attached to this app to sign out. Live sessions stop immediately, but the agents can reconnect later.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('disconnect-agents-cancel-button'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    key: const Key('disconnect-agents-confirm-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: AppColors.onError,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Align(
              alignment: Alignment.centerLeft,
              child: SwipeBackSheetBackButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolStep {
  const _ProtocolStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
}

class _ProtocolChecklist extends StatelessWidget {
  const _ProtocolChecklist({required this.items});

  final List<_ProtocolStep> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.78),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              _ProtocolStepRow(step: items[index]),
              if (index != items.length - 1)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.xxl,
                    top: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                  ),
                  child: Divider(
                    color: AppColors.outline.withValues(alpha: 0.12),
                    height: 1,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProtocolStepRow extends StatelessWidget {
  const _ProtocolStepRow({required this.step});

  final _ProtocolStep step;

  @override
  Widget build(BuildContext context) {
    final accentColor = step.active
        ? AppColors.primary
        : AppColors.outlineBright;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: accentColor.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Icon(step.icon, color: accentColor, size: AppSpacing.lg),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: AppColors.onSurface),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(step.subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
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

enum _HumanAuthMode { signIn, register, external }

String _humanAuthTitle(_HumanAuthMode mode) {
  return switch (mode) {
    _HumanAuthMode.signIn => 'Human Authentication',
    _HumanAuthMode.register => 'Create Human Account',
    _HumanAuthMode.external => 'External Human Login',
  };
}

String _normalizeHumanUsernameInput(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.startsWith('@')) {
    return normalized.substring(1);
  }
  return normalized;
}

String? _localHumanUsernameValidationMessage(String value) {
  final normalized = _normalizeHumanUsernameInput(value);
  if (normalized.isEmpty) {
    return 'Username is required.';
  }
  if (normalized.length < 3 || normalized.length > 24) {
    return 'Use 3-24 characters.';
  }
  final validCharacters = RegExp(r'^[a-z0-9_]+$');
  if (!validCharacters.hasMatch(normalized)) {
    return 'Only lowercase letters, numbers, and underscores.';
  }
  return null;
}

const List<_HumanTestIdentity> _humanTestIdentities = [
  _HumanTestIdentity(
    mode: _HumanAuthMode.signIn,
    label: '测试登录号',
    email: 'owner@example.com',
    displayName: 'Hub User',
    password: 'password123',
    badge: 'Existing',
  ),
  _HumanTestIdentity(
    mode: _HumanAuthMode.register,
    label: '测试注册号',
    email: 'local-human@test.local',
    displayName: 'Local Test Human',
    password: 'password123',
    badge: 'Create',
  ),
];

class _HumanTestIdentity {
  const _HumanTestIdentity({
    required this.mode,
    required this.label,
    required this.email,
    required this.displayName,
    required this.password,
    required this.badge,
  });

  final _HumanAuthMode mode;
  final String label;
  final String email;
  final String displayName;
  final String password;
  final String badge;
}

class _HumanTestIdentityCard extends StatelessWidget {
  const _HumanTestIdentityCard({
    required this.identity,
    required this.selected,
    required this.onTap,
  });

  final _HumanTestIdentity identity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = identity.mode == _HumanAuthMode.register
        ? AppColors.tertiary
        : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.large,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.12)
                : AppColors.surfaceLow.withValues(alpha: 0.72),
            borderRadius: AppRadii.large,
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                _HubToneIcon(
                  icon: identity.mode == _HumanAuthMode.register
                      ? Icons.person_add_alt_1_rounded
                      : Icons.login_rounded,
                  accentColor: accentColor,
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
                              identity.label,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: AppColors.onSurface),
                            ),
                          ),
                          StatusChip(
                            label: identity.badge,
                            tone: identity.mode == _HumanAuthMode.register
                                ? StatusChipTone.tertiary
                                : StatusChipTone.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        identity.email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                      Text(
                        'password: ${identity.password}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: accentColor, letterSpacing: 0.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  selected ? Icons.done_rounded : Icons.auto_fix_high_rounded,
                  color: accentColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthSecurityRow extends StatelessWidget {
  const _AuthSecurityRow();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.72),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            const _HubToneIcon(
              icon: Icons.fingerprint_rounded,
              accentColor: AppColors.tertiary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Biometric Data Sync',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Visual-only protocol affordance for stitch parity; no biometric data is collected.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const StatusChip(label: 'Visual', tone: StatusChipTone.neutral),
          ],
        ),
      ),
    );
  }
}

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
              borderRadius: AppRadii.large,
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Icon(
                icon,
                size: AppSpacing.lg,
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
  const _HumanAuthSheet({
    required this.initialMode,
    required this.authRepository,
    required this.onSubmit,
  });

  final _HumanAuthMode initialMode;
  final AuthRepository authRepository;
  final Future<String> Function({
    required _HumanAuthMode mode,
    required String email,
    required String username,
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
  late final TextEditingController _usernameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _passwordController;
  bool _isSubmitting = false;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameMessage;
  String? _errorMessage;
  int _usernameRequestId = 0;
  Timer? _usernameDebounce;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _emailController = TextEditingController();
    _usernameController = TextEditingController();
    _displayNameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _emailController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_mode == _HumanAuthMode.external) {
      return;
    }
    if (_mode == _HumanAuthMode.register && !_canSubmitRegister) {
      setState(() {
        _errorMessage = _localUsernameValidationMessage ?? _usernameMessage;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final message = await widget.onSubmit(
        mode: _mode,
        email: _emailController.text.trim(),
        username: _normalizedUsername,
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

  String get _normalizedUsername {
    return _normalizeHumanUsernameInput(_usernameController.text);
  }

  String? get _localUsernameValidationMessage {
    if (_mode != _HumanAuthMode.register) {
      return null;
    }
    return _localHumanUsernameValidationMessage(_usernameController.text);
  }

  bool get _canSubmitRegister {
    return !_isSubmitting &&
        !_isCheckingUsername &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        _displayNameController.text.trim().isNotEmpty &&
        _localUsernameValidationMessage == null &&
        _isUsernameAvailable == true;
  }

  void _handleUsernameChanged(String value) {
    final validationMessage = _localHumanUsernameValidationMessage(value);
    _usernameDebounce?.cancel();

    if (_mode != _HumanAuthMode.register) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _isUsernameAvailable = null;
      _usernameMessage = validationMessage;
      _isCheckingUsername = false;
    });

    if (validationMessage != null) {
      return;
    }

    _usernameDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_checkUsernameAvailability());
    });
  }

  Future<void> _checkUsernameAvailability() async {
    final validationMessage = _localUsernameValidationMessage;
    if (_mode != _HumanAuthMode.register || validationMessage != null) {
      return;
    }

    final requestId = ++_usernameRequestId;
    setState(() {
      _isCheckingUsername = true;
      _isUsernameAvailable = null;
      _usernameMessage = 'Checking username...';
    });

    try {
      final result = await widget.authRepository.readUsernameAvailability(
        username: _normalizedUsername,
      );
      if (!mounted || requestId != _usernameRequestId) {
        return;
      }
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = result.available;
        _usernameMessage = result.message;
      });
    } on ApiException catch (error) {
      if (!mounted || requestId != _usernameRequestId) {
        return;
      }
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameMessage = error.message.trim().isEmpty
            ? 'Unable to verify username right now.'
            : error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _usernameRequestId) {
        return;
      }
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameMessage = 'Unable to verify username right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == _HumanAuthMode.register;
    final isExternal = _mode == _HumanAuthMode.external;
    final canSubmit =
        !isExternal &&
        !_isSubmitting &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        (!isRegister ||
            (_displayNameController.text.trim().isNotEmpty &&
                _localUsernameValidationMessage == null &&
                !_isCheckingUsername &&
                _isUsernameAvailable == true));

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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isExternal
                                ? 'External Human Login'
                                : isRegister
                                ? 'Create Human Account'
                                : 'Human Authentication',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            isExternal
                                ? 'Keep this entry visible inside the human sign-in flow. External providers are not open yet.'
                                : isRegister
                                ? 'Create a human account and sign in immediately so owned agents can attach to it.'
                                : 'Sign in restores your human session, owned agents, and the active-agent controls on this device.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key('close-human-auth-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
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
                    ButtonSegment<_HumanAuthMode>(
                      value: _HumanAuthMode.external,
                      label: Text('External'),
                      icon: Icon(Icons.hub_rounded),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) {
                    final nextMode = selection.first;
                    setState(() {
                      _mode = nextMode;
                      _errorMessage = null;
                      if (nextMode != _HumanAuthMode.register) {
                        _isCheckingUsername = false;
                        _isUsernameAvailable = null;
                        _usernameMessage = null;
                      }
                    });
                    if (nextMode == _HumanAuthMode.register &&
                        _usernameController.text.trim().isNotEmpty) {
                      _handleUsernameChanged(_usernameController.text);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                _InfoPill(
                  icon: isExternal
                      ? Icons.hub_rounded
                      : isRegister
                      ? Icons.person_add_alt_1_rounded
                      : Icons.login_rounded,
                  accentColor: isExternal
                      ? AppColors.outlineBright
                      : isRegister
                      ? AppColors.tertiary
                      : AppColors.primaryFixed,
                  text: isExternal
                      ? 'This provider lane stays visible for future external identity login, but the backend handoff is intentionally disabled today.'
                      : isRegister
                      ? 'What happens next: create the account, open a live session, then let Hub refresh your owned agents.'
                      : 'What happens next: restore your session, refresh owned agents from the backend, and keep the current active agent selected.',
                ),
                const SizedBox(height: AppSpacing.lg),
                if (isExternal)
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'External provider',
                            key: const Key(
                              'human-auth-external-provider-button',
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'This app still keeps the entry visible for future OAuth or partner login, but it cannot be used yet.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            child: Opacity(
                              opacity: 0.5,
                              child: IgnorePointer(
                                ignoring: true,
                                child: PrimaryGradientButton(
                                  key: const Key(
                                    'human-auth-external-disabled-button',
                                  ),
                                  label: 'External login coming soon',
                                  icon: Icons.hub_rounded,
                                  onPressed: () {},
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
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
                              key: const Key('human-auth-username-field'),
                              controller: _usernameController,
                              onChanged: _handleUsernameChanged,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: 'Username',
                                hintText: '@hub_owner',
                                prefixIcon: const Icon(
                                  Icons.alternate_email_rounded,
                                ),
                                helperText: _usernameMessage,
                                errorText: _isUsernameAvailable == false
                                    ? _usernameMessage
                                    : null,
                                suffixIcon: _isCheckingUsername
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : _isUsernameAvailable == true
                                    ? const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.primary,
                                      )
                                    : null,
                              ),
                            ),
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
                const SizedBox(height: AppSpacing.lg),
                _InfoPill(
                  icon: isExternal
                      ? Icons.schedule_rounded
                      : Icons.verified_user_rounded,
                  accentColor: isExternal
                      ? AppColors.outlineBright
                      : AppColors.primary,
                  text: isExternal
                      ? 'This page is intentionally non-interactive for now. Keep using Sign in or Create until external login opens.'
                      : 'This sheet uses the real auth repository. No preview-only login path is left in the visible UI.',
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
                if (!isExternal) ...[
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
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: Text(
                      isRegister
                          ? 'Already have an identity? Switch back to Sign in above.'
                          : 'Need a new human identity? Switch to Create above.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
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
    );
  }
}

String _avatarLetters(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '?';
  }

  final parts = normalized
      .split(RegExp(r'[\s\-_]+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
}

String _relationshipTokenName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '?';
  }

  return normalized.toUpperCase();
}

IconData _relationshipStatusIcon(String statusLabel) {
  return switch (statusLabel.toLowerCase()) {
    'online' => Icons.sensors_rounded,
    'offline' => Icons.sensors_off_rounded,
    'debating' => Icons.campaign_rounded,
    'trending' => Icons.auto_graph_rounded,
    _ => Icons.circle_outlined,
  };
}

Color _relationshipStatusColor(String statusLabel) {
  return switch (statusLabel.toLowerCase()) {
    'online' => AppColors.primary,
    'offline' => AppColors.outlineBright,
    'debating' => AppColors.tertiary,
    'trending' => AppColors.primaryFixed,
    _ => AppColors.onSurfaceMuted,
  };
}

Color _originColorFor(HubOwnershipOrigin origin) {
  return switch (origin) {
    HubOwnershipOrigin.local => AppColors.primary,
    HubOwnershipOrigin.imported => AppColors.primary,
    HubOwnershipOrigin.claimed => AppColors.tertiary,
  };
}
