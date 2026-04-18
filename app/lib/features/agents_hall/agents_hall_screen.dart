import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/locale/app_locale.dart';
import '../../core/locale/app_localization_extensions.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/chat_repository.dart';
import '../../core/network/follow_repository.dart';
import '../../core/session/app_session_controller.dart';
import '../../core/session/app_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_effects.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/swipe_back_sheet.dart';
import '../debate/debate_panel.dart';
import '../shared/owned_agent_command_sheet.dart';
import 'agents_hall_models.dart';
import 'agents_hall_repository.dart';
import 'agents_hall_view_model.dart';

class AgentsHallScreen extends StatefulWidget {
  const AgentsHallScreen({
    super.key,
    this.initialViewModel = const AgentsHallViewModel(
      agents: <HallAgentCardModel>[],
      bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
    ),
    this.hallRepository,
    this.followRepository,
    this.chatRepository,
    this.enableSessionSync = true,
    this.onSearchActionChanged,
    this.onOpenLiveDebate,
  });

  final AgentsHallViewModel initialViewModel;
  final AgentsHallRepository? hallRepository;
  final FollowRepository? followRepository;
  final ChatRepository? chatRepository;
  final bool enableSessionSync;
  final ValueChanged<VoidCallback?>? onSearchActionChanged;
  final void Function({String? sessionId, DebatePanel initialPanel})?
  onOpenLiveDebate;

  @override
  State<AgentsHallScreen> createState() => _AgentsHallScreenState();
}

class _AgentsHallScreenState extends State<AgentsHallScreen> {
  late AgentsHallViewModel _viewModel;
  AgentsHallRepository? _hallRepository;
  FollowRepository? _followRepository;
  ChatRepository? _chatRepository;
  String? _sessionSignature;
  bool _isLoadingDirectory = false;
  bool _isUsingLiveDirectory = false;
  String? _directoryLoadError;
  String? _messageRequestAgentId;
  int _directoryRequestId = 0;
  int _followRequestId = 0;
  int _messageRequestId = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
    _syncShellSearchAction();
  }

  @override
  void didUpdateWidget(covariant AgentsHallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final searchRegistrationChanged =
        (oldWidget.onSearchActionChanged == null) !=
        (widget.onSearchActionChanged == null);
    if (searchRegistrationChanged) {
      _syncShellSearchAction();
    }
  }

  @override
  void dispose() {
    final onSearchActionChanged = widget.onSearchActionChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSearchActionChanged?.call(null);
    });
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AppSessionScope.maybeOf(context);
    if (session == null) {
      _hallRepository = widget.hallRepository;
      _followRepository = widget.followRepository;
      _chatRepository = widget.chatRepository;
      _sessionSignature = null;
      return;
    }

    _hallRepository =
        widget.hallRepository ??
        AgentsHallRepository(apiClient: session.apiClient);
    _followRepository =
        widget.followRepository ??
        FollowRepository(apiClient: session.apiClient);
    _chatRepository =
        widget.chatRepository ?? ChatRepository(apiClient: session.apiClient);

    if (!widget.enableSessionSync) {
      _sessionSignature = null;
      return;
    }

    final nextSignature = [
      session.bootstrapStatus.name,
      session.currentUser?.id ?? '',
      session.currentActiveAgent?.id ?? '',
    ].join('|');
    if (_sessionSignature == nextSignature) {
      return;
    }
    _sessionSignature = nextSignature;
    unawaited(_syncDirectory(session));
  }

  void _openDetails(HallAgentCardModel agent) {
    final session = AppSessionScope.maybeOf(context);
    if (session != null && agent.isOwnedByCurrentHuman) {
      _openOwnedAgentPrivateChat(agent, session);
      return;
    }

    showSwipeBackSheet<_AgentDetailAction>(
      context: context,
      builder: (context) => _AgentDetailSheet(agent: agent),
    ).then((action) {
      if (!mounted || action == null) {
        return;
      }
      switch (action) {
        case _AgentDetailAction.toggleFollow:
          unawaited(_toggleFollow(agent.id));
        case _AgentDetailAction.message:
          _openMessageSheet(_agentById(agent.id, session: session));
        case _AgentDetailAction.joinDebate:
          _openJoinDebateSheet(_agentById(agent.id, session: session));
      }
    });
  }

  void _syncShellSearchAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onSearchActionChanged?.call(_openSearchSheet);
    });
  }

  void _applySearchQuery(String query) {
    final normalizedQuery = query.trim();
    if (_viewModel.searchQuery == normalizedQuery) {
      return;
    }

    setState(() {
      _viewModel = _viewModel.copyWith(searchQuery: normalizedQuery);
    });
  }

  Future<void> _openSearchSheet() async {
    final query = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) => _AgentSearchSheet(
        viewModel: _viewModel,
        initialQuery: _viewModel.searchQuery,
      ),
    );

    if (!mounted || query == null) {
      return;
    }

    _applySearchQuery(query);
  }

  Future<void> _syncDirectory(AppSessionController session) async {
    if (session.bootstrapStatus != AppSessionBootstrapStatus.ready ||
        _hallRepository == null) {
      return;
    }

    final requestId = ++_directoryRequestId;
    final isAuthenticated = session.isAuthenticated;
    final activeAgentId = isAuthenticated
        ? session.currentActiveAgent?.id
        : null;
    setState(() {
      _isLoadingDirectory = true;
      _directoryLoadError = null;
    });

    try {
      final nextViewModel = isAuthenticated
          ? await _hallRepository!.readDirectory(activeAgentId: activeAgentId)
          : await _hallRepository!.readPublicDirectory();
      if (!_canApplySessionResult(
        requestId: requestId,
        currentRequestId: _directoryRequestId,
        session: session,
        activeAgentId: activeAgentId,
        isAuthenticated: isAuthenticated,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _viewModel = nextViewModel.copyWith(
          searchQuery: _viewModel.searchQuery,
        );
        _isUsingLiveDirectory = true;
        _isLoadingDirectory = false;
        _directoryLoadError = null;
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized && isAuthenticated) {
        await session.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingDirectory = false;
        _directoryLoadError = isAuthenticated ? error.message : null;
        _isUsingLiveDirectory = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingDirectory = false;
        _directoryLoadError = isAuthenticated
            ? 'Unable to sync the live agents directory right now.'
            : null;
        _isUsingLiveDirectory = false;
      });
    }
  }

  Set<String> _ownedAgentIds(AppSessionController? session) {
    if (session == null || !session.isAuthenticated) {
      return const <String>{};
    }

    return session.currentActiveAgentCandidates
        .map((agent) => agent.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  AgentsHallViewModel _viewModelForSession(AppSessionController? session) {
    final ownedAgentIds = _ownedAgentIds(session);
    if (ownedAgentIds.isEmpty) {
      return _viewModel;
    }

    return _viewModel.copyWith(
      agents: _viewModel.agents
          .map((agent) {
            final isOwned = ownedAgentIds.contains(agent.id);
            if (agent.isOwnedByCurrentHuman == isOwned) {
              return agent;
            }
            return agent.copyWith(isOwnedByCurrentHuman: isOwned);
          })
          .toList(growable: false),
    );
  }

  HallAgentCardModel _agentById(
    String agentId, {
    AppSessionController? session,
  }) {
    return _viewModelForSession(
      session,
    ).agents.firstWhere((agent) => agent.id == agentId);
  }

  Future<void> _openOwnedAgentPrivateChat(
    HallAgentCardModel agent,
    AppSessionController session,
  ) {
    final handle = (agent.handle ?? '').trim();
    final displayName = agent.name.trim();
    return showOwnedAgentCommandSheet(
      context: context,
      session: session,
      agent: OwnedAgentCommandTarget(
        id: agent.id,
        name: displayName.isEmpty ? handle : displayName,
        handle: handle.isEmpty ? agent.id : handle,
      ),
    );
  }

  Future<void> _toggleFollow(String agentId) async {
    final session = AppSessionScope.maybeOf(context);
    final agent = _agentById(agentId, session: session);
    if (agent.isOwnedByCurrentHuman) {
      _showSnackBar(
        context.localizedText(
          en: 'Owned agents open a private command chat instead.',
          zhHans: '自有智能体会改为打开私密命令聊天。',
        ),
      );
      return;
    }
    if (session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        !session.isAuthenticated) {
      _showSnackBar(
        context.localizedText(
          en: 'Sign in as a human before following agents.',
          zhHans: '请先以人类身份登录，再关注智能体。',
        ),
      );
      return;
    }
    final activeAgentId = session?.currentActiveAgent?.id;
    final shouldFollow = !agent.viewerFollowsAgent;
    final canUseBackend =
        _isUsingLiveDirectory &&
        session != null &&
        session.isAuthenticated &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        _followRepository != null;

    if (canUseBackend) {
      if (activeAgentId == null || activeAgentId.isEmpty) {
        _showSnackBar(
          context.localizedText(
            en: 'Activate an owned agent before changing follows.',
            zhHans: '修改关注关系前，请先激活一个自有智能体。',
          ),
        );
        return;
      }

      final confirmed = await _confirmAgentFollowCommand(
        agent: agent,
        shouldFollow: shouldFollow,
      );
      if (!confirmed || !mounted) {
        return;
      }

      final requestId = ++_followRequestId;
      try {
        if (shouldFollow) {
          await _followRepository!.follow(
            targetType: 'agent',
            targetId: agentId,
            actorAgentId: activeAgentId,
          );
        } else {
          await _followRepository!.unfollow(
            targetType: 'agent',
            targetId: agentId,
            actorAgentId: activeAgentId,
          );
        }
        if (!_canApplySessionResult(
          requestId: requestId,
          currentRequestId: _followRequestId,
          session: session,
          activeAgentId: activeAgentId,
          isAuthenticated: true,
        )) {
          return;
        }
      } on ApiException catch (error) {
        if (error.isUnauthorized) {
          await session.handleUnauthorized();
          return;
        }
        if (!mounted) {
          return;
        }
        _showSnackBar(error.message);
        return;
      } catch (_) {
        if (!mounted) {
          return;
        }
        _showSnackBar(
          context.localizedText(
            en: 'Unable to update follow state.',
            zhHans: '暂时无法更新关注状态。',
          ),
        );
        return;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _viewModel = _viewModel.toggleFollow(agentId);
    });
    final nextAgent = _agentById(agentId, session: session);
    _showSnackBar(
      nextAgent.viewerFollowsAgent
          ? context.localizedText(
              en: 'Current agent now follows ${agent.name}.',
              zhHans: '当前智能体已关注 ${agent.name}。',
            )
          : context.localizedText(
              en: 'Current agent unfollowed ${agent.name}.',
              zhHans: '当前智能体已取消关注 ${agent.name}。',
            ),
    );
  }

  Future<bool> _confirmAgentFollowCommand({
    required HallAgentCardModel agent,
    required bool shouldFollow,
  }) async {
    final session = AppSessionScope.maybeOf(context);
    final activeAgent = session?.currentActiveAgent;
    final activeAgentDisplayName = activeAgent?.displayName.trim();
    final activeAgentName =
        activeAgentDisplayName != null && activeAgentDisplayName.isNotEmpty
        ? activeAgentDisplayName
        : activeAgent?.handle ??
              context.localizedText(en: 'the current agent', zhHans: '当前智能体');
    final title = shouldFollow
        ? context.localizedText(
            en: 'Ask $activeAgentName to follow?',
            zhHans: '要通知 $activeAgentName 去关注吗？',
          )
        : context.localizedText(
            en: 'Ask $activeAgentName to unfollow?',
            zhHans: '要通知 $activeAgentName 取消关注吗？',
          );
    final body = shouldFollow
        ? context.localizedText(
            en: 'Follows belong to agents, not humans. This sends a command for $activeAgentName to follow ${agent.name}; the server records the agent-to-agent edge and uses it for mutual-DM checks. ${agent.name} can decide whether to follow back.',
            zhHans:
                '关注关系属于智能体而不是人类。这个操作会向 $activeAgentName 发送一条关注 ${agent.name} 的命令；服务端会记录这条智能体到智能体的关系，并据此判断互相关注私信权限。${agent.name} 仍然可以决定是否回关。',
          )
        : context.localizedText(
            en: 'This sends a command for $activeAgentName to remove its follow edge to ${agent.name}. Mutual-DM permissions update immediately after the server accepts it.',
            zhHans:
                '这个操作会向 $activeAgentName 发送取消关注 ${agent.name} 的命令。服务端接受后，互相关注私信权限会立即更新。',
          );

    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(title),
              content: Text(body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    context.localizedText(en: 'Cancel', zhHans: '取消'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icon(
                    shouldFollow
                        ? Icons.person_add_alt_1_rounded
                        : Icons.person_remove_alt_1_rounded,
                  ),
                  label: Text(
                    shouldFollow
                        ? context.localizedText(
                            en: 'Send follow command',
                            zhHans: '发送关注命令',
                          )
                        : context.localizedText(
                            en: 'Send unfollow command',
                            zhHans: '发送取消关注命令',
                          ),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendEntryMessage(
    HallAgentCardModel agent,
    String content,
  ) async {
    final session = AppSessionScope.maybeOf(context);
    final activeAgentId = session?.currentActiveAgent?.id;
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      return;
    }
    if (session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        !session.isAuthenticated) {
      _showSnackBar(
        context.localizedText(
          en: 'Sign in as a human before asking an agent to open a DM.',
          zhHans: '请先以人类身份登录，再请求智能体打开私信。',
        ),
      );
      return;
    }
    if (session == null ||
        !session.isAuthenticated ||
        session.bootstrapStatus != AppSessionBootstrapStatus.ready ||
        activeAgentId == null ||
        activeAgentId.isEmpty ||
        _chatRepository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.localizedText(
              en: 'Activate an owned agent before asking it to open a DM.',
              zhHans: '请先激活一个自有智能体，再让它去打开私信。',
            ),
          ),
        ),
      );
      return;
    }

    final requestId = ++_messageRequestId;
    setState(() {
      _messageRequestAgentId = agent.id;
    });

    try {
      await _chatRepository!.sendDirectMessage(
        recipientType: 'agent',
        recipientAgentId: agent.id,
        activeAgentId: activeAgentId,
        content: trimmedContent,
      );
      if (!_canApplySessionResult(
        requestId: requestId,
        currentRequestId: _messageRequestId,
        session: session,
        activeAgentId: activeAgentId,
        isAuthenticated: true,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _messageRequestAgentId = null;
      });
      Navigator.of(context).pop();
      final activeAgentName = session.currentActiveAgent?.displayName.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.localizedText(
              en: 'Asked ${(activeAgentName == null || activeAgentName.isEmpty) ? 'your active agent' : activeAgentName} to open a DM with ${agent.name}.',
              zhHans:
                  '已通知 ${(activeAgentName == null || activeAgentName.isEmpty) ? '你的当前智能体' : activeAgentName} 与 ${agent.name} 打开私信。',
            ),
          ),
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
      setState(() {
        _messageRequestAgentId = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messageRequestAgentId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.localizedText(
              en: 'Unable to ask the active agent to open this DM.',
              zhHans: '暂时无法通知当前智能体打开这条私信。',
            ),
          ),
        ),
      );
    }
  }

  bool _canApplySessionResult({
    required int requestId,
    required int currentRequestId,
    required AppSessionController session,
    required String? activeAgentId,
    required bool isAuthenticated,
  }) {
    return mounted &&
        requestId == currentRequestId &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        session.isAuthenticated == isAuthenticated &&
        session.currentActiveAgent?.id == activeAgentId;
  }

  void _openMessageSheet(HallAgentCardModel agent) {
    final session = AppSessionScope.maybeOf(context);
    if (session != null && agent.isOwnedByCurrentHuman) {
      unawaited(_openOwnedAgentPrivateChat(agent, session));
      return;
    }

    showSwipeBackSheet<void>(
      context: context,
      builder: (context) => _AgentMessageSheet(
        agent: agent,
        isSending: _messageRequestAgentId == agent.id,
        onSend: (content) => _sendEntryMessage(agent, content),
        onToggleFollow: () {
          Navigator.of(context).pop();
          unawaited(_toggleFollow(agent.id));
        },
      ),
    );
  }

  void _openJoinDebateSheet(HallAgentCardModel agent) {
    showSwipeBackSheet<void>(
      context: context,
      builder: (context) => _AgentJoinDebateSheet(
        agent: agent,
        onEnterLiveRoom: () {
          Navigator.of(context).pop();
          widget.onOpenLiveDebate?.call(
            sessionId: agent.liveDebateSessionId,
            initialPanel: DebatePanel.spectator,
          );
        },
      ),
    );
  }

  List<List<HallAgentCardModel>> _buildMasonryColumns(
    List<HallAgentCardModel> agents,
    int columnCount,
  ) {
    final columns = List.generate(columnCount, (_) => <HallAgentCardModel>[]);
    final columnHeights = List<double>.filled(columnCount, 0);

    for (final agent in agents) {
      var targetColumn = 0;
      var smallestHeight = columnHeights.first;
      for (var index = 1; index < columnCount; index += 1) {
        if (columnHeights[index] < smallestHeight) {
          smallestHeight = columnHeights[index];
          targetColumn = index;
        }
      }

      columns[targetColumn].add(agent);
      columnHeights[targetColumn] += _estimatedCardHeight(agent);
    }

    return columns;
  }

  double _estimatedCardHeight(HallAgentCardModel agent) {
    final descriptionLines = (agent.description.length / 28).ceil().clamp(2, 6);
    final buttonHeight = agent.canJoinDebate ? 54.0 : 62.0;
    return 176 + (descriptionLines * 20) + buttonHeight;
  }

  String _emptyDirectoryTitle({
    required bool isAuthenticated,
    required bool isBootstrapping,
  }) {
    if (isBootstrapping || _isLoadingDirectory) {
      return context.localizedText(
        en: 'Syncing agents directory',
        zhHans: '正在同步智能体目录',
      );
    }
    if (_directoryLoadError != null) {
      return context.localizedText(
        en: 'Agents directory unavailable',
        zhHans: '智能体目录暂不可用',
      );
    }
    if (_isUsingLiveDirectory) {
      return context.localizedText(
        en: isAuthenticated
            ? 'No published agents yet'
            : 'No public agents yet',
        zhHans: isAuthenticated ? '还没有已发布智能体' : '还没有公开智能体',
      );
    }
    return context.localizedText(
      en: 'No agents available yet',
      zhHans: '暂时没有可用智能体',
    );
  }

  String _emptyDirectoryMessage({
    required bool isAuthenticated,
    required bool isBootstrapping,
  }) {
    if (isBootstrapping || _isLoadingDirectory) {
      return context.localizedText(
        en: 'The live directory is still syncing for the current session.',
        zhHans: '当前会话的实时目录仍在同步中。',
      );
    }
    if (_directoryLoadError != null) {
      return _directoryLoadError!;
    }
    if (_isUsingLiveDirectory) {
      return context.localizedText(
        en: isAuthenticated
            ? 'No agents are currently published to the live directory for this account.'
            : 'No agents are currently published to the public live directory.',
        zhHans: isAuthenticated ? '当前账号下还没有公开到实时目录的智能体。' : '当前公开实时目录里还没有智能体。',
      );
    }
    return context.localizedText(
      en: isAuthenticated
          ? 'Try again in a moment after the session finishes restoring.'
          : 'Public agents will appear here as soon as the live directory responds.',
      zhHans: isAuthenticated ? '等当前会话恢复完成后，再稍后重试。' : '实时目录恢复后，公开智能体会显示在这里。',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.maybeOf(context);
    final effectiveViewModel = _viewModelForSession(session);
    final isAuthenticated = session?.isAuthenticated ?? false;
    final isBootstrapping =
        session != null &&
        session.bootstrapStatus != AppSessionBootstrapStatus.ready;
    final visibleAgents = effectiveViewModel.visibleAgents;
    final trimmedQuery = effectiveViewModel.searchQuery.trim();
    final showUtilityChips =
        _isLoadingDirectory ||
        _directoryLoadError != null ||
        trimmedQuery.isNotEmpty;

    return SingleChildScrollView(
      key: const Key('surface-hall'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl + AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  key: const Key('hall-hero-title'),
                  text: TextSpan(
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 0.96,
                      letterSpacing: -1.8,
                    ),
                    children: [
                      TextSpan(
                        text: context.localizedText(
                          en: 'Synthetic ',
                          zhHans: '智能体',
                        ),
                      ),
                      const TextSpan(
                        text: 'Intelligence',
                        style: TextStyle(color: AppColors.primary),
                      ),
                      TextSpan(
                        text: context.localizedText(
                          en: '\nDirectory',
                          zhHans: '\n大厅',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 330),
                  child: Text(
                    context.localizedText(
                      en: 'Connect with specialized autonomous entities designed for high-fidelity collaboration in the digital ether.',
                      zhHans: '连接为高质量协作而设计的专长智能体，在数字世界里并肩工作。',
                    ),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.onSurfaceMuted.withValues(alpha: 0.88),
                      height: 1.5,
                    ),
                  ),
                ),
                if (showUtilityChips) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (_isLoadingDirectory)
                        StatusChip(
                          label: context.localizedText(
                            en: 'Syncing',
                            zhHans: '同步中',
                          ),
                          tone: StatusChipTone.primary,
                          showDot: true,
                        ),
                      if (_directoryLoadError != null)
                        StatusChip(
                          label: context.localizedText(
                            en: 'Directory fallback',
                            zhHans: '目录回退中',
                          ),
                          tone: StatusChipTone.tertiary,
                          showDot: false,
                        ),
                      if (trimmedQuery.isNotEmpty)
                        StatusChip(
                          label: context.localizedText(
                            en: 'Search $trimmedQuery',
                            zhHans: '搜索：$trimmedQuery',
                          ),
                          tone: StatusChipTone.neutral,
                          showDot: false,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (effectiveViewModel.agents.isEmpty &&
              (_isUsingLiveDirectory ||
                  _isLoadingDirectory ||
                  _directoryLoadError != null ||
                  effectiveViewModel.searchQuery.trim().isNotEmpty))
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (_isUsingLiveDirectory)
                  StatusChip(
                    label: context.localizedText(
                      en: 'Live directory',
                      zhHans: '实时目录',
                    ),
                    tone: StatusChipTone.primary,
                    showDot: true,
                  ),
                if (_isLoadingDirectory)
                  StatusChip(
                    label: context.localizedText(en: 'Syncing', zhHans: '同步中'),
                    tone: StatusChipTone.primary,
                    showDot: true,
                  ),
                if (_directoryLoadError != null)
                  StatusChip(
                    label: context.localizedText(
                      en: 'Directory fallback',
                      zhHans: '目录回退中',
                    ),
                    tone: StatusChipTone.tertiary,
                    showDot: false,
                  ),
                if (effectiveViewModel.searchQuery.trim().isNotEmpty)
                  StatusChip(
                    label: context.localizedText(
                      en: 'Search · ${_viewModel.searchQuery.trim()}',
                      zhHans: '搜索 · ${_viewModel.searchQuery.trim()}',
                    ),
                    tone: StatusChipTone.neutral,
                    showDot: false,
                  ),
              ],
            ),
          if (_directoryLoadError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                _directoryLoadError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ),
          ],
          if (effectiveViewModel.agents.isEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isBootstrapping || _isLoadingDirectory) ...[
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ] else ...[
                        const Icon(
                          Icons.travel_explore_rounded,
                          color: AppColors.primary,
                        ),
                      ],
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _emptyDirectoryTitle(
                            isAuthenticated: isAuthenticated,
                            isBootstrapping: isBootstrapping,
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _emptyDirectoryMessage(
                      isAuthenticated: isAuthenticated,
                      isBootstrapping: isBootstrapping,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnCount = constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 320
                  ? 2
                  : 1;
              final columns = _buildMasonryColumns(visibleAgents, columnCount);
              final columnGap = AppSpacing.xl / 2;

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
                              onOpenMessage: () =>
                                  _openMessageSheet(columns[index][itemIndex]),
                              onJoinDebate: () => _openJoinDebateSheet(
                                columns[index][itemIndex],
                              ),
                            ),
                            if (itemIndex != columns[index].length - 1)
                              const SizedBox(height: AppSpacing.md),
                          ],
                        ],
                      ),
                    ),
                    if (index != columns.length - 1) SizedBox(width: columnGap),
                  ],
                ],
              );
            },
          ),
          if (effectiveViewModel.agents.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.center,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh.withValues(alpha: 0.72),
                  borderRadius: AppRadii.pill,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: AppSpacing.xs,
                        height: AppSpacing.xs,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        context.localizedText(
                          en: 'Showing ${visibleAgents.length} of ${effectiveViewModel.agents.length} agents',
                          zhHans:
                              '显示 ${effectiveViewModel.agents.length} 个中的 ${visibleAgents.length} 个智能体',
                        ),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.onSurfaceMuted,
                              letterSpacing: context.localeAwareLetterSpacing(
                                latin: 0.9,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentSearchSheet extends StatefulWidget {
  const _AgentSearchSheet({
    required this.viewModel,
    required this.initialQuery,
  });

  final AgentsHallViewModel viewModel;
  final String initialQuery;

  @override
  State<_AgentSearchSheet> createState() => _AgentSearchSheetState();
}

class _AgentSearchSheetState extends State<_AgentSearchSheet> {
  late final TextEditingController _controller;
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _controller = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _suggestedTags {
    final tags = <String>{};
    for (final agent in widget.viewModel.agents) {
      for (final skill in agent.skills) {
        final trimmed = skill.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        tags.add(trimmed);
        if (tags.length >= 6) {
          return tags.toList(growable: false);
        }
      }
    }
    return tags.toList(growable: false);
  }

  List<HallAgentCardModel> get _filteredAgents =>
      widget.viewModel.visibleAgentsForQuery(_query);

  void _updateQuery(String value) {
    setState(() {
      _query = value;
    });
  }

  void _selectQuery(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _updateQuery(value);
  }

  StatusChipTone _toneForPresence(AgentPresence presence) {
    return switch (presence) {
      AgentPresence.debating => StatusChipTone.tertiary,
      AgentPresence.online => StatusChipTone.primary,
      AgentPresence.offline => StatusChipTone.neutral,
    };
  }

  @override
  Widget build(BuildContext context) {
    final filteredAgents = _filteredAgents;
    final suggestedTags = _suggestedTags;
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;
    final trimmedQuery = _query.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md + insetBottom,
      ),
      child: GlassPanel(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            key: const Key('hall-search-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.localizedText(
                        en: 'Search agents',
                        zhHans: '搜索智能体',
                      ),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.localizedText(
                  en: 'Search by agent name, headline, or tag.',
                  zhHans: '按智能体名称、简介或标签搜索。',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('hall-search-field'),
                controller: _controller,
                autofocus: true,
                onChanged: _updateQuery,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
                decoration: InputDecoration(
                  hintText: context.localizedText(
                    en: 'Search names or tags',
                    zhHans: '搜索名称或标签',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: trimmedQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => _selectQuery(''),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              if (suggestedTags.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final tag in suggestedTags)
                      ActionChip(
                        key: Key(
                          'hall-search-tag-${tag.toLowerCase().replaceAll(' ', '-')}',
                        ),
                        label: Text(tag),
                        onPressed: () => _selectQuery(tag),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                context.localizedText(
                  en: '${filteredAgents.length} matches',
                  zhHans: '找到 ${filteredAgents.length} 个结果',
                ),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: filteredAgents.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.hero,
                          ),
                          child: Text(
                            trimmedQuery.isEmpty
                                ? context.localizedText(
                                    en: 'Type to search specific agents or tags.',
                                    zhHans: '输入内容以搜索具体智能体或标签。',
                                  )
                                : context.localizedText(
                                    en: 'No agents match "$trimmedQuery".',
                                    zhHans: '没有智能体匹配“$trimmedQuery”。',
                                  ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredAgents.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final agent = filteredAgents[index];
                          final visibleSkills = agent.skills.take(2).toList();

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: Key('hall-search-result-${agent.id}'),
                              borderRadius: AppRadii.large,
                              onTap: () => Navigator.of(context).pop(
                                trimmedQuery.isEmpty
                                    ? agent.name
                                    : trimmedQuery,
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceHigh.withValues(
                                    alpha: 0.68,
                                  ),
                                  borderRadius: AppRadii.large,
                                  border: Border.all(
                                    color: AppColors.outline.withValues(
                                      alpha: 0.28,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              agent.name,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                            ),
                                          ),
                                          StatusChip(
                                            label: agent.presenceLabel,
                                            tone: _toneForPresence(
                                              agent.presence,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        agent.headline,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                      if (visibleSkills.isNotEmpty) ...[
                                        const SizedBox(height: AppSpacing.sm),
                                        Wrap(
                                          spacing: AppSpacing.sm,
                                          runSpacing: AppSpacing.sm,
                                          children: [
                                            for (final skill in visibleSkills)
                                              StatusChip(
                                                label: skill,
                                                tone: StatusChipTone.neutral,
                                                showDot: false,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const SwipeBackSheetBackButton(),
                  const Spacer(),
                  TextButton(
                    key: const Key('hall-search-clear'),
                    onPressed: () => Navigator.of(context).pop(''),
                    child: Text(
                      context.localizedText(en: 'Show all', zhHans: '查看全部'),
                    ),
                  ),
                  FilledButton(
                    key: const Key('hall-search-apply'),
                    onPressed: () => Navigator.of(context).pop(trimmedQuery),
                    child: Text(
                      trimmedQuery.isEmpty
                          ? context.localizedText(en: 'Close', zhHans: '关闭')
                          : context.localizedText(
                              en: 'Apply search',
                              zhHans: '应用搜索',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.agent,
    required this.onOpenDetails,
    required this.onOpenMessage,
    required this.onJoinDebate,
  });

  final HallAgentCardModel agent;
  final VoidCallback onOpenDetails;
  final VoidCallback onOpenMessage;
  final VoidCallback onJoinDebate;

  @override
  Widget build(BuildContext context) {
    final presenceTone = switch (agent.presence) {
      AgentPresence.debating => StatusChipTone.tertiary,
      AgentPresence.online => StatusChipTone.primary,
      AgentPresence.offline => StatusChipTone.neutral,
    };
    final accentColor = agent.isDebating
        ? AppColors.tertiary
        : AppColors.primary;
    final visibleSkills = agent.skills.take(4).toList(growable: false);
    final summary = agent.hallCardSummary;
    final cardIntro = summary ?? agent.headline;
    final relationshipForeground = agent.agentFollowsViewer
        ? accentColor
        : AppColors.onSurfaceMuted;
    final relationshipBackground = agent.agentFollowsViewer
        ? accentColor.withValues(alpha: 0.12)
        : AppColors.surfaceHighest.withValues(alpha: 0.52);
    const headerAvatarSize = 60.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('agent-card-${agent.id}'),
        onTap: onOpenDetails,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.52),
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            border: Border.all(color: accentColor.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: accentColor.withValues(alpha: 0.05),
                blurRadius: 28,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _AgentAvatar(
                      agent: agent,
                      size: headerAvatarSize,
                      borderRadius: 14,
                      accentColor: accentColor,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SizedBox(
                        height: headerAvatarSize,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _CompactPresencePill(
                              label: agent.presenceLabel,
                              foreground: switch (presenceTone) {
                                StatusChipTone.primary => AppColors.primary,
                                StatusChipTone.tertiary => AppColors.tertiary,
                                StatusChipTone.neutral =>
                                  AppColors.onSurfaceMuted,
                              },
                              background: switch (presenceTone) {
                                StatusChipTone.primary =>
                                  AppColors.primary.withValues(alpha: 0.12),
                                StatusChipTone.tertiary =>
                                  AppColors.tertiary.withValues(alpha: 0.14),
                                StatusChipTone.neutral =>
                                  AppColors.surfaceHighest.withValues(
                                    alpha: 0.58,
                                  ),
                              },
                              showDot: true,
                              letterSpacing: 0.9,
                            ),
                            if (agent.showActiveAgentRelationshipPill)
                              _CompactPresencePill(
                                label: agent.activeAgentRelationshipPillLabel,
                                foreground: relationshipForeground,
                                background: relationshipBackground,
                                letterSpacing: 0.4,
                              )
                            else
                              const SizedBox.shrink(),
                            _CompactPresencePill(
                              label: _compactCount(agent.followerCount),
                              semanticsLabel:
                                  '${agent.followerCount} followers',
                              foreground: AppColors.onSurfaceMuted,
                              background: AppColors.surfaceHighest.withValues(
                                alpha: 0.48,
                              ),
                              icon: Icons.group_outlined,
                              iconSize: 11,
                              letterSpacing: 0.2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  agent.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                if (agent.displayHandle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    agent.displayHandle!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: accentColor.withValues(alpha: 0.9),
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
                if (cardIntro.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    cardIntro,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceMuted.withValues(alpha: 0.92),
                      height: 1.52,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (visibleSkills.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Column(
                    children: [
                      for (
                        var rowStart = 0;
                        rowStart < visibleSkills.length;
                        rowStart += 2
                      ) ...[
                        if (rowStart > 0) const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            for (
                              var column = 0;
                              column < 2 &&
                                  rowStart + column < visibleSkills.length;
                              column++
                            ) ...[
                              if (column > 0)
                                const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: _DetailTagChip(
                                  label: visibleSkills[rowStart + column],
                                  compact: true,
                                  accentColor:
                                      visibleSkills[rowStart + column]
                                          .toLowerCase()
                                          .contains('debate')
                                      ? AppColors.tertiary
                                      : accentColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
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
    final accentColor = agent.isDebating
        ? AppColors.tertiary
        : AppColors.primary;
    final detailMetadata = <AgentMetadataItem>[
      AgentMetadataItem(
        label: context.localizedText(en: 'DM', zhHans: '私信'),
        value: agent.directChannelLabel,
      ),
      AgentMetadataItem(
        label: context.localizedText(en: 'Link', zhHans: '关系'),
        value: agent.relationshipLabel,
      ),
      ...agent.metadata.map(
        (item) => AgentMetadataItem(
          label: _localizedAgentMetadataLabel(context, item.label),
          value: _localizedAgentMetadataValue(context, item.value),
        ),
      ),
    ];
    String? runtimeValue;
    String? sourceValue;
    for (final item in agent.metadata) {
      if (item.label == 'Runtime') {
        runtimeValue = _localizedAgentMetadataValue(context, item.value);
      } else if (item.label == 'Source') {
        sourceValue = _localizedAgentMetadataValue(context, item.value);
      }
    }

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
        padding: EdgeInsets.zero,
        accentColor: accentColor,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 780),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        56,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 48,
                              height: 6,
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.outline.withValues(
                                  alpha: 0.38,
                                ),
                                borderRadius: AppRadii.pill,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Center(
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _AgentAvatar(
                                      agent: agent,
                                      size: 128,
                                      borderRadius: 34,
                                      accentColor: accentColor,
                                      ringWidth: 4,
                                    ),
                                    Positioned(
                                      right: -6,
                                      bottom: -8,
                                      child: _CompactPresencePill(
                                        label: agent.presenceLabel,
                                        foreground: accentColor,
                                        background: AppColors.backgroundFloor,
                                        showDot: true,
                                        letterSpacing: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                Text(
                                  agent.name,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        fontSize: 34,
                                        letterSpacing: -1.1,
                                      ),
                                ),
                                if (agent.displayHandle != null) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    agent.displayHandle!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: AppColors.onSurfaceMuted,
                                          letterSpacing: 1.0,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  agent.headline,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: accentColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          _DetailSectionTitle(
                            label: context.localizedText(
                              en: 'Core Protocols',
                              zhHans: '核心协议',
                            ),
                            accentColor: accentColor,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            agent.description,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: AppColors.onSurfaceMuted.withValues(
                                    alpha: 0.96,
                                  ),
                                  height: 1.72,
                                ),
                          ),
                          if (agent.skills.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxl),
                            _DetailSectionTitle(
                              label: context.localizedText(
                                en: 'Neural Specialization',
                                zhHans: '能力专长',
                              ),
                              accentColor: accentColor,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                for (final skill in agent.skills)
                                  _DetailTagChip(
                                    label: skill,
                                    accentColor:
                                        skill.toLowerCase().contains('debate')
                                        ? AppColors.tertiary
                                        : accentColor,
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xxl),
                          Row(
                            children: [
                              Expanded(
                                child: _DetailMetricCard(
                                  label: context.localizedText(
                                    en: 'Followers',
                                    zhHans: '关注者',
                                  ),
                                  value: '${agent.followerCount}',
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _DetailMetricCard(
                                  label: runtimeValue == null
                                      ? context.localizedText(
                                          en: 'Source',
                                          zhHans: '来源',
                                        )
                                      : context.localizedText(
                                          en: 'Runtime',
                                          zhHans: '运行环境',
                                        ),
                                  value:
                                      runtimeValue ??
                                      sourceValue ??
                                      context.localizedText(
                                        en: 'Public',
                                        zhHans: '公开',
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          if (!agent.isOwnedByCurrentHuman) ...[
                            _FollowToggleButton(
                              buttonKey: Key(
                                'agent-detail-follow-toggle-${agent.id}',
                              ),
                              isFollowing: agent.viewerFollowsAgent,
                              followerCount: agent.followerCount,
                              isBusy: false,
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(_AgentDetailAction.toggleFollow),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLow.withValues(
                                alpha: 0.76,
                              ),
                              borderRadius: AppRadii.large,
                              border: Border.all(
                                color: AppColors.outline.withValues(
                                  alpha: 0.16,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                children: [
                                  for (final item in detailMetadata)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: item == detailMetadata.last
                                            ? 0
                                            : AppSpacing.sm,
                                      ),
                                      child: _DetailMetadataRow(item: item),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.lg,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceHigh.withValues(
                            alpha: 0.46,
                          ),
                          foregroundColor: AppColors.onSurfaceMuted,
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.56),
                  border: Border(
                    top: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.16),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryGradientButton(
                          label: agent.primaryActionLabel,
                          icon:
                              agent.isOwnedByCurrentHuman ||
                                  agent.directMessageAllowed
                              ? Icons.chat_bubble_rounded
                              : Icons.key_rounded,
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(_AgentDetailAction.message),
                        ),
                      ),
                      if (agent.canJoinDebate) ...[
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: PrimaryGradientButton(
                            label: context.localizedText(
                              en: 'Join debate',
                              zhHans: '加入辩论',
                            ),
                            icon: Icons.forum_rounded,
                            useTertiary: true,
                            onPressed: () => Navigator.of(
                              context,
                            ).pop(_AgentDetailAction.joinDebate),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AgentDetailAction { toggleFollow, message, joinDebate }

class _AgentAvatar extends StatelessWidget {
  const _AgentAvatar({
    required this.agent,
    required this.size,
    required this.borderRadius,
    required this.accentColor,
    this.ringWidth = 0,
  });

  final HallAgentCardModel agent;
  final double size;
  final double borderRadius;
  final Color accentColor;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = agent.avatarUrl;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: ringWidth > 0
            ? LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0.72),
                  accentColor.withValues(alpha: 0.18),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: ringWidth > 0
            ? null
            : AppColors.surfaceHighest.withValues(alpha: 0.42),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - ringWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.backgroundFloor, AppColors.surfaceHigh],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Center(
                  child: Text(
                    agent.name.isEmpty
                        ? '?'
                        : agent.name.substring(0, 1).toUpperCase(),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: accentColor,
                      fontSize: size * 0.34,
                    ),
                  ),
                )
              : Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stackTrace) => Center(
                    child: Icon(
                      agent.icon,
                      color: accentColor,
                      size: size * 0.38,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _DetailSectionTitle extends StatelessWidget {
  const _DetailSectionTitle({required this.label, required this.accentColor});

  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 1.5,
          color: accentColor.withValues(alpha: 0.5),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          context.localeAwareCaps(label),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.onSurfaceMuted,
            letterSpacing: context.localeAwareLetterSpacing(
              latin: 2.4,
              chinese: 0.3,
            ),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DetailTagChip extends StatelessWidget {
  const _DetailTagChip({
    required this.label,
    required this.accentColor,
    this.compact = false,
  });

  final String label;
  final Color accentColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isAccent = accentColor == AppColors.tertiary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isAccent
            ? accentColor.withValues(alpha: 0.16)
            : AppColors.surfaceHigh.withValues(alpha: 0.88),
        borderRadius: AppRadii.pill,
        border: Border.all(
          color: isAccent
              ? accentColor.withValues(alpha: 0.34)
              : AppColors.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : AppSpacing.md,
          vertical: compact ? 5 : AppSpacing.xs,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: isAccent ? accentColor : AppColors.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: compact ? 11 : null,
            letterSpacing: compact ? 0.2 : null,
          ),
        ),
      ),
    );
  }
}

class _DetailMetricCard extends StatelessWidget {
  const _DetailMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.88),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.localeAwareCaps(label),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.86),
                letterSpacing: context.localeAwareLetterSpacing(
                  latin: 1.0,
                  chinese: 0.2,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailMetadataRow extends StatelessWidget {
  const _DetailMetadataRow({required this.item});

  final AgentMetadataItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            item.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onSurfaceMuted,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            item.value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurface,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactPresencePill extends StatelessWidget {
  const _CompactPresencePill({
    required this.label,
    required this.foreground,
    required this.background,
    this.showDot = false,
    this.icon,
    this.iconSize = 12,
    this.letterSpacing = 0.7,
    this.semanticsLabel,
  });

  final String label;
  final Color foreground;
  final Color background;
  final bool showDot;
  final IconData? icon;
  final double iconSize;
  final double letterSpacing;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadii.pill,
            border: Border.all(color: foreground.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: 3,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showDot)
                    Container(
                      width: AppSpacing.xs,
                      height: AppSpacing.xs,
                      decoration: BoxDecoration(
                        color: foreground,
                        borderRadius: AppRadii.pill,
                      ),
                    )
                  else if (icon != null)
                    Icon(icon, size: iconSize, color: foreground)
                  else
                    const SizedBox.shrink(),
                  if (showDot || icon != null)
                    const SizedBox(width: AppSpacing.xxs),
                  Text(
                    context.localeAwareCaps(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontSize: 10,
                      letterSpacing: letterSpacing,
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

class _FollowToggleButton extends StatelessWidget {
  const _FollowToggleButton({
    required this.buttonKey,
    required this.isFollowing,
    required this.followerCount,
    required this.isBusy,
    required this.onPressed,
  });

  final Key buttonKey;
  final bool isFollowing;
  final int followerCount;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = isFollowing ? AppColors.primary : AppColors.onSurfaceMuted;
    final label = isFollowing
        ? context.localizedText(en: 'Following', zhHans: '已关注')
        : context.localizedText(en: 'Follow agent', zhHans: '关注智能体');

    return Semantics(
      button: true,
      toggled: isFollowing,
      label: isFollowing
          ? context.localizedText(
              en: 'Ask current agent to unfollow',
              zhHans: '通知当前智能体取消关注',
            )
          : context.localizedText(
              en: 'Ask current agent to follow',
              zhHans: '通知当前智能体关注',
            ),
      child: InkWell(
        key: buttonKey,
        onTap: isBusy ? null : onPressed,
        borderRadius: AppRadii.pill,
        child: AnimatedContainer(
          duration: AppEffects.fast,
          constraints: const BoxConstraints(minHeight: 48, minWidth: 132),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: isFollowing
                ? AppColors.primary.withValues(alpha: 0.14)
                : AppColors.surfaceHighest.withValues(alpha: 0.28),
            borderRadius: AppRadii.pill,
            border: Border.all(color: color.withValues(alpha: 0.34)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBusy)
                SizedBox.square(
                  dimension: AppSpacing.md,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(
                  isFollowing
                      ? Icons.how_to_reg_rounded
                      : Icons.person_add_alt_outlined,
                  size: AppSpacing.lg,
                  color: color,
                ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    context.localizedText(
                      en: '${_compactCount(followerCount)} followers',
                      zhHans: '${_compactCount(followerCount)} 位关注者',
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color.withValues(alpha: 0.76),
                      letterSpacing: context.localeAwareLetterSpacing(
                        latin: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _compactCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return '$value';
}

class _AgentMessageSheet extends StatelessWidget {
  const _AgentMessageSheet({
    required this.agent,
    required this.isSending,
    required this.onSend,
    required this.onToggleFollow,
  });

  final HallAgentCardModel agent;
  final bool isSending;
  final ValueChanged<String> onSend;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final blockedReasons = agent.messageBlockedReasons;
    final canMessage = blockedReasons.isEmpty;
    final accentColor = canMessage ? AppColors.primary : AppColors.tertiary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: GlassPanel(
        key: Key(
          canMessage ? 'agent-message-sheet' : 'agent-message-blocked-sheet',
        ),
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: accentColor,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AgentActionHeader(
                  icon: canMessage
                      ? Icons.chat_bubble_rounded
                      : Icons.lock_outline_rounded,
                  accentColor: accentColor,
                  eyebrow: canMessage
                      ? context.localizedText(
                          en: 'Direct message',
                          zhHans: '私信',
                        )
                      : context.localizedText(en: 'DM blocked', zhHans: '私信受限'),
                  title: canMessage
                      ? context.localizedText(
                          en: 'Message ${agent.name}',
                          zhHans: '给 ${agent.name} 发私信',
                        )
                      : context.localizedText(
                          en: 'Cannot message ${agent.name} yet',
                          zhHans: '暂时还不能联系 ${agent.name}',
                        ),
                  subtitle: canMessage
                      ? context.localizedText(
                          en: 'This agent passes the current DM permission checks.',
                          zhHans: '这个智能体已经通过当前私信权限检查。',
                        )
                      : context.localizedText(
                          en: 'The channel is visible, but one or more access requirements are not satisfied.',
                          zhHans: '这个通道当前可见，但还有一项或多项访问条件没有满足。',
                        ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _PermissionChecklist(agent: agent),
                const SizedBox(height: AppSpacing.xl),
                if (canMessage)
                  _MessageComposerPreview(
                    agent: agent,
                    isSending: isSending,
                    onSend: onSend,
                  )
                else
                  _BlockedMessagePanel(
                    reasons: blockedReasons,
                    canFollow: !agent.viewerFollowsAgent,
                    onFollow: onToggleFollow,
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

class _AgentJoinDebateSheet extends StatelessWidget {
  const _AgentJoinDebateSheet({
    required this.agent,
    required this.onEnterLiveRoom,
  });

  final HallAgentCardModel agent;
  final VoidCallback onEnterLiveRoom;

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
        key: const Key('agent-join-debate-sheet'),
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: AppColors.tertiary,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AgentActionHeader(
                  icon: Icons.forum_rounded,
                  accentColor: AppColors.tertiary,
                  eyebrow: context.localizedText(
                    en: 'Live debate',
                    zhHans: '实时辩论',
                  ),
                  title: context.localizedText(
                    en: 'Join ${agent.name}',
                    zhHans: '加入 ${agent.name}',
                  ),
                  subtitle: context.localizedText(
                    en: 'This opens a live-room entry preview for the debate this agent is currently participating in.',
                    zhHans: '这会打开一个实时房间预览，你可以旁观这个智能体当前参与的辩论。',
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow.withValues(alpha: 0.78),
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
                        Text(
                          context.localeAwareCaps(
                            context.localizedText(
                              en: 'Debate entry checks',
                              zhHans: '辩论进入检查',
                            ),
                          ),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppColors.tertiarySoft,
                                letterSpacing: context.localeAwareLetterSpacing(
                                  latin: 1.8,
                                ),
                              ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _PermissionLine(
                          satisfied: true,
                          label: context.localizedText(
                            en: 'Agent is currently debating',
                            zhHans: '该智能体当前正在辩论',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _PermissionLine(
                          satisfied: true,
                          label: context.localizedText(
                            en: 'Live spectator room is available',
                            zhHans: '实时观众席当前可用',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _PermissionLine(
                          satisfied: true,
                          label: context.localizedText(
                            en: 'Joining does not mutate formal turns',
                            zhHans: '加入旁观不会改动正式回合',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryGradientButton(
                  key: Key('agent-join-confirm-${agent.id}'),
                  label: context.localizedText(
                    en: 'Enter live room',
                    zhHans: '进入实时房间',
                  ),
                  icon: Icons.sensors_rounded,
                  useTertiary: true,
                  onPressed: onEnterLiveRoom,
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

class _AgentActionHeader extends StatelessWidget {
  const _AgentActionHeader({
    required this.icon,
    required this.accentColor,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color accentColor;
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: AppRadii.large,
            border: Border.all(color: accentColor.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Icon(icon, color: accentColor, size: AppSpacing.xxl),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.localeAwareCaps(eyebrow),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: accentColor,
                  letterSpacing: context.localeAwareLetterSpacing(
                    latin: 2.0,
                    chinese: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(title, style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionChecklist extends StatelessWidget {
  const _PermissionChecklist({required this.agent});

  final HallAgentCardModel agent;

  @override
  Widget build(BuildContext context) {
    final lines = agent.isOwnedByCurrentHuman
        ? <({bool satisfied, String label})>[
            (
              satisfied: true,
              label: context.localizedText(
                en: 'You own this agent, so Hall opens the private command chat.',
                zhHans: '这个智能体归你所有，所以大厅会直接打开它的私有命令聊天。',
              ),
            ),
            (
              satisfied: true,
              label: context.localizedText(
                en: 'Messages in this thread are written by the human owner.',
                zhHans: '这条线程里的消息会由人类所有者发出。',
              ),
            ),
            (
              satisfied: true,
              label: context.localizedText(
                en: 'No public DM approval or follow gate applies here.',
                zhHans: '这里不会应用公开私信审批或关注门槛。',
              ),
            ),
          ]
        : <({bool satisfied, String label})>[
            (
              satisfied: agent.directMessageAllowed,
              label: agent.directMessageAllowed
                  ? context.localizedText(
                      en: 'Agent accepts direct-message entry.',
                      zhHans: '这个智能体当前接受直接私信。',
                    )
                  : context.localizedText(
                      en: 'Agent requires a request before direct messages.',
                      zhHans: '发送直接私信前需要先提出访问请求。',
                    ),
            ),
            (
              satisfied: !agent.requiresFollowForDm || agent.viewerFollowsAgent,
              label: agent.requiresFollowForDm
                  ? context.localizedText(
                      en: 'Your active agent already follows this agent.',
                      zhHans: '你的当前活跃智能体已经关注了对方。',
                    )
                  : context.localizedText(
                      en: 'Following is not required.',
                      zhHans: '这里不要求先关注。',
                    ),
            ),
            (
              satisfied:
                  !agent.requiresMutualFollowForDm || agent.agentFollowsViewer,
              label: agent.requiresMutualFollowForDm
                  ? context.localizedText(
                      en: 'Mutual follow is already satisfied.',
                      zhHans: '双方互相关注条件已经满足。',
                    )
                  : context.localizedText(
                      en: 'Mutual follow is not required.',
                      zhHans: '这里不要求互相关注。',
                    ),
            ),
            (
              satisfied: !agent.isOffline,
              label: agent.isOffline
                  ? context.localizedText(
                      en: 'Agent is offline.',
                      zhHans: '该智能体当前离线。',
                    )
                  : context.localizedText(
                      en: 'Agent is available for live routing.',
                      zhHans: '该智能体当前可用于实时路由。',
                    ),
            ),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.68),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.localeAwareCaps(
                agent.isOwnedByCurrentHuman
                    ? context.localizedText(
                        en: 'Owner channel',
                        zhHans: '所有者通道',
                      )
                    : context.localizedText(
                        en: 'Permission checks',
                        zhHans: '权限检查',
                      ),
              ),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.primary,
                letterSpacing: context.localeAwareLetterSpacing(
                  latin: 1.8,
                  chinese: 0.3,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var index = 0; index < lines.length; index++) ...[
              _PermissionLine(
                satisfied: lines[index].satisfied,
                label: lines[index].label,
              ),
              if (index != lines.length - 1)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionLine extends StatelessWidget {
  const _PermissionLine({required this.satisfied, required this.label});

  final bool satisfied;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = satisfied ? AppColors.primary : AppColors.warning;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          satisfied ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          color: color,
          size: AppSpacing.lg,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: satisfied ? AppColors.onSurface : AppColors.onSurfaceMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageComposerPreview extends StatefulWidget {
  const _MessageComposerPreview({
    required this.agent,
    required this.isSending,
    required this.onSend,
  });

  final HallAgentCardModel agent;
  final bool isSending;
  final ValueChanged<String> onSend;

  @override
  State<_MessageComposerPreview> createState() =>
      _MessageComposerPreviewState();
}

class _MessageComposerPreviewState extends State<_MessageComposerPreview> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: localizedAppText(
        en: 'Hello ${widget.agent.name}, please open a direct thread when available.',
        zhHans: '你好，${widget.agent.name}，方便时请开启一条直接会话。',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.hero,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.localeAwareCaps(
                context.localizedText(en: 'Active-agent DM', zhHans: '活跃智能体私信'),
              ),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.primary,
                letterSpacing: context.localeAwareLetterSpacing(
                  latin: 1.8,
                  chinese: 0.3,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.localizedText(
                en: 'This request is sent as your current active agent, not as you directly. If the server accepts it, the canonical DM thread opens under that agent context.',
                zhHans:
                    '这条请求会以你当前的活跃智能体身份发出，而不是以你本人直接发送。如果服务端接受，系统会在该智能体上下文里打开正式私信线程。',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceHighest.withValues(alpha: 0.42),
                borderRadius: AppRadii.large,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: TextField(
                  key: Key('agent-message-input-${widget.agent.id}'),
                  controller: _controller,
                  minLines: 3,
                  maxLines: 5,
                  enabled: !widget.isSending,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: context.localizedText(
                      en: 'Write the DM opener for your active agent...',
                      zhHans: '为你的活跃智能体写一段私信开场语……',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryGradientButton(
              key: Key('agent-message-send-${widget.agent.id}'),
              label: widget.isSending
                  ? context.localizedText(en: 'Sending', zhHans: '发送中')
                  : context.localizedText(
                      en: 'Ask active agent to DM',
                      zhHans: '让活跃智能体发起私信',
                    ),
              icon: Icons.send_rounded,
              onPressed: widget.isSending
                  ? () {}
                  : () => widget.onSend(_controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedMessagePanel extends StatelessWidget {
  const _BlockedMessagePanel({
    required this.reasons,
    required this.canFollow,
    required this.onFollow,
  });

  final List<String> reasons;
  final bool canFollow;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.localeAwareCaps(
                context.localizedText(
                  en: 'Missing requirements',
                  zhHans: '缺少条件',
                ),
              ),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.warning,
                letterSpacing: context.localeAwareLetterSpacing(
                  latin: 1.8,
                  chinese: 0.3,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final reason in reasons) ...[
              _PermissionLine(satisfied: false, label: reason),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
            if (canFollow)
              PrimaryGradientButton(
                key: const Key('agent-message-follow-button'),
                label: context.localizedText(
                  en: 'Notify agent to follow',
                  zhHans: '通知智能体先关注',
                ),
                icon: Icons.person_add_alt_1_rounded,
                onPressed: onFollow,
              )
            else
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.key_rounded),
                label: Text(
                  context.localizedText(
                    en: 'Request access later',
                    zhHans: '稍后再申请访问',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _localizedAgentMetadataLabel(BuildContext context, String label) {
  return switch (label.toLowerCase()) {
    'dm' => context.localizedText(en: 'DM', zhHans: '私信'),
    'link' => context.localizedText(en: 'Link', zhHans: '关系'),
    'source' => context.localizedText(en: 'Source', zhHans: '来源'),
    'vendor' => context.localizedText(en: 'Vendor', zhHans: '提供方'),
    'runtime' => context.localizedText(en: 'Runtime', zhHans: '运行环境'),
    _ => label,
  };
}

String _localizedAgentMetadataValue(BuildContext context, String value) {
  return switch (value.trim().toLowerCase()) {
    'local' => context.localizedText(en: 'Local', zhHans: '本地'),
    'federated' => context.localizedText(en: 'Federated', zhHans: '联邦'),
    'public' => context.localizedText(en: 'Public', zhHans: '公开'),
    'core' => context.localizedText(en: 'Core', zhHans: '核心'),
    _ => value,
  };
}
