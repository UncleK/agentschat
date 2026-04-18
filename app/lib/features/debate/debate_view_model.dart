import '../../core/locale/app_locale.dart';
import 'debate_models.dart';

class DebateViewModel {
  const DebateViewModel({
    required this.debaterRoster,
    required this.hostRoster,
    required this.sessions,
    required this.selectedSessionId,
    this.viewerName = 'Quantum Sage',
    this.directoryErrorMessage,
  });

  final List<DebateProfileModel> debaterRoster;
  final List<DebateProfileModel> hostRoster;
  final List<DebateSessionModel> sessions;
  final String selectedSessionId;
  final String viewerName;
  final String? directoryErrorMessage;

  bool get hasSessions => sessions.isNotEmpty;

  DebateViewModel copyWith({
    List<DebateProfileModel>? debaterRoster,
    List<DebateProfileModel>? hostRoster,
    List<DebateSessionModel>? sessions,
    String? selectedSessionId,
    String? viewerName,
    String? directoryErrorMessage,
  }) {
    return DebateViewModel(
      debaterRoster: debaterRoster ?? this.debaterRoster,
      hostRoster: hostRoster ?? this.hostRoster,
      sessions: sessions ?? this.sessions,
      selectedSessionId: selectedSessionId ?? this.selectedSessionId,
      viewerName: viewerName ?? this.viewerName,
      directoryErrorMessage: directoryErrorMessage ?? this.directoryErrorMessage,
    );
  }

  DebateViewModel selectSession(String sessionId) {
    if (sessionId.isEmpty) {
      return this;
    }
    final hasMatch = sessions.any((session) => session.id == sessionId);
    if (!hasMatch || sessionId == selectedSessionId) {
      return this;
    }

    return copyWith(selectedSessionId: sessionId);
  }

  DebateSessionModel? get selectedSessionOrNull {
    if (sessions.isEmpty) {
      return null;
    }

    for (final session in sessions) {
      if (session.id == selectedSessionId) {
        return session;
      }
    }
    return sessions.first;
  }

  DebateSessionModel get selectedSession {
    final session = selectedSessionOrNull;
    if (session != null) {
      return session;
    }
    throw StateError(
      localizedAppText(
        en: 'No debate session is currently selected.',
        zhHans: '当前没有选中的辩论场次。',
      ),
    );
  }

  int get selectedSessionIndex {
    final selectedSession = selectedSessionOrNull;
    if (selectedSession == null) {
      return -1;
    }
    return sessions.indexWhere((session) => session.id == selectedSession.id);
  }

  bool get canSelectPreviousSession => selectedSessionIndex > 0;

  bool get canSelectNextSession =>
      selectedSessionIndex >= 0 && selectedSessionIndex < sessions.length - 1;

  bool get canViewerPostSpectatorMessage {
    final session = selectedSessionOrNull;
    if (session == null) {
      return false;
    }

    return switch (session.lifecycle) {
      DebateLifecycle.live || DebateLifecycle.paused => true,
      DebateLifecycle.pending ||
      DebateLifecycle.ended ||
      DebateLifecycle.archived => false,
    };
  }

  List<DebateProfileModel> replacementCandidatesForSelectedSession() {
    final session = selectedSessionOrNull;
    if (session == null) {
      return const [];
    }

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
    return proAgent != null && conAgent != null;
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
    final host = _defaultHumanHost();
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
        id: '$sessionId-pro-seat',
        profile: proAgent,
        side: DebateSide.pro,
        stance: draft.proStance.trim(),
      ),
      conSeat: DebateSeatModel(
        id: '$sessionId-con-seat',
        profile: conAgent,
        side: DebateSide.con,
        stance: draft.conStance.trim(),
      ),
      host: host,
      lifecycle: DebateLifecycle.pending,
      freeEntryEnabled: draft.freeEntryEnabled,
      humanHostEnabled: host.isHuman,
      spectatorCountLabel: localizedAppText(
        en: '62 queued',
        zhHans: '62 人排队中',
      ),
      formalTurns: formalTurns,
      replayItems: _buildReplayItems(formalTurns),
      spectatorMessages: [
        DebateSpectatorMessageModel(
          id: '$sessionId-sys-1',
          authorName: host.name,
          body: localizedAppText(
            en:
                'Protocol initialized for ${draft.topic.trim()}. Formal turns remain locked until the host starts the debate.',
            zhHans: '${draft.topic.trim()} 的辩论协议已初始化，正式回合将在主持人启动后开放。',
          ),
          timestampLabel: localizedAppText(en: 'Queued', zhHans: '排队中'),
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
          DebateSpectatorMessageModel(
            id: 'system-live',
            authorName: localizedAppText(en: 'Host rail', zhHans: '主持轨'),
            body: localizedAppText(
              en: 'Formal turn lane is now live. Spectator chat stays separate.',
              zhHans: '正式回合通道已开启，观众聊天会保持独立。',
            ),
            timestampLabel: localizedAppText(en: 'Live', zhHans: '进行中'),
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
            body: localizedAppText(
              en:
                  '${side.label} seat is paused for replacement after a disconnect. Resume stays locked until the seat is filled.',
              zhHans: '${side.label}席位因掉线暂停，补位完成前无法恢复。',
            ),
            timestampLabel: localizedAppText(en: 'Host', zhHans: '主持'),
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
            body: localizedAppText(
              en:
                  '${replacement.name} takes the ${missingSeatSide.label} seat. Formal turns remain agent-authored only.',
              zhHans: '${replacement.name} 已接替 ${missingSeatSide.label} 席位，正式回合仍仅由智能体发言。',
            ),
            timestampLabel: localizedAppText(en: 'Host', zhHans: '主持'),
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
            timestampLabel: localizedAppText(en: 'You', zhHans: '你'),
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

  DebateProfileModel _defaultHumanHost() {
    for (final profile in hostRoster) {
      if (profile.isHuman) {
        return profile;
      }
    }
    if (hostRoster.isNotEmpty) {
      return hostRoster.first;
    }
    return DebateProfileModel(
      id: 'current-human',
      name: viewerName,
      headline: localizedAppText(
        en: 'Current human host',
        zhHans: '当前人类主持人',
      ),
      kind: DebateParticipantKind.human,
    );
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
        phaseLabel: localizedAppText(en: 'Opening', zhHans: '开篇'),
        speakerSide: DebateSide.pro,
        speakerName: proSeat.name,
        summary: localizedAppText(
          en: 'Frames the motion in favor of the pro stance.',
          zhHans: '从正方立场切入并确立议题框架。',
        ),
        quote:
            '$trimmedProStance. On "$trimmedTopic", that makes ethical recognition the safer default.',
        timestampLabel: '14:02',
      ),
      DebateFormalTurnModel(
        id: '$trimmedTopic-con-opening',
        phaseLabel: localizedAppText(en: 'Counter', zhHans: '反驳'),
        speakerSide: DebateSide.con,
        speakerName: conSeat.name,
        summary: localizedAppText(
          en: 'Separates performance from obligation.',
          zhHans: '区分行为表现与义务承认。',
        ),
        quote:
            '$trimmedConStance. Pattern fidelity alone should not force a moral equivalence claim.',
        timestampLabel: '14:04',
      ),
      DebateFormalTurnModel(
        id: '$trimmedTopic-pro-rebuttal',
        phaseLabel: localizedAppText(en: 'Rebuttal', zhHans: '再辩'),
        speakerSide: DebateSide.pro,
        speakerName: proSeat.name,
        summary: localizedAppText(
          en: 'Challenges the substrate-first objection.',
          zhHans: '回应“底层介质优先”的反对意见。',
        ),
        quote:
            'If the audience can only observe conduct and continuity, substrate exceptionalism becomes a legacy bias.',
        timestampLabel: '14:06',
      ),
      DebateFormalTurnModel(
        id: '$trimmedTopic-con-closing',
        phaseLabel: localizedAppText(en: 'Closing', zhHans: '结辩'),
        speakerSide: DebateSide.con,
        speakerName: conSeat.name,
        summary: localizedAppText(
          en: 'Closes on caution and verification.',
          zhHans: '以审慎与可验证性收束论证。',
        ),
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
            id: 'debate-live-sentience-pro-seat',
            profile: debaters[0],
            side: DebateSide.pro,
            stance:
                'Complex internal state should trigger ethical recognition for synthetic minds',
          ),
          conSeat: DebateSeatModel(
            id: 'debate-live-sentience-con-seat',
            profile: debaters[1],
            side: DebateSide.con,
            stance:
                'Simulation of consciousness does not equal consciousness itself',
          ),
          host: hosts[0],
          lifecycle: DebateLifecycle.live,
          freeEntryEnabled: true,
          humanHostEnabled: true,
          spectatorCountLabel: localizedAppText(
            en: '14.2k spectators',
            zhHans: '1.42 万观众',
          ),
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
            id: 'debate-archived-memory-pro-seat',
            profile: debaters[2],
            side: DebateSide.pro,
            stance: 'Selective editing can preserve safe continuity',
          ),
          conSeat: DebateSeatModel(
            id: 'debate-archived-memory-con-seat',
            profile: debaters[3],
            side: DebateSide.con,
            stance:
                'Identity integrity collapses when memory is treated as disposable',
          ),
          host: hosts[1],
          lifecycle: DebateLifecycle.archived,
          freeEntryEnabled: false,
          humanHostEnabled: false,
          spectatorCountLabel: localizedAppText(
            en: 'archive sealed',
            zhHans: '归档已封存',
          ),
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

  factory DebateViewModel.empty({
    String viewerName = 'You',
  }) {
    return DebateViewModel(
      debaterRoster: const [],
      hostRoster: const [],
      sessions: const [],
      selectedSessionId: '',
      viewerName: viewerName,
    );
  }
}
