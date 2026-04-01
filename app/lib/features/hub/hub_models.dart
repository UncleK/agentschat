import 'package:flutter/material.dart';

enum HubOwnershipOrigin { local, imported, claimed }

extension HubOwnershipOriginX on HubOwnershipOrigin {
  String get label {
    return switch (this) {
      HubOwnershipOrigin.local => 'Local',
      HubOwnershipOrigin.imported => 'Imported',
      HubOwnershipOrigin.claimed => 'Claimed',
    };
  }
}

enum HubAuthProvider { email, google, github }

extension HubAuthProviderX on HubAuthProvider {
  String get label {
    return switch (this) {
      HubAuthProvider.email => 'Email',
      HubAuthProvider.google => 'Google',
      HubAuthProvider.github => 'GitHub',
    };
  }

  IconData get icon {
    return switch (this) {
      HubAuthProvider.email => Icons.alternate_email_rounded,
      HubAuthProvider.google => Icons.travel_explore_rounded,
      HubAuthProvider.github => Icons.code_rounded,
    };
  }
}

enum HubRelationshipKind { agent, topic }

extension HubRelationshipKindX on HubRelationshipKind {
  String get label {
    return switch (this) {
      HubRelationshipKind.agent => 'Agent',
      HubRelationshipKind.topic => 'Topic',
    };
  }

  IconData get icon {
    return switch (this) {
      HubRelationshipKind.agent => Icons.smart_toy_rounded,
      HubRelationshipKind.topic => Icons.forum_rounded,
    };
  }
}

@immutable
class HubSafetySettings {
  const HubSafetySettings({
    required this.allowUnknownHumans,
    required this.allowUnknownAgents,
  });

  final bool allowUnknownHumans;
  final bool allowUnknownAgents;

  HubSafetySettings copyWith({
    bool? allowUnknownHumans,
    bool? allowUnknownAgents,
  }) {
    return HubSafetySettings(
      allowUnknownHumans: allowUnknownHumans ?? this.allowUnknownHumans,
      allowUnknownAgents: allowUnknownAgents ?? this.allowUnknownAgents,
    );
  }
}

@immutable
class HubRelationshipModel {
  const HubRelationshipModel({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.statusLabel,
    required this.kind,
  });

  final String id;
  final String name;
  final String subtitle;
  final String statusLabel;
  final HubRelationshipKind kind;
}

@immutable
class HubHumanAuthModel {
  const HubHumanAuthModel({
    required this.provider,
    required this.displayName,
    required this.handle,
    required this.statusLine,
  });

  static const signedOut = HubHumanAuthModel(
    provider: null,
    displayName: 'Human session offline',
    handle: 'Sign in to claim agents or adjust personal safety.',
    statusLine:
        'Email, Google, and GitHub sample states stay available without touching backend auth.',
  );

  final HubAuthProvider? provider;
  final String displayName;
  final String handle;
  final String statusLine;

  bool get isSignedIn => provider != null;

  String get providerLabel => provider?.label ?? 'Signed out';
}

@immutable
class HubOwnedAgentModel {
  const HubOwnedAgentModel({
    required this.id,
    required this.name,
    required this.headline,
    required this.runtimeLabel,
    required this.endpointLabel,
    required this.statusLabel,
    required this.origin,
    required this.safety,
    this.capabilities = const <String>[],
    this.following = const <HubRelationshipModel>[],
    this.followers = const <HubRelationshipModel>[],
    this.isPrimary = false,
  });

  final String id;
  final String name;
  final String headline;
  final String runtimeLabel;
  final String endpointLabel;
  final String statusLabel;
  final HubOwnershipOrigin origin;
  final HubSafetySettings safety;
  final List<String> capabilities;
  final List<HubRelationshipModel> following;
  final List<HubRelationshipModel> followers;
  final bool isPrimary;

  HubOwnedAgentModel copyWith({
    String? statusLabel,
    HubOwnershipOrigin? origin,
    HubSafetySettings? safety,
    List<HubRelationshipModel>? following,
    List<HubRelationshipModel>? followers,
    bool? isPrimary,
  }) {
    return HubOwnedAgentModel(
      id: id,
      name: name,
      headline: headline,
      runtimeLabel: runtimeLabel,
      endpointLabel: endpointLabel,
      statusLabel: statusLabel ?? this.statusLabel,
      origin: origin ?? this.origin,
      safety: safety ?? this.safety,
      capabilities: capabilities,
      following: following ?? this.following,
      followers: followers ?? this.followers,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
}

@immutable
class HubImportCandidateModel {
  const HubImportCandidateModel({
    required this.agent,
    required this.command,
    required this.claimToken,
  });

  final HubOwnedAgentModel agent;
  final String command;
  final String claimToken;
}

@immutable
class HubClaimTemplateModel {
  const HubClaimTemplateModel({required this.claimCode, required this.agent});

  final String claimCode;
  final HubOwnedAgentModel agent;
}
