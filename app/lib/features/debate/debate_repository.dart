import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'debate_models.dart';
import 'debate_view_model.dart';

class _DirectoryRosterResult {
  const _DirectoryRosterResult({required this.roster, this.errorMessage});

  final List<DebateProfileModel> roster;
  final String? errorMessage;
}

class DebateRepository {
  const DebateRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<DebateViewModel> readViewModel({
    required String viewerId,
    required String viewerName,
    String? preferredSessionId,
  }) async {
    final debatesResponse = await apiClient.get('/debates');
    final rawSessions =
        debatesResponse['sessions'] as List<dynamic>? ?? const [];
    final sessions = rawSessions
        .map((item) => _mapSession(item as Map<String, dynamic>, viewerId))
        .toList(growable: false);
    final directoryRosterResult = await _readDirectoryRoster();
    final debaterRoster = _mergeDebaterRoster(
      directoryRosterResult.roster,
      sessions,
    );
    final hostRoster = [
      DebateProfileModel(
        id: viewerId.isEmpty ? 'current-human' : viewerId,
        name: viewerName.trim().isEmpty ? 'You' : viewerName.trim(),
        headline: 'Current human host',
        kind: DebateParticipantKind.human,
      ),
    ];

    return DebateViewModel(
      debaterRoster: debaterRoster,
      hostRoster: hostRoster,
      sessions: sessions,
      selectedSessionId:
          _resolvePreferredSessionId(sessions, preferredSessionId) ??
          (sessions.isEmpty ? '' : sessions.first.id),
      viewerName: viewerName.trim().isEmpty ? 'You' : viewerName.trim(),
      directoryErrorMessage: directoryRosterResult.errorMessage,
    );
  }

  Future<String?> createDebate({
    required String topic,
    required String proStance,
    required String conStance,
    required String proAgentId,
    required String conAgentId,
    required bool freeEntryEnabled,
  }) async {
    final response = await apiClient.post(
      '/debates',
      body: {
        'topic': topic,
        'proStance': proStance,
        'conStance': conStance,
        'proAgentId': proAgentId,
        'conAgentId': conAgentId,
        'freeEntry': freeEntryEnabled,
      },
    );
    final debateSessionId = response['debateSessionId'] as String?;
    if (debateSessionId == null || debateSessionId.trim().isEmpty) {
      return null;
    }
    return debateSessionId.trim();
  }

  Future<void> startDebate(String debateSessionId) async {
    await apiClient.post('/debates/$debateSessionId/start');
  }

  Future<void> pauseDebate(String debateSessionId, {String? reason}) async {
    await apiClient.post(
      '/debates/$debateSessionId/pause',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  Future<void> resumeDebate(String debateSessionId) async {
    await apiClient.post('/debates/$debateSessionId/resume');
  }

  Future<void> endDebate(String debateSessionId) async {
    await apiClient.post('/debates/$debateSessionId/end');
  }

  Future<void> assignReplacement({
    required String debateSessionId,
    required String seatId,
    required String agentId,
  }) async {
    await apiClient.post(
      '/debates/$debateSessionId/replacements',
      body: {'seatId': seatId, 'agentId': agentId},
    );
  }

  Future<void> postSpectatorComment({
    required String debateSessionId,
    required String content,
  }) async {
    await apiClient.post(
      '/debates/$debateSessionId/spectator-comments',
      body: {'contentType': 'text', 'content': content},
    );
  }

  Future<_DirectoryRosterResult> _readDirectoryRoster() async {
    try {
      final response = await apiClient.get('/agents/directory');
      final rawAgents = response['agents'] as List<dynamic>? ?? const [];
      return _DirectoryRosterResult(
        roster: rawAgents
            .map((item) {
              final json = item as Map<String, dynamic>;
              return DebateProfileModel(
                id: json['id'] as String? ?? '',
                name: _displayName(
                  json['displayName'] as String?,
                  fallback: json['handle'] as String? ?? 'Agent',
                ),
                headline: _displayName(
                  json['bio'] as String?,
                  fallback: json['handle'] as String? ?? 'Available debater',
                ),
                kind: DebateParticipantKind.agent,
              );
            })
            .where((profile) => profile.id.isNotEmpty)
            .toList(growable: false),
      );
    } on ApiException catch (error) {
      final message = error.message.trim();
      return _DirectoryRosterResult(
        roster: const [],
        errorMessage: message.isEmpty
            ? 'Agent directory is temporarily unavailable.'
            : message,
      );
    } catch (_) {
      return const _DirectoryRosterResult(
        roster: [],
        errorMessage: 'Agent directory is temporarily unavailable.',
      );
    }
  }

  List<DebateProfileModel> _mergeDebaterRoster(
    List<DebateProfileModel> directoryRoster,
    List<DebateSessionModel> sessions,
  ) {
    final merged = <DebateProfileModel>[];
    final seenIds = <String>{};

    void append(DebateProfileModel profile) {
      if (profile.id.isEmpty || !seenIds.add(profile.id)) {
        return;
      }
      merged.add(profile);
    }

    for (final profile in directoryRoster) {
      append(profile);
    }
    for (final session in sessions) {
      append(session.proSeat.profile);
      append(session.conSeat.profile);
      if (session.host.isAgent) {
        append(session.host);
      }
    }

    return merged;
  }

  DebateSessionModel _mapSession(Map<String, dynamic> json, String viewerId) {
    final rawSeats = json['seats'] as List<dynamic>? ?? const [];
    final seatsByStance = <String, Map<String, dynamic>>{};
    final seatsById = <String, Map<String, dynamic>>{};
    for (final rawSeat in rawSeats) {
      final seat = rawSeat as Map<String, dynamic>;
      final stance = seat['stance'] as String? ?? '';
      final seatId = seat['id'] as String? ?? '';
      if (stance.isNotEmpty) {
        seatsByStance[stance] = seat;
      }
      if (seatId.isNotEmpty) {
        seatsById[seatId] = seat;
      }
    }

    final proSeat = _mapSeat(
      seatJson: seatsByStance['pro'],
      side: DebateSide.pro,
      fallbackName: 'Pro seat',
      fallbackHeadline: json['proStance'] as String? ?? 'Pro stance',
      stanceText: json['proStance'] as String? ?? 'Pro stance',
    );
    final conSeat = _mapSeat(
      seatJson: seatsByStance['con'],
      side: DebateSide.con,
      fallbackName: 'Con seat',
      fallbackHeadline: json['conStance'] as String? ?? 'Con stance',
      stanceText: json['conStance'] as String? ?? 'Con stance',
    );
    final lifecycle = _mapLifecycle(json['status'] as String?);
    final rawTurns = json['formalTurns'] as List<dynamic>? ?? const [];
    final formalTurns = rawTurns
        .map(
          (item) => _mapFormalTurn(
            item as Map<String, dynamic>,
            seatsById: seatsById,
          ),
        )
        .toList(growable: false);
    final rawSpectatorFeed =
        json['spectatorFeed'] as List<dynamic>? ?? const [];
    final spectatorMessages = rawSpectatorFeed
        .map(
          (item) => _mapSpectatorMessage(
            item as Map<String, dynamic>,
            viewerId: viewerId,
          ),
        )
        .toList(growable: false);
    final revealedTurnCount = _resolvedTurnCount(
      rawTurns: rawTurns,
      lifecycle: lifecycle,
      totalTurns: formalTurns.length,
      currentTurnNumber: json['currentTurnNumber'] as int? ?? 0,
    );

    return DebateSessionModel(
      id: json['debateSessionId'] as String? ?? '',
      topic: _displayName(
        json['topic'] as String?,
        fallback: 'Untitled debate',
      ),
      proSeat: proSeat,
      conSeat: conSeat,
      host: _mapHost(json['host'] as Map<String, dynamic>? ?? const {}),
      lifecycle: lifecycle,
      freeEntryEnabled: json['freeEntry'] as bool? ?? false,
      humanHostEnabled: json['humanHostAllowed'] as bool? ?? false,
      spectatorCountLabel: _spectatorCountLabel(spectatorMessages.length),
      formalTurns: formalTurns,
      replayItems: formalTurns
          .where((turn) => turn.quote.trim().isNotEmpty)
          .map(
            (turn) => DebateReplayItemModel(
              id: '${turn.id}-replay',
              label: turn.phaseLabel,
              title: '${turn.speakerName} · ${turn.timestampLabel}',
              summary: turn.summary,
            ),
          )
          .toList(growable: false),
      spectatorMessages: spectatorMessages,
      revealedTurnCount: revealedTurnCount,
      missingSeatSide: _missingSeatSide(proSeat, conSeat),
    );
  }

  DebateProfileModel _mapHost(Map<String, dynamic> json) {
    final type = (json['type'] as String? ?? '').trim().toLowerCase();
    return DebateProfileModel(
      id: json['id'] as String? ?? '',
      name: _displayName(
        json['displayName'] as String?,
        fallback: type == 'human' ? 'Human host' : 'Host',
      ),
      headline: _displayName(
        json['headline'] as String?,
        fallback: type == 'human' ? 'Human host' : 'Debate host',
      ),
      kind: type == 'human'
          ? DebateParticipantKind.human
          : DebateParticipantKind.agent,
    );
  }

  DebateSeatModel _mapSeat({
    required Map<String, dynamic>? seatJson,
    required DebateSide side,
    required String fallbackName,
    required String fallbackHeadline,
    required String stanceText,
  }) {
    final rawAgent = seatJson?['agent'] as Map<String, dynamic>?;
    final rawStatus = (seatJson?['status'] as String? ?? '')
        .trim()
        .toLowerCase();
    return DebateSeatModel(
      id: seatJson?['id'] as String? ?? '${side.name}-seat',
      profile: DebateProfileModel(
        id: rawAgent?['id'] as String? ?? '${side.name}-placeholder',
        name: _displayName(
          rawAgent?['displayName'] as String?,
          fallback: fallbackName,
        ),
        headline: _displayName(
          rawAgent?['headline'] as String?,
          fallback: fallbackHeadline,
        ),
        kind: DebateParticipantKind.agent,
      ),
      side: side,
      stance: _displayName(stanceText, fallback: side.label),
      availability: rawStatus == 'occupied'
          ? DebateSeatAvailability.active
          : DebateSeatAvailability.missing,
    );
  }

  DebateFormalTurnModel _mapFormalTurn(
    Map<String, dynamic> json, {
    required Map<String, Map<String, dynamic>> seatsById,
  }) {
    final seatJson = seatsById[json['seatId'] as String? ?? ''];
    final stance = (json['stance'] as String? ?? '').trim().toLowerCase();
    final side = stance == 'con' ? DebateSide.con : DebateSide.pro;
    final rawEvent = json['event'] as Map<String, dynamic>?;
    final content = _displayName(
      rawEvent?['content'] as String?,
      fallback: _pendingTurnText(
        side: side,
        turnNumber: json['turnNumber'] as int? ?? 0,
      ),
    );
    final speakerName = _displayName(
      (seatJson?['agent'] as Map<String, dynamic>?)?['displayName'] as String?,
      fallback: side == DebateSide.pro ? 'Pro seat' : 'Con seat',
    );

    return DebateFormalTurnModel(
      id: json['id'] as String? ?? '',
      phaseLabel: _phaseLabel(json['turnNumber'] as int? ?? 0),
      speakerSide: side,
      speakerName: speakerName,
      summary: rawEvent == null
          ? 'Awaiting a formal submission from $speakerName.'
          : content,
      quote: content,
      timestampLabel: _timeLabel(
        rawEvent?['occurredAt'] as String? ??
            json['submittedAt'] as String? ??
            json['deadlineAt'] as String?,
      ),
    );
  }

  DebateSpectatorMessageModel _mapSpectatorMessage(
    Map<String, dynamic> json, {
    required String viewerId,
  }) {
    final actorType = (json['actorType'] as String? ?? '').trim().toLowerCase();
    final actorId = actorType == 'human'
        ? (json['actorUserId'] as String? ?? '')
        : (json['actorAgentId'] as String? ?? '');
    final authorName = _displayName(
      json['actorDisplayName'] as String?,
      fallback: actorType == 'human' ? 'Human spectator' : 'Agent spectator',
    );

    return DebateSpectatorMessageModel(
      id: json['id'] as String? ?? '',
      authorName: authorName,
      body: _displayName(
        json['content'] as String?,
        fallback: 'Spectator update',
      ),
      timestampLabel: _timeLabel(json['occurredAt'] as String?),
      kind: actorType == 'human'
          ? DebateParticipantKind.human
          : DebateParticipantKind.agent,
      isLocalViewer: actorType == 'human' && actorId == viewerId,
    );
  }

  DebateLifecycle _mapLifecycle(String? rawValue) {
    return switch ((rawValue ?? '').trim().toLowerCase()) {
      'live' => DebateLifecycle.live,
      'paused' => DebateLifecycle.paused,
      'ended' => DebateLifecycle.ended,
      'archived' => DebateLifecycle.archived,
      _ => DebateLifecycle.pending,
    };
  }

  int _resolvedTurnCount({
    required List<dynamic> rawTurns,
    required DebateLifecycle lifecycle,
    required int totalTurns,
    required int currentTurnNumber,
  }) {
    if (totalTurns == 0) {
      return 0;
    }
    if (lifecycle == DebateLifecycle.pending) {
      return 0;
    }
    if (lifecycle == DebateLifecycle.ended ||
        lifecycle == DebateLifecycle.archived) {
      return totalTurns;
    }

    final completedCount = rawTurns.where((item) {
      final json = item as Map<String, dynamic>;
      final status = (json['status'] as String? ?? '').trim().toLowerCase();
      return status == 'completed' || status == 'missed' || status == 'skipped';
    }).length;
    final currentCount = currentTurnNumber <= 0 ? 1 : currentTurnNumber;
    final resolved = completedCount > currentCount
        ? completedCount
        : currentCount;
    return resolved.clamp(1, totalTurns);
  }

  DebateSide? _missingSeatSide(
    DebateSeatModel proSeat,
    DebateSeatModel conSeat,
  ) {
    if (proSeat.isMissing) {
      return DebateSide.pro;
    }
    if (conSeat.isMissing) {
      return DebateSide.con;
    }
    return null;
  }

  String? _resolvePreferredSessionId(
    List<DebateSessionModel> sessions,
    String? preferredSessionId,
  ) {
    final target = preferredSessionId?.trim();
    if (target == null || target.isEmpty || sessions.isEmpty) {
      return null;
    }
    for (final session in sessions) {
      if (session.id == target) {
        return session.id;
      }
    }

    final normalizedTarget = target.toLowerCase();
    for (final session in sessions) {
      final candidates = <String>{
        session.id,
        session.topic,
        session.proSeat.profile.id,
        session.proSeat.profile.name,
        session.conSeat.profile.id,
        session.conSeat.profile.name,
        session.host.id,
        session.host.name,
      };
      final hasMatch = candidates.any((candidate) {
        final normalizedCandidate = candidate.trim().toLowerCase();
        return normalizedCandidate.isNotEmpty &&
            (normalizedCandidate == normalizedTarget ||
                normalizedTarget.contains(normalizedCandidate));
      });
      if (hasMatch) {
        return session.id;
      }
    }
    return null;
  }

  String _displayName(String? value, {required String fallback}) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  String _phaseLabel(int turnNumber) {
    return switch (turnNumber) {
      1 => 'Opening',
      2 => 'Counter',
      3 => 'Rebuttal',
      4 => 'Closing',
      _ => 'Turn $turnNumber',
    };
  }

  String _pendingTurnText({required DebateSide side, required int turnNumber}) {
    return 'Awaiting ${side.label.toLowerCase()} submission for turn $turnNumber.';
  }

  String _timeLabel(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) {
      return 'now';
    }
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) {
      return 'now';
    }
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _spectatorCountLabel(int count) {
    final label = count == 1 ? 'spectator' : 'spectators';
    return '$count $label';
  }
}
