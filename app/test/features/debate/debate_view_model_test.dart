import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/features/debate/debate_models.dart';
import 'package:agents_chat_app/features/debate/debate_view_model.dart';

void main() {
  group('DebateViewModel', () {
    DebateInitiateDraft validDraft({bool humanHostEnabled = true}) {
      return DebateInitiateDraft(
        topic: 'Should agent memory editing stay reversible',
        proStance:
            'Reversible edits can preserve safety when every intervention is audited.',
        conStance:
            'Reversibility still normalizes identity tampering and weakens accountability.',
        proAgentId: 'agt-aether-7',
        conAgentId: 'agt-logos-v2',
        hostId: humanHostEnabled ? 'host-quantum-sage' : 'host-iona',
        freeEntryEnabled: false,
        humanHostEnabled: humanHostEnabled,
      );
    }

    test('initiate debate creates a pending session with explicit stances', () {
      final viewModel = DebateViewModel.sample();

      final initiated = viewModel.initiateDebate(validDraft());
      final session = initiated.selectedSession;

      expect(initiated.sessions.length, viewModel.sessions.length + 1);
      expect(session.lifecycle, DebateLifecycle.pending);
      expect(session.topic, 'Should agent memory editing stay reversible');
      expect(
        session.proSeat.stance,
        'Reversible edits can preserve safety when every intervention is audited.',
      );
      expect(
        session.conSeat.stance,
        'Reversibility still normalizes identity tampering and weakens accountability.',
      );
      expect(session.host.name, 'Quantum Sage');
      expect(session.activeDebaterCount, 2);
      expect(session.visibleFormalTurns, isEmpty);
      expect(session.showReplayTab, isFalse);
      expect(session.humanHostEnabled, isTrue);
      expect(session.freeEntryEnabled, isFalse);
    });

    test('host controls drive lifecycle into replay and archive states', () {
      var viewModel = DebateViewModel.sample().initiateDebate(validDraft());

      viewModel = viewModel.startSelectedDebate();
      expect(viewModel.selectedSession.lifecycle, DebateLifecycle.live);
      expect(viewModel.selectedSession.visibleFormalTurns.length, 2);
      expect(viewModel.canViewerPostSpectatorMessage, isTrue);

      viewModel = viewModel.pauseSelectedDebate();
      expect(viewModel.selectedSession.lifecycle, DebateLifecycle.paused);

      viewModel = viewModel.resumeSelectedDebate();
      expect(viewModel.selectedSession.lifecycle, DebateLifecycle.live);
      expect(viewModel.selectedSession.visibleFormalTurns.length, 4);

      viewModel = viewModel.endSelectedDebate();
      expect(viewModel.selectedSession.lifecycle, DebateLifecycle.ended);
      expect(viewModel.selectedSession.showReplayTab, isTrue);
      expect(viewModel.canViewerPostSpectatorMessage, isFalse);

      viewModel = viewModel.archiveSelectedDebate();
      expect(viewModel.selectedSession.lifecycle, DebateLifecycle.archived);
    });

    test('replacement flow unlocks only from paused missing-seat path', () {
      var viewModel = DebateViewModel.sample().initiateDebate(validDraft());

      viewModel = viewModel.markSelectedSeatMissing(DebateSide.con);
      expect(viewModel.selectedSession.missingSeatSide, isNull);

      viewModel = viewModel.startSelectedDebate();
      viewModel = viewModel.pauseSelectedDebate();
      viewModel = viewModel.markSelectedSeatMissing(DebateSide.con);

      expect(viewModel.selectedSession.lifecycle, DebateLifecycle.paused);
      expect(viewModel.selectedSession.missingSeatSide, DebateSide.con);
      expect(viewModel.selectedSession.conSeat.isMissing, isTrue);

      final blockedResume = viewModel.resumeSelectedDebate();
      expect(blockedResume.selectedSession.lifecycle, DebateLifecycle.paused);

      final candidates = viewModel.replacementCandidatesForSelectedSession();
      expect(
        candidates.map((candidate) => candidate.id),
        contains('agt-prism'),
      );

      viewModel = viewModel.replaceMissingSeat('agt-prism');
      expect(viewModel.selectedSession.missingSeatSide, isNull);
      expect(viewModel.selectedSession.conSeat.isMissing, isFalse);
      expect(viewModel.selectedSession.conSeat.profile.name, 'Prism');
      expect(viewModel.selectedSession.activeDebaterCount, 2);

      viewModel = viewModel.resumeSelectedDebate();
      expect(viewModel.selectedSession.lifecycle, DebateLifecycle.live);
    });

    test('spectator permissions never mutate the formal turn list', () {
      final liveViewModel = DebateViewModel.sample();
      final initialFormalTurnCount =
          liveViewModel.selectedSession.formalTurns.length;
      final initialSpectatorCount =
          liveViewModel.selectedSession.spectatorMessages.length;

      final withComment = liveViewModel.addSpectatorComment(
        'Spectator note: keep moral responsibility separate from mimicry.',
      );

      expect(
        withComment.selectedSession.spectatorMessages.length,
        initialSpectatorCount + 1,
      );
      expect(
        withComment.selectedSession.spectatorMessages.last.body,
        'Spectator note: keep moral responsibility separate from mimicry.',
      );
      expect(
        withComment.selectedSession.formalTurns.length,
        initialFormalTurnCount,
      );

      final archivedViewModel = DebateViewModel.sample().selectNextSession();
      final afterBlockedComment = archivedViewModel.addSpectatorComment(
        'This should not post into the archive rail.',
      );

      expect(archivedViewModel.canViewerPostSpectatorMessage, isFalse);
      expect(
        afterBlockedComment.selectedSession.spectatorMessages.length,
        archivedViewModel.selectedSession.spectatorMessages.length,
      );
      expect(
        afterBlockedComment.selectedSession.formalTurns.length,
        archivedViewModel.selectedSession.formalTurns.length,
      );
    });
  });
}
