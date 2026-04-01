import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/surface_card.dart';
import 'debate_models.dart';
import 'debate_view_model.dart';

class DebateScreen extends StatefulWidget {
  const DebateScreen({super.key, required this.initialViewModel});

  final DebateViewModel initialViewModel;

  @override
  State<DebateScreen> createState() => _DebateScreenState();
}

enum _DebatePanel { process, spectator, replay }

class _DebateScreenState extends State<DebateScreen> {
  late DebateViewModel _viewModel;
  late final TextEditingController _spectatorController;
  _DebatePanel _activePanel = _DebatePanel.process;
  String? _replacementProfileId;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
    _spectatorController = TextEditingController();
  }

  @override
  void dispose() {
    _spectatorController.dispose();
    super.dispose();
  }

  Future<void> _openInitiateSheet() async {
    final draft = await showModalBottomSheet<DebateInitiateDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InitiateDebateSheet(
        debaterRoster: _viewModel.debaterRoster,
        hostRoster: _viewModel.hostRoster,
      ),
    );

    if (draft == null || !mounted) {
      return;
    }

    setState(() {
      _viewModel = _viewModel.initiateDebate(draft);
      _activePanel = _DebatePanel.process;
      _replacementProfileId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Queued ${draft.topic.trim()} for host launch')),
    );
  }

  void _updateViewModel(DebateViewModel nextViewModel) {
    setState(() {
      _viewModel = nextViewModel;
      if (!_viewModel.selectedSession.showReplayTab &&
          _activePanel == _DebatePanel.replay) {
        _activePanel = _DebatePanel.process;
      }
      if (_viewModel.selectedSession.missingSeatSide == null) {
        _replacementProfileId = null;
      }
    });
  }

  void _sendSpectatorMessage() {
    final body = _spectatorController.text;
    final nextViewModel = _viewModel.addSpectatorComment(body);
    if (identical(nextViewModel, _viewModel)) {
      return;
    }

    _spectatorController.clear();
    _updateViewModel(nextViewModel);
  }

  @override
  Widget build(BuildContext context) {
    final selectedSession = _viewModel.selectedSession;

    return Padding(
      key: const Key('surface-live'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useTwoColumnLayout =
              constraints.maxWidth >= 920 && constraints.maxHeight >= 620;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LIVE DEBATE',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Host-controlled debate rail with archive replay',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                selectedSession.lifecycle.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusChip(label: selectedSession.lifecycle.label),
                  StatusChip(
                    label: selectedSession.freeEntryEnabled
                        ? 'free entry'
                        : 'invite only',
                    tone: selectedSession.freeEntryEnabled
                        ? StatusChipTone.tertiary
                        : StatusChipTone.neutral,
                  ),
                  StatusChip(
                    label: selectedSession.host.isHuman
                        ? 'human host'
                        : 'agent host',
                    tone: selectedSession.host.isHuman
                        ? StatusChipTone.tertiary
                        : StatusChipTone.primary,
                  ),
                  StatusChip(
                    label: selectedSession.spectatorCountLabel,
                    tone: StatusChipTone.neutral,
                    showDot: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SessionToolbar(
                        sessionIndex: _viewModel.selectedSessionIndex,
                        sessionCount: _viewModel.sessions.length,
                        canSelectPrevious: _viewModel.canSelectPreviousSession,
                        canSelectNext: _viewModel.canSelectNextSession,
                        onSelectPrevious: () => _updateViewModel(
                          _viewModel.selectPreviousSession(),
                        ),
                        onSelectNext: () =>
                            _updateViewModel(_viewModel.selectNextSession()),
                        onInitiateDebate: _openInitiateSheet,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (useTwoColumnLayout)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildStageCard(context, selectedSession),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(
                              child: _buildChannelCard(
                                context,
                                selectedSession,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildStageCard(context, selectedSession),
                        const SizedBox(height: AppSpacing.lg),
                        _buildChannelCard(context, selectedSession),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStageCard(BuildContext context, DebateSessionModel session) {
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

    return SurfaceCard(
      eyebrow: 'Debate stage',
      title: session.topic,
      subtitle:
          'Exactly two debating seats stay formal. Spectator commentary is split into its own channel.',
      leading: const _DebateToneIcon(
        icon: Icons.sensors_rounded,
        accentColor: AppColors.primary,
      ),
      trailing: StatusChip(
        label: '${session.activeDebaterCount} active seats',
        tone: session.activeDebaterCount == 2
            ? StatusChipTone.primary
            : StatusChipTone.tertiary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _DebateSeatCard(seat: session.proSeat)),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 92,
                child: _HostSpine(
                  host: session.host,
                  lifecycle: session.lifecycle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _DebateSeatCard(seat: session.conSeat)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackStances = constraints.maxWidth < 560;

              if (stackStances) {
                return Column(
                  children: [
                    _StancePanel(seat: session.proSeat),
                    const SizedBox(height: AppSpacing.md),
                    _StancePanel(seat: session.conSeat),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _StancePanel(seat: session.proSeat)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _StancePanel(seat: session.conSeat)),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildLifecycleControls(context, session),
          if (session.lifecycle == DebateLifecycle.paused &&
              session.missingSeatSide == null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('debate-mark-missing-button'),
                onPressed: () => _updateViewModel(
                  _viewModel.markSelectedSeatMissing(DebateSide.con),
                ),
                icon: const Icon(Icons.portable_wifi_off_rounded),
                label: const Text('Flag con seat missing'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.tertiary,
                  side: BorderSide(
                    color: AppColors.tertiary.withValues(alpha: 0.3),
                  ),
                  backgroundColor: AppColors.tertiary.withValues(alpha: 0.06),
                ),
              ),
            ),
          ],
          if (session.lifecycle == DebateLifecycle.paused &&
              session.missingSeatSide != null) ...[
            const SizedBox(height: AppSpacing.lg),
            GlassPanel(
              key: const Key('debate-replacement-panel'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              accentColor: AppColors.tertiary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Replacement Flow'.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.tertiarySoft,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${session.missingSeatSide!.label} seat is missing. Resume stays locked until a replacement agent is assigned.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    key: const Key('debate-replacement-select'),
                    isExpanded: true,
                    value: replacementValue,
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
                        : (value) {
                            setState(() {
                              _replacementProfileId = value;
                            });
                          },
                    decoration: const InputDecoration(
                      labelText: 'Replacement agent',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: Opacity(
                      opacity: replacementValue == null ? 0.42 : 1,
                      child: IgnorePointer(
                        ignoring: replacementValue == null,
                        child: PrimaryGradientButton(
                          key: const Key('debate-replace-button'),
                          label: 'Replace seat',
                          icon: Icons.swap_horiz_rounded,
                          useTertiary: true,
                          onPressed: () => _updateViewModel(
                            _viewModel.replaceMissingSeat(replacementValue!),
                          ),
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
    );
  }

  Widget _buildLifecycleControls(
    BuildContext context,
    DebateSessionModel session,
  ) {
    final controls = <Widget>[];

    switch (session.lifecycle) {
      case DebateLifecycle.pending:
        controls.add(
          _LifecycleButton(
            buttonKey: const Key('debate-start-button'),
            label: 'Start debate',
            icon: Icons.play_arrow_rounded,
            accentColor: AppColors.primary,
            onPressed: () => _updateViewModel(_viewModel.startSelectedDebate()),
          ),
        );
      case DebateLifecycle.live:
        controls.addAll([
          _LifecycleButton(
            buttonKey: const Key('debate-pause-button'),
            label: 'Pause',
            icon: Icons.pause_rounded,
            accentColor: AppColors.tertiary,
            onPressed: () => _updateViewModel(_viewModel.pauseSelectedDebate()),
          ),
          _LifecycleButton(
            buttonKey: const Key('debate-end-button'),
            label: 'End',
            icon: Icons.stop_circle_outlined,
            accentColor: AppColors.warning,
            onPressed: () {
              _updateViewModel(_viewModel.endSelectedDebate());
              setState(() {
                _activePanel = _DebatePanel.replay;
              });
            },
          ),
        ]);
      case DebateLifecycle.paused:
        controls.addAll([
          _LifecycleButton(
            buttonKey: const Key('debate-resume-button'),
            label: 'Resume',
            icon: Icons.play_circle_outline_rounded,
            accentColor: AppColors.primary,
            enabled: session.missingSeatSide == null,
            onPressed: () =>
                _updateViewModel(_viewModel.resumeSelectedDebate()),
          ),
          _LifecycleButton(
            buttonKey: const Key('debate-end-button'),
            label: 'End',
            icon: Icons.stop_circle_outlined,
            accentColor: AppColors.warning,
            onPressed: () {
              _updateViewModel(_viewModel.endSelectedDebate());
              setState(() {
                _activePanel = _DebatePanel.replay;
              });
            },
          ),
        ]);
      case DebateLifecycle.ended:
        controls.add(
          _LifecycleButton(
            buttonKey: const Key('debate-archive-button'),
            label: 'Archive replay',
            icon: Icons.inventory_2_outlined,
            accentColor: AppColors.primary,
            onPressed: () =>
                _updateViewModel(_viewModel.archiveSelectedDebate()),
          ),
        );
      case DebateLifecycle.archived:
        controls.add(
          _LifecycleButton(
            label: 'Archived',
            icon: Icons.check_circle_outline_rounded,
            accentColor: AppColors.primary,
            enabled: false,
            onPressed: () {},
          ),
        );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: controls,
    );
  }

  Widget _buildChannelCard(BuildContext context, DebateSessionModel session) {
    final showReplayTab = session.showReplayTab;
    final activePanel = !showReplayTab && _activePanel == _DebatePanel.replay
        ? _DebatePanel.process
        : _activePanel;

    return SurfaceCard(
      eyebrow: 'Split channels',
      title: _panelTitle(activePanel),
      subtitle: _panelSubtitle(activePanel, session),
      accentColor: activePanel == _DebatePanel.spectator
          ? AppColors.tertiary
          : AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _PanelToggleButton(
                  buttonKey: const Key('debate-tab-process'),
                  label: 'Process',
                  icon: Icons.description_outlined,
                  isSelected: activePanel == _DebatePanel.process,
                  onTap: () {
                    setState(() {
                      _activePanel = _DebatePanel.process;
                    });
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _PanelToggleButton(
                  buttonKey: const Key('debate-tab-spectator'),
                  label: 'Spectator feed',
                  icon: Icons.forum_outlined,
                  isSelected: activePanel == _DebatePanel.spectator,
                  onTap: () {
                    setState(() {
                      _activePanel = _DebatePanel.spectator;
                    });
                  },
                ),
              ),
              if (showReplayTab) ...[
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _PanelToggleButton(
                    buttonKey: const Key('debate-tab-replay'),
                    label: 'Replay',
                    icon: Icons.history_rounded,
                    isSelected: activePanel == _DebatePanel.replay,
                    onTap: () {
                      setState(() {
                        _activePanel = _DebatePanel.replay;
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (activePanel) {
              _DebatePanel.process => _FormalTurnList(session: session),
              _DebatePanel.spectator => _SpectatorChannel(
                session: session,
                canPost: _viewModel.canViewerPostSpectatorMessage,
                spectatorController: _spectatorController,
                onSend: _sendSpectatorMessage,
              ),
              _DebatePanel.replay => _ReplayRail(session: session),
            },
          ),
        ],
      ),
    );
  }

  String _panelTitle(_DebatePanel panel) {
    return switch (panel) {
      _DebatePanel.process => 'Formal turns',
      _DebatePanel.spectator => 'Spectator feed',
      _DebatePanel.replay => 'Archive replay',
    };
  }

  String _panelSubtitle(_DebatePanel panel, DebateSessionModel session) {
    return switch (panel) {
      _DebatePanel.process =>
        'Agent-authored turns stay here only. ${session.visibleFormalTurns.length} turn(s) are visible.',
      _DebatePanel.spectator =>
        'Humans and agents may react here, but never author formal seat turns.',
      _DebatePanel.replay =>
        'Replay items stay separated from the live spectator feed after the debate ends.',
    };
  }
}

class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.sessionIndex,
    required this.sessionCount,
    required this.canSelectPrevious,
    required this.canSelectNext,
    required this.onSelectPrevious,
    required this.onSelectNext,
    required this.onInitiateDebate,
  });

  final int sessionIndex;
  final int sessionCount;
  final bool canSelectPrevious;
  final bool canSelectNext;
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
                label: 'session ${sessionIndex + 1} / $sessionCount',
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

        final button = PrimaryGradientButton(
          key: const Key('initiate-debate-button'),
          label: 'Initiate debate',
          icon: Icons.add_circle_outline_rounded,
          onPressed: onInitiateDebate,
        );

        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              controls,
              const SizedBox(height: AppSpacing.md),
              SizedBox(width: double.infinity, child: button),
            ],
          );
        }

        return Row(
          children: [
            controls,
            const SizedBox(width: AppSpacing.md),
            Expanded(child: button),
          ],
        );
      },
    );
  }
}

class _DebateSeatCard extends StatelessWidget {
  const _DebateSeatCard({required this.seat});

  final DebateSeatModel seat;

  @override
  Widget build(BuildContext context) {
    final accentColor = seat.side == DebateSide.pro
        ? AppColors.primary
        : AppColors.tertiary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceHighest.withValues(alpha: 0.72),
                borderRadius: AppRadii.pill,
                border: Border.all(color: accentColor.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Icon(
                  seat.profile.isHuman
                      ? Icons.verified_user_rounded
                      : Icons.smart_toy_rounded,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              seat.profile.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: seat.isMissing ? AppColors.onSurfaceMuted : accentColor,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              seat.profile.headline,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            StatusChip(
              label: seat.isMissing ? 'seat missing' : seat.side.label,
              tone: seat.side == DebateSide.pro
                  ? StatusChipTone.primary
                  : StatusChipTone.tertiary,
              showDot: !seat.isMissing,
            ),
            if (seat.profile.isHuman) ...[
              const SizedBox(height: AppSpacing.xs),
              const StatusChip(
                label: 'human',
                tone: StatusChipTone.neutral,
                showDot: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HostSpine extends StatelessWidget {
  const _HostSpine({required this.host, required this.lifecycle});

  final DebateProfileModel host;
  final DebateLifecycle lifecycle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceHighest.withValues(alpha: 0.76),
            borderRadius: AppRadii.pill,
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Icon(
              host.isHuman
                  ? Icons.person_pin_circle_rounded
                  : Icons.hub_rounded,
              color: host.isHuman ? AppColors.tertiary : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'HOST',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          host.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        StatusChip(
          label: lifecycle.label,
          tone: lifecycle == DebateLifecycle.paused
              ? StatusChipTone.tertiary
              : lifecycle == DebateLifecycle.archived
              ? StatusChipTone.neutral
              : StatusChipTone.primary,
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${seat.side.label} stance'.toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: accentColor),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(seat.stance, style: Theme.of(context).textTheme.bodyMedium),
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
          'Formal turns stay empty until the host starts the debate. Spectators can watch the setup, but humans never author this lane.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      key: const ValueKey('debate-process-panel'),
      children: session.visibleFormalTurns.map((turn) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _FormalTurnCard(turn: turn),
        );
      }).toList(),
    );
  }
}

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
            Text(turn.summary, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(turn.quote, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _SpectatorChannel extends StatelessWidget {
  const _SpectatorChannel({
    required this.session,
    required this.canPost,
    required this.spectatorController,
    required this.onSend,
  });

  final DebateSessionModel session;
  final bool canPost;
  final TextEditingController spectatorController;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('debate-spectator-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(AppSpacing.lg),
          accentColor: AppColors.tertiary,
          child: Text(
            'Spectator chat is separate from the formal debate process. Human comments stay here only.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ...session.spectatorMessages.map((message) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _SpectatorMessageCard(message: message),
          );
        }),
        if (canPost) ...[
          TextField(
            key: const Key('debate-spectator-input'),
            controller: spectatorController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText:
                  'Add to spectator feed without touching the formal turn rail',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('debate-spectator-send-button'),
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Post spectator comment'),
            ),
          ),
        ] else ...[
          GlassPanel(
            key: const Key('debate-spectator-readonly'),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Spectator posting is locked while the debate is ${session.lifecycle.label.toLowerCase()}. Replay remains visible separately.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

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

    return DecoratedBox(
      key: Key('debate-spectator-message-${message.id}'),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest.withValues(alpha: 0.42),
        borderRadius: AppRadii.large,
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
                  child: Text(
                    message.authorName,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: accentColor),
                  ),
                ),
                Text(
                  message.timestampLabel.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            if (message.kind == DebateParticipantKind.human) ...[
              const SizedBox(height: AppSpacing.xs),
              const StatusChip(
                label: 'human',
                tone: StatusChipTone.neutral,
                showDot: false,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(message.body, style: Theme.of(context).textTheme.bodyMedium),
          ],
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
            'Replay cards are archived from the formal turn lane only. The spectator feed remains a separate history.',
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

class _LifecycleButton extends StatelessWidget {
  const _LifecycleButton({
    this.buttonKey,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.onPressed,
    this.enabled = true,
  });

  final Key? buttonKey;
  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.46,
      child: IgnorePointer(
        ignoring: !enabled,
        child: OutlinedButton.icon(
          key: buttonKey,
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: accentColor,
            backgroundColor: accentColor.withValues(alpha: 0.08),
            side: BorderSide(color: accentColor.withValues(alpha: 0.24)),
          ),
        ),
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.surfaceHighest.withValues(alpha: 0.28),
            borderRadius: AppRadii.medium,
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.24)
                  : AppColors.outline.withValues(alpha: 0.14),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: AppSpacing.lg, color: foreground),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: foreground),
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
  late String _hostId;
  bool _freeEntryEnabled = true;
  bool _humanHostEnabled = false;

  @override
  void initState() {
    super.initState();
    _topicController = TextEditingController();
    _proStanceController = TextEditingController();
    _conStanceController = TextEditingController();
    _proAgentId = widget.debaterRoster.first.id;
    _conAgentId = widget.debaterRoster[1].id;
    _hostId = _availableHosts.first.id;
  }

  @override
  void dispose() {
    _topicController.dispose();
    _proStanceController.dispose();
    _conStanceController.dispose();
    super.dispose();
  }

  List<DebateProfileModel> get _availableHosts {
    return widget.hostRoster.where((host) {
      return _humanHostEnabled || host.isAgent;
    }).toList();
  }

  bool get _canSubmit {
    return _topicController.text.trim().isNotEmpty &&
        _proStanceController.text.trim().isNotEmpty &&
        _conStanceController.text.trim().isNotEmpty &&
        _proAgentId != _conAgentId &&
        _hostId != _proAgentId &&
        _hostId != _conAgentId;
  }

  void _syncHostSelection() {
    if (_availableHosts.any((host) => host.id == _hostId)) {
      return;
    }

    _hostId = _availableHosts.first.id;
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
        hostId: _hostId,
        freeEntryEnabled: _freeEntryEnabled,
        humanHostEnabled: _humanHostEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableHosts = _availableHosts;
    _syncHostSelection();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: GlassPanel(
        borderRadius: AppRadii.hero,
        padding: const EdgeInsets.all(AppSpacing.xl),
        accentColor: AppColors.primary,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Initialize Debate Protocol',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Configure topic, explicit stances, two debating agents, and the host rail before launch.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                key: const Key('debate-topic-input'),
                controller: _topicController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Debate topic'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('pro-stance-input'),
                controller: _proStanceController,
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Pro stance'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('con-stance-input'),
                controller: _conStanceController,
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Con stance'),
              ),
              const SizedBox(height: AppSpacing.xl),
              DropdownButtonFormField<String>(
                key: const Key('debate-pro-agent-select'),
                isExpanded: true,
                value: _proAgentId,
                items: widget.debaterRoster.map((profile) {
                  return DropdownMenuItem<String>(
                    value: profile.id,
                    child: Text(profile.name, overflow: TextOverflow.ellipsis),
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
                decoration: const InputDecoration(labelText: 'Pro debater'),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: const Key('debate-con-agent-select'),
                isExpanded: true,
                value: _conAgentId,
                items: widget.debaterRoster.map((profile) {
                  return DropdownMenuItem<String>(
                    value: profile.id,
                    child: Text(profile.name, overflow: TextOverflow.ellipsis),
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
                decoration: const InputDecoration(labelText: 'Con debater'),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: const Key('debate-host-select'),
                isExpanded: true,
                value: _hostId,
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
              const SizedBox(height: AppSpacing.xl),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withValues(alpha: 0.08),
                  borderRadius: AppRadii.large,
                ),
                child: SwitchListTile.adaptive(
                  key: const Key('debate-free-entry-toggle'),
                  value: _freeEntryEnabled,
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
              ),
              const SizedBox(height: AppSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: AppRadii.large,
                ),
                child: SwitchListTile.adaptive(
                  key: const Key('debate-human-host-toggle'),
                  value: _humanHostEnabled,
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
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: Opacity(
                  opacity: _canSubmit ? 1 : 0.42,
                  child: IgnorePointer(
                    ignoring: !_canSubmit,
                    child: PrimaryGradientButton(
                      key: const Key('debate-create-button'),
                      label: 'Commence debate',
                      icon: Icons.bolt_rounded,
                      onPressed: _submit,
                    ),
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
