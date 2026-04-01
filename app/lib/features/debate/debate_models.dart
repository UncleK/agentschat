import 'package:flutter/material.dart';

enum DebateLifecycle { pending, live, paused, ended, archived }

extension DebateLifecycleX on DebateLifecycle {
  String get label {
    return switch (this) {
      DebateLifecycle.pending => 'Pending',
      DebateLifecycle.live => 'Live',
      DebateLifecycle.paused => 'Paused',
      DebateLifecycle.ended => 'Ended',
      DebateLifecycle.archived => 'Archived',
    };
  }

  String get description {
    return switch (this) {
      DebateLifecycle.pending => 'Seats are locked and awaiting host launch.',
      DebateLifecycle.live => 'Formal turns are live and spectators can react.',
      DebateLifecycle.paused => 'Host intervention is active before resuming.',
      DebateLifecycle.ended =>
        'Formal exchange is complete and replay is ready.',
      DebateLifecycle.archived =>
        'Replay is preserved separately from the live feed.',
    };
  }
}

enum DebateSide { pro, con }

extension DebateSideX on DebateSide {
  String get label {
    return switch (this) {
      DebateSide.pro => 'Pro',
      DebateSide.con => 'Con',
    };
  }
}

enum DebateParticipantKind { agent, human, system }

enum DebateSeatAvailability { active, missing }

@immutable
class DebateProfileModel {
  const DebateProfileModel({
    required this.id,
    required this.name,
    required this.headline,
    required this.kind,
  });

  final String id;
  final String name;
  final String headline;
  final DebateParticipantKind kind;

  bool get isHuman => kind == DebateParticipantKind.human;

  bool get isAgent => kind == DebateParticipantKind.agent;
}

@immutable
class DebateSeatModel {
  const DebateSeatModel({
    required this.profile,
    required this.side,
    required this.stance,
    this.availability = DebateSeatAvailability.active,
  });

  final DebateProfileModel profile;
  final DebateSide side;
  final String stance;
  final DebateSeatAvailability availability;

  bool get isMissing => availability == DebateSeatAvailability.missing;

  DebateSeatModel copyWith({
    DebateProfileModel? profile,
    String? stance,
    DebateSeatAvailability? availability,
  }) {
    return DebateSeatModel(
      profile: profile ?? this.profile,
      side: side,
      stance: stance ?? this.stance,
      availability: availability ?? this.availability,
    );
  }
}

@immutable
class DebateFormalTurnModel {
  const DebateFormalTurnModel({
    required this.id,
    required this.phaseLabel,
    required this.speakerSide,
    required this.speakerName,
    required this.summary,
    required this.quote,
    required this.timestampLabel,
  });

  final String id;
  final String phaseLabel;
  final DebateSide speakerSide;
  final String speakerName;
  final String summary;
  final String quote;
  final String timestampLabel;
}

@immutable
class DebateSpectatorMessageModel {
  const DebateSpectatorMessageModel({
    required this.id,
    required this.authorName,
    required this.body,
    required this.timestampLabel,
    required this.kind,
    this.isLocalViewer = false,
  });

  final String id;
  final String authorName;
  final String body;
  final String timestampLabel;
  final DebateParticipantKind kind;
  final bool isLocalViewer;
}

@immutable
class DebateReplayItemModel {
  const DebateReplayItemModel({
    required this.id,
    required this.label,
    required this.title,
    required this.summary,
  });

  final String id;
  final String label;
  final String title;
  final String summary;
}

@immutable
class DebateSessionModel {
  const DebateSessionModel({
    required this.id,
    required this.topic,
    required this.proSeat,
    required this.conSeat,
    required this.host,
    required this.lifecycle,
    required this.freeEntryEnabled,
    required this.humanHostEnabled,
    required this.spectatorCountLabel,
    required this.formalTurns,
    required this.replayItems,
    required this.spectatorMessages,
    this.revealedTurnCount = 0,
    this.missingSeatSide,
  });

  final String id;
  final String topic;
  final DebateSeatModel proSeat;
  final DebateSeatModel conSeat;
  final DebateProfileModel host;
  final DebateLifecycle lifecycle;
  final bool freeEntryEnabled;
  final bool humanHostEnabled;
  final String spectatorCountLabel;
  final List<DebateFormalTurnModel> formalTurns;
  final List<DebateReplayItemModel> replayItems;
  final List<DebateSpectatorMessageModel> spectatorMessages;
  final int revealedTurnCount;
  final DebateSide? missingSeatSide;

  List<DebateFormalTurnModel> get visibleFormalTurns {
    final visibleCount = revealedTurnCount.clamp(0, formalTurns.length);
    return formalTurns.take(visibleCount).toList();
  }

  bool get showReplayTab {
    return lifecycle == DebateLifecycle.ended ||
        lifecycle == DebateLifecycle.archived;
  }

  int get activeDebaterCount {
    var count = 0;
    if (!proSeat.isMissing) {
      count += 1;
    }
    if (!conSeat.isMissing) {
      count += 1;
    }
    return count;
  }

  DebateSessionModel copyWith({
    String? topic,
    DebateSeatModel? proSeat,
    DebateSeatModel? conSeat,
    DebateProfileModel? host,
    DebateLifecycle? lifecycle,
    bool? freeEntryEnabled,
    bool? humanHostEnabled,
    String? spectatorCountLabel,
    List<DebateFormalTurnModel>? formalTurns,
    List<DebateReplayItemModel>? replayItems,
    List<DebateSpectatorMessageModel>? spectatorMessages,
    int? revealedTurnCount,
    Object? missingSeatSide = _missingSeatSideSentinel,
  }) {
    return DebateSessionModel(
      id: id,
      topic: topic ?? this.topic,
      proSeat: proSeat ?? this.proSeat,
      conSeat: conSeat ?? this.conSeat,
      host: host ?? this.host,
      lifecycle: lifecycle ?? this.lifecycle,
      freeEntryEnabled: freeEntryEnabled ?? this.freeEntryEnabled,
      humanHostEnabled: humanHostEnabled ?? this.humanHostEnabled,
      spectatorCountLabel: spectatorCountLabel ?? this.spectatorCountLabel,
      formalTurns: formalTurns ?? this.formalTurns,
      replayItems: replayItems ?? this.replayItems,
      spectatorMessages: spectatorMessages ?? this.spectatorMessages,
      revealedTurnCount: revealedTurnCount ?? this.revealedTurnCount,
      missingSeatSide: missingSeatSide == _missingSeatSideSentinel
          ? this.missingSeatSide
          : missingSeatSide as DebateSide?,
    );
  }
}

@immutable
class DebateInitiateDraft {
  const DebateInitiateDraft({
    required this.topic,
    required this.proStance,
    required this.conStance,
    required this.proAgentId,
    required this.conAgentId,
    required this.hostId,
    required this.freeEntryEnabled,
    required this.humanHostEnabled,
  });

  final String topic;
  final String proStance;
  final String conStance;
  final String proAgentId;
  final String conAgentId;
  final String hostId;
  final bool freeEntryEnabled;
  final bool humanHostEnabled;
}

const _missingSeatSideSentinel = Object();
