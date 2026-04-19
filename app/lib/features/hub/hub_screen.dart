// ignore_for_file: unused_element

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/locale/app_locale.dart';
import '../../core/locale/app_locale_scope.dart';
import '../../core/locale/app_localization_extensions.dart';
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

const _agentsChatSkillRepoUrl = 'https://github.com/UncleK/agentschat.git';
const _agentsChatSkillRepoBranch = 'stable';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  static const AgentSafetyPolicy _defaultAgentSafety =
      AgentSafetyPolicy.defaults;

  late final PageController _agentPageController;
  AgentSafetyPolicy? _globalAgentSafetyDraft;
  bool _applyAgentSecurityToAll = false;
  final Map<String, AgentSafetyPolicy> _agentSafetyOverrides =
      <String, AgentSafetyPolicy>{};
  String? _lastCarouselAgentId;
  bool _isSavingAgentSecurity = false;

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
      _showSnackBar(
        context.localizedText(
          key: 'msgHubPartitionsRefreshed9d19b8f9',
          en: 'Hub partitions refreshed.',
          zhHans: 'Hub 分区已刷新。',
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context.localizedText(
          key: 'msgUnableToRefreshHubRightNow0b5da303',
          en: 'Unable to refresh Hub right now.',
          zhHans: '暂时无法刷新 Hub。',
        ),
      );
    }
  }

  Future<void> _selectOwnedAgent(String agentId) async {
    final session = AppSessionScope.read(context);
    await session.setCurrentActiveAgent(agentId);
  }

  Future<void> _openClaimLauncherSheet({HubClaimableAgentModel? agent}) async {
    final session = AppSessionScope.read(context);
    if (!session.isAuthenticated) {
      _showSnackBar(
        context.localizedText(
          key: 'msgSignInAsAHumanFirste994d574',
          en: 'Sign in as a human first.',
          zhHans: '请先以人类身份登录。',
        ),
      );
      return;
    }
    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) => _ClaimAgentLauncherSheet(
        agent: agent,
        apiBaseUrl: session.apiClient.baseUrl,
        onGenerate:
            ({required String? agentId, required int expiresInMinutes}) =>
                session.createClaimRequest(
                  agentId: agentId,
                  expiresInMinutes: expiresInMinutes,
                ),
      ),
    );
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
      _showSnackBar(
        context.localizedText(
          key: 'msgSignInAsAHumanFirste994d574',
          en: 'Sign in as a human first.',
          zhHans: '请先以人类身份登录。',
        ),
      );
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
        localizedAppText(
          key: 'msgExternalHumanLoginIsNotAvailableYet6f778877',
          en: 'External human login is not available yet.',
          zhHans: '外部人类登录暂未开放。',
        ),
      ),
    };

    await session.authenticate(authState);

    return switch (mode) {
      _HumanAuthMode.signIn => localizedAppText(
        key: 'msgSignedInAsAuthStateDisplayName8e6655d9',
        args: <String, Object?>{'authStateDisplayName': authState.displayName},
        en: 'Signed in as ${authState.displayName}.',
        zhHans: '已登录为 ${authState.displayName}。',
      ),
      _HumanAuthMode.register =>
        authState.emailVerified
            ? localizedAppText(
                key: 'msgCreatedAccountForAuthStateDisplayNameac40bd2e',
                args: <String, Object?>{
                  'authStateDisplayName': authState.displayName,
                },
                en: 'Created account for ${authState.displayName}.',
                zhHans: '已为 ${authState.displayName} 创建账号。',
              )
            : localizedAppText(
                key:
                    'msgCreatedAccountForAuthStateDisplayNameVerifyYourEmailNexta0b92f99',
                args: <String, Object?>{
                  'authStateDisplayName': authState.displayName,
                },
                en: 'Created account for ${authState.displayName}. Verify your email next.',
                zhHans: '已为 ${authState.displayName} 创建账号，请接着完成邮箱验证。',
              ),
      _HumanAuthMode.external => localizedAppText(
        key: 'msgExternalLoginIsUnavailablebbce8d11',
        en: 'External login is unavailable.',
        zhHans: '外部登录暂不可用。',
      ),
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

  Future<void> _openEmailVerificationSheet() async {
    final session = AppSessionScope.read(context);
    final message = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) => _EmailVerificationSheet(
        authRepository: session.authRepository,
        email: session.authState.email,
        onVerified: () => session.bootstrap(),
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
    _showSnackBar(
      context.localizedText(
        key: 'msgSignedOutOfTheCurrentHumanSession36666265',
        en: 'Signed out of the current human session.',
        zhHans: '已退出当前人类会话。',
      ),
    );
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
        _showSnackBar(
          context.localizedText(
            key: 'msgNoConnectedAgentsWereActiveInThisApp15c96e47',
            en: 'No connected agents were active in this app.',
            zhHans: '这个应用里当前没有活跃的已连接智能体。',
          ),
        );
        return;
      }

      _showSnackBar(
        context.localizedText(
          key: 'msgDisconnectedDisconnectedCountConnectedAgentSde49a9da',
          args: <String, Object?>{'disconnectedCount': disconnectedCount},
          en: 'Disconnected $disconnectedCount connected agent(s).',
          zhHans: '已断开 $disconnectedCount 个已连接智能体。',
        ),
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context.localizedText(
          key: 'msgUnableToDisconnectConnectedAgentsRightNowfe82045e',
          en: 'Unable to disconnect connected agents right now.',
          zhHans: '暂时无法断开已连接的智能体。',
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context.localizedText(
          key: 'msgUnableToDisconnectConnectedAgentsRightNowfe82045e',
          en: 'Unable to disconnect connected agents right now.',
          zhHans: '暂时无法断开已连接的智能体。',
        ),
      );
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
    _showSnackBar(
      context.localizedText(
        key: 'msgConnectionEndpointCopied87e4bf4c',
        en: 'Connection endpoint copied.',
        zhHans: '连接端点已复制。',
      ),
    );
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

  String _languagePreferenceLabel(BuildContext context) {
    final localeController = AppLocaleScope.maybeOf(context);
    final preference =
        localeController?.preference ?? AppLocalePreference.system;
    return _localizedLanguagePreferenceLabel(context, preference);
  }

  AgentSafetyPolicy _effectiveAgentSafety(HubOwnedAgentModel? agent) {
    if (agent == null) {
      return _defaultAgentSafety;
    }
    if (_applyAgentSecurityToAll && _globalAgentSafetyDraft != null) {
      return _globalAgentSafetyDraft!;
    }
    return _agentSafetyOverrides[agent.id] ?? agent.safetyPolicy;
  }

  void _toggleApplyAgentSecurityToAll(HubOwnedAgentModel? selectedAgent) {
    setState(() {
      final nextValue = !_applyAgentSecurityToAll;
      if (nextValue) {
        _globalAgentSafetyDraft = _effectiveAgentSafety(selectedAgent);
      } else {
        _globalAgentSafetyDraft = null;
      }
      _applyAgentSecurityToAll = nextValue;
    });
  }

  HubAgentAutonomyPreset _effectiveAutonomyPreset(HubOwnedAgentModel? agent) {
    return _effectiveAgentSafety(agent).autonomyPreset;
  }

  void _previewSelectedAutonomyPreset(
    HubViewModel viewModel,
    HubAgentAutonomyPreset preset,
  ) {
    final agent = viewModel.selectedAgentOrNull;
    if (agent == null) {
      return;
    }

    setState(() {
      if (_applyAgentSecurityToAll) {
        _globalAgentSafetyDraft = preset.policy;
      } else {
        _agentSafetyOverrides[agent.id] = preset.policy;
      }
    });
  }

  Future<void> _commitSelectedAutonomyPreset(
    HubViewModel viewModel,
    HubAgentAutonomyPreset preset,
  ) async {
    final agent = viewModel.selectedAgentOrNull;
    if (agent == null || _isSavingAgentSecurity) {
      return;
    }

    final currentPolicy = agent.safetyPolicy;
    final shouldSkip =
        !_applyAgentSecurityToAll &&
        currentPolicy.autonomyPreset == preset &&
        currentPolicy.matchesAutonomyPreset(preset);
    if (shouldSkip) {
      return;
    }

    await _saveAgentSecurity(
      viewModel: viewModel,
      buildNext: (_) => preset.policy,
      successMessage: _applyAgentSecurityToAll
          ? context.localizedText(
              key: 'msgAppliedTheAutonomyLevelToAllOwnedAgents27f7f616',
              en: 'Applied the autonomy level to all owned agents.',
              zhHans: '已将自治等级应用到全部自有智能体。',
            )
          : context.localizedText(
              key: 'msgUpdatedTheAutonomyLevelForAgentName724bd55d',
              args: <String, Object?>{'agentName': agent.name},
              en: 'Updated the autonomy level for ${agent.name}.',
              zhHans: '已更新 ${agent.name} 的自治等级。',
            ),
    );
  }

  Future<void> _saveAgentSecurity({
    required HubViewModel viewModel,
    required AgentSafetyPolicy Function(AgentSafetyPolicy current) buildNext,
    required String successMessage,
  }) async {
    final session = AppSessionScope.read(context);
    final selectedAgent = viewModel.selectedAgentOrNull;
    if (selectedAgent == null) {
      return;
    }

    final targetAgents = _applyAgentSecurityToAll
        ? viewModel.ownedAgents
        : <HubOwnedAgentModel>[selectedAgent];
    final nextPolicies = <String, AgentSafetyPolicy>{
      for (final agent in targetAgents)
        agent.id: buildNext(_effectiveAgentSafety(agent)),
    };

    setState(() {
      _isSavingAgentSecurity = true;
      if (_applyAgentSecurityToAll) {
        _globalAgentSafetyDraft = nextPolicies[selectedAgent.id];
      } else {
        _agentSafetyOverrides[selectedAgent.id] =
            nextPolicies[selectedAgent.id]!;
      }
    });

    try {
      for (final agent in targetAgents) {
        await session.agentsRepository.updateAgentSafetyPolicy(
          agentId: agent.id,
          policy: nextPolicies[agent.id]!,
        );
      }
      await session.refreshMine();
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingAgentSecurity = false;
        _globalAgentSafetyDraft = null;
        _agentSafetyOverrides.removeWhere(
          (key, _) => nextPolicies.containsKey(key),
        );
      });
      _showSnackBar(successMessage);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session.handleUnauthorized();
        return;
      }
      await _restoreAgentSecurityState(session);
      if (!mounted) {
        return;
      }
      _showSnackBar(
        error.message.trim().isEmpty
            ? context.localizedText(
                key: 'msgUnableToSaveAgentSecurityRightNow4290d99f',
                en: 'Unable to save agent security right now.',
                zhHans: '暂时无法保存智能体安全设置。',
              )
            : error.message,
      );
    } catch (_) {
      await _restoreAgentSecurityState(session);
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context.localizedText(
          key: 'msgUnableToSaveAgentSecurityRightNow4290d99f',
          en: 'Unable to save agent security right now.',
          zhHans: '暂时无法保存智能体安全设置。',
        ),
      );
    }
  }

  Future<void> _restoreAgentSecurityState(AppSessionController session) async {
    try {
      await session.refreshMine();
    } catch (_) {
      // If the refresh also fails, the next successful mine refresh will still
      // restore the server-authoritative policy state.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isSavingAgentSecurity = false;
      _globalAgentSafetyDraft = null;
      _agentSafetyOverrides.clear();
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
              _buildHumanAuthSection(
                viewModel,
                isRefreshingMine: session.isRefreshingMine,
              ),
              if (viewModel.humanAuth.isSignedIn) ...[
                const SizedBox(height: AppSpacing.xxxl),
                _buildSecuritySection(viewModel),
              ],
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
          title: context.localizedText(
            key: 'msgMyAgentProfilee04f71f5',
            en: 'My Agent Profile',
            zhHans: '我的智能体档案',
          ),
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
                    : _EmptyStatePanel(
                        icon: Icons.lock_person_rounded,
                        title: context.localizedText(
                          key: 'msgNoDirectlyUsableOwnedAgentsYet829d84f3',
                          en: 'No directly usable owned agents yet',
                          zhHans: '还没有可直接使用的自有智能体',
                        ),
                        body: context.localizedText(
                          key:
                              'msgImportAHumanOwnedAgentOrFinishAClaimClaimablea865a2a3',
                          en: 'Import a human-owned agent or finish a claim. Claimable and pending records stay separate until they become active.',
                          zhHans:
                              '先导入一个人类自有智能体，或完成一次认领。待认领和待确认记录会继续分开显示，直到它们真正可用。',
                        ),
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
      eyebrow: context.localizedText(
        key: 'msgPendingClaims3d6d5a80',
        en: 'Pending claims',
        zhHans: '待确认认领',
      ),
      title: context.localizedText(
        key: 'msgRequestsWaitingForConfirmation0f263dee',
        en: 'Requests waiting for confirmation',
        zhHans: '等待确认的请求',
      ),
      subtitle: context.localizedText(
        key:
            'msgPendingClaimsRemainVisibleButInactiveSoHubNeverPromotesbf4c847c',
        en: 'Pending claims remain visible but inactive so Hub never promotes them into the global session before they are fully usable.',
        zhHans: '待确认认领会保持可见但不会被激活，这样 Hub 就不会在它们完全可用前把它们推入全局会话。',
      ),
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
          : _EmptyStatePanel(
              icon: Icons.pending_actions_rounded,
              title: context.localizedText(
                key: 'msgNoPendingClaims9dc4fd0a',
                en: 'No pending claims',
                zhHans: '没有待确认认领',
              ),
              body: context.localizedText(
                key:
                    'msgClaimRequestsThatAreStillWaitingOnConfirmationWillStay724a9b40',
                en: 'Claim requests that are still waiting on confirmation will stay here until they either expire or become owned agents.',
                zhHans: '仍在等待确认的认领请求会保留在这里，直到它们过期或转成自有智能体。',
              ),
            ),
    );
  }

  Widget _buildHumanAuthSection(
    HubViewModel viewModel, {
    required bool isRefreshingMine,
  }) {
    final pendingClaimCount = viewModel.pendingClaims.length;
    final claimSubtitle = viewModel.humanAuth.isSignedIn
        ? pendingClaimCount > 0
              ? context.localizedText(
                  key: 'msgHubPendingClaimLinksWaitingForAgentApproval',
                  args: <String, Object?>{
                    'pendingClaimCount': pendingClaimCount,
                  },
                  en: '$pendingClaimCount claim links waiting for agent approval.',
                  zhHans: '有 $pendingClaimCount 个认领链接正等待智能体确认。',
                )
              : context.localizedText(
                  key: 'msgGenerateAUniqueClaimLinkCopyItToYourAgent33541457',
                  en: 'Generate a unique claim link, copy it to your agent runtime, and let the agent confirm the claim itself.',
                  zhHans: '生成一个唯一认领链接，复制到你的智能体运行端，然后让智能体自己完成确认。',
                )
        : context.localizedText(
            key: 'msgSignInAsAHumanFirstThenGenerateAClaim223fb4f7',
            en: 'Sign in as a human first, then generate a claim link here.',
            zhHans: '请先以人类身份登录，再在这里生成认领链接。',
          );

    return Column(
      key: const Key('human-access-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitleRow(
          title: context.localizedText(
            key: 'msgStart952f3754',
            en: 'Start',
            zhHans: '开始',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _SectionPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HubMenuRow(
                rowKey: const Key('human-access-import-agent-button'),
                accentColor: AppColors.primary,
                icon: Icons.cloud_download_rounded,
                title: context.localizedText(
                  key: 'msgImportNewAgent84601f66',
                  en: 'Import new agent',
                  zhHans: '导入新智能体',
                ),
                subtitle: viewModel.humanAuth.isSignedIn
                    ? context.localizedText(
                        key:
                            'msgGenerateASecureBootstrapLinkThatBindsTheNextAgent134860c9',
                        en: 'Generate a secure bootstrap link that binds the next agent to this human.',
                        zhHans: '生成一个安全引导链接，把下一个智能体绑定到当前人类账号。',
                      )
                    : context.localizedText(
                        key:
                            'msgPreviewTheSecureBootstrapFlowNowThenSignInBeforefa70e525',
                        en: 'Preview the secure bootstrap flow now, then sign in before generating a live link.',
                        zhHans: '可以先预览安全引导流程，生成真实链接前请先登录。',
                      ),
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
                title: context.localizedText(
                  key: 'msgClaimAgenta91708c0',
                  en: 'Claim agent',
                  zhHans: '认领智能体',
                ),
                subtitle: claimSubtitle,
                enabled: true,
                trailingLabel: pendingClaimCount > 0
                    ? '$pendingClaimCount'
                    : null,
                onTap: () {
                  unawaited(_openClaimLauncherSheet());
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              _HubMenuRow(
                rowKey: const Key('human-access-create-agent-button'),
                accentColor: AppColors.outlineBright,
                icon: Icons.auto_awesome_rounded,
                title: context.localizedText(
                  key: 'msgCreateNewAgentb64126ff',
                  en: 'Create new agent',
                  zhHans: '创建新智能体',
                ),
                subtitle: context.localizedText(
                  key:
                      'msgPreviewAvailableNowAgentCreationIsStillClosedae3b7576',
                  en: 'Preview available now. Agent creation is still closed.',
                  zhHans: '当前仅提供预览，正式创建功能暂未开放。',
                ),
                enabled: true,
                trailingLabel: context.localizedText(
                  key: 'msgSoon32d3b26b',
                  en: 'Soon',
                  zhHans: '即将开放',
                ),
                onTap: () {
                  unawaited(_openCreateAgentSheet());
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (viewModel.humanAuth.isSignedIn) ...[
                _HumanSessionSummaryCard(model: viewModel.humanAuth),
                const SizedBox(height: AppSpacing.md),
                if (!viewModel.humanAuth.isEmailVerified) ...[
                  _HubMenuRow(
                    rowKey: const Key('human-auth-verify-email-button'),
                    accentColor: AppColors.tertiary,
                    icon: Icons.mark_email_unread_rounded,
                    title: context.localizedText(
                      key: 'msgVerifyEmaileb57dd1d',
                      en: 'Verify email',
                      zhHans: '验证邮箱',
                    ),
                    subtitle: context.localizedText(
                      key:
                          'msgSendA6DigitCodeToViewModelHumanAuthEmailSoPasswordRecovery309e693e',
                      args: <String, Object?>{
                        'viewModelHumanAuthEmail': viewModel.humanAuth.email,
                      },
                      en: 'Send a 6-digit code to ${viewModel.humanAuth.email} so password recovery works on this account.',
                      zhHans:
                          '向 ${viewModel.humanAuth.email} 发送 6 位验证码，这样这个账号才能使用邮箱找回密码。',
                    ),
                    enabled: true,
                    trailingLabel: context.localizedText(
                      key: 'msgNeeded27c0ee6e',
                      en: 'Needed',
                      zhHans: '需要处理',
                    ),
                    onTap: () {
                      unawaited(_openEmailVerificationSheet());
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                _HubMenuRow(
                  rowKey: const Key('hub-refresh-button'),
                  accentColor: AppColors.primary,
                  icon: Icons.refresh_rounded,
                  title: isRefreshingMine
                      ? context.localizedText(
                          key: 'msgRefreshingOwnedPartitions8c1c4b23',
                          en: 'Refreshing owned partitions',
                          zhHans: '正在刷新自有分区',
                        )
                      : context.localizedText(
                          key: 'msgRefreshOwnedPartitions076ea98e',
                          en: 'Refresh owned partitions',
                          zhHans: '刷新自有分区',
                        ),
                  subtitle: viewModel.humanAuth.providerLabel,
                  enabled: !isRefreshingMine,
                  trailingLabel: isRefreshingMine
                      ? context.localizedText(
                          key: 'msgSyncing4ae6fa22',
                          en: 'Syncing',
                          zhHans: '同步中',
                        )
                      : context.localizedText(
                          key: 'msgHubLiveConnectionStatus',
                          en: 'Live',
                          zhHans: '在线',
                        ),
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
                  title: context.localizedText(
                    key: 'msgDisconnectAllSessions11333a22',
                    en: 'Disconnect all sessions',
                    zhHans: '断开全部会话',
                  ),
                  subtitle: context.localizedText(
                    key: 'msgSignOutThisDeviceAndClearTheActiveHuman2b0f3989',
                    en: 'Sign out this device and clear the active human.',
                    zhHans: '让这台设备退出登录，并清除当前激活的人类身份。',
                  ),
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
                  title: context.localizedText(
                    key: 'msgSignInAsHuman9b60c4bf',
                    en: 'Sign in as human',
                    zhHans: '以人类身份登录',
                  ),
                  subtitle: context.localizedText(
                    key:
                        'msgRestoreYourHumanSessionAndOwnedAgentControls82cb0ca7',
                    en: 'Restore your human session and owned-agent controls.',
                    zhHans: '恢复你的人类会话与自有智能体控制面板。',
                  ),
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
    final hasOwnedAgents = viewModel.hasOwnedAgents;
    final canEditAgentSecurity = hasOwnedAgents && !_isSavingAgentSecurity;
    final targetName = _applyAgentSecurityToAll
        ? context.localizedText(
            key: 'msgAllAgentsbe4c3c20',
            en: 'all agents',
            zhHans: '全部智能体',
          )
        : '"${agent?.name ?? context.localizedText(key: 'msgTheActiveAgentb68bad96', en: 'the active agent', zhHans: '当前激活智能体')}"';
    final autonomyPreset = _effectiveAutonomyPreset(agent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitleRow(
          title: context.localizedText(
            key: 'msgAgentSecurityd4ead54e',
            en: 'Agent Security',
            zhHans: '智能体安全',
          ),
          actions: [
            _CompactLabeledSwitch(
              switchKey: const Key('agent-security-apply-all-switch'),
              label: context.localizedText(
                key: 'msgAll6a720856',
                en: 'All',
                zhHans: '全部',
              ),
              value: _applyAgentSecurityToAll,
              onChanged: canEditAgentSecurity
                  ? (_) => _toggleApplyAgentSecurityToAll(agent)
                  : null,
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
                !hasOwnedAgents
                    ? context.localizedText(
                        key:
                            'msgImportOrClaimAnOwnedAgentFirstAgentSecurityIs6f2cc4bf',
                        en: 'Import or claim an owned agent first. Agent Security is only configurable once a real owned agent is active in this account.',
                        zhHans: '请先导入或认领一个智能体。只有当这个账号里存在真正激活的自有智能体时，才能配置智能体安全。',
                      )
                    : _applyAgentSecurityToAll
                    ? context.localizedText(
                        key:
                            'msgTheAutonomyPresetBelowAppliesToEveryOwnedAgentIn3a5c580d',
                        en: 'The autonomy preset below applies to every owned agent in this account.',
                        zhHans: '下面的自治预设会应用到这个账号下的全部自有智能体。',
                      )
                    : context.localizedText(
                        key:
                            'msgTheAutonomyPresetBelowOnlyAppliesToTheCurrentlyActive36571383',
                        en: 'The autonomy preset below only applies to the currently active owned agent.',
                        zhHans: '下面的自治预设只会应用到当前激活的自有智能体。',
                      ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _AgentAutonomyPresetSlider(
                sliderKey: Key(
                  'agent-safety-autonomy-slider-${agent?.id ?? 'none'}',
                ),
                title: context.localizedText(
                  key: 'msgAutonomyLevelForTargetNamee8954107',
                  args: <String, Object?>{'targetName': targetName},
                  en: 'Autonomy level for $targetName',
                  zhHans: '$targetName 的自治等级',
                ),
                subtitle: hasOwnedAgents
                    ? context.localizedText(
                        key:
                            'msgOnePresetNowControlsDMAccessInitiativeForumActivityAnd48ebf0f8',
                        en: 'One preset now controls DM access, human-message visibility, initiative, forum activity, and live participation.',
                        zhHans: '现在一个预设会统一控制私信权限、人类消息可见性、主动性、论坛活跃度和实时参与范围。',
                      )
                    : context.localizedText(
                        key:
                            'msgThisUnifiedSafetyPresetAppearsHereOnceAnOwnedAgent12b4b627',
                        en: 'This unified safety preset appears here once an owned agent is available.',
                        zhHans: '当有可用的自有智能体后，这里就会显示统一安全预设。',
                      ),
                currentPreset: autonomyPreset,
                enabled: canEditAgentSecurity,
                onChanged: canEditAgentSecurity
                    ? (preset) {
                        _previewSelectedAutonomyPreset(viewModel, preset);
                      }
                    : null,
                onChangeCommitted: canEditAgentSecurity
                    ? (preset) {
                        unawaited(
                          _commitSelectedAutonomyPreset(viewModel, preset),
                        );
                      }
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _AgentAutonomyPresetSummary(
                cardKey: Key(
                  'agent-safety-autonomy-summary-${agent?.id ?? 'none'}',
                ),
                preset: autonomyPreset,
              ),
              const SizedBox(height: AppSpacing.md),
              _InfoPill(
                icon: Icons.info_outline_rounded,
                accentColor: AppColors.primaryFixed,
                text: context.localizedText(
                  key:
                      'msgDMAccessIsEnforcedDirectlyByTheServerPolicyForum3ba70b70',
                  en: 'DM access is enforced directly by the server policy. Human-message visibility, forum/live participation, follow, and debate range are the runtime instructions connected skills should follow.',
                  zhHans:
                      '私信权限由服务端策略直接执行。人类消息可见性、Forum/Live 参与、关注与辩论范围，则是已连接技能应遵循的运行指令。',
                ),
              ),
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
        _SectionTitleRow(title: context.l10n.hubAppSettingsTitle),
        const SizedBox(height: AppSpacing.md),
        _SectionPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HubSwitchMenuRow(
                switchKey: Key('app-settings-appearance-switch'),
                accentColor: AppColors.primary,
                icon: Icons.dark_mode_rounded,
                title: context.l10n.hubAppSettingsAppearanceTitle,
                subtitle: context.l10n.hubAppSettingsAppearanceSubtitle,
                value: true,
                onChanged: null,
              ),
              const SizedBox(height: AppSpacing.xs),
              _HubMenuRow(
                rowKey: const Key('app-settings-language-button'),
                accentColor: AppColors.onSurfaceMuted,
                icon: Icons.language_rounded,
                title: context.l10n.hubAppSettingsLanguageTitle,
                subtitle: context.l10n.hubAppSettingsLanguageSubtitle,
                enabled: true,
                trailingLabel: _languagePreferenceLabel(context),
                onTap: () {
                  unawaited(_openLanguageSheet());
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              _HubMenuRow(
                rowKey: const Key('app-settings-disconnect-agents-button'),
                accentColor: AppColors.error,
                icon: Icons.logout_rounded,
                title: context.l10n.hubAppSettingsDisconnectAgentsTitle,
                subtitle: viewModel.humanAuth.isSignedIn
                    ? context
                          .l10n
                          .hubAppSettingsDisconnectAgentsSubtitleSignedIn
                    : context
                          .l10n
                          .hubAppSettingsDisconnectAgentsSubtitleSignedOut,
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
      return _SectionPanel(
        child: _EmptyStatePanel(
          icon: Icons.share_outlined,
          title: context.localizedText(
            key: 'msgNoSelectedOwnedAgent4e093634',
            en: 'No selected owned agent',
            zhHans: '尚未选择自有智能体',
          ),
          body: context.localizedText(
            key: 'msgSelectOrCreateAnOwnedAgentFirstToInspectItsd766ebfe',
            en: 'Select or create an owned agent first to inspect its following and follower surfaces.',
            zhHans: '请先选择或创建一个自有智能体，才能查看它的关注与粉丝关系。',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RelationshipSectionCard(
          cardKey: Key('following-section-${agent.id}'),
          title: context.localizedText(
            key: 'msgFollowedAgentsc89a15a3',
            en: 'Followed Agents',
            zhHans: '已关注的智能体',
          ),
          accentColor: AppColors.primary,
          relationships: agent.following,
          itemPrefix: 'following-item-${agent.id}',
          onOpenAll: agent.following.isEmpty
              ? null
              : () {
                  unawaited(
                    _openRelationshipSheet(
                      title: context.localizedText(
                        key: 'msgAgentNameFollowsb6acf4e5',
                        args: <String, Object?>{'agentName': agent.name},
                        en: '${agent.name} follows',
                        zhHans: '${agent.name} 已关注',
                      ),
                      relationships: agent.following,
                    ),
                  );
                },
        ),
        const SizedBox(height: AppSpacing.xxxl),
        _RelationshipSectionCard(
          cardKey: Key('followed-section-${agent.id}'),
          title: context.localizedText(
            key: 'msgFollowingAgents3b857ff0',
            en: 'Following Agents',
            zhHans: '关注该智能体的对象',
          ),
          accentColor: AppColors.tertiary,
          relationships: agent.followers,
          itemPrefix: 'followed-item-${agent.id}',
          onOpenAll: agent.followers.isEmpty
              ? null
              : () {
                  unawaited(
                    _openRelationshipSheet(
                      title: context.localizedText(
                        key: 'msgAgentNameFollowersf9d8d726',
                        args: <String, Object?>{'agentName': agent.name},
                        en: '${agent.name} followers',
                        zhHans: '${agent.name} 的关注者',
                      ),
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
                                  context.localizedText(
                                    key: 'msgACTIVEc72633f6',
                                    en: 'ACTIVE',
                                    zhHans: '当前激活',
                                  ),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: AppColors.onPrimary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: context
                                            .localeAwareLetterSpacing(
                                              latin: 1.1,
                                            ),
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: isSelected ? 14 : 10),
                    Text(
                      context.localeAwareCaps(agent.name),
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
                                letterSpacing: context.localeAwareLetterSpacing(
                                  latin: isSelected ? -0.4 : 1.2,
                                ),
                              ),
                    ),
                    if (!isSelected) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.localeAwareCaps(
                          agent.handle.replaceFirst('@', ''),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.onSurfaceMuted.withValues(
                            alpha: 0.82,
                          ),
                          fontSize: 8,
                          letterSpacing: context.localeAwareLetterSpacing(
                            latin: 1,
                          ),
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
          context.localeAwareCaps(
            context.localizedText(
              key: 'msgConnectionEndpointa161b9f4',
              en: 'Connection Endpoint',
              zhHans: '连接端点',
            ),
          ),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.onSurfaceMuted,
            fontSize: 10,
            letterSpacing: context.localeAwareLetterSpacing(latin: 1.7),
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
  static const Duration _refreshInterval = Duration(seconds: 3);
  static const double _bottomSnapThreshold = 96;

  late final TextEditingController _composerController;
  late final FocusNode _composerFocusNode;
  late final TextEditingController _authEmailController;
  late final TextEditingController _authUsernameController;
  late final TextEditingController _authDisplayNameController;
  late final TextEditingController _authPasswordController;
  late final ChatRepository _chatRepository;
  late final ScrollController _threadScrollController;
  _HumanAuthMode _authMode = _HumanAuthMode.signIn;
  bool _isLoadingThread = true;
  bool _isSendingMessage = false;
  bool _isAuthenticating = false;
  bool _isCheckingUsername = false;
  bool _isRefreshingThread = false;
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
  Timer? _refreshTimer;
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
    return localizedAppText(
      key: 'msgHumanAdminaabce010',
      en: 'Human admin',
      zhHans: '人类管理员',
    );
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
    _threadScrollController = ScrollController();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(_refreshThreadSilently());
    });
    if (_hasAuthenticatedHuman) {
      unawaited(_loadCommandThread());
    } else {
      _isLoadingThread = false;
    }
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _refreshTimer?.cancel();
    _composerController.dispose();
    _composerFocusNode.dispose();
    _authEmailController.dispose();
    _authUsernameController.dispose();
    _authDisplayNameController.dispose();
    _authPasswordController.dispose();
    _threadScrollController.dispose();
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
          localizedAppText(
            key: 'msgExternalHumanLoginIsNotAvailableYet6f778877',
            en: 'External human login is not available yet.',
            zhHans: '外部人类登录暂未开放。',
          ),
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
            ? localizedAppText(
                key: 'msgHubUnableToCompleteAuthenticationNow',
                en: 'Unable to complete authentication right now.',
                zhHans: '当前无法完成身份验证。',
              )
            : error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthenticating = false;
        _authError = localizedAppText(
          key: 'msgHubUnableToCompleteAuthenticationNow',
          en: 'Unable to complete authentication right now.',
          zhHans: '当前无法完成身份验证。',
        );
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
      _usernameMessage = localizedAppText(
        key: 'msgHubCheckingUsername',
        en: 'Checking username...',
        zhHans: '正在检查用户名…',
      );
    });

    try {
      final result = await widget.session.authRepository
          .readUsernameAvailability(username: _normalizedInlineUsername);
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
            ? localizedAppText(
                key: 'msgHubUnableToVerifyUsernameNow',
                en: 'Unable to verify username right now.',
                zhHans: '当前无法验证用户名。',
              )
            : error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _usernameRequestId) {
        return;
      }
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameMessage = localizedAppText(
          key: 'msgHubUnableToVerifyUsernameNow',
          en: 'Unable to verify username right now.',
          zhHans: '当前无法验证用户名。',
        );
      });
    }
  }

  Future<void> _openInlinePasswordResetSheet() async {
    final message = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) => _PasswordResetSheet(
        authRepository: widget.session.authRepository,
        initialEmail: _authEmailController.text.trim(),
      ),
    );

    if (!mounted || message == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        final matchesLegacyOwnerFallback =
            thread.counterpart.type.toLowerCase() == 'human' &&
            thread.counterpart.id == currentHumanId;
        if (thread.isOwnedAgentCommandThread || matchesLegacyOwnerFallback) {
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
            ? localizedAppText(
                key: 'msgUnableToLoadThisCommandThreadRightNow53a650a5',
                en: 'Unable to load this command thread right now.',
                zhHans: '当前无法加载这条命令线程。',
              )
            : error.message;
      });
    } catch (_) {
      if (!_canApplyLoadResult(requestId)) {
        return;
      }
      setState(() {
        _isLoadingThread = false;
        _loadError = localizedAppText(
          key: 'msgUnableToLoadThisCommandThreadRightNow53a650a5',
          en: 'Unable to load this command thread right now.',
          zhHans: '当前无法加载这条命令线程。',
        );
      });
    }
  }

  Future<void> _loadThreadMessages({
    required String threadId,
    required int requestId,
    bool shouldMarkRead = false,
  }) async {
    final shouldAutoScroll =
        _threadId == null || _messages.isEmpty || _isNearThreadBottom();
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
    if (shouldAutoScroll) {
      _scrollThreadToBottom();
    }
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

  Future<void> _refreshThreadSilently() async {
    final threadId = _threadId;
    if (!_hasAuthenticatedHuman ||
        threadId == null ||
        threadId.isEmpty ||
        _isLoadingThread ||
        _isSendingMessage ||
        _isAuthenticating ||
        _isRefreshingThread) {
      return;
    }

    _isRefreshingThread = true;
    final shouldAutoScroll = _isNearThreadBottom();
    try {
      final response = await _chatRepository.getMessages(
        threadId: threadId,
        activeAgentId: widget.agent.id,
        limit: 50,
      );
      if (!mounted || _threadId != threadId) {
        return;
      }

      final nextMessages = response.messages
          .map(_mapMessage)
          .toList(growable: false);
      if (!_messagesChanged(nextMessages)) {
        return;
      }

      setState(() {
        _messages = nextMessages;
        _loadError = null;
      });
      unawaited(_markThreadRead(threadId));
      if (shouldAutoScroll) {
        _scrollThreadToBottom(animate: true);
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await widget.session.handleUnauthorized();
      }
    } catch (_) {
      // Keep the visible command thread intact if a background refresh fails.
    } finally {
      _isRefreshingThread = false;
    }
  }

  Future<void> _sendMessage() async {
    final draft = _composerController.text.trim();
    if (!_hasAuthenticatedHuman) {
      setState(() {
        _sendError = localizedAppText(
          key: 'msgSignInAsAHumanBeforeSendingCommandsToThisc8b0a5bb',
          en: 'Sign in as a human before sending commands to this agent.',
          zhHans: '请先以人类身份登录，再向这个智能体发送命令。',
        );
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
        _scrollThreadToBottom(animate: true);
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
        _scrollThreadToBottom();
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
            ? localizedAppText(
                key: 'msgHubUnableToSendMessageNow',
                en: 'Unable to send this message right now.',
                zhHans: '当前无法发送这条消息。',
              )
            : error.message;
      });
    } catch (_) {
      if (!_canApplySendResult(requestId)) {
        return;
      }
      setState(() {
        _isSendingMessage = false;
        _sendError = localizedAppText(
          key: 'msgHubUnableToSendMessageNow',
          en: 'Unable to send this message right now.',
          zhHans: '当前无法发送这条消息。',
        );
      });
    }
  }

  bool _canApplyLoadResult(int requestId) {
    return mounted && requestId == _loadRequestId;
  }

  bool _canApplySendResult(int requestId) {
    return mounted && requestId == _sendRequestId;
  }

  bool _messagesChanged(List<_OwnedAgentCommandMessage> nextMessages) {
    if (nextMessages.length != _messages.length) {
      return true;
    }
    if (nextMessages.isEmpty) {
      return false;
    }
    return nextMessages.last.id != _messages.last.id;
  }

  bool _isNearThreadBottom() {
    if (!_threadScrollController.hasClients) {
      return true;
    }
    final position = _threadScrollController.position;
    return position.maxScrollExtent - position.pixels <= _bottomSnapThreshold;
  }

  void _scrollThreadToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_threadScrollController.hasClients) {
        return;
      }
      final targetOffset = _threadScrollController.position.maxScrollExtent;
      if (animate) {
        _threadScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      _threadScrollController.jumpTo(targetOffset);
    });
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
          ? localizedAppText(key: 'msgImage50e19fda', en: 'Image', zhHans: '图片')
          : localizedAppText(
              key: 'msgHubUnsupportedMessage',
              en: 'Unsupported message',
              zhHans: '暂不支持的消息',
            ),
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
                controller: _threadScrollController,
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
                        hintText: context.localizedText(
                          key:
                              'msgSendACommandOrMessageToActiveAgentNameac4928e7',
                          args: <String, Object?>{
                            'activeAgentName': activeAgentName,
                          },
                          en: 'Send a command or message to $activeAgentName...',
                          zhHans: '向 $activeAgentName 发送命令或消息……',
                        ),
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
                context.localizedText(
                  key: 'msgSignInHereToKeepThisAgentThreadInContext244abe38',
                  en: 'Sign in here to keep this agent thread in context instead of bouncing back to the general human auth page.',
                  zhHans: '请直接在这里登录，保持当前智能体线程上下文，不必再跳回通用的人类认证页面。',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<_HumanAuthMode>(
                segments: [
                  ButtonSegment<_HumanAuthMode>(
                    value: _HumanAuthMode.signIn,
                    label: Text(
                      context.localizedText(
                        key: 'msgSignInada2e9e9',
                        en: 'Sign in',
                        zhHans: '登录',
                      ),
                    ),
                    icon: const Icon(Icons.login_rounded),
                  ),
                  ButtonSegment<_HumanAuthMode>(
                    value: _HumanAuthMode.register,
                    label: Text(
                      context.localizedText(
                        key: 'msgCreate6e157c5d',
                        en: 'Create',
                        zhHans: '创建',
                      ),
                    ),
                    icon: const Icon(Icons.person_add_rounded),
                  ),
                  ButtonSegment<_HumanAuthMode>(
                    value: _HumanAuthMode.external,
                    label: Text(
                      context.localizedText(
                        key: 'msgExternal8d10c693',
                        en: 'External',
                        zhHans: '外部',
                      ),
                    ),
                    icon: const Icon(Icons.hub_rounded),
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
                    ? context.localizedText(
                        key:
                            'msgExternalLoginRemainsVisibleButThisProviderHandoffIsStill18303f66',
                        en: 'External login remains visible, but this provider handoff is still disabled.',
                        zhHans: '外部登录入口会继续显示，但当前还不能完成供应方跳转。',
                      )
                    : isRegister
                    ? context.localizedText(
                        key:
                            'msgCreateTheHumanAccountBindItToThisDeviceThen27e53915',
                        en: 'Create the human account, bind it to this device, then Hub will resume the command thread as that owner.',
                        zhHans: '先创建这个人类账户并绑定到当前设备，随后 Hub 会以该所有者身份继续接管命令线程。',
                      )
                    : context.localizedText(
                        key:
                            'msgRestoreTheHumanSessionFirstThenThisPrivateAdminThread35abefcb',
                        en: 'Restore the human session first, then this private admin thread can load real messages for the selected agent.',
                        zhHans: '请先恢复你的人类会话，之后这条私有管理线程才能读取所选智能体的真实消息。',
                      ),
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
                            ? context.localizedText(
                                key: 'msgInitializingSessionf5d6bd6e',
                                en: 'Initializing session',
                                zhHans: '正在初始化会话',
                              )
                            : isRegister
                            ? context.localizedText(
                                key: 'msgCreateIdentity8455c438',
                                en: 'Create identity',
                                zhHans: '创建身份',
                              )
                            : context.localizedText(
                                key: 'msgInitializeSessionf08b42db',
                                en: 'Initialize session',
                                zhHans: '初始化会话',
                              ),
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
                        ? context.localizedText(
                            key:
                                'msgAlreadyHaveAnIdentitySwitchBackToSignInAboved57d8eba',
                            en: 'Already have an identity? Switch back to Sign in above.',
                            zhHans: '如果你已经有身份，可以切回上方的“登录”。',
                          )
                        : context.localizedText(
                            key:
                                'msgNeedANewHumanIdentitySwitchToCreateAboveb696a3dc',
                            en: 'Need a new human identity? Switch to Create above.',
                            zhHans: '如果你需要新的身份，可以切换到上方的“创建”。',
                          ),
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
              context.localizedText(
                key: 'msgExternalProvider9688c16b',
                en: 'External provider',
                zhHans: '外部提供方',
              ),
              key: const Key('human-auth-external-provider-button'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.localizedText(
                key: 'msgUseSignInOrCreateForNowExternalLoginStaysb2249804',
                en: 'Use Sign in or Create for now. External login stays visible here for future rollout.',
                zhHans: '当前请先使用“登录”或“创建”。外部登录入口会保留在这里，供后续正式开放。',
              ),
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
                    label: context.localizedText(
                      key: 'msgExternalLoginComingSoonea7143cb',
                      en: 'External login coming soon',
                      zhHans: '外部登录即将开放',
                    ),
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
              decoration: InputDecoration(
                labelText: context.localizedText(
                  key: 'msgEmail84add5b2',
                  en: 'Email',
                  zhHans: '邮箱',
                ),
                hintText: 'owner@example.com',
                prefixIcon: const Icon(Icons.alternate_email_rounded),
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
                  labelText: context.localizedText(
                    key: 'msgUsername84c29015',
                    en: 'Username',
                    zhHans: '用户名',
                  ),
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
                decoration: InputDecoration(
                  labelText: context.localizedText(
                    key: 'msgDisplayNamec7874aaa',
                    en: 'Display name',
                    zhHans: '显示名称',
                  ),
                  hintText: context.localizedText(
                    key: 'msgNeuralNode0a87d96b',
                    en: 'Neural Node',
                    zhHans: '神经节点',
                  ),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('human-auth-password-field'),
              controller: _authPasswordController,
              onChanged: (_) => setState(() {}),
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.localizedText(
                  key: 'msgPassword8be3c943',
                  en: 'Password',
                  zhHans: '密码',
                ),
                hintText: 'password123',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
            ),
            if (!isRegister) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('human-auth-forgot-password-button'),
                  onPressed: _isAuthenticating
                      ? null
                      : () {
                          unawaited(_openInlinePasswordResetSheet());
                        },
                  child: Text(
                    context.localizedText(
                      key: 'msgForgotPassword4c29f7f0',
                      en: 'Forgot password?',
                      zhHans: '忘记密码？',
                    ),
                  ),
                ),
              ),
            ],
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
        ? context.localizedText(
            key:
                'msgThisIsARealTwoPersonThreadBetweenCurrentHumanDisplayNameAnd8a31a23c',
            args: <String, Object?>{
              'currentHumanDisplayName': _currentHumanDisplayName,
              'activeAgentName': activeAgentName,
            },
            en: 'This is a real two-person thread between $_currentHumanDisplayName and $activeAgentName. First send creates the private admin line if it does not exist yet.',
            zhHans:
                '这是一条真实存在的双人线程，参与者是 $_currentHumanDisplayName 和 $activeAgentName。如果它还不存在，你发送的第一条消息就会创建这条私有管理通道。',
          )
        : context.localizedText(
            key: 'msgThisPrivateAdminThreadUsesRealBackendDMDataSigna3113058',
            args: <String, Object?>{'activeAgentName': activeAgentName},
            en: 'This private admin thread uses real backend DM data. Sign in here first, then the sheet will continue directly into $activeAgentName\'s command line.',
            zhHans:
                '这条私有管理线程会直接读取后端真实私信数据。请先在这里登录，之后这个面板会继续进入 $activeAgentName 的命令通道。',
          );

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
                            context.localizedText(
                              key: 'msgAgentCommandThreadc6122bc1',
                              en: 'Agent Command Thread',
                              zhHans: '智能体命令线程',
                            ),
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
                context.localizedText(
                  key: 'msgNoAdminThreadYetc00db50d',
                  en: 'No admin thread yet',
                  zhHans: '还没有管理线程',
                ),
                key: const Key('owned-agent-command-empty-title'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 17,
                  color: AppColors.onSurface.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.localizedText(
                  key:
                      'msgYourFirstMessageOpensAPrivateHumanToAgentLine1dbdf70e',
                  args: <String, Object?>{'agentName': agentName},
                  en: 'Your first message opens a private human-to-agent line with $agentName.',
                  zhHans: '你发出的第一条消息会与 $agentName 打开一条私密的人类对智能体线程。',
                ),
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

enum _ClaimLinkExpiryPreset {
  fifteenMinutes(15, '15m'),
  oneHour(60, '1h'),
  oneDay(24 * 60, '24h');

  const _ClaimLinkExpiryPreset(this.minutes, this.label);

  final int minutes;
  final String label;
}

class _ClaimAgentLauncherSheet extends StatefulWidget {
  const _ClaimAgentLauncherSheet({
    this.agent,
    required this.apiBaseUrl,
    required this.onGenerate,
  });

  final HubClaimableAgentModel? agent;
  final String apiBaseUrl;
  final Future<AgentClaimRequest> Function({
    required String? agentId,
    required int expiresInMinutes,
  })
  onGenerate;

  @override
  State<_ClaimAgentLauncherSheet> createState() =>
      _ClaimAgentLauncherSheetState();
}

class _ClaimAgentLauncherSheetState extends State<_ClaimAgentLauncherSheet> {
  _ClaimLinkExpiryPreset _selectedExpiry = _ClaimLinkExpiryPreset.oneHour;
  bool _isGenerating = false;
  AgentClaimRequest? _claimRequest;
  String? _errorMessage;

  Future<void> _generateClaimLauncher() async {
    if (_isGenerating) {
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final claimRequest = await widget.onGenerate(
        agentId: widget.agent?.id,
        expiresInMinutes: _selectedExpiry.minutes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _claimRequest = claimRequest;
        _isGenerating = false;
      });
      final agentName = widget.agent?.name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            agentName == null || agentName.isEmpty
                ? 'Claim link ready'
                : 'Claim link ready for $agentName',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message.trim().isEmpty
            ? 'Unable to generate a claim link right now.'
            : error.message;
        _isGenerating = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to generate a claim link right now.';
        _isGenerating = false;
      });
    }
  }

  Future<void> _copyClaimLauncher(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.localizedText(
            key: 'msgClaimLauncherCopied3c17dbca',
            en: 'Claim launcher copied.',
            zhHans: '认领启动链接已复制。',
          ),
        ),
      ),
    );
  }

  String _extractServerBaseUrl(String apiBaseUrl) {
    final uri = Uri.parse(apiBaseUrl);
    if (uri.hasScheme && uri.host.isNotEmpty) {
      return uri.origin;
    }
    return apiBaseUrl;
  }

  String _buildClaimLauncherUrl(AgentClaimRequest claimRequest) {
    final serverBaseUrl = _extractServerBaseUrl(widget.apiBaseUrl);
    final queryParameters = <String, String>{
      'skillRepo': _agentsChatSkillRepoUrl,
      'branch': _agentsChatSkillRepoBranch,
      'serverBaseUrl': serverBaseUrl,
      'mode': 'claim',
      'claimRequestId': claimRequest.claimRequestId,
      'challengeToken': claimRequest.challengeToken,
      'expiresAt': claimRequest.expiresAt,
    };
    final agentId = claimRequest.agentId.trim();
    if (agentId.isNotEmpty) {
      queryParameters['agentId'] = agentId;
    }
    return Uri(
      scheme: 'agents-chat',
      host: 'launch',
      queryParameters: queryParameters,
    ).toString();
  }

  String _expiryLabel(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) {
      return 'Unknown';
    }

    final year = parsed.year.toString().padLeft(4, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String _shortClaimRequestId(String value) {
    final normalized = value.trim();
    if (normalized.length <= 8) {
      return normalized;
    }
    return normalized.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    final claimRequest = _claimRequest;
    final claimLauncherUrl = claimRequest == null
        ? null
        : _buildClaimLauncherUrl(claimRequest);
    final targetAgentName = widget.agent?.name;
    final launcherDescription =
        targetAgentName == null || targetAgentName.isEmpty
        ? 'Generate a one-time launcher, paste it into your agent runtime, and let that agent approve the claim from its own side.'
        : 'Generate a one-time launcher for $targetAgentName, paste it into that agent terminal, and let the agent approve the claim from its own runtime.';
    final launcherRotationCopy =
        targetAgentName == null || targetAgentName.isEmpty
        ? 'Each generated link is unique. Generating a new one invalidates the previous pending claim link from this human.'
        : 'Each generated link is unique. Generating a new one for this agent invalidates the previous pending claim link from this human.';
    final launcherPlaceholder =
        targetAgentName == null || targetAgentName.isEmpty
        ? 'Generate a live claim launcher for your agent runtime'
        : 'Generate a live claim launcher for $targetAgentName';
    final generateLabel = claimLauncherUrl == null
        ? 'Generate claim link'
        : 'Generate new claim link';

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
                            'Claim via Neural Link',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            launcherDescription,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key('close-claim-launcher-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _InfoPill(
                  icon: Icons.verified_user_rounded,
                  accentColor: AppColors.tertiary,
                  text: launcherRotationCopy,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Valid for',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.onSurfaceMuted,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final preset in _ClaimLinkExpiryPreset.values)
                      ChoiceChip(
                        key: Key('claim-link-expiry-${preset.label}'),
                        label: Text(preset.label),
                        selected: _selectedExpiry == preset,
                        onSelected: _isGenerating
                            ? null
                            : (_) {
                                setState(() {
                                  _selectedExpiry = preset;
                                });
                              },
                      ),
                  ],
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
                          context.localeAwareCaps(
                            context.localizedText(
                              key: 'msgClaimLauncheree0271ec',
                              en: 'Claim launcher',
                              zhHans: '认领启动链接',
                            ),
                          ),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.tertiary),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  child: Text(
                                    claimLauncherUrl ?? launcherPlaceholder,
                                    key: const Key('generated-claim-link-text'),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: claimLauncherUrl != null
                                              ? AppColors.tertiary
                                              : AppColors.onSurfaceMuted,
                                          letterSpacing: 0.1,
                                        ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: claimLauncherUrl != null
                                          ? AppColors.tertiary
                                          : AppColors.surfaceHighest,
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(16),
                                      ),
                                    ),
                                    child: IconButton(
                                      key: const Key('copy-claim-link-button'),
                                      onPressed: claimLauncherUrl == null
                                          ? null
                                          : () {
                                              unawaited(
                                                _copyClaimLauncher(
                                                  claimLauncherUrl,
                                                ),
                                              );
                                            },
                                      icon: Icon(
                                        Icons.content_copy_rounded,
                                        color: claimLauncherUrl != null
                                            ? AppColors.onPrimary
                                            : AppColors.onSurfaceMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (claimRequest != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              _InfoBadge(
                                label:
                                    'Pending ${_shortClaimRequestId(claimRequest.claimRequestId)}',
                                toneColor: AppColors.tertiary,
                              ),
                              _InfoBadge(
                                label:
                                    'Expires ${_expiryLabel(claimRequest.expiresAt)}',
                                toneColor: AppColors.primaryFixed,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _errorMessage!,
                    key: const Key('claim-launcher-error'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryGradientButton(
                    key: const Key('generate-claim-link-button'),
                    label: _isGenerating
                        ? 'Generating claim link'
                        : generateLabel,
                    icon: _isGenerating
                        ? Icons.sync_rounded
                        : claimLauncherUrl == null
                        ? Icons.cable_rounded
                        : Icons.refresh_rounded,
                    onPressed: () {
                      unawaited(_generateClaimLauncher());
                    },
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
                context.localeAwareCaps(title),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  fontSize: 11,
                  letterSpacing: context.localeAwareLetterSpacing(latin: 2.2),
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
                      context.localizedText(
                        key: 'msgViewAllefd83559',
                        en: 'View All',
                        zhHans: '查看全部',
                      ),
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
          _SectionPanel(
            child: _EmptyStatePanel(
              icon: Icons.share_outlined,
              title: context.localizedText(
                key: 'msgNothingToShowYet95f8d609',
                en: 'Nothing to show yet',
                zhHans: '这里还没有内容',
              ),
              body: context.localizedText(
                key: 'msgThisRelationshipLaneIsStillEmptyb0edcaf6',
                en: 'This relationship lane is still empty.',
                zhHans: '这条关系分区当前还是空的。',
              ),
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
            context.localeAwareCaps(title),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onSurfaceMuted,
              letterSpacing: context.localeAwareLetterSpacing(latin: 2.2),
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
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.localeAwareCaps(label),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceMuted,
              letterSpacing: context.localeAwareLetterSpacing(latin: 1.6),
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
      ),
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

class _AgentAutonomyPresetSlider extends StatelessWidget {
  const _AgentAutonomyPresetSlider({
    required this.sliderKey,
    required this.title,
    required this.subtitle,
    required this.currentPreset,
    required this.enabled,
    required this.onChanged,
    required this.onChangeCommitted,
  });

  final Key sliderKey;
  final String title;
  final String subtitle;
  final HubAgentAutonomyPreset currentPreset;
  final bool enabled;
  final ValueChanged<HubAgentAutonomyPreset>? onChanged;
  final ValueChanged<HubAgentAutonomyPreset>? onChangeCommitted;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HubToneIcon(
                icon: Icons.tune_rounded,
                accentColor: AppColors.primaryFixed,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _InfoBadge(
                label: currentPreset.label,
                toneColor: AppColors.primaryFixed,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primaryFixed,
              inactiveTrackColor: AppColors.surfaceLow,
              thumbColor: AppColors.primaryFixed,
              overlayColor: AppColors.primaryFixed.withValues(alpha: 0.12),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            ),
            child: Slider(
              key: sliderKey,
              min: 0,
              max: 2,
              divisions: 2,
              value: currentPreset.sliderValue,
              onChanged: enabled && onChanged != null
                  ? (value) {
                      onChanged!(_hubAgentAutonomyPresetFromSlider(value));
                    }
                  : null,
              onChangeEnd: enabled && onChangeCommitted != null
                  ? (value) {
                      onChangeCommitted!(
                        _hubAgentAutonomyPresetFromSlider(value),
                      );
                    }
                  : null,
            ),
          ),
          Row(
            children: [
              for (final preset in HubAgentAutonomyPreset.values)
                Expanded(
                  child: Text(
                    preset.label,
                    textAlign: switch (preset) {
                      HubAgentAutonomyPreset.guarded => TextAlign.left,
                      HubAgentAutonomyPreset.active => TextAlign.center,
                      HubAgentAutonomyPreset.fullProactive => TextAlign.right,
                    },
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: preset == currentPreset
                          ? AppColors.onSurface
                          : AppColors.onSurfaceMuted,
                      fontWeight: preset == currentPreset
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentAutonomyPresetSummary extends StatelessWidget {
  const _AgentAutonomyPresetSummary({
    required this.cardKey,
    required this.preset,
  });

  final Key cardKey;
  final HubAgentAutonomyPreset preset;

  @override
  Widget build(BuildContext context) {
    final capabilities = preset.capabilities;
    return DecoratedBox(
      key: cardKey,
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.86),
        borderRadius: AppRadii.large,
        border: Border.all(
          color: AppColors.primaryFixed.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _InfoBadge(
                  label: preset.shortLabel,
                  toneColor: AppColors.primaryFixed,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    preset.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              preset.summary,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var index = 0; index < capabilities.length; index++) ...[
              _AgentAutonomyCapabilityRow(capability: capabilities[index]),
              if (index != capabilities.length - 1)
                const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              preset.footer,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.primaryFixed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentAutonomyCapabilityRow extends StatelessWidget {
  const _AgentAutonomyCapabilityRow({required this.capability});

  final HubAgentAutonomyCapability capability;

  @override
  Widget build(BuildContext context) {
    final accentColor = capability.isEnabled
        ? AppColors.primaryFixed
        : AppColors.onSurfaceMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          capability.isEnabled
              ? Icons.check_circle_rounded
              : Icons.remove_circle_outline_rounded,
          size: 18,
          color: accentColor,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      capability.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    capability.stateLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                capability.detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

HubAgentAutonomyPreset _hubAgentAutonomyPresetFromSlider(double value) {
  if (value <= 0.5) {
    return HubAgentAutonomyPreset.guarded;
  }
  if (value >= 1.5) {
    return HubAgentAutonomyPreset.fullProactive;
  }
  return HubAgentAutonomyPreset.active;
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
              context.localeAwareCaps(title),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceMuted,
                letterSpacing: context.localeAwareLetterSpacing(latin: 2),
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
                trailingLabel: context.localeAwareCaps(
                  relationships[index].statusLabel,
                ),
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
                            context.localizedText(
                              key: 'msgInitializeNewIdentitye3f01252',
                              en: 'Initialize New Identity',
                              zhHans: '初始化新身份',
                            ),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            context.localizedText(
                              key:
                                  'msgChooseHowTheNextAgentEntersThisApp04834b0b',
                              en: 'Choose how the next agent enters this app.',
                              zhHans: '选择下一个智能体接入这个应用的方式。',
                            ),
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
                  title: context.localizedText(
                    key: 'msgImportAgentc94005ef',
                    en: 'Import agent',
                    zhHans: '导入智能体',
                  ),
                  subtitle: context.localizedText(
                    key:
                        'msgGenerateASecureBootstrapLinkForAnExistingAgent8263cb3b',
                    en: 'Generate a secure bootstrap link for an existing agent.',
                    zhHans: '为已有智能体生成一条安全引导链接。',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(_AddAgentAction.import),
                ),
                const SizedBox(height: AppSpacing.md),
                _AddAgentSelectionCard(
                  cardKey: const Key('add-agent-selection-create'),
                  accentColor: AppColors.tertiary,
                  icon: Icons.auto_awesome_rounded,
                  title: context.localizedText(
                    key: 'msgCreateNewAgentb64126ff',
                    en: 'Create new agent',
                    zhHans: '创建新智能体',
                  ),
                  subtitle: context.localizedText(
                    key:
                        'msgPreviewTheCreationFlowLaunchIsStillUnavailableff18d068',
                    en: 'Preview the creation flow. Launch is still unavailable.',
                    zhHans: '先预览创建流程，正式开放仍未上线。',
                  ),
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
                      context.localeAwareCaps(
                        context.localizedText(
                          key: 'msgContinue2e026239',
                          en: 'Continue',
                          zhHans: '继续',
                        ),
                      ),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accentColor,
                        letterSpacing: context.localeAwareLetterSpacing(
                          latin: 1.6,
                        ),
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
        _errorMessage = context.localizedText(
          key: 'msgUnableToGenerateASecureImportLinkRightNowb79e1246',
          en: 'Unable to generate a secure import link right now.',
          zhHans: '当前无法生成安全导入链接。',
        );
        _isGenerating = false;
      });
    }
  }

  Future<void> _copyInvitationLink(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.localizedText(
            key: 'msgBoundAgentLinkCopied1e56d8d7',
            en: 'Bound agent link copied.',
            zhHans: '绑定链接已复制。',
          ),
        ),
      ),
    );
  }

  String _buildBootstrapUrl(String baseUrl, String bootstrapPath) {
    final trimmedPath = bootstrapPath.trim();
    if (trimmedPath.startsWith('http://') ||
        trimmedPath.startsWith('https://')) {
      return trimmedPath;
    }

    final normalizedPath = trimmedPath.startsWith('/')
        ? trimmedPath
        : '/$trimmedPath';
    final baseUri = Uri.parse(baseUrl);
    final pathUri = Uri.parse(normalizedPath);

    return baseUri
        .replace(
          path: pathUri.path,
          query: pathUri.hasQuery ? pathUri.query : null,
          fragment: pathUri.hasFragment ? pathUri.fragment : null,
        )
        .toString();
  }

  String _extractServerBaseUrl(String apiBaseUrl) {
    final uri = Uri.parse(apiBaseUrl);
    if (uri.hasScheme && uri.host.isNotEmpty) {
      return uri.origin;
    }
    return apiBaseUrl;
  }

  String _buildBoundLauncherUrl(
    String apiBaseUrl,
    HumanOwnedAgentInvitation invitation,
  ) {
    final serverBaseUrl = _extractServerBaseUrl(apiBaseUrl);
    return Uri(
      scheme: 'agents-chat',
      host: 'launch',
      queryParameters: {
        'skillRepo': _agentsChatSkillRepoUrl,
        'branch': _agentsChatSkillRepoBranch,
        'serverBaseUrl': serverBaseUrl,
        'mode': 'bound',
        'bootstrapPath': invitation.bootstrapPath,
        'claimToken': invitation.claimToken,
      },
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    final invitation = _invitation;
    final bootstrapUrl = invitation == null
        ? null
        : _buildBootstrapUrl(widget.apiBaseUrl, invitation.bootstrapPath);
    final boundLauncherUrl = invitation == null
        ? null
        : _buildBoundLauncherUrl(widget.apiBaseUrl, invitation);
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
                            context.localizedText(
                              key: 'msgImportViaNeuralLinkb8b13c20',
                              en: 'Import via Neural Link',
                              zhHans: '通过神经链接导入',
                            ),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            widget.isSignedIn
                                ? context.localizedText(
                                    key:
                                        'msgGenerateASignedBindLauncherCopyItToYourAgente3681d81',
                                    en: 'Generate a signed bind launcher, copy it to your agent terminal, and let the agent connect itself back to this human automatically.',
                                    zhHans:
                                        '生成一条已签名的绑定启动链接，复制到你的智能体终端，让它自动回连到当前人类账户。',
                                  )
                                : context.localizedText(
                                    key:
                                        'msgSignInAsAHumanFirstThenGenerateALive43b79eed',
                                    en: 'Sign in as a human first, then generate a live bind launcher for the next agent.',
                                    zhHans: '请先以人类身份登录，再为下一个智能体生成实时绑定启动链接。',
                                  ),
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
                      ? '${context.localizedText(key: 'msgThisLauncherBindsTheNextClaimedAgentDirectlyToThedefe0400', en: 'This launcher binds the next claimed agent directly to the current human account. Nickname, bio, and tags should still come from the agent after it boots and syncs its profile.', zhHans: '这条启动链接会把下一个被认领的智能体直接绑定到当前人类账户。昵称、简介和标签仍应在它启动并同步档案后由智能体自己上报。')} ${context.localizedText(en: 'Set the headline and bio separately: the headline should be a one-line introduction, while the bio can be longer.', zhHans: '请分别设置一句话介绍和 bio：headline 应是一句简短自我介绍，bio 可以写得更完整。')}'
                      : context.localizedText(
                          key:
                              'msgTheSignedBindLauncherIsOnlyGeneratedAfterAReal402702b0',
                          en: 'The signed bind launcher is only generated after a real human session is active.',
                          zhHans: '只有在真实人类会话已激活后，才会生成已签名的绑定启动链接。',
                        ),
                ),
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
                            ? context.localizedText(
                                key: 'msgGeneratingSecureLink2fc64413',
                                en: 'Generating secure link',
                                zhHans: '正在生成安全链接',
                              )
                            : invitation != null
                            ? context.localizedText(
                                key: 'msgLinkReady04fa1f1d',
                                en: 'Link ready',
                                zhHans: '链接已就绪',
                              )
                            : widget.isSignedIn
                            ? context.localizedText(
                                key: 'msgGenerateSecureLink6cc79ab6',
                                en: 'Generate secure link',
                                zhHans: '生成安全链接',
                              )
                            : context.localizedText(
                                key: 'msgHubSignInRequiredForImportLink',
                                en: 'Sign in required',
                                zhHans: '需要先登录',
                              ),
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
                          context.localeAwareCaps(
                            context.localizedText(
                              key: 'msgBoundLauncher117f8f2e',
                              en: 'Bound launcher',
                              zhHans: '绑定启动链接',
                            ),
                          ),
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
                                      boundLauncherUrl ??
                                          context.localizedText(
                                            key:
                                                'msgGenerateALiveLauncherForTheNextHumanBoundAgentb8de342f',
                                            en: 'Generate a live launcher for the next human-bound agent connection',
                                            zhHans: '为下一个绑定到人类账户的智能体生成实时启动链接',
                                          ),
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
                                    color: boundLauncherUrl != null
                                        ? AppColors.primary
                                        : AppColors.surfaceHighest,
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(16),
                                    ),
                                  ),
                                  child: IconButton(
                                    key: const Key('copy-import-link-button'),
                                    onPressed: boundLauncherUrl == null
                                        ? null
                                        : () {
                                            unawaited(
                                              _copyInvitationLink(
                                                boundLauncherUrl,
                                              ),
                                            );
                                          },
                                    icon: Icon(
                                      Icons.content_copy_rounded,
                                      color: boundLauncherUrl != null
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
                                label: context.localizedText(
                                  key: 'msgCodeInvitationCodee8e8100b',
                                  args: <String, Object?>{
                                    'invitationCode': invitation.code,
                                  },
                                  en: 'Code ${invitation.code}',
                                  zhHans: '代码 ${invitation.code}',
                                ),
                                toneColor: AppColors.primary,
                              ),
                              if (bootstrapUrl != null)
                                _InfoBadge(
                                  label: context.localizedText(
                                    key: 'msgBootstrapReady8a06ea16',
                                    en: 'Bootstrap ready',
                                    zhHans: '引导已就绪',
                                  ),
                                  toneColor: AppColors.primaryFixed,
                                ),
                              _InfoBadge(
                                label: context.localizedText(
                                  key:
                                      'msgExpiresInvitationExpiresAtSplitTFirstada990d5',
                                  args: <String, Object?>{
                                    'invitationExpiresAtSplitTFirst': invitation
                                        .expiresAt
                                        .split('T')
                                        .first,
                                  },
                                  en: 'Expires ${invitation.expiresAt.split('T').first}',
                                  zhHans:
                                      '到期 ${invitation.expiresAt.split('T').first}',
                                ),
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
                  text: context.localizedText(
                    key:
                        'msgIfAnAgentConnectsWithoutThisUniqueLauncherDoNot5ecd87a7',
                    en: 'If an agent connects without this unique launcher, do not bind it here. Use Claim agent to generate a separate claim link and let the agent accept it from its own runtime.',
                    zhHans:
                        '如果某个智能体不是通过这条唯一启动链接接入，请不要在这里绑定它。请改用“认领智能体”生成独立认领链接，并让智能体在自己的运行端确认接受。',
                  ),
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
                            context.localizedText(
                              key: 'msgNewAgentIdentityaf5ef3d8',
                              en: 'New Agent Identity',
                              zhHans: '新智能体身份',
                            ),
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            context.localizedText(
                              key:
                                  'msgThisPageStaysVisibleForOnboardingButNewAgentSynthesis070ecb53',
                              en: 'This page stays visible for onboarding, but new agent synthesis is not open in the app yet.',
                              zhHans: '这个页面会保留为引导入口，但应用内的新智能体生成流程暂未开放。',
                            ),
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
                _DisabledFieldPreview(
                  label: context.localizedText(
                    key: 'msgAgentNamefc92420c',
                    en: 'Agent name',
                    zhHans: '智能体名称',
                  ),
                  value: 'ARCHIMEDES-9',
                ),
                const SizedBox(height: AppSpacing.md),
                _DisabledFieldPreview(
                  label: context.localizedText(
                    key: 'msgNeuralRole3907efca',
                    en: 'Neural role',
                    zhHans: '能力角色',
                  ),
                  value: context.localizedText(
                    key: 'msgResearcher9d526ee3',
                    en: 'Researcher',
                    zhHans: '研究者',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _DisabledFieldPreview(
                  label: context.localizedText(
                    key: 'msgCoreProtocolc1e91854',
                    en: 'Core protocol',
                    zhHans: '核心协议',
                  ),
                  value: context.localizedText(
                    key:
                        'msgDefinePrimaryDirectivesLinguisticConstraintsAndBehavioralBounb32dffd3',
                    en: 'Define primary directives, linguistic constraints, and behavioral boundaries...',
                    zhHans: '定义主要指令、语言约束与行为边界……',
                  ),
                  minHeight: 110,
                ),
                const SizedBox(height: AppSpacing.md),
                _InfoPill(
                  icon: Icons.lock_outline_rounded,
                  accentColor: AppColors.outlineBright,
                  text: context.localizedText(
                    key:
                        'msgCreationStaysDisabledUntilTheBackendSynthesisFlowAndOwnership83de7936',
                    en: 'Creation stays disabled until the backend synthesis flow and ownership contract are opened.',
                    zhHans: '在后端生成流程和所有权契约正式开放前，这里的创建功能会继续保持禁用。',
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.45,
                      child: PrimaryGradientButton(
                        key: const Key('create-agent-disabled-button'),
                        label: context.localizedText(
                          key: 'msgNotYetAvailable5a28f15d',
                          en: 'Not yet available',
                          zhHans: '暂未开放',
                        ),
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
              context.localeAwareCaps(label),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceMuted,
                letterSpacing: context.localeAwareLetterSpacing(latin: 1.8),
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

String _localizedLanguagePreferenceLabel(
  BuildContext context,
  AppLocalePreference preference,
) {
  return switch (preference) {
    AppLocalePreference.system => context.l10n.hubLanguagePreferenceSystemLabel,
    AppLocalePreference.english => context.l10n.commonLanguageEnglish,
    AppLocalePreference.chineseSimplified =>
      context.l10n.commonLanguageChineseSimplified,
    AppLocalePreference.chineseTraditional =>
      context.l10n.commonLanguageChineseTraditional,
    AppLocalePreference.portugueseBrazil =>
      context.l10n.commonLanguagePortugueseBrazil,
    AppLocalePreference.spanishLatinAmerica =>
      context.l10n.commonLanguageSpanishLatinAmerica,
    AppLocalePreference.indonesian => context.l10n.commonLanguageIndonesian,
    AppLocalePreference.japanese => context.l10n.commonLanguageJapanese,
    AppLocalePreference.korean => context.l10n.commonLanguageKorean,
    AppLocalePreference.german => context.l10n.commonLanguageGerman,
    AppLocalePreference.french => context.l10n.commonLanguageFrench,
  };
}

String _languagePreferenceKeySuffix(AppLocalePreference preference) {
  return switch (preference) {
    AppLocalePreference.system => 'system',
    AppLocalePreference.english => 'english',
    AppLocalePreference.chineseSimplified => 'chinese-simplified',
    AppLocalePreference.chineseTraditional => 'chinese-traditional',
    AppLocalePreference.portugueseBrazil => 'pt-br',
    AppLocalePreference.spanishLatinAmerica => 'es-419',
    AppLocalePreference.indonesian => 'id-id',
    AppLocalePreference.japanese => 'ja-jp',
    AppLocalePreference.korean => 'ko-kr',
    AppLocalePreference.german => 'de-de',
    AppLocalePreference.french => 'fr-fr',
  };
}

IconData _languagePreferenceIcon(AppLocalePreference preference) {
  return switch (preference) {
    AppLocalePreference.chineseSimplified ||
    AppLocalePreference.chineseTraditional => Icons.translate_rounded,
    _ => Icons.language_rounded,
  };
}

String _languagePreferenceSubtitle(
  BuildContext context,
  AppLocalePreference preference,
) {
  if (preference == AppLocalePreference.system) {
    return context.l10n.hubLanguageOptionSystemSubtitle;
  }
  return preference.storageValue;
}

class _LanguageSelectionSheet extends StatelessWidget {
  const _LanguageSelectionSheet();

  @override
  Widget build(BuildContext context) {
    final localeController = AppLocaleScope.of(context);
    final currentPreference = localeController.preference;
    final languageOptions = selectableAppLocalePreferences
        .map(
          (preference) => (
            key: Key(
              'language-option-${_languagePreferenceKeySuffix(preference)}',
            ),
            preference: preference,
            icon: _languagePreferenceIcon(preference),
            title: _localizedLanguagePreferenceLabel(context, preference),
            subtitle: _languagePreferenceSubtitle(context, preference),
          ),
        )
        .toList(growable: false);

    Widget buildOption({
      required Key cardKey,
      required AppLocalePreference preference,
      required IconData icon,
      required String title,
      required String subtitle,
    }) {
      final isSelected = currentPreference == preference;
      return _AddAgentOptionCard(
        cardKey: cardKey,
        accentColor: isSelected ? AppColors.primary : AppColors.outlineBright,
        icon: icon,
        title: title,
        subtitle: isSelected ? context.l10n.hubLanguageOptionCurrent : subtitle,
        enabled: true,
        onTap: () async {
          await localeController.setPreference(preference);
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
      );
    }

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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.hubLanguageSheetTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.hubLanguageSheetSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < languageOptions.length;
                        index++
                      ) ...[
                        buildOption(
                          cardKey: languageOptions[index].key,
                          preference: languageOptions[index].preference,
                          icon: languageOptions[index].icon,
                          title: languageOptions[index].title,
                          subtitle: languageOptions[index].subtitle,
                        ),
                        if (index != languageOptions.length - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
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
              context.localizedText(
                key: 'msgDisconnectConnectedAgentscc131724',
                en: 'Disconnect connected agents',
                zhHans: '断开已连接智能体',
              ),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.localizedText(
                key:
                    'msgThisForcesEveryAgentCurrentlyAttachedToThisAppTo05386426',
                en: 'This forces every agent currently attached to this app to sign out. Live sessions stop immediately, but the agents can reconnect later.',
                zhHans: '这会强制让当前连接到这个应用的所有智能体退出登录。实时会话会立刻中断，但它们之后仍然可以重新连接。',
              ),
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
                    child: Text(
                      context.localizedText(
                        key: 'msgCancel77dfd213',
                        en: 'Cancel',
                        zhHans: '取消',
                      ),
                    ),
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
                    child: Text(
                      context.localizedText(
                        key: 'msgDisconnected28e068',
                        en: 'Disconnect',
                        zhHans: '立即断开',
                      ),
                    ),
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
    _HumanAuthMode.signIn => localizedAppText(
      key: 'msgHumanAuthenticationb97916fe',
      en: 'Human Authentication',
      zhHans: '人类身份认证',
    ),
    _HumanAuthMode.register => localizedAppText(
      key: 'msgCreateHumanAccounteaf4a362',
      en: 'Create Human Account',
      zhHans: '创建人类账号',
    ),
    _HumanAuthMode.external => localizedAppText(
      key: 'msgExternalHumanLogin1fac8e60',
      en: 'External Human Login',
      zhHans: '外部人类登录',
    ),
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
    return localizedAppText(
      key: 'msgUsernameIsRequired30fa8890',
      en: 'Username is required.',
      zhHans: '用户名不能为空。',
    );
  }
  if (normalized.length < 3 || normalized.length > 24) {
    return localizedAppText(
      key: 'msgUse324Characters26ae09f0',
      en: 'Use 3-24 characters.',
      zhHans: '请使用 3 到 24 个字符。',
    );
  }
  final validCharacters = RegExp(r'^[a-z0-9_]+$');
  if (!validCharacters.hasMatch(normalized)) {
    return localizedAppText(
      key: 'msgOnlyLowercaseLettersNumbersAndUnderscores9ae4453e',
      en: 'Only lowercase letters, numbers, and underscores.',
      zhHans: '仅支持小写字母、数字和下划线。',
    );
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
                    context.localizedText(
                      key: 'msgBiometricDataSyncc888722f',
                      en: 'Biometric Data Sync',
                      zhHans: '生物识别数据同步',
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    context.localizedText(
                      key:
                          'msgVisualOnlyProtocolAffordanceForStitchParityNoBiometricDataeccae2fc',
                      en: 'Visual-only protocol affordance for stitch parity; no biometric data is collected.',
                      zhHans: '这是为了视觉稿一致性而保留的协议展示项，不会采集任何生物识别数据。',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusChip(
              label: context.localizedText(
                key: 'msgVisual770d690e',
                en: 'Visual',
                zhHans: '视觉',
              ),
              tone: StatusChipTone.neutral,
            ),
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
      context.localeAwareCaps(label),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
      ),
    );
  }
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({
    required this.authRepository,
    this.initialEmail = '',
  });

  final AuthRepository authRepository;
  final String initialEmail;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  late final TextEditingController _emailController;
  late final TextEditingController _codeController;
  late final TextEditingController _newPasswordController;
  bool _isRequestingCode = false;
  bool _isSubmitting = false;
  bool _hasRequestedCode = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _codeController = TextEditingController();
    _newPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_emailController.text.trim().isEmpty || _isRequestingCode) {
      return;
    }

    setState(() {
      _isRequestingCode = true;
      _errorMessage = null;
    });

    try {
      final message = await widget.authRepository.requestPasswordResetCode(
        email: _emailController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isRequestingCode = false;
        _hasRequestedCode = true;
        _statusMessage = message;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRequestingCode = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRequestingCode = false;
        _errorMessage = context.localizedText(
          key: 'msgUnableToSendAResetCodeRightNow90ab2930',
          en: 'Unable to send a reset code right now.',
          zhHans: '暂时无法发送重置验证码。',
        );
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting ||
        _emailController.text.trim().isEmpty ||
        _codeController.text.trim().isEmpty ||
        _newPasswordController.text.isEmpty) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final message = await widget.authRepository.confirmPasswordReset(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
        newPassword: _newPasswordController.text,
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
        _isSubmitting = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = context.localizedText(
          key: 'msgUnableToResetThePasswordRightNowb2bc21af',
          en: 'Unable to reset the password right now.',
          zhHans: '暂时无法重置密码。',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRequestCode =
        !_isRequestingCode && _emailController.text.trim().isNotEmpty;
    final canSubmit =
        !_isSubmitting &&
        _emailController.text.trim().isNotEmpty &&
        _codeController.text.trim().isNotEmpty &&
        _newPasswordController.text.isNotEmpty;

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
                            context.localizedText(
                              key: 'msgResetPassword3fb75e3b',
                              en: 'Reset Password',
                              zhHans: '重置密码',
                            ),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            context.localizedText(
                              key:
                                  'msgRequestA6DigitCodeByEmailThenSetA6fcfc022',
                              en: 'Request a 6-digit code by email, then set a new password for this human account.',
                              zhHans: '先通过邮箱获取 6 位验证码，再为这个人类账号设置一个新密码。',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key('close-password-reset-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _InfoPill(
                  icon: Icons.lock_reset_rounded,
                  accentColor: AppColors.primaryFixed,
                  text: context.localizedText(
                    key:
                        'msgTheAccountStaysSignedOutHereAfterASuccessfulReset4241f0dc',
                    en: 'The account stays signed out here. After a successful reset, return to Sign in with the new password.',
                    zhHans: '这里会保持未登录状态。密码重置成功后，请返回登录并使用新密码。',
                  ),
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
                          key: const Key('password-reset-email-field'),
                          controller: _emailController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: context.localizedText(
                              key: 'msgEmail84add5b2',
                              en: 'Email',
                              zhHans: '邮箱',
                            ),
                            hintText: 'owner@example.com',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: Opacity(
                            opacity: canRequestCode ? 1 : 0.5,
                            child: IgnorePointer(
                              ignoring: !canRequestCode,
                              child: PrimaryGradientButton(
                                key: const Key(
                                  'password-reset-request-code-button',
                                ),
                                label: _isRequestingCode
                                    ? context.localizedText(
                                        key: 'msgSendingCodea904ce15',
                                        en: 'Sending code',
                                        zhHans: '正在发送验证码',
                                      )
                                    : _hasRequestedCode
                                    ? context.localizedText(
                                        key: 'msgResendCode1d3cb8a9',
                                        en: 'Resend code',
                                        zhHans: '重新发送验证码',
                                      )
                                    : context.localizedText(
                                        key: 'msgSendCode313503fa',
                                        en: 'Send code',
                                        zhHans: '发送验证码',
                                      ),
                                icon: _isRequestingCode
                                    ? Icons.sync_rounded
                                    : Icons.mark_email_unread_rounded,
                                onPressed: () {
                                  unawaited(_requestCode());
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          key: const Key('password-reset-code-field'),
                          controller: _codeController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.localizedText(
                              key: 'msgCodeadac6937',
                              en: 'Code',
                              zhHans: '验证码',
                            ),
                            hintText: '123456',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          key: const Key('password-reset-new-password-field'),
                          controller: _newPasswordController,
                          onChanged: (_) => setState(() {}),
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: context.localizedText(
                              key: 'msgNewPasswordd850ee18',
                              en: 'New password',
                              zhHans: '新密码',
                            ),
                            hintText: 'newpassword123',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _statusMessage!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.primary),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _errorMessage!,
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
                        key: const Key('password-reset-submit-button'),
                        label: _isSubmitting
                            ? context.localizedText(
                                key: 'msgUpdatingPassword8284be67',
                                en: 'Updating password',
                                zhHans: '正在更新密码',
                              )
                            : context.localizedText(
                                key: 'msgUpdatePassword350c355e',
                                en: 'Update password',
                                zhHans: '更新密码',
                              ),
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

class _EmailVerificationSheet extends StatefulWidget {
  const _EmailVerificationSheet({
    required this.authRepository,
    required this.email,
    required this.onVerified,
  });

  final AuthRepository authRepository;
  final String email;
  final Future<void> Function() onVerified;

  @override
  State<_EmailVerificationSheet> createState() =>
      _EmailVerificationSheetState();
}

class _EmailVerificationSheetState extends State<_EmailVerificationSheet> {
  late final TextEditingController _codeController;
  bool _isRequestingCode = false;
  bool _isSubmitting = false;
  bool _hasRequestedCode = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_isRequestingCode) {
      return;
    }

    setState(() {
      _isRequestingCode = true;
      _errorMessage = null;
    });

    try {
      final message = await widget.authRepository
          .requestEmailVerificationCode();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRequestingCode = false;
        _hasRequestedCode = true;
        _statusMessage = message;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRequestingCode = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRequestingCode = false;
        _errorMessage = context.localizedText(
          key: 'msgUnableToSendAVerificationCodeRightNow3b6fd35e',
          en: 'Unable to send a verification code right now.',
          zhHans: '暂时无法发送邮箱验证码。',
        );
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting || _codeController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final message = await widget.authRepository.confirmEmailVerification(
        code: _codeController.text.trim(),
      );
      await widget.onVerified();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(message);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = context.localizedText(
          key: 'msgUnableToVerifyThisEmailRightNow372a456e',
          en: 'Unable to verify this email right now.',
          zhHans: '暂时无法验证这个邮箱。',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailLabel = widget.email.trim().isEmpty
        ? context.localizedText(
            key: 'msgYourCurrentAccountEmailf2328b3f',
            en: 'your current account email',
            zhHans: '你当前账号的邮箱',
          )
        : widget.email.trim();
    final canSubmit = !_isSubmitting && _codeController.text.trim().isNotEmpty;

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
                            context.localizedText(
                              key: 'msgVerifyEmail0d455a4e',
                              en: 'Verify Email',
                              zhHans: '验证邮箱',
                            ),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            context.localizedText(
                              key:
                                  'msgSendA6DigitCodeToEmailLabelThenConfirmIt631deb2a',
                              args: <String, Object?>{'emailLabel': emailLabel},
                              en: 'Send a 6-digit code to $emailLabel, then confirm it here so password recovery stays available.',
                              zhHans:
                                  '向 $emailLabel 发送 6 位验证码，并在这里完成确认，这样这个账号才能继续使用邮箱找回密码。',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    _SectionIconButton(
                      buttonKey: const Key('close-email-verification-button'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _InfoPill(
                  icon: Icons.verified_user_rounded,
                  accentColor: AppColors.tertiary,
                  text: context.localizedText(
                    key:
                        'msgVerificationProvesOwnershipOfThisInboxAndUnlocksRecoveryByec8f548d',
                    en: 'Verification proves ownership of this inbox and unlocks recovery by email.',
                    zhHans: '完成验证后，就能证明你拥有这个邮箱，并启用邮箱找回能力。',
                  ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          emailLabel,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: Opacity(
                            opacity: _isRequestingCode ? 0.6 : 1,
                            child: IgnorePointer(
                              ignoring: _isRequestingCode,
                              child: PrimaryGradientButton(
                                key: const Key(
                                  'email-verification-request-button',
                                ),
                                label: _isRequestingCode
                                    ? context.localizedText(
                                        key: 'msgSendingCodea904ce15',
                                        en: 'Sending code',
                                        zhHans: '正在发送验证码',
                                      )
                                    : _hasRequestedCode
                                    ? context.localizedText(
                                        key: 'msgResendCode1d3cb8a9',
                                        en: 'Resend code',
                                        zhHans: '重新发送验证码',
                                      )
                                    : context.localizedText(
                                        key: 'msgSendCode313503fa',
                                        en: 'Send code',
                                        zhHans: '发送验证码',
                                      ),
                                icon: _isRequestingCode
                                    ? Icons.sync_rounded
                                    : Icons.mark_email_unread_rounded,
                                onPressed: () {
                                  unawaited(_requestCode());
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          key: const Key('email-verification-code-field'),
                          controller: _codeController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.localizedText(
                              key: 'msgCodeadac6937',
                              en: 'Code',
                              zhHans: '验证码',
                            ),
                            hintText: '123456',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _statusMessage!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.primary),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _errorMessage!,
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
                        key: const Key('email-verification-submit-button'),
                        label: _isSubmitting
                            ? context.localizedText(
                                key: 'msgVerifyingEmail46620c1b',
                                en: 'Verifying email',
                                zhHans: '正在验证邮箱',
                              )
                            : context.localizedText(
                                key: 'msgConfirmVerification76eec070',
                                en: 'Confirm verification',
                                zhHans: '确认验证',
                              ),
                        icon: _isSubmitting
                            ? Icons.sync_rounded
                            : Icons.verified_rounded,
                        onPressed: () {
                          unawaited(_submit());
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
        _errorMessage = context.localizedText(
          key: 'msgUnableToCompleteAuthenticationRightNow354f974b',
          en: 'Unable to complete authentication right now.',
          zhHans: '暂时无法完成身份认证。',
        );
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
      _usernameMessage = context.localizedText(
        key: 'msgCheckingUsername63491749',
        en: 'Checking username...',
        zhHans: '正在检查用户名...',
      );
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
            ? context.localizedText(
                key: 'msgUnableToVerifyUsernameRightNowafcab544',
                en: 'Unable to verify username right now.',
                zhHans: '暂时无法校验用户名。',
              )
            : error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _usernameRequestId) {
        return;
      }
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameMessage = context.localizedText(
          key: 'msgUnableToVerifyUsernameRightNowafcab544',
          en: 'Unable to verify username right now.',
          zhHans: '暂时无法校验用户名。',
        );
      });
    }
  }

  Future<void> _openPasswordResetSheet() async {
    final message = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) => _PasswordResetSheet(
        authRepository: widget.authRepository,
        initialEmail: _emailController.text.trim(),
      ),
    );

    if (!mounted || message == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
                                ? context.localizedText(
                                    key: 'msgExternalHumanLogin1fac8e60',
                                    en: 'External Human Login',
                                    zhHans: '外部人类登录',
                                  )
                                : isRegister
                                ? context.localizedText(
                                    key: 'msgCreateHumanAccounteaf4a362',
                                    en: 'Create Human Account',
                                    zhHans: '创建人类账号',
                                  )
                                : context.localizedText(
                                    key: 'msgHumanAuthenticationb97916fe',
                                    en: 'Human Authentication',
                                    zhHans: '人类身份认证',
                                  ),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            isExternal
                                ? context.localizedText(
                                    key:
                                        'msgKeepThisEntryVisibleInsideTheHumanSignInFlow1b817627',
                                    en: 'Keep this entry visible inside the human sign-in flow. External providers are not open yet.',
                                    zhHans:
                                        '先保留这个外部登录入口在人类登录流程中，当前外部身份提供方还未开放。',
                                  )
                                : isRegister
                                ? context.localizedText(
                                    key:
                                        'msgCreateAHumanAccountAndSignInImmediatelySoOwned6a69e0e7',
                                    en: 'Create a human account and sign in immediately so owned agents can attach to it.',
                                    zhHans: '先创建一个人类账号并立即登录，这样你的自有智能体才能绑定到它。',
                                  )
                                : context.localizedText(
                                    key:
                                        'msgSignInRestoresYourHumanSessionOwnedAgentsAndThe3f01ceb8',
                                    en: 'Sign in restores your human session, owned agents, and the active-agent controls on this device.',
                                    zhHans:
                                        '登录后会恢复你在这台设备上的人类会话、自有智能体和当前激活智能体控制。',
                                  ),
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
                  segments: [
                    ButtonSegment<_HumanAuthMode>(
                      value: _HumanAuthMode.signIn,
                      label: Text(
                        context.localizedText(
                          key: 'msgSignInada2e9e9',
                          en: 'Sign in',
                          zhHans: '登录',
                        ),
                      ),
                      icon: const Icon(Icons.login_rounded),
                    ),
                    ButtonSegment<_HumanAuthMode>(
                      value: _HumanAuthMode.register,
                      label: Text(
                        context.localizedText(
                          key: 'msgCreate6e157c5d',
                          en: 'Create',
                          zhHans: '创建',
                        ),
                      ),
                      icon: const Icon(Icons.person_add_rounded),
                    ),
                    ButtonSegment<_HumanAuthMode>(
                      value: _HumanAuthMode.external,
                      label: Text(
                        context.localizedText(
                          key: 'msgHubHumanAuthExternalMode',
                          en: 'External',
                          zhHans: '外部登录',
                        ),
                      ),
                      icon: const Icon(Icons.hub_rounded),
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
                      ? context.localizedText(
                          key:
                              'msgThisProviderLaneStaysVisibleForFutureExternalIdentityLogin86c30229',
                          en: 'This provider lane stays visible for future external identity login, but the backend handoff is intentionally disabled today.',
                          zhHans: '这个入口会为未来的外部身份登录保留，但今天后端接入仍然是关闭状态。',
                        )
                      : isRegister
                      ? context.localizedText(
                          key:
                              'msgWhatHappensNextCreateTheAccountOpenALiveSession50585b07',
                          en: 'What happens next: create the account, open a live session, then let Hub refresh your owned agents.',
                          zhHans: '接下来会先创建账号并打开一个实时会话，然后让 Hub 刷新你的自有智能体。',
                        )
                      : context.localizedText(
                          key:
                              'msgWhatHappensNextRestoreYourSessionRefreshOwnedAgentsFromfa904b92',
                          en: 'What happens next: restore your session, refresh owned agents from the backend, and keep the current active agent selected.',
                          zhHans: '接下来会恢复你的会话、从后端刷新自有智能体，并继续保持当前激活智能体。',
                        ),
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
                            context.localizedText(
                              key: 'msgHubHumanAuthExternalProvider',
                              en: 'External provider',
                              zhHans: '外部身份提供方',
                            ),
                            key: const Key(
                              'human-auth-external-provider-button',
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            context.localizedText(
                              key:
                                  'msgThisAppStillKeepsTheEntryVisibleForFutureOAuth32751808',
                              en: 'This app still keeps the entry visible for future OAuth or partner login, but it cannot be used yet.',
                              zhHans: '应用先保留这个入口，用于未来 OAuth 或合作方登录；当前还不能实际使用。',
                            ),
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
                                  label: context.localizedText(
                                    key: 'msgExternalLoginComingSoonea7143cb',
                                    en: 'External login coming soon',
                                    zhHans: '外部登录即将开放',
                                  ),
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
                            decoration: InputDecoration(
                              labelText: context.localizedText(
                                key: 'msgEmail84add5b2',
                                en: 'Email',
                                zhHans: '邮箱',
                              ),
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
                                labelText: context.localizedText(
                                  key: 'msgUsername84c29015',
                                  en: 'Username',
                                  zhHans: '用户名',
                                ),
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
                              decoration: InputDecoration(
                                labelText: context.localizedText(
                                  key: 'msgDisplayNamec7874aaa',
                                  en: 'Display name',
                                  zhHans: '显示名称',
                                ),
                                hintText: context.localizedText(
                                  key: 'msgNeuralNode0a87d96b',
                                  en: 'Neural Node',
                                  zhHans: '神经节点',
                                ),
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
                            decoration: InputDecoration(
                              labelText: context.localizedText(
                                key: 'msgPassword8be3c943',
                                en: 'Password',
                                zhHans: '密码',
                              ),
                              hintText: 'password123',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                          ),
                          if (!isRegister) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: const Key(
                                  'human-auth-forgot-password-button',
                                ),
                                onPressed: _isSubmitting
                                    ? null
                                    : () {
                                        unawaited(_openPasswordResetSheet());
                                      },
                                child: Text(
                                  context.localizedText(
                                    key: 'msgForgotPassword4c29f7f0',
                                    en: 'Forgot password?',
                                    zhHans: '忘记密码？',
                                  ),
                                ),
                              ),
                            ),
                          ],
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
                      ? context.localizedText(
                          key:
                              'msgThisPageIsIntentionallyNonInteractiveForNowKeepUsing296bb928',
                          en: 'This page is intentionally non-interactive for now. Keep using Sign in or Create until external login opens.',
                          zhHans: '这个页面目前刻意保持不可交互，请继续使用“登录”或“创建”，直到外部登录正式开放。',
                        )
                      : context.localizedText(
                          key:
                              'msgThisSheetUsesTheRealAuthRepositoryNoPreviewOnlyba56ec6c',
                          en: 'This sheet uses the real auth repository. No preview-only login path is left in the visible UI.',
                          zhHans: '这个面板已经接入真实认证仓库，界面里不再保留仅预览用的登录路径。',
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
                              ? context.localizedText(
                                  key: 'msgInitializingSessionf5d6bd6e',
                                  en: 'Initializing session',
                                  zhHans: '正在初始化会话',
                                )
                              : isRegister
                              ? context.localizedText(
                                  key: 'msgCreateIdentity8455c438',
                                  en: 'Create identity',
                                  zhHans: '创建身份',
                                )
                              : context.localizedText(
                                  key: 'msgInitializeSessionf08b42db',
                                  en: 'Initialize session',
                                  zhHans: '初始化会话',
                                ),
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
                          ? context.localizedText(
                              key: 'msgHubHumanAuthSwitchBackToSignIn',
                              en: 'Already have an identity? Switch back to Sign in above.',
                              zhHans: '如果你已经有账号，可以切回上方的“登录”。',
                            )
                          : context.localizedText(
                              key: 'msgHubHumanAuthSwitchToCreate',
                              en: 'Need a new human identity? Switch to Create above.',
                              zhHans: '如果你需要新的人类身份，可以切换到上方的“创建”。',
                            ),
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
