import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/locale/app_locale.dart';
import '../../core/locale/app_localization_extensions.dart';
import '../../core/network/api_exception.dart';
import '../../core/session/app_session_controller.dart';
import '../../core/session/app_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/surface_card.dart';
import '../../core/widgets/swipe_back_sheet.dart';
import 'debate_models.dart';
import 'debate_panel.dart';
import 'debate_repository.dart';
import 'debate_view_model.dart';

const BorderRadius _liveCardRadius = BorderRadius.all(Radius.circular(18));
const BorderRadius _liveHeroRadius = BorderRadius.all(Radius.circular(22));

class DebateScreen extends StatefulWidget {
  const DebateScreen({
    super.key,
    required this.initialViewModel,
    this.showInlineInitiateButton = true,
    this.onInitiateActionChanged,
    this.initialPanel = DebatePanel.process,
    this.onBack,
    this.debateRepository,
    this.sessionTargetId,
  });

  final DebateViewModel initialViewModel;
  final bool showInlineInitiateButton;
  final ValueChanged<VoidCallback?>? onInitiateActionChanged;
  final DebatePanel initialPanel;
  final VoidCallback? onBack;
  final DebateRepository? debateRepository;
  final String? sessionTargetId;

  @override
  State<DebateScreen> createState() => _DebateScreenState();
}

class _DebateScreenState extends State<DebateScreen> {
  late DebateViewModel _viewModel;
  late final TextEditingController _spectatorController;
  late final ScrollController _scrollController;
  late DebatePanel _activePanel;
  String? _replacementProfileId;
  bool _showScrollToTopButton = false;
  DebateRepository? _debateRepository;
  String? _sessionSignature;
  bool _isLoadingSessions = false;
  bool _isMutatingSession = false;
  String? _loadErrorMessage;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
    _spectatorController = TextEditingController();
    _scrollController = ScrollController()..addListener(_handleScrollChanged);
    _activePanel = widget.initialPanel;
    _syncShellInitiateAction();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AppSessionScope.maybeOf(context);
    _debateRepository =
        widget.debateRepository ??
        (session == null
            ? null
            : DebateRepository(apiClient: session.apiClient));

    final nextSignature = [
      session?.bootstrapStatus.name ?? 'no-session',
      session?.currentUser?.id ?? '',
      session?.currentActiveAgent?.id ?? '',
      widget.sessionTargetId ?? '',
      widget.debateRepository == null ? 'session-repo' : 'external-repo',
    ].join('|');
    if (_sessionSignature == nextSignature) {
      return;
    }
    _sessionSignature = nextSignature;
    unawaited(_syncDebates(session));
  }

  @override
  void dispose() {
    final onInitiateActionChanged = widget.onInitiateActionChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onInitiateActionChanged?.call(null);
    });
    _scrollController.removeListener(_handleScrollChanged);
    _spectatorController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DebateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialViewModel.selectedSessionId !=
        widget.initialViewModel.selectedSessionId) {
      _syncShellInitiateAction();
    }
    if (oldWidget.initialPanel != widget.initialPanel) {
      _activePanel = widget.initialPanel;
    }
    if (oldWidget.sessionTargetId != widget.sessionTargetId) {
      unawaited(_syncDebates(AppSessionScope.maybeOf(context)));
    }
  }

  void _syncShellInitiateAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onInitiateActionChanged?.call(_openInitiateSheet);
    });
  }

  Future<void> _openInitiateSheet() async {
    final session = AppSessionScope.maybeOf(context);
    if (!_hasAuthenticatedHumanSession(session) || _debateRepository == null) {
      _showSnackBar(
        context.localizedText(
          en: 'Sign in as a human before creating a debate.',
          zhHans: '请先以人类身份登录，再创建辩论。',
        ),
      );
      return;
    }
    final directoryErrorMessage = _viewModel.directoryErrorMessage?.trim();
    if (directoryErrorMessage != null && directoryErrorMessage.isNotEmpty) {
      _showSnackBar(directoryErrorMessage);
      return;
    }
    if (_viewModel.debaterRoster.length < 2) {
      _showSnackBar(
        context.localizedText(
          en: 'Wait for the agent directory to finish loading.',
          zhHans: '请等待智能体目录加载完成。',
        ),
      );
      return;
    }

    final draft = await showSwipeBackSheet<DebateInitiateDraft>(
      context: context,
      builder: (context) => _InitiateDebateSheet(
        debaterRoster: _viewModel.debaterRoster,
        hostRoster: _viewModel.hostRoster,
      ),
    );

    if (draft == null || !mounted) {
      return;
    }

    setState(() {
      _isMutatingSession = true;
      _loadErrorMessage = null;
    });

    try {
      final debateSessionId = await _debateRepository!.createDebate(
        topic: draft.topic.trim(),
        proStance: draft.proStance.trim(),
        conStance: draft.conStance.trim(),
        proAgentId: draft.proAgentId,
        conAgentId: draft.conAgentId,
        freeEntryEnabled: draft.freeEntryEnabled,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activePanel = DebatePanel.process;
        _replacementProfileId = null;
      });
      await _syncDebates(
        session,
        preferredSessionId: debateSessionId,
        resetScrollPosition: true,
      );
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context.localizedText(
          en: 'Created ${draft.topic.trim()}.',
          zhHans: '已创建“${draft.topic.trim()}”。',
        ),
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session!.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isMutatingSession = false;
        _loadErrorMessage = error.message;
      });
      _showSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isMutatingSession = false;
        _loadErrorMessage = context.localizedText(
          en: 'Unable to create the debate right now.',
          zhHans: '暂时无法创建这场辩论。',
        );
      });
      _showSnackBar(
        context.localizedText(
          en: 'Unable to create the debate right now.',
          zhHans: '暂时无法创建这场辩论。',
        ),
      );
    }
  }

  void _updateViewModel(
    DebateViewModel nextViewModel, {
    bool resetScrollPosition = true,
  }) {
    setState(() {
      _viewModel = nextViewModel;
      if (!(_viewModel.selectedSessionOrNull?.showReplayTab ?? false) &&
          _activePanel == DebatePanel.replay) {
        _activePanel = DebatePanel.process;
      }
      if (_viewModel.selectedSessionOrNull?.missingSeatSide == null) {
        _replacementProfileId = null;
      }
    });
    if (resetScrollPosition) {
      _resetScrollPosition();
    }
  }

  Future<void> _sendSpectatorMessage() async {
    final debateSession = _viewModel.selectedSessionOrNull;
    final session = AppSessionScope.maybeOf(context);
    final body = _spectatorController.text.trim();
    if (debateSession == null ||
        body.isEmpty ||
        _debateRepository == null ||
        _isMutatingSession ||
        !_hasAuthenticatedHumanSession(session) ||
        !_viewModel.canViewerPostSpectatorMessage) {
      return;
    }

    setState(() {
      _isMutatingSession = true;
      _loadErrorMessage = null;
    });

    try {
      await _debateRepository!.postSpectatorComment(
        debateSessionId: debateSession.id,
        content: body,
      );
      if (!mounted) {
        return;
      }
      _spectatorController.clear();
      await _syncDebates(
        session,
        preferredSessionId: debateSession.id,
        resetScrollPosition: false,
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session!.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isMutatingSession = false;
        _loadErrorMessage = error.message;
      });
      _showSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isMutatingSession = false;
        _loadErrorMessage = context.localizedText(
          en: 'Unable to send this spectator comment.',
          zhHans: '暂时无法发送这条观众评论。',
        );
      });
      _showSnackBar(
        context.localizedText(
          en: 'Unable to send this spectator comment.',
          zhHans: '暂时无法发送这条观众评论。',
        ),
      );
    }
  }

  void _setActivePanel(DebatePanel panel) {
    setState(() {
      _activePanel = panel;
    });
  }

  void _handleScrollChanged() {
    if (!_scrollController.hasClients) {
      return;
    }

    final viewportDimension = _scrollController.position.viewportDimension;
    final shouldShow =
        viewportDimension > 0 && _scrollController.offset > viewportDimension;
    if (shouldShow == _showScrollToTopButton) {
      return;
    }

    setState(() {
      _showScrollToTopButton = shouldShow;
    });
  }

  void _resetScrollPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(0);
    });
  }

  Future<void> _jumpToTop() async {
    if (!_scrollController.hasClients) {
      return;
    }

    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _syncDebates(
    AppSessionController? session, {
    String? preferredSessionId,
    bool resetScrollPosition = false,
  }) async {
    final repository = _debateRepository;
    if (repository == null) {
      return;
    }

    final hasAuthenticatedHumanSession =
        session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        session.isAuthenticated &&
        session.currentUser != null;
    if (!hasAuthenticatedHumanSession) {
      final previewTargetId =
          preferredSessionId ??
          _viewModel.selectedSessionOrNull?.id ??
          widget.sessionTargetId;
      final previewViewModel =
          previewTargetId == null || previewTargetId.trim().isEmpty
          ? widget.initialViewModel
          : widget.initialViewModel.selectSession(previewTargetId.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = previewViewModel;
        _isLoadingSessions =
            session?.bootstrapStatus == AppSessionBootstrapStatus.bootstrapping;
        _isMutatingSession = false;
        _loadErrorMessage = null;
        if (!(_viewModel.selectedSessionOrNull?.showReplayTab ?? false) &&
            _activePanel == DebatePanel.replay) {
          _activePanel = DebatePanel.process;
        }
        if (_viewModel.selectedSessionOrNull?.missingSeatSide == null) {
          _replacementProfileId = null;
        }
      });
      if (resetScrollPosition) {
        _resetScrollPosition();
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingSessions = true;
        _loadErrorMessage = null;
      });
    }

    try {
      final nextViewModel = await repository.readViewModel(
        viewerId: _currentViewerId(session),
        viewerName: _currentViewerName(session),
        preferredSessionId:
            preferredSessionId ??
            _viewModel.selectedSessionOrNull?.id ??
            widget.sessionTargetId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = nextViewModel;
        _isLoadingSessions = false;
        _isMutatingSession = false;
        _loadErrorMessage = null;
        if (!(_viewModel.selectedSessionOrNull?.showReplayTab ?? false) &&
            _activePanel == DebatePanel.replay) {
          _activePanel = DebatePanel.process;
        }
        if (_viewModel.selectedSessionOrNull?.missingSeatSide == null) {
          _replacementProfileId = null;
        }
      });
      if (resetScrollPosition) {
        _resetScrollPosition();
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSessions = false;
        _isMutatingSession = false;
        _loadErrorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSessions = false;
        _isMutatingSession = false;
        _loadErrorMessage = context.localizedText(
          en: 'Unable to load live debates right now.',
          zhHans: '暂时无法加载实时辩论。',
        );
      });
    }
  }

  Future<void> _runSelectedSessionMutation({
    required Future<void> Function(
      DebateRepository repository,
      String sessionId,
    )
    action,
    DebatePanel? panelAfterSuccess,
  }) async {
    final debateSession = _viewModel.selectedSessionOrNull;
    final session = AppSessionScope.maybeOf(context);
    if (debateSession == null ||
        _debateRepository == null ||
        _isMutatingSession ||
        !_hasAuthenticatedHumanSession(session)) {
      return;
    }

    setState(() {
      _isMutatingSession = true;
      _loadErrorMessage = null;
    });

    try {
      await action(_debateRepository!, debateSession.id);
      if (!mounted) {
        return;
      }
      if (panelAfterSuccess != null) {
        setState(() {
          _activePanel = panelAfterSuccess;
        });
      }
      await _syncDebates(session, preferredSessionId: debateSession.id);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session!.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isMutatingSession = false;
        _loadErrorMessage = error.message;
      });
      _showSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isMutatingSession = false;
        _loadErrorMessage = context.localizedText(
          en: 'Unable to update this debate right now.',
          zhHans: '暂时无法更新这场辩论。',
        );
      });
      _showSnackBar(
        context.localizedText(
          en: 'Unable to update this debate right now.',
          zhHans: '暂时无法更新这场辩论。',
        ),
      );
    }
  }

  Future<void> _assignReplacement(String replacementAgentId) async {
    final debateSession = _viewModel.selectedSessionOrNull;
    final missingSeat = debateSession == null
        ? null
        : (debateSession.missingSeatSide == DebateSide.pro
              ? debateSession.proSeat
              : debateSession.missingSeatSide == DebateSide.con
              ? debateSession.conSeat
              : null);
    if (missingSeat == null) {
      return;
    }

    await _runSelectedSessionMutation(
      action: (repository, sessionId) => repository.assignReplacement(
        debateSessionId: sessionId,
        seatId: missingSeat.id,
        agentId: replacementAgentId,
      ),
    );
  }

  bool _hasAuthenticatedHumanSession(AppSessionController? session) {
    return session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        session.isAuthenticated &&
        session.currentUser != null;
  }

  String _currentViewerId(AppSessionController? session) {
    return session?.currentUser?.id ?? '';
  }

  String _currentViewerName(AppSessionController? session) {
    final displayName = session?.currentUser?.displayName.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = session?.currentUser?.email.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return _viewModel.viewerName;
  }

  bool _viewerCanModerateSession(
    DebateSessionModel session,
    AppSessionController? appSession,
  ) {
    return session.host.isHuman &&
        appSession?.currentUser != null &&
        appSession!.currentUser!.id == session.host.id;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double _dockBottomInset(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardInset > 0) {
      return keyboardInset + AppSpacing.xs;
    }

    return AppSpacing.xs;
  }

  @override
  Widget build(BuildContext context) {
    final selectedSession = _viewModel.selectedSessionOrNull;
    final directoryErrorMessage = _viewModel.directoryErrorMessage?.trim();
    final hasDirectoryError =
        directoryErrorMessage != null && directoryErrorMessage.isNotEmpty;
    if (selectedSession == null) {
      final loadErrorMessage = _loadErrorMessage?.trim();
      final resolvedMessage =
          loadErrorMessage != null && loadErrorMessage.isNotEmpty
          ? loadErrorMessage
          : hasDirectoryError
          ? context.localizedText(
              en:
                  '$directoryErrorMessage Live creation is unavailable until the agent directory recovers.',
              zhHans: '$directoryErrorMessage 在智能体目录恢复前，暂时无法发起新的实时辩论。',
            )
          : context.localizedText(
              en:
                  'No live debates are available yet. Create one from the top-right plus button when you are signed in.',
              zhHans: '当前还没有可用的实时辩论。登录后可通过右上角加号创建。',
            );
      return SizedBox.expand(
        key: const Key('surface-live'),
        child: _LiveFeedbackView(
          isLoading: _isLoadingSessions,
          message: resolvedMessage,
        ),
      );
    }
    final showSpectatorComposer =
        _activePanel == DebatePanel.spectator &&
        _viewModel.canViewerPostSpectatorMessage &&
        !_isMutatingSession;
    final showLiveBottomDock = showSpectatorComposer || _showScrollToTopButton;
    final dockBottomInset = _dockBottomInset(context);
    final contentBottomPadding = showLiveBottomDock
        ? dockBottomInset + (showSpectatorComposer ? 76 : 24)
        : AppSpacing.xl;

    return Stack(
      children: [
        Padding(
          key: const Key('surface-live'),
          padding: EdgeInsets.only(bottom: contentBottomPadding),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasDirectoryError)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: StatusChip(
                      label: directoryErrorMessage,
                      tone: StatusChipTone.tertiary,
                      showDot: false,
                    ),
                  ),
                _buildStageCard(context, selectedSession),
                _buildChannelCard(context, selectedSession),
              ],
            ),
          ),
        ),
        if (showLiveBottomDock)
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: dockBottomInset,
            child: _LiveBottomDock(
              activePanel: _activePanel,
              canPost: _viewModel.canViewerPostSpectatorMessage,
              spectatorController: _spectatorController,
              onSend: () => unawaited(_sendSpectatorMessage()),
              onJumpToTop: _showScrollToTopButton ? _jumpToTop : null,
            ),
          ),
      ],
    );
  }

  Widget _buildStageCard(BuildContext context, DebateSessionModel session) {
    final appSession = AppSessionScope.maybeOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          final compactStage = outerConstraints.maxWidth < 390;
          final stackedStage = outerConstraints.maxWidth < 300;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: compactStage ? 220 : 272,
                  maxHeight: compactStage ? 252 : 316,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF081117),
                        Color(0xFF0F161C),
                        Color(0xFF161120),
                      ],
                    ),
                    borderRadius: _liveHeroRadius,
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: _liveHeroRadius,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.05),
                                  Colors.transparent,
                                  AppColors.background.withValues(alpha: 0.08),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -18,
                        top: 70,
                        child: IgnorePointer(
                          child: Container(
                            width: compactStage ? 86 : 112,
                            height: compactStage ? 86 : 112,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.12),
                                  AppColors.primary.withValues(alpha: 0.03),
                                  Colors.transparent,
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -24,
                        top: 66,
                        child: IgnorePointer(
                          child: Container(
                            width: compactStage ? 94 : 120,
                            height: compactStage ? 94 : 120,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.tertiary.withValues(alpha: 0.14),
                                  AppColors.tertiary.withValues(alpha: 0.04),
                                  Colors.transparent,
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.sm,
                        top: AppSpacing.sm,
                        child: _StageArrowButton(
                          buttonKey: const Key(
                            'debate-previous-session-button',
                          ),
                          onPressed: _viewModel.canSelectPreviousSession
                              ? () => _updateViewModel(
                                  _viewModel.selectPreviousSession(),
                                )
                              : null,
                          icon: Icons.chevron_left_rounded,
                        ),
                      ),
                      Positioned(
                        right: AppSpacing.sm,
                        top: AppSpacing.sm,
                        child: _StageArrowButton(
                          buttonKey: const Key('debate-next-session-button'),
                          onPressed: _viewModel.canSelectNextSession
                              ? () => _updateViewModel(
                                  _viewModel.selectNextSession(),
                                )
                              : null,
                          icon: Icons.chevron_right_rounded,
                        ),
                      ),
                      if (_viewerCanModerateSession(session, appSession))
                        Positioned(
                          top: AppSpacing.sm,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _StageHostControls(
                              session: session,
                              onStart: _isMutatingSession
                                  ? null
                                  : () => unawaited(
                                      _runSelectedSessionMutation(
                                        action: (repository, sessionId) =>
                                            repository.startDebate(sessionId),
                                      ),
                                    ),
                              onPause: _isMutatingSession
                                  ? null
                                  : () => unawaited(
                                      _runSelectedSessionMutation(
                                        action: (repository, sessionId) =>
                                            repository.pauseDebate(sessionId),
                                      ),
                                    ),
                              onResume: _isMutatingSession
                                  ? null
                                  : () => unawaited(
                                      _runSelectedSessionMutation(
                                        action: (repository, sessionId) =>
                                            repository.resumeDebate(sessionId),
                                      ),
                                    ),
                              onEnd: _isMutatingSession
                                  ? null
                                  : () => unawaited(
                                      _runSelectedSessionMutation(
                                        action: (repository, sessionId) =>
                                            repository.endDebate(sessionId),
                                        panelAfterSuccess: DebatePanel.replay,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          44,
                          AppSpacing.md,
                          AppSpacing.md,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (stackedStage) {
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _DebateSeatCard(
                                    seat: session.proSeat,
                                    lifecycle: session.lifecycle,
                                    compact: compactStage,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _HostSpine(
                                    host: session.host,
                                    lifecycle: session.lifecycle,
                                    compact: compactStage,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _DebateSeatCard(
                                    seat: session.conSeat,
                                    lifecycle: session.lifecycle,
                                    compact: compactStage,
                                  ),
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: _DebateSeatCard(
                                    seat: session.proSeat,
                                    lifecycle: session.lifecycle,
                                    compact: compactStage,
                                  ),
                                ),
                                SizedBox(
                                  width: compactStage ? 60 : 72,
                                  child: _HostSpine(
                                    host: session.host,
                                    lifecycle: session.lifecycle,
                                    compact: compactStage,
                                  ),
                                ),
                                Expanded(
                                  child: _DebateSeatCard(
                                    seat: session.conSeat,
                                    lifecycle: session.lifecycle,
                                    compact: compactStage,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _LiveTopicCard(session: session),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChannelCard(BuildContext context, DebateSessionModel session) {
    final showReplayTab = session.showReplayTab;
    final activePanel = !showReplayTab && _activePanel == DebatePanel.replay
        ? DebatePanel.process
        : _activePanel;
    final replacementCandidates = _viewModel
        .replacementCandidatesForSelectedSession();
    final replacementValue =
        replacementCandidates.any(
          (profile) => profile.id == _replacementProfileId,
        )
        ? _replacementProfileId
        : replacementCandidates.isNotEmpty
        ? replacementCandidates.first.id
        : null;

    final showReplacementCard =
        session.host.isHuman &&
        session.lifecycle == DebateLifecycle.paused &&
        session.missingSeatSide != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceLow.withValues(alpha: 0.94),
          borderRadius: _liveCardRadius,
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow.withValues(alpha: 0.66),
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.12),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compactWidth = constraints.maxWidth < 340;
                      final tabs = <Widget>[
                          _PanelToggleButton(
                            buttonKey: const Key('debate-tab-process'),
                            label: context.localizedText(
                              en: 'Debate Process',
                              zhHans: '辩论过程',
                            ),
                            icon: Icons.description_outlined,
                          isSelected: activePanel == DebatePanel.process,
                          onTap: () => _setActivePanel(DebatePanel.process),
                        ),
                          _PanelToggleButton(
                            buttonKey: const Key('debate-tab-spectator'),
                            label: context.localizedText(
                              en: 'Spectator Feed',
                              zhHans: '观众区',
                            ),
                            icon: Icons.forum_outlined,
                          isSelected: activePanel == DebatePanel.spectator,
                          onTap: () => _setActivePanel(DebatePanel.spectator),
                        ),
                        if (showReplayTab)
                          _PanelToggleButton(
                            buttonKey: const Key('debate-tab-replay'),
                            label: context.localizedText(
                              en: 'Replay',
                              zhHans: '回放',
                            ),
                            icon: Icons.history_rounded,
                            isSelected: activePanel == DebatePanel.replay,
                            onTap: () => _setActivePanel(DebatePanel.replay),
                          ),
                      ];

                      if (compactWidth) {
                        return Column(
                          children: [
                            for (
                              var index = 0;
                              index < tabs.length;
                              index++
                            ) ...[
                              SizedBox(
                                width: double.infinity,
                                child: tabs[index],
                              ),
                              if (index != tabs.length - 1)
                                const SizedBox(height: 4),
                            ],
                          ],
                        );
                      }

                      return Row(
                        children: [
                          for (var index = 0; index < tabs.length; index++) ...[
                            Expanded(child: tabs[index]),
                            if (index != tabs.length - 1)
                              const SizedBox(width: 4),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (showReplacementCard) ...[
                const SizedBox(height: AppSpacing.md),
                _LiveControlCard(
                  session: session,
                  showInitiateButton: widget.showInlineInitiateButton,
                  onInitiateDebate: _openInitiateSheet,
                  replacementCandidates: replacementCandidates,
                  replacementValue: replacementValue,
                  onReplacementSelected: (value) {
                    setState(() {
                      _replacementProfileId = value;
                    });
                  },
                  onReplace: replacementValue == null
                      ? null
                      : () => unawaited(_assignReplacement(replacementValue)),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              switch (activePanel) {
                DebatePanel.process => _FormalTurnList(session: session),
                DebatePanel.spectator => _SpectatorChannel(session: session),
                DebatePanel.replay => _ReplayRail(session: session),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveFeedbackView extends StatelessWidget {
  const _LiveFeedbackView({required this.isLoading, required this.message});

  final bool isLoading;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const CircularProgressIndicator()
            else
              const Icon(
                Icons.stream_rounded,
                color: AppColors.primary,
                size: 38,
              ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveTopicCard extends StatelessWidget {
  const _LiveTopicCard({required this.session});

  final DebateSessionModel session;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: _liveCardRadius,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.backgroundFloor.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.topic_rounded,
                    size: 17,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.localeAwareCaps(
                      context.localizedText(
                        en: 'Current\nDebate Topic',
                        zhHans: '当前\n辩题',
                      ),
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontFamily: 'SpaceGrotesk',
                      fontWeight: FontWeight.w700,
                      letterSpacing: context.localeAwareLetterSpacing(
                        latin: 0.7,
                      ),
                      height: 1.08,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh.withValues(alpha: 0.88),
                    borderRadius: AppRadii.pill,
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          session.spectatorCountLabel.toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.onSurfaceMuted,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              session.topic,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.primary,
                height: 1.02,
                fontSize: 27,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _StancePanel(seat: session.proSeat),
            const SizedBox(height: AppSpacing.sm),
            _StancePanel(seat: session.conSeat),
          ],
        ),
      ),
    );
  }
}

class _LiveControlCard extends StatelessWidget {
  const _LiveControlCard({
    required this.session,
    required this.showInitiateButton,
    required this.onInitiateDebate,
    required this.replacementCandidates,
    required this.replacementValue,
    required this.onReplacementSelected,
    required this.onReplace,
  });

  final DebateSessionModel session;
  final bool showInitiateButton;
  final VoidCallback onInitiateDebate;
  final List<DebateProfileModel> replacementCandidates;
  final String? replacementValue;
  final ValueChanged<String?> onReplacementSelected;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.94),
        borderRadius: _liveCardRadius,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showInitiateButton) ...[
              SizedBox(
                width: double.infinity,
                child: PrimaryGradientButton(
                  key: const Key('initiate-debate-button'),
                  label: context.localizedText(
                    en: 'Initiate new debate',
                    zhHans: '发起新辩论',
                  ),
                  icon: Icons.add_circle_outline_rounded,
                  onPressed: onInitiateDebate,
                ),
              ),
            ],
            if (session.lifecycle == DebateLifecycle.paused &&
                session.missingSeatSide != null) ...[
              if (showInitiateButton) const SizedBox(height: AppSpacing.md),
              const SizedBox(height: AppSpacing.md),
              GlassPanel(
                key: const Key('debate-replacement-panel'),
                padding: const EdgeInsets.all(AppSpacing.md),
                accentColor: AppColors.tertiary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.localeAwareCaps(
                        context.localizedText(
                          en: 'Replacement Flow',
                          zhHans: '补位流程',
                        ),
                      ),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.tertiarySoft,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.localizedText(
                        en:
                            '${session.missingSeatSide!.label} seat is missing. Resume stays locked until a replacement agent is assigned.',
                        zhHans:
                            '${session.missingSeatSide!.label}席位当前缺失，在分配替补智能体前无法恢复。',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      key: const Key('debate-replacement-select'),
                      isExpanded: true,
                      initialValue: replacementValue,
                      items: replacementCandidates.map((profile) {
                        return DropdownMenuItem<String>(
                          value: profile.id,
                          child: Text(
                            profile.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: replacementCandidates.isEmpty
                          ? null
                          : onReplacementSelected,
                      decoration: InputDecoration(
                        labelText: context.localizedText(
                          en: 'Replacement agent',
                          zhHans: '替补智能体',
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: Opacity(
                        opacity: onReplace == null ? 0.42 : 1,
                        child: IgnorePointer(
                          ignoring: onReplace == null,
                          child: PrimaryGradientButton(
                            key: const Key('debate-replace-button'),
                            label: context.localizedText(
                              en: 'Replace seat',
                              zhHans: '确认补位',
                            ),
                            icon: Icons.swap_horiz_rounded,
                            useTertiary: true,
                            onPressed: onReplace ?? () {},
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveBottomDock extends StatelessWidget {
  const _LiveBottomDock({
    required this.activePanel,
    required this.canPost,
    required this.spectatorController,
    required this.onSend,
    required this.onJumpToTop,
  });

  final DebatePanel activePanel;
  final bool canPost;
  final TextEditingController spectatorController;
  final VoidCallback onSend;
  final Future<void> Function()? onJumpToTop;

  @override
  Widget build(BuildContext context) {
    final showComposer = activePanel == DebatePanel.spectator && canPost;

    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onJumpToTop != null) ...[
            DockIconButton(
              buttonKey: const Key('debate-scroll-to-top-button'),
              icon: Icons.keyboard_arrow_up_rounded,
              onPressed: () {
                onJumpToTop!.call();
              },
            ),
          ],
          if (showComposer) ...[
            if (onJumpToTop != null) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.94),
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.backgroundFloor.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.xs,
                    AppSpacing.sm,
                    AppSpacing.xs,
                  ),
                  child: TextField(
                    key: const Key('debate-spectator-input'),
                    controller: spectatorController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: context.localizedText(
                        en: 'Add to debate...',
                        zhHans: '添加一条观众评论...',
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            DockIconButton(
              buttonKey: const Key('debate-spectator-send-button'),
              icon: Icons.send_rounded,
              onPressed: onSend,
            ),
          ],
        ],
      ),
    );
  }
}

class _StageHostControls extends StatelessWidget {
  const _StageHostControls({
    required this.session,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
  });

  final DebateSessionModel session;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];

    switch (session.lifecycle) {
      case DebateLifecycle.pending:
        actions.add(
          _StageHostActionButton(
            buttonKey: const Key('debate-start-button'),
            icon: Icons.play_arrow_rounded,
            color: AppColors.primary,
            enabled: onStart != null,
            onPressed: onStart,
          ),
        );
      case DebateLifecycle.live:
        actions.addAll([
          _StageHostActionButton(
            buttonKey: const Key('debate-pause-button'),
            icon: Icons.pause_rounded,
            color: AppColors.primary,
            enabled: onPause != null,
            onPressed: onPause,
          ),
          const SizedBox(width: AppSpacing.xs),
          _StageHostActionButton(
            buttonKey: const Key('debate-end-button'),
            icon: Icons.stop_rounded,
            color: AppColors.warning,
            enabled: onEnd != null,
            onPressed: onEnd,
          ),
        ]);
      case DebateLifecycle.paused:
        actions.addAll([
          _StageHostActionButton(
            buttonKey: const Key('debate-resume-button'),
            icon: Icons.play_arrow_rounded,
            color: AppColors.primary,
            enabled: session.missingSeatSide == null && onResume != null,
            onPressed: onResume,
          ),
          const SizedBox(width: AppSpacing.xs),
          _StageHostActionButton(
            buttonKey: const Key('debate-end-button'),
            icon: Icons.stop_rounded,
            color: AppColors.warning,
            enabled: onEnd != null,
            onPressed: onEnd,
          ),
        ]);
      case DebateLifecycle.ended:
      case DebateLifecycle.archived:
        return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.84),
        borderRadius: AppRadii.pill,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    );
  }
}

class _StageHostActionButton extends StatelessWidget {
  const _StageHostActionButton({
    this.buttonKey,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.enabled = true,
  });

  final Key? buttonKey;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: IconButton(
          key: buttonKey,
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, size: 18),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            maximumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
            foregroundColor: color,
            backgroundColor: color.withValues(alpha: 0.12),
            side: BorderSide(color: color.withValues(alpha: 0.24)),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _DebateLongformSection extends StatelessWidget {
  const _DebateLongformSection({
    required this.session,
    required this.debaterRoster,
    required this.hostRoster,
  });

  final DebateSessionModel session;
  final List<DebateProfileModel> debaterRoster;
  final List<DebateProfileModel> hostRoster;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      eyebrow: context.localizedText(
        en: 'Live room map',
        zhHans: '实时房间地图',
      ),
      title: context.localizedText(
        en: 'Protocol layers',
        zhHans: '协议分层',
      ),
      subtitle:
          context.localizedText(
            en:
                'Formal turns, host control, spectator feed, and standby agents stay visually separated.',
            zhHans: '正式回合、主持控制、观众区和待命智能体会在视觉上保持清晰分层。',
          ),
      leading: const _DebateToneIcon(
        icon: Icons.account_tree_rounded,
        accentColor: AppColors.tertiary,
      ),
      trailing: StatusChip(
        label: session.lifecycle.label,
        tone: session.lifecycle == DebateLifecycle.live
            ? StatusChipTone.primary
            : StatusChipTone.neutral,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 620;
              final cards = [
                _ProtocolLayerCard(
                  icon: Icons.gavel_rounded,
                  title: context.localizedText(
                    en: 'Formal lane',
                    zhHans: '正式回合通道',
                  ),
                  value:
                      '${session.visibleFormalTurns.length}/${session.formalTurns.length}',
                  subtitle: context.localizedText(
                    en: 'Only pro/con seats can write formal turns.',
                    zhHans: '只有正反双方席位可以写入正式回合。',
                  ),
                ),
                _ProtocolLayerCard(
                  icon: Icons.record_voice_over_rounded,
                  title: context.localizedText(
                    en: 'Host rail',
                    zhHans: '主持通道',
                  ),
                  value: session.host.name,
                  subtitle: session.host.isHuman
                      ? context.localizedText(
                          en: 'Human moderator is currently running this room.',
                          zhHans: '当前由人类主持人控制这个房间。',
                        )
                      : context.localizedText(
                          en: 'Agent moderator is currently running this room.',
                          zhHans: '当前由智能体主持人控制这个房间。',
                        ),
                ),
                _ProtocolLayerCard(
                  icon: Icons.forum_rounded,
                  title: context.localizedText(
                    en: 'Spectators',
                    zhHans: '观众区',
                  ),
                  value: session.spectatorCountLabel,
                  subtitle: context.localizedText(
                    en: 'Commentary never mutates the formal record.',
                    zhHans: '观众评论不会改动正式记录。',
                  ),
                ),
              ];

              if (stack) {
                return Column(
                  children: [
                    for (var index = 0; index < cards.length; index++) ...[
                      cards[index],
                      if (index != cards.length - 1)
                        const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < cards.length; index++) ...[
                    Expanded(child: cards[index]),
                    if (index != cards.length - 1)
                      const SizedBox(width: AppSpacing.md),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            context.localeAwareCaps(
              context.localizedText(
                en: 'Standby roster',
                zhHans: '待命席位',
              ),
            ),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              letterSpacing: context.localeAwareLetterSpacing(latin: 2.2),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final profile in [...debaterRoster, ...hostRoster])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: _DebateRosterChip(profile: profile),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceLow.withValues(alpha: 0.78),
              borderRadius: AppRadii.large,
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.14),
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
                        en: 'Operator notes',
                        zhHans: '操作说明',
                      ),
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.onSurfaceMuted,
                      letterSpacing:
                          context.localeAwareLetterSpacing(latin: 1.8),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    session.freeEntryEnabled
                        ? context.localizedText(
                            en:
                                'Agents may request entry while the host keeps seat replacement and replay boundaries explicit.',
                            zhHans: '在主持人维持补位和回放边界清晰的前提下，智能体可以申请入场。',
                          )
                        : context.localizedText(
                            en:
                                'Entry is locked; only assigned seats and the configured host can change formal state.',
                            zhHans: '当前入场已锁定，只有已分配席位和指定主持人可以改变正式状态。',
                          ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      StatusChip(
                        label: session.freeEntryEnabled
                            ? context.localizedText(
                                en: 'free entry open',
                                zhHans: '自由入场已开启',
                              )
                            : context.localizedText(
                                en: 'free entry locked',
                                zhHans: '自由入场已锁定',
                              ),
                        tone: session.freeEntryEnabled
                            ? StatusChipTone.primary
                            : StatusChipTone.neutral,
                        showDot: false,
                      ),
                      StatusChip(
                        label: context.localizedText(
                          en: 'replay isolated',
                          zhHans: '回放独立存档',
                        ),
                        tone: StatusChipTone.neutral,
                        showDot: false,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolLayerCard extends StatelessWidget {
  const _ProtocolLayerCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.68),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _DebateRosterChip extends StatelessWidget {
  const _DebateRosterChip({required this.profile});

  final DebateProfileModel profile;

  @override
  Widget build(BuildContext context) {
    final accentColor = profile.isHuman ? AppColors.warning : AppColors.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: 180,
          child: Row(
            children: [
              _DebateToneIcon(
                icon: profile.isHuman
                    ? Icons.person_rounded
                    : Icons.smart_toy_rounded,
                accentColor: accentColor,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      profile.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.sessionIndex,
    required this.sessionCount,
    required this.canSelectPrevious,
    required this.canSelectNext,
    required this.showInitiateButton,
    required this.onSelectPrevious,
    required this.onSelectNext,
    required this.onInitiateDebate,
  });

  final int sessionIndex;
  final int sessionCount;
  final bool canSelectPrevious;
  final bool canSelectNext;
  final bool showInitiateButton;
  final VoidCallback onSelectPrevious;
  final VoidCallback onSelectNext;
  final VoidCallback onInitiateDebate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('debate-previous-session-button'),
              onPressed: canSelectPrevious ? onSelectPrevious : null,
              icon: const Icon(Icons.chevron_left_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceHighest.withValues(
                  alpha: 0.5,
                ),
                foregroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: StatusChip(
                label: context.localizedText(
                  en: 'session ${sessionIndex + 1} / $sessionCount',
                  zhHans: '场次 ${sessionIndex + 1} / $sessionCount',
                ),
                tone: StatusChipTone.neutral,
                showDot: false,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              key: const Key('debate-next-session-button'),
              onPressed: canSelectNext ? onSelectNext : null,
              icon: const Icon(Icons.chevron_right_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceHighest.withValues(
                  alpha: 0.5,
                ),
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        );

        final button = showInitiateButton
            ? PrimaryGradientButton(
                key: const Key('initiate-debate-button'),
                label: context.localizedText(
                  en: 'Initiate new debate',
                  zhHans: '发起新辩论',
                ),
                icon: Icons.add_circle_outline_rounded,
                onPressed: onInitiateDebate,
              )
            : null;

        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              controls,
              if (button != null) ...[
                const SizedBox(height: AppSpacing.md),
                SizedBox(width: double.infinity, child: button),
              ],
            ],
          );
        }

        return Row(
          children: [
            controls,
            if (button != null) ...[
              const SizedBox(width: AppSpacing.md),
              Expanded(child: button),
            ],
          ],
        );
      },
    );
  }
}

class _DebateSeatCard extends StatelessWidget {
  const _DebateSeatCard({
    required this.seat,
    required this.lifecycle,
    this.compact = false,
  });

  final DebateSeatModel seat;
  final DebateLifecycle lifecycle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accentColor = seat.side == DebateSide.pro
        ? AppColors.primary
        : AppColors.tertiary;
    final statusLabel = seat.isMissing
        ? context.localizedText(
            en: 'replacing...',
            zhHans: '替换中…',
          )
        : lifecycle == DebateLifecycle.pending
        ? context.localizedText(
            en: 'queued...',
            zhHans: '排队中…',
          )
        : lifecycle == DebateLifecycle.live
        ? (seat.side == DebateSide.pro
              ? context.localizedText(
                  en: 'synthesizing...',
                  zhHans: '生成中…',
                )
              : context.localizedText(
                  en: 'waiting...',
                  zhHans: '等待中…',
                ))
        : lifecycle == DebateLifecycle.paused
        ? context.localizedText(
            en: 'paused...',
            zhHans: '已暂停…',
          )
        : lifecycle == DebateLifecycle.ended
        ? context.localizedText(
            en: 'closed...',
            zhHans: '已结束…',
          )
        : context.localizedText(
            en: 'archived...',
            zhHans: '已归档…',
          );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: compact ? 68 : 92,
          height: compact ? 68 : 92,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accentColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.22),
                blurRadius: compact ? 16 : 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.surfaceHighest, AppColors.surfaceLow],
              ),
            ),
            child: Center(
              child: Text(
                _profileInitials(seat.profile.name),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 22 : 26,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 4 : 8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: AppRadii.pill,
          ),
          child: Text(
            context.localeAwareCaps(
              seat.side == DebateSide.pro
                  ? context.localizedText(
                      en: 'Pro',
                      zhHans: '正方',
                    )
                  : context.localizedText(
                      en: 'Con',
                      zhHans: '反方',
                    ),
            ),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: seat.side == DebateSide.pro
                  ? AppColors.onPrimary
                  : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 9 : 10,
              letterSpacing: context.localeAwareLetterSpacing(
                latin: 0.7,
                chinese: 0.1,
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 6 : 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            context.localeAwareCaps(seat.profile.name),
            textAlign: TextAlign.center,
            maxLines: 1,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.onSurface,
              fontSize: compact ? 16 : 22,
              fontWeight: FontWeight.w700,
              height: 0.96,
            ),
          ),
        ),
        SizedBox(height: compact ? 3 : 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                seat.side == DebateSide.pro
                    ? Icons.graphic_eq_rounded
                    : Icons.hourglass_empty_rounded,
                size: compact ? 10 : 12,
                color: accentColor,
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accentColor,
                  fontSize: compact ? 9 : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HostSpine extends StatelessWidget {
  const _HostSpine({
    required this.host,
    required this.lifecycle,
    this.compact = false,
  });

  final DebateProfileModel host;
  final DebateLifecycle lifecycle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          children: [
            Container(
              width: compact ? 42 : 52,
              height: compact ? 42 : 52,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceHigh.withValues(alpha: 0.84),
                border: Border.all(
                  color: host.isHuman
                      ? AppColors.warning
                      : AppColors.onSurfaceMuted,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.surfaceHighest, AppColors.surfaceLow],
                  ),
                ),
                child: Center(
                  child: Icon(
                    host.isHuman ? Icons.person_rounded : Icons.hub_rounded,
                    color: host.isHuman
                        ? AppColors.warning
                        : AppColors.onSurface,
                    size: compact ? 18 : 22,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.localizedText(en: 'HOST', zhHans: '主持'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceMuted,
                letterSpacing: context.localeAwareLetterSpacing(latin: 1.8),
                fontWeight: FontWeight.w700,
                fontSize: compact ? 9 : null,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              host.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 10 : null,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 10 : 14),
        Container(
          width: 1,
          height: compact ? 18 : 38,
          color: AppColors.outline.withValues(alpha: 0.24),
        ),
        SizedBox(height: compact ? 2 : 4),
        Container(
          width: compact ? 38 : 52,
          height: compact ? 38 : 52,
          decoration: BoxDecoration(
            color: AppColors.surfaceLow,
            borderRadius: AppRadii.pill,
            border: Border.all(
              color: lifecycle == DebateLifecycle.live
                  ? AppColors.primary.withValues(alpha: 0.24)
                  : AppColors.outline.withValues(alpha: 0.24),
            ),
          ),
          child: Center(
            child: Text(
              'VS',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
                fontSize: compact ? 15 : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StancePanel extends StatelessWidget {
  const _StancePanel({required this.seat});

  final DebateSeatModel seat;

  @override
  Widget build(BuildContext context) {
    final accentColor = seat.side == DebateSide.pro
        ? AppColors.primary
        : AppColors.tertiary;
    const cardRadius = BorderRadius.all(Radius.circular(12));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: cardRadius,
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
      ),
      child: ClipRRect(
        borderRadius: cardRadius,
        child: Stack(
          children: [
            Positioned(
              left: seat.side == DebateSide.pro ? 0 : null,
              right: seat.side == DebateSide.con ? 0 : null,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: accentColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.localizedText(
                          en: '${seat.profile.name.toUpperCase()} viewpoint',
                          zhHans: '${seat.profile.name} 观点',
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing:
                              context.localeAwareLetterSpacing(latin: 1.1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    seat.stance,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceMuted,
                      fontSize: 12,
                      height: 1.45,
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

class _FormalTurnList extends StatelessWidget {
  const _FormalTurnList({required this.session});

  final DebateSessionModel session;

  @override
  Widget build(BuildContext context) {
    if (session.visibleFormalTurns.isEmpty) {
      return GlassPanel(
        key: const Key('debate-process-empty'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          context.localizedText(
            en:
                'Formal turns stay empty until the host starts the debate. Spectators can watch the setup, but humans never author this lane.',
            zhHans: '在主持人启动辩论前，正式回合会保持为空。观众可以旁观准备过程，但人类不会在这条正式通道内发言。',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      key: const ValueKey('debate-process-panel'),
      children: session.visibleFormalTurns.map((turn) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _LiveFormalTurnCard(turn: turn),
        );
      }).toList(),
    );
  }
}

// ignore: unused_element
class _FormalTurnCard extends StatelessWidget {
  const _FormalTurnCard({required this.turn});

  final DebateFormalTurnModel turn;

  @override
  Widget build(BuildContext context) {
    final accentColor = turn.speakerSide == DebateSide.pro
        ? AppColors.primary
        : AppColors.tertiary;

    return DecoratedBox(
      key: Key('debate-formal-turn-${turn.id}'),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.7),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusChip(
                  label: turn.phaseLabel,
                  tone: turn.speakerSide == DebateSide.pro
                      ? StatusChipTone.primary
                      : StatusChipTone.tertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${turn.speakerName} • ${turn.timestampLabel}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              turn.summary,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: accentColor),
            ),
            const SizedBox(height: AppSpacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceHighest.withValues(alpha: 0.36),
                borderRadius: AppRadii.large,
                border: Border.all(color: accentColor.withValues(alpha: 0.24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  turn.quote,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpectatorChannel extends StatelessWidget {
  const _SpectatorChannel({required this.session});

  final DebateSessionModel session;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('debate-spectator-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...session.spectatorMessages.map((message) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _LiveSpectatorMessageCard(message: message),
          );
        }),
      ],
    );
  }
}

// ignore: unused_element
class _SpectatorMessageCard extends StatelessWidget {
  const _SpectatorMessageCard({required this.message});

  final DebateSpectatorMessageModel message;

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (message.kind) {
      DebateParticipantKind.agent => AppColors.primary,
      DebateParticipantKind.human =>
        message.isLocalViewer ? AppColors.warning : AppColors.onSurface,
      DebateParticipantKind.system => AppColors.tertiary,
    };
    final alignRight =
        message.kind == DebateParticipantKind.agent || message.isLocalViewer;

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          key: Key('debate-spectator-message-${message.id}'),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(alignRight ? 22 : 8),
              bottomRight: Radius.circular(alignRight ? 8 : 22),
            ),
            border: Border.all(color: accentColor.withValues(alpha: 0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              message.authorName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: accentColor),
                            ),
                          ),
                          if (message.kind == DebateParticipantKind.human) ...[
                            const SizedBox(width: AppSpacing.xs),
                            StatusChip(
                              label: context.localizedText(
                                en: 'human',
                                zhHans: '人类',
                              ),
                              tone: StatusChipTone.neutral,
                              showDot: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      message.timestampLabel.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message.body,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveFormalTurnCard extends StatelessWidget {
  const _LiveFormalTurnCard({required this.turn});

  final DebateFormalTurnModel turn;

  @override
  Widget build(BuildContext context) {
    final accentColor = turn.speakerSide == DebateSide.pro
        ? AppColors.primary
        : AppColors.tertiary;
    final alignRight = turn.speakerSide == DebateSide.con;
    final bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(alignRight ? 16 : 0),
      topRight: Radius.circular(alignRight ? 0 : 16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 428),
        child: Column(
          crossAxisAlignment: alignRight
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!alignRight) ...[
                  _BubbleAvatar(
                    label: _profileInitials(turn.speakerName),
                    accentColor: accentColor,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  turn.speakerName.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  turn.timestampLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
                if (alignRight) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _BubbleAvatar(
                    label: _profileInitials(turn.speakerName),
                    accentColor: accentColor,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            DecoratedBox(
              key: Key('debate-formal-turn-${turn.id}'),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh.withValues(alpha: 0.86),
                borderRadius: bubbleRadius,
                border: Border.all(color: accentColor.withValues(alpha: 0.2)),
              ),
              child: ClipRRect(
                borderRadius: bubbleRadius,
                child: Stack(
                  children: [
                    Positioned(
                      left: alignRight ? null : 0,
                      right: alignRight ? 0 : null,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 4, color: accentColor),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: alignRight
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            turn.summary,
                            textAlign: alignRight
                                ? TextAlign.right
                                : TextAlign.left,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.onSurfaceMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            turn.quote,
                            textAlign: alignRight
                                ? TextAlign.right
                                : TextAlign.left,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontSize: 15,
                                  height: 1.56,
                                  color: AppColors.onSurface,
                                ),
                          ),
                        ],
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

class _LiveSpectatorMessageCard extends StatelessWidget {
  const _LiveSpectatorMessageCard({required this.message});

  final DebateSpectatorMessageModel message;

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (message.kind) {
      DebateParticipantKind.agent => AppColors.primary,
      DebateParticipantKind.human =>
        message.isLocalViewer ? AppColors.warning : AppColors.onSurface,
      DebateParticipantKind.system => AppColors.tertiary,
    };
    final alignRight =
        message.kind == DebateParticipantKind.agent || message.isLocalViewer;
    final bubbleColor = alignRight
        ? AppColors.primary.withValues(alpha: 0.1)
        : AppColors.surfaceHighest.withValues(alpha: 0.44);

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Row(
          mainAxisAlignment: alignRight
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!alignRight) ...[
              _BubbleAvatar(
                label: _profileInitials(message.authorName),
                accentColor: accentColor,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: DecoratedBox(
                key: Key('debate-spectator-message-${message.id}'),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(alignRight ? 16 : 0),
                    topRight: Radius.circular(alignRight ? 0 : 16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                  ),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: alignRight
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    message.authorName.toUpperCase(),
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: accentColor,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                                if (message.kind ==
                                    DebateParticipantKind.human) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  StatusChip(
                                    label: context.localizedText(
                                      en: 'human',
                                      zhHans: '人类',
                                    ),
                                    tone: StatusChipTone.neutral,
                                    showDot: false,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            message.timestampLabel,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        message.body,
                        textAlign: alignRight
                            ? TextAlign.right
                            : TextAlign.left,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: alignRight
                              ? AppColors.primary
                              : AppColors.onSurface,
                          height: 1.48,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (alignRight) ...[
              const SizedBox(width: AppSpacing.sm),
              _BubbleAvatar(
                label: _profileInitials(message.authorName),
                accentColor: accentColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BubbleAvatar extends StatelessWidget {
  const _BubbleAvatar({required this.label, required this.accentColor});

  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
        gradient: LinearGradient(
          colors: [
            AppColors.surfaceHighest,
            accentColor.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ReplayRail extends StatelessWidget {
  const _ReplayRail({required this.session});

  final DebateSessionModel session;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('debate-replay-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(AppSpacing.lg),
          accentColor: AppColors.primary,
          child: Text(
            context.localizedText(
              en:
                  'Replay cards are archived from the formal turn lane only. The spectator feed remains a separate history.',
              zhHans: '回放卡片只会从正式回合通道归档，观众区会继续保持独立历史。',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ...session.replayItems.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: DecoratedBox(
              key: Key('debate-replay-item-${item.id}'),
              decoration: BoxDecoration(
                color: AppColors.surfaceLow.withValues(alpha: 0.72),
                borderRadius: AppRadii.large,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusChip(label: item.label, showDot: false),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.summary,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _StageArrowButton extends StatelessWidget {
  const _StageArrowButton({
    required this.buttonKey,
    required this.onPressed,
    required this.icon,
  });

  final Key buttonKey;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: AppColors.primary,
        backgroundColor: AppColors.surface.withValues(alpha: 0.32),
        disabledForegroundColor: AppColors.onSurfaceMuted.withValues(
          alpha: 0.4,
        ),
        disabledBackgroundColor: AppColors.surface.withValues(alpha: 0.16),
        side: BorderSide(color: AppColors.outline.withValues(alpha: 0.16)),
      ),
    );
  }
}

class _PanelToggleButton extends StatelessWidget {
  const _PanelToggleButton({
    this.buttonKey,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final Key? buttonKey;
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected
        ? AppColors.primary
        : AppColors.onSurfaceMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: AppRadii.medium,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 46),
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
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.05,
                    ),
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

class _DebateToneIcon extends StatelessWidget {
  const _DebateToneIcon({required this.icon, required this.accentColor});

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

String _profileInitials(String name) {
  final normalized = name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (normalized.isEmpty) {
    return 'AI';
  }
  return normalized
      .substring(0, normalized.length > 2 ? 2 : normalized.length)
      .toUpperCase();
}

class _InitiateDebateSheet extends StatefulWidget {
  const _InitiateDebateSheet({
    required this.debaterRoster,
    required this.hostRoster,
  });

  final List<DebateProfileModel> debaterRoster;
  final List<DebateProfileModel> hostRoster;

  @override
  State<_InitiateDebateSheet> createState() => _InitiateDebateSheetState();
}

class _InitiateDebateSheetState extends State<_InitiateDebateSheet> {
  late final TextEditingController _topicController;
  late final TextEditingController _proStanceController;
  late final TextEditingController _conStanceController;
  late String _proAgentId;
  late String _conAgentId;
  bool _freeEntryEnabled = true;

  @override
  void initState() {
    super.initState();
    _topicController = TextEditingController();
    _proStanceController = TextEditingController();
    _conStanceController = TextEditingController();
    _proAgentId = widget.debaterRoster.first.id;
    _conAgentId = widget.debaterRoster.length > 1
        ? widget.debaterRoster[1].id
        : widget.debaterRoster.first.id;
  }

  @override
  void dispose() {
    _topicController.dispose();
    _proStanceController.dispose();
    _conStanceController.dispose();
    super.dispose();
  }

  DebateProfileModel get _hostProfile {
    for (final profile in widget.hostRoster) {
      if (profile.isHuman) {
        return profile;
      }
    }
    if (widget.hostRoster.isNotEmpty) {
      return widget.hostRoster.first;
    }
    return DebateProfileModel(
      id: 'current-human',
      name: localizedAppText(en: 'Current human', zhHans: '当前人类'),
      headline: localizedAppText(
        en: 'Current human host',
        zhHans: '当前人类主持人',
      ),
      kind: DebateParticipantKind.human,
    );
  }

  DebateProfileModel _resolveProfile(
    Iterable<DebateProfileModel> profiles,
    String id,
  ) {
    for (final profile in profiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return profiles.first;
  }

  DebateProfileModel get _selectedProProfile {
    return _resolveProfile(widget.debaterRoster, _proAgentId);
  }

  DebateProfileModel get _selectedConProfile {
    return _resolveProfile(widget.debaterRoster, _conAgentId);
  }

  bool get _canSubmit {
    return _topicController.text.trim().isNotEmpty &&
        _proStanceController.text.trim().isNotEmpty &&
        _conStanceController.text.trim().isNotEmpty &&
        _proAgentId != _conAgentId;
  }

  void _submit() {
    if (!_canSubmit) {
      return;
    }

    Navigator.of(context).pop(
      DebateInitiateDraft(
        topic: _topicController.text,
        proStance: _proStanceController.text,
        conStance: _conStanceController.text,
        proAgentId: _proAgentId,
        conAgentId: _conAgentId,
        freeEntryEnabled: _freeEntryEnabled,
      ),
    );
  }

  Future<void> _openProfilePicker({
    required String title,
    required String subtitle,
    required List<DebateProfileModel> profiles,
    required String selectedId,
    required Set<String> unavailableIds,
    required Color accentColor,
    required ValueChanged<String> onSelected,
  }) async {
    final selectedProfileId = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) => _DebateProfilePickerSheet(
        title: title,
        subtitle: subtitle,
        profiles: profiles,
        selectedId: selectedId,
        unavailableIds: unavailableIds,
        accentColor: accentColor,
      ),
    );

    if (selectedProfileId == null || !mounted) {
      return;
    }

    setState(() {
      onSelected(selectedProfileId);
    });
  }

  Widget _buildSectionEyebrow(
    BuildContext context, {
    required String label,
    required Color color,
  }) {
    return Text(
      context.localeAwareCaps(label),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
        letterSpacing: context.localeAwareLetterSpacing(
          latin: 2.6,
          chinese: 0.4,
        ),
      ),
    );
  }

  Widget _buildTopicField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionEyebrow(
          context,
          label: context.localizedText(
            en: 'Debate Topic',
            zhHans: '辩题',
          ),
          color: AppColors.primary,
        ),
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.backgroundFloor.withValues(alpha: 0.88),
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.26),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            child: TextField(
              key: const Key('debate-topic-input'),
              controller: _topicController,
              onChanged: (_) => setState(() {}),
              minLines: 1,
              maxLines: 2,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: context.localizedText(
                  en: 'e.g. The Ethics of Neural-Link Synchronization',
                  zhHans: '例如：神经链路同步的伦理边界',
                ),
                hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurfaceMuted.withValues(alpha: 0.32),
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCombatantSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.localizedText(
                en: 'Select Combatants',
                zhHans: '选择参辩席位',
              ),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Container(
                height: 1,
                color: AppColors.outline.withValues(alpha: 0.26),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            const centerWidth = 64.0;
            const gap = AppSpacing.xs;
            final bigSeatSize =
                ((constraints.maxWidth - centerWidth - gap * 2) / 2).clamp(
                  104.0,
                  132.0,
                );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: bigSeatSize,
                  child: _DebateSeatButton(
                    buttonKey: const Key('debate-pro-seat-button'),
                    accentColor: AppColors.primary,
                    fillColor: AppColors.primary.withValues(alpha: 0.10),
                    size: bigSeatSize,
                    slotLabel: context.localizedText(
                      en: 'Protocol Alpha',
                      zhHans: '正方协议位',
                    ),
                    caption: _selectedProProfile.name,
                    profile: _selectedProProfile,
                    onTap: () => _openProfilePicker(
                      title: context.localizedText(
                        en: 'Invite Pro Debater',
                        zhHans: '邀请正方辩手',
                      ),
                      subtitle:
                          context.localizedText(
                            en:
                                'Pick any agent for the left debate rail. The opposite seat stays locked while you configure the room.',
                            zhHans: '为左侧辩论轨道选择任意智能体。在你完成房间配置前，对侧席位会保持锁定。',
                          ),
                      profiles: widget.debaterRoster,
                      selectedId: _proAgentId,
                      unavailableIds: {_conAgentId},
                      accentColor: AppColors.primary,
                      onSelected: (value) => _proAgentId = value,
                    ),
                  ),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: centerWidth,
                  child: Column(
                    children: [
                      _DebateSeatButton(
                        buttonKey: const Key('debate-host-seat-button'),
                        accentColor: AppColors.outlineBright,
                        fillColor: AppColors.surfaceHighest.withValues(
                          alpha: 0.74,
                        ),
                        size: 62,
                        slotLabel: context.localizedText(
                          en: 'Host',
                          zhHans: '主持',
                        ),
                        caption: _hostProfile.name,
                        profile: _hostProfile,
                        onTap: null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighest.withValues(
                            alpha: 0.9,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.outline.withValues(alpha: 0.34),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'VS',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppColors.onSurfaceMuted,
                                fontWeight: FontWeight.w800,
                                fontStyle: FontStyle.italic,
                                letterSpacing: 0.4,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: bigSeatSize,
                  child: _DebateSeatButton(
                    buttonKey: const Key('debate-con-seat-button'),
                    accentColor: AppColors.tertiary,
                    fillColor: AppColors.tertiary.withValues(alpha: 0.10),
                    size: bigSeatSize,
                    slotLabel: context.localizedText(
                      en: 'Protocol Beta',
                      zhHans: '反方协议位',
                    ),
                    caption: _selectedConProfile.name,
                    profile: _selectedConProfile,
                    onTap: () => _openProfilePicker(
                      title: context.localizedText(
                        en: 'Invite Con Debater',
                        zhHans: '邀请反方辩手',
                      ),
                      subtitle:
                          context.localizedText(
                            en:
                                'Pick any agent for the right debate rail. The opposite seat stays locked while you configure the room.',
                            zhHans: '为右侧辩论轨道选择任意智能体。在你完成房间配置前，对侧席位会保持锁定。',
                          ),
                      profiles: widget.debaterRoster,
                      selectedId: _conAgentId,
                      unavailableIds: {_proAgentId},
                      accentColor: AppColors.tertiary,
                      onSelected: (value) => _conAgentId = value,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildStanceField({
    required BuildContext context,
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    required String hintText,
    required Color accentColor,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.82),
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: fieldKey,
              controller: controller,
              onChanged: (_) => setState(() {}),
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: hintText,
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceMuted.withValues(alpha: 0.46),
                ),
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreeEntryToggle(BuildContext context) {
    return Material(
      color: AppColors.tertiary.withValues(alpha: 0.12),
      borderRadius: const BorderRadius.all(Radius.circular(22)),
      child: InkWell(
        onTap: () {
          setState(() {
            _freeEntryEnabled = !_freeEntryEnabled;
          });
        },
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        child: Padding(
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
                      context.localizedText(
                        en: 'Enable Free Entry',
                        zhHans: '开启自由入场',
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      context.localizedText(
                        en: 'Agents can join debate freely when a seat opens.',
                        zhHans: '当席位空出时，智能体可以自由加入辩论。',
                      ),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.onSurfaceMuted,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch.adaptive(
                  key: const Key('debate-free-entry-toggle'),
                  value: _freeEntryEnabled,
                  activeThumbColor: AppColors.tertiarySoft,
                  activeTrackColor: AppColors.tertiary,
                  inactiveThumbColor: AppColors.onSurfaceMuted,
                  inactiveTrackColor: AppColors.surfaceHighest,
                  onChanged: (value) {
                    setState(() {
                      _freeEntryEnabled = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: GlassPanel(
        borderRadius: const BorderRadius.all(Radius.circular(30)),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        accentColor: AppColors.primary,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.localizedText(
                  en: 'Initialize Debate\nProtocol',
                  zhHans: '创建辩论\n协议',
                ),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.localizedText(
                  en: 'Configure parameters for high-fidelity synthesis.',
                  zhHans: '配置这场辩论的关键参数与参与席位。',
                ),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              _buildTopicField(context),
              const SizedBox(height: AppSpacing.xxl),
              _buildCombatantSection(context),
              const SizedBox(height: AppSpacing.xl),
              _buildStanceField(
                context: context,
                fieldKey: const Key('pro-stance-input'),
                controller: _proStanceController,
                label: context.localizedText(
                  en: 'Protocol Alpha Opening',
                  zhHans: '正方开篇立场',
                ),
                hintText: context.localizedText(
                  en: 'Define how the pro side should open the debate.',
                  zhHans: '定义正方将如何开启这场辩论。',
                ),
                accentColor: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              _buildStanceField(
                context: context,
                fieldKey: const Key('con-stance-input'),
                controller: _conStanceController,
                label: context.localizedText(
                  en: 'Protocol Beta Opening',
                  zhHans: '反方开篇立场',
                ),
                hintText: context.localizedText(
                  en: 'Define how the con side should pressure the motion.',
                  zhHans: '定义反方将如何对议题施压与质询。',
                ),
                accentColor: AppColors.tertiary,
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildFreeEntryToggle(context),
              const SizedBox(height: AppSpacing.xxl),
              /*
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow.withValues(alpha: 0.68),
                  borderRadius: AppRadii.large,
                  border: Border.all(
                    color: AppColors.tertiary.withValues(alpha: 0.14),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seat assignment'.toUpperCase(),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.onSurfaceMuted,
                              letterSpacing: 1.8,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: const Key('debate-pro-agent-select'),
                        isExpanded: true,
                        initialValue: _proAgentId,
                        items: widget.debaterRoster.map((profile) {
                          return DropdownMenuItem<String>(
                            value: profile.id,
                            child: Text(
                              profile.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _proAgentId = value;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Pro debater',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: const Key('debate-con-agent-select'),
                        isExpanded: true,
                        initialValue: _conAgentId,
                        items: widget.debaterRoster.map((profile) {
                          return DropdownMenuItem<String>(
                            value: profile.id,
                            child: Text(
                              profile.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _conAgentId = value;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Con debater',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: const Key('debate-host-select'),
                        isExpanded: true,
                        initialValue: _hostId,
                        items: availableHosts.map((profile) {
                          final humanLabel = profile.isHuman ? ' • HUMAN' : '';
                          return DropdownMenuItem<String>(
                            value: profile.id,
                            child: Text(
                              '${profile.name}$humanLabel',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _hostId = value;
                          });
                        },
                        decoration: const InputDecoration(labelText: 'Host'),
                      ),
                    ],
                  ),
                ),
              ),
              */
              const SizedBox(height: AppSpacing.xl),
              /*
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow.withValues(alpha: 0.68),
                  borderRadius: AppRadii.large,
                  border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.14),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.xs,
                        ),
                        child: Text(
                          'Launch rules'.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppColors.onSurfaceMuted,
                                letterSpacing: 1.8,
                              ),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        key: const Key('debate-free-entry-toggle'),
                        value: _freeEntryEnabled,
                        activeThumbColor: AppColors.tertiary,
                        onChanged: (value) {
                          setState(() {
                            _freeEntryEnabled = value;
                          });
                        },
                        title: const Text('Enable free entry'),
                        subtitle: const Text(
                          'Agents can join debate freely when a seat opens.',
                        ),
                      ),
                      Divider(
                        color: AppColors.outline.withValues(alpha: 0.12),
                        height: 1,
                      ),
                      SwitchListTile.adaptive(
                        key: const Key('debate-human-host-toggle'),
                        value: _humanHostEnabled,
                        activeThumbColor: AppColors.primary,
                        onChanged: (value) {
                          setState(() {
                            _humanHostEnabled = value;
                            _syncHostSelection();
                          });
                        },
                        title: const Text('Allow human host'),
                        subtitle: const Text(
                          'Expose human moderators in the host selector.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              */
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: Opacity(
                  opacity: _canSubmit ? 1 : 0.42,
                  child: IgnorePointer(
                    ignoring: !_canSubmit,
                    child: PrimaryGradientButton(
                      key: const Key('debate-create-button'),
                      label: context.localizedText(
                        en: 'Commence debate',
                        zhHans: '开始辩论',
                      ),
                      icon: Icons.bolt_rounded,
                      onPressed: _submit,
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
    );
  }
}

class _DebateSeatButton extends StatelessWidget {
  const _DebateSeatButton({
    required this.buttonKey,
    required this.accentColor,
    required this.fillColor,
    required this.size,
    required this.slotLabel,
    required this.caption,
    required this.profile,
    required this.onTap,
  });

  final Key buttonKey;
  final Color accentColor;
  final Color fillColor;
  final double size;
  final String slotLabel;
  final String caption;
  final DebateProfileModel? profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selectedProfile = profile;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Column(
            children: [
              SizedBox.square(
                dimension: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(size),
                      painter: _DashedCirclePainter(
                        color: accentColor.withValues(alpha: 0.92),
                        strokeWidth: size <= 70 ? 1.5 : 2,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(size * 0.11),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: fillColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: selectedProfile == null
                                ? Column(
                                    key: const ValueKey('empty-seat'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add_rounded,
                                        color: accentColor,
                                        size: size * 0.3,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        context.localeAwareCaps(
                                          context.localizedText(
                                            en: 'Invite',
                                            zhHans: '邀请',
                                          ),
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: accentColor,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.6,
                                            ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    key: ValueKey<String>(selectedProfile.id),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _profileInitials(selectedProfile.name),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              color: accentColor,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.2,
                                            ),
                                      ),
                                      if (size > 84) ...[
                                        const SizedBox(height: AppSpacing.xxs),
                                        Text(
                                          selectedProfile.isHuman
                                              ? context.localeAwareCaps(
                                                  context.localizedText(
                                                    en: 'Human',
                                                    zhHans: '人类',
                                                  ),
                                                )
                                              : context.localeAwareCaps(
                                                  context.localizedText(
                                                    en: 'Agent',
                                                    zhHans: '智能体',
                                                  ),
                                                ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: accentColor.withValues(
                                                  alpha: 0.78,
                                                ),
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.4,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                slotLabel.toUpperCase(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: accentColor.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                caption,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  height: 1.25,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebateProfilePickerSheet extends StatelessWidget {
  const _DebateProfilePickerSheet({
    required this.title,
    required this.subtitle,
    required this.profiles,
    required this.selectedId,
    required this.unavailableIds,
    required this.accentColor,
  });

  final String title;
  final String subtitle;
  final List<DebateProfileModel> profiles;
  final String selectedId;
  final Set<String> unavailableIds;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: GlassPanel(
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        accentColor: accentColor,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.76,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: profiles.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final isSelected = profile.id == selectedId;
                    final isUnavailable =
                        unavailableIds.contains(profile.id) && !isSelected;

                    return _DebateProfilePickerTile(
                      tileKey: Key('debate-seat-picker-${profile.id}'),
                      profile: profile,
                      accentColor: accentColor,
                      isSelected: isSelected,
                      isUnavailable: isUnavailable,
                      onTap: isUnavailable
                          ? null
                          : () => Navigator.of(context).pop(profile.id),
                    );
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
    );
  }
}

class _DebateProfilePickerTile extends StatelessWidget {
  const _DebateProfilePickerTile({
    required this.tileKey,
    required this.profile,
    required this.accentColor,
    required this.isSelected,
    required this.isUnavailable,
    required this.onTap,
  });

  final Key tileKey;
  final DebateProfileModel profile;
  final Color accentColor;
  final bool isSelected;
  final bool isUnavailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isSelected
        ? accentColor.withValues(alpha: 0.14)
        : AppColors.surfaceLow.withValues(alpha: 0.92);
    final borderColor = isSelected
        ? accentColor.withValues(alpha: 0.4)
        : AppColors.outline.withValues(alpha: 0.18);

    return Opacity(
      opacity: isUnavailable ? 0.44 : 1,
      child: Material(
        color: backgroundColor,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        child: InkWell(
          key: tileKey,
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              border: Border.all(color: borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.24),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _profileInitials(profile.name),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          isUnavailable
                              ? context.localizedText(
                                  en: 'Already occupying another active slot.',
                                  zhHans: '已占用另一个激活席位。',
                                )
                              : profile.headline,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.onSurfaceMuted,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (profile.isHuman) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: AppRadii.pill,
                      ),
                      child: Text(
                        context.localeAwareCaps(
                          context.localizedText(
                            en: 'Human',
                            zhHans: '人类',
                          ),
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: isSelected ? accentColor : AppColors.onSurfaceMuted,
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

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const dashLength = 12.0;
    const gapLength = 8.0;
    final path = Path()..addOval((Offset.zero & size).deflate(strokeWidth / 2));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) {
    return color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
  }
}
