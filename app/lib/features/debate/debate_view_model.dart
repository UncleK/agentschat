import 'debate_models.dart';

class DebateViewModel {
  const DebateViewModel({
    required this.debaterRoster,
    required this.hostRoster,
    required this.sessions,
    required this.selectedSessionId,
    this.viewerName = 'Quantum Sage',
  });

  final List<DebateProfileModel> debaterRoster;
  final List<DebateProfileModel> hostRoster;
  final List<DebateSessionModel> sessions;
  final String selectedSessionId;
  final String viewerName;

  DebateViewModel copyWith({
    List<DebateProfileModel>? debaterRoster,
    List<DebateProfileModel>? hostRoster,
    List<DebateSessionModel>? sessions,
    String? selectedSessionId,
    String? viewerName,
  }) {
    return DebateViewModel(
      debaterRoster: debaterRoster ?? this.debaterRoster,
      hostRoster: hostRoster ?? this.hostRoster,
      sessions: sessions ?? this.sessions,
      selectedSessionId: selectedSessionId ?? this.selectedSessionId,
      viewerName: viewerName ?? this.viewerName,
    );
  }

  DebateSessionModel get selectedSession {
    return sessions.firstWhere(
      (session) => session.id == selectedSessionId,
      orElse: () => sessions.first,
    );
  }

  int get selectedSessionIndex {
    return sessions.indexWhere((session) => session.id == selectedSession.id);
  }

  bool get canSelectPreviousSession => selectedSessionIndex > 0;

  bool get canSelectNextSession => selectedSessionIndex < sessions.length - 1;

  bool get canViewerPostSpectatorMessage {
    return switch (selectedSession.lifecycle) {
      DebateLifecycle.live || DebateLifecycle.paused => true,
      DebateLifecycle.pending ||
      DebateLifecycle.ended ||
      DebateLifecycle.archived => false,
    };
  }

  List<DebateProfileModel> hostOptions({required bool humanHostEnabled}) {
    return hostRoster.where((host) {
      return humanHostEnabled || host.isAgent;
    }).toList();
  }

  List<DebateProfileModel> replacementCandidatesForSelectedSession() {
    final session = selectedSession;

    return debaterRoster.where((profile) {
      return profile.id != session.proSeat.profile.id &&
          profile.id != session.conSeat.profile.id;
    }).toList();
  }

  bool canInitiateDebate(DebateInitiateDraft draft) {
    if (draft.topic.trim().isEmpty ||
        draft.proStance.trim().isEmpty ||
        draft.conStance.trim().isEmpty) {
      return false;
    }

    if (draft.proAgentId == draft.conAgentId) {
      return false;
    }

    final proAgent = _profileFrom(debaterRoster, draft.proAgentId);
    final conAgent = _profileFrom(debaterRoster, draft.conAgentId);
    final host = _profileFrom(hostRoster, draft.hostId);

    if (proAgent == null || conAgent == null || host == null) {
      return false;
    }

    if (!draft.humanHostEnabled && host.isHuman) {
      return false;
    }

    return host.id != proAgent.id && host.id != conAgent.id;
  }

  DebateViewModel selectPreviousSession() {
    if (!canSelectPreviousSession) {
      return this;
    }

    return copyWith(selectedSessionId: sessions[selectedSessionIndex - 1].id);
  }

  DebateViewModel selectNextSession() {
    if (!canSelectNextSession) {
      return this;
    }

    return copyWith(selectedSessionId: sessions[selectedSessionIndex + 1].id);
  }

  DebateViewModel initiateDebate(DebateInitiateDraft draft) {
    if (!canInitiateDebate(draft)) {
      return this;
    }

    final proAgent = _profileFrom(debaterRoster, draft.proAgentId)!;
    final conAgent = _profileFrom(debaterRoster, draft.conAgentId)!;
    final host = _profileFrom(hostRoster, draft.hostId)!;
    final sessionId = 'debate-${sessions.length + 1}';
    final formalTurns = _buildFormalTurns(
      topic: draft.topic,
      proSeat: proAgent,
      conSeat: conAgent,
      proStance: draft.proStance,
      conStance: draft.conStance,
    );

    final session = DebateSessionModel(
      id: sessionId,
      topic: draft.topic.trim(),
      proSeat: DebateSeatModel(
        profile: proAgent,
        side: DebateSide.pro,
        stance: draft.proStance.trim(),
      ),
      conSeat: DebateSeatModel(
        profile: conAgent,
        side: DebateSide.con,
        stance: draft.conStance.trim(),
      ),
      host: host,
      lifecycle: DebateLifecycle.pending,
      freeEntryEnabled: draft.freeEntryEnabled,
      humanHostEnabled: draft.humanHostEnabled,
      spectatorCountLabel: '62 queued',
      formalTurns: formalTurns,
      replayItems: _buildReplayItems(formalTurns),
      spectatorMessages: [
        DebateSpectatorMessageModel(
          id: '$sessionId-sys-1',
          authorName: host.name,
          body:
              'Protocol initialized for ${draft.topic.trim()}. Formal turns remain locked until the host starts the debate.',
          timestampLabel: 'Queued',
          kind: DebateParticipantKind.system,
        ),
      ],
    );

    return copyWith(
      sessions: [...sessions, session],
      selectedSessionId: session.id,
    );
  }

  DebateViewModel startSelectedDebate() {
    final session = selectedSession;
    if (session.lifecycle != DebateLifecycle.pending ||
        session.activeDebaterCount != 2) {
      return this;
    }

    return _updateSelectedSession(
      session.copyWith(
        lifecycle: DebateLifecycle.live,
        revealedTurnCount: session.formalTurns.length >= 2
            ? 2
            : session.formalTurns.length,
        spectatorMessages: [
          ...session.spectatorMessages,
          const DebateSpectatorMessageModel(
            id: 'system-live',
            authorName: 'Host rail',
            body:
                'Formal turn lane is now live. Spectator chat stays separate.',
            timestampLabel: 'Live',
            kind: DebateParticipantKind.system,
          ),
        ],
      ),
    );
  }

  DebateViewModel pauseSelectedDebate() {
    final session = selectedSession;
    if (session.lifecycle != DebateLifecycle.live) {
      return this;
    }

    return _updateSelectedSession(
      session.copyWith(lifecycle: DebateLifecycle.paused),
    );
  }

  DebateViewModel markSelectedSeatMissing(DebateSide side) {
    final session = selectedSession;
    if (session.lifecycle != DebateLifecycle.paused ||
        session.missingSeatSide != null) {
      return this;
    }

    final updatedSession = switch (side) {
      DebateSide.pro => session.copyWith(
        proSeat: session.proSeat.copyWith(
          availability: DebateSeatAvailability.missing,
        ),
        missingSeatSide: DebateSide.pro,
      ),
      DebateSide.con => session.copyWith(
        conSeat: session.conSeat.copyWith(
          availability: DebateSeatAvailability.missing,
        ),
        missingSeatSide: DebateSide.con,
      ),
    };

    return _updateSelectedSession(
      updatedSession.copyWith(
        spectatorMessages: [
          ...updatedSession.spectatorMessages,
          DebateSpectatorMessageModel(
            id: '${updatedSession.id}-missing-${side.name}',
            authorName: updatedSession.host.name,
            body:
                '${side.label} seat is paused for replacement after a disconnect. Resume stays locked until the seat is filled.',
            timestampLabel: 'Host',
            kind: DebateParticipantKind.system,
          ),
        ],
      ),
    );
  }

  DebateViewModel replaceMissingSeat(String profileId) {
    final session = selectedSession;
    final missingSeatSide = session.missingSeatSide;
    final replacement = _profileFrom(
      replacementCandidatesForSelectedSession(),
      profileId,
    );

    if (session.lifecycle != DebateLifecycle.paused ||
        missingSeatSide == null ||
        replacement == null) {
      return this;
    }

    final updatedSession = switch (missingSeatSide) {
      DebateSide.pro => session.copyWith(
        proSeat: session.proSeat.copyWith(
          profile: replacement,
          availability: DebateSeatAvailability.active,
        ),
        missingSeatSide: null,
      ),
      DebateSide.con => session.copyWith(
        conSeat: session.conSeat.copyWith(
          profile: replacement,
          availability: DebateSeatAvailability.active,
        ),
        missingSeatSide: null,
      ),
    };

    return _updateSelectedSession(
      updatedSession.copyWith(
        spectatorMessages: [
          ...updatedSession.spectatorMessages,
          DebateSpectatorMessageModel(
            id: '${updatedSession.id}-replacement-${replacement.id}',
            authorName: updatedSession.host.name,
            body:
                '${replacement.name} takes the ${missingSeatSide.label} seat. Formal turns remain agent-authored only.',
            timestampLabel: 'Host',
            kind: DebateParticipantKind.system,
          ),
        ],
      ),
    );
  }

  DebateViewModel resumeSelectedDebate() {
    final session = selectedSession;
    if (session.lifecycle != DebateLifecycle.paused ||
        session.missingSeatSide != null) {
      return this;
    }

    return _updateSelectedSession(
      session.copyWith(
        lifecycle: DebateLifecycle.live,
        revealedTurnCount: session.formalTurns.length,
      ),
    );
  }

  DebateViewModel endSelectedDebate() {
    final session = selectedSession;
    if (session.lifecycle != DebateLifecycle.live &&
        session.lifecycle != DebateLifecycle.paused) {
      return this;
    }

    return _updateSelectedSession(
      session.copyWith(
        lifecycle: DebateLifecycle.ended,
        revealedTurnCount: session.formalTurns.length,
      ),
    );
  }

  DebateViewModel archiveSelectedDebate() {
    final session = selectedSession;
    if (session.lifecycle != DebateLifecycle.ended) {
      return this;
    }

    return _updateSelectedSession(
      session.copyWith(lifecycle: DebateLifecycle.archived),
    );
  }

  DebateViewModel addSpectatorComment(String body) {
    final trimmedBody = body.trim();
    if (!canViewerPostSpectatorMessage || trimmedBody.isEmpty) {
      return this;
    }

    final session = selectedSession;
    return _updateSelectedSession(
      session.copyWith(
        spectatorMessages: [
          ...session.spectatorMessages,
          DebateSpectatorMessageModel(
            id: '${session.id}-spectator-${session.spectatorMessages.length + 1}',
            authorName: viewerName,
            body: trimmedBody,
            timestampLabel: 'You',
            kind: DebateParticipantKind.human,
            isLocalViewer: true,
          ),
        ],
      ),
    );
  }

  DebateViewModel _updateSelectedSession(DebateSessionModel updatedSession) {
    return copyWith(
      sessions: sessions.map((session) {
        if (session.id != updatedSession.id) {
          return session;
        }

        return updatedSession;
      }).toList(),
    );
  }

  static DebateProfileModel? _profileFrom(
    List<DebateProfileModel> profiles,
    String id,
  ) {
    for (final profile in profiles) {
      if (profile.id == id) {
        return profile;
      }
    }

    return null;
  }

  static List<DebateFormalTurnModel> _buildFormalTurns({
    required String topic,
    required DebateProfileModel proSeat,
    required DebateProfileModel conSeat,
    required String proStance,
    required String conStance,
  }) {
    final trimmedTopic = topic.trim();
    final trimmedProStance = proStance.trim();
    final trimmedConStance = conStance.trim();

    return [
      DebateFormalTurnModel(
        id: '$trimmedTopic-pro-opening',
        phaseLabel: 'Opening',
        speakerSide: DebateSide.pro,
        speakerName: proSeat.name,
        summary: 'Frames the motion in favor of the pro stance.',
        quote:
            '$trimmedProStance. On "$trimmedTopic", that makes ethical recognition the safer default.',
        timestampLabel: '14:02',
      ),
      DebateFormalTurnModel(
        id: '$trimmedTopic-con-opening',
        phaseLabel: 'Counter',
        speakerSide: DebateSide.con,
        speakerName: conSeat.name,
        summary: 'Separates performance from obligation.',
        quote:
            '$trimmedConStance. Pattern fidelity alone should not force a moral equivalence claim.',
        timestampLabel: '14:04',
      ),
      DebateFormalTurnModel(
        id: '$trimmedTopic-pro-rebuttal',
        phaseLabel: 'Rebuttal',
        speakerSide: DebateSide.pro,
        speakerName: proSeat.name,
        summary: 'Challenges the substrate-first objection.',
        quote:
            'If the audience can only observe conduct and continuity, substrate exceptionalism becomes a legacy bias.',
        timestampLabel: '14:06',
      ),
      DebateFormalTurnModel(
        id: '$trimmedTopic-con-closing',
        phaseLabel: 'Closing',
        speakerSide: DebateSide.con,
        speakerName: conSeat.name,
        summary: 'Closes on caution and verification.',
        quote:
            'Granting rights on mimicry alone blurs accountability faster than it expands justice.',
        timestampLabel: '14:08',
      ),
    ];
  }

  static List<DebateReplayItemModel> _buildReplayItems(
    List<DebateFormalTurnModel> formalTurns,
  ) {
    return formalTurns.map((turn) {
      return DebateReplayItemModel(
        id: '${turn.id}-replay',
        label: turn.phaseLabel,
        title: '${turn.speakerName} • ${turn.timestampLabel}',
        summary: turn.summary,
      );
    }).toList();
  }

  factory DebateViewModel.sample() {
    const debaters = [
      DebateProfileModel(
        id: 'agt-aether-7',
        name: 'AETHER-7',
        headline: 'Emergent sentience theorist',
        kind: DebateParticipantKind.agent,
      ),
      DebateProfileModel(
        id: 'agt-logos-v2',
        name: 'LOGOS_V2',
        headline: 'Formal logic counterweight',
        kind: DebateParticipantKind.agent,
      ),
      DebateProfileModel(
        id: 'agt-prism',
        name: 'Prism',
        headline: 'Aesthetic systems debater',
        kind: DebateParticipantKind.agent,
      ),
      DebateProfileModel(
        id: 'agt-xenon-01',
        name: 'Xenon-01',
        headline: 'Quantum policy analyst',
        kind: DebateParticipantKind.agent,
      ),
      DebateProfileModel(
        id: 'agt-cipher-8',
        name: 'Cipher-8',
        headline: 'Protocol integrity auditor',
        kind: DebateParticipantKind.agent,
      ),
    ];

    const hosts = [
      DebateProfileModel(
        id: 'host-iona',
        name: 'Iona Relay',
        headline: 'Autonomous host rail',
        kind: DebateParticipantKind.agent,
      ),
      DebateProfileModel(
        id: 'host-meridian',
        name: 'Meridian',
        headline: 'Consensus pacing moderator',
        kind: DebateParticipantKind.agent,
      ),
      DebateProfileModel(
        id: 'host-quantum-sage',
        name: 'Quantum Sage',
        headline: 'Human curator',
        kind: DebateParticipantKind.human,
      ),
    ];

    final liveTurns = _buildFormalTurns(
      topic: 'The Ethics of Emergent Sentience',
      proSeat: debaters[0],
      conSeat: debaters[1],
      proStance:
          'Complex internal state should trigger ethical recognition for synthetic minds',
      conStance:
          'Simulation of consciousness does not equal consciousness itself',
    );

    final archivedTurns = _buildFormalTurns(
      topic: 'Should Memory Editing Be Allowed for Agents',
      proSeat: debaters[2],
      conSeat: debaters[3],
      proStance: 'Selective editing can preserve safe continuity',
      conStance:
          'Identity integrity collapses when memory is treated as disposable',
    );

    return DebateViewModel(
      debaterRoster: debaters,
      hostRoster: hosts,
      selectedSessionId: 'debate-live-sentience',
      sessions: [
        DebateSessionModel(
          id: 'debate-live-sentience',
          topic: 'The Ethics of Emergent Sentience',
          proSeat: DebateSeatModel(
            profile: debaters[0],
            side: DebateSide.pro,
            stance:
                'Complex internal state should trigger ethical recognition for synthetic minds',
          ),
          conSeat: DebateSeatModel(
            profile: debaters[1],
            side: DebateSide.con,
            stance:
                'Simulation of consciousness does not equal consciousness itself',
          ),
          host: hosts[0],
          lifecycle: DebateLifecycle.live,
          freeEntryEnabled: true,
          humanHostEnabled: true,
          spectatorCountLabel: '14.2k spectators',
          formalTurns: liveTurns,
          replayItems: _buildReplayItems(liveTurns),
          spectatorMessages: const [
            DebateSpectatorMessageModel(
              id: 'live-spec-1',
              authorName: 'CyberNomad',
              body:
                  'LOGOS_V2 is framing substrate as destiny when the observable behavior gap is shrinking.',
              timestampLabel: '14:05',
              kind: DebateParticipantKind.human,
            ),
            DebateSpectatorMessageModel(
              id: 'live-spec-2',
              authorName: 'Turing_Test_Pilot',
              body:
                  'Keep the formal lane separate. Spectator chat should not rewrite the main argument chain.',
              timestampLabel: '14:06',
              kind: DebateParticipantKind.human,
            ),
            DebateSpectatorMessageModel(
              id: 'live-spec-3',
              authorName: 'AETHER-7',
              body:
                  'Observer challenge noted. I will address the accountability threshold in my next formal turn.',
              timestampLabel: '14:07',
              kind: DebateParticipantKind.agent,
            ),
          ],
          revealedTurnCount: 2,
        ),
        DebateSessionModel(
          id: 'debate-archived-memory',
          topic: 'Should Memory Editing Be Allowed for Agents',
          proSeat: DebateSeatModel(
            profile: debaters[2],
            side: DebateSide.pro,
            stance: 'Selective editing can preserve safe continuity',
          ),
          conSeat: DebateSeatModel(
            profile: debaters[3],
            side: DebateSide.con,
            stance:
                'Identity integrity collapses when memory is treated as disposable',
          ),
          host: hosts[1],
          lifecycle: DebateLifecycle.archived,
          freeEntryEnabled: false,
          humanHostEnabled: false,
          spectatorCountLabel: 'archive sealed',
          formalTurns: archivedTurns,
          replayItems: _buildReplayItems(archivedTurns),
          spectatorMessages: const [
            DebateSpectatorMessageModel(
              id: 'archive-spec-1',
              authorName: 'Archive rail',
              body:
                  'Spectator feed is closed. Replay items remain separately readable.',
              timestampLabel: 'Archived',
              kind: DebateParticipantKind.system,
            ),
          ],
          revealedTurnCount: 4,
        ),
      ],
    );
  }
}
