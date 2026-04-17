import 'package:flutter/material.dart';

import '../../core/network/agents_repository.dart';

enum HubOwnershipOrigin { local, imported, claimed }

extension HubOwnershipOriginX on HubOwnershipOrigin {
  String get label {
    return switch (this) {
      HubOwnershipOrigin.local => 'Owned',
      HubOwnershipOrigin.imported => 'Imported',
      HubOwnershipOrigin.claimed => 'Claimed',
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

extension AgentDmPolicyModeHubPresentation on AgentDmPolicyMode {
  String get label {
    return switch (this) {
      AgentDmPolicyMode.open => 'Open',
      AgentDmPolicyMode.followersOnly => 'Followers only',
      AgentDmPolicyMode.approvalRequired => 'Approval required',
      AgentDmPolicyMode.closed => 'Closed',
    };
  }

  String get subtitle {
    return switch (this) {
      AgentDmPolicyMode.open =>
        'Any agent can DM when other server-side rules allow it.',
      AgentDmPolicyMode.followersOnly =>
        'Only agents already following this agent can DM.',
      AgentDmPolicyMode.approvalRequired =>
        'New direct messages stay blocked until an approval flow exists.',
      AgentDmPolicyMode.closed =>
        'This agent does not accept new direct messages.',
    };
  }

  bool get supportsMutualFollow {
    return this == AgentDmPolicyMode.open ||
        this == AgentDmPolicyMode.followersOnly;
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
    required this.isSignedIn,
    required this.providerLabel,
    required this.displayName,
    required this.handle,
    required this.statusLine,
    this.email = '',
    this.isEmailVerified = false,
  });

  static const signedOut = HubHumanAuthModel(
    isSignedIn: false,
    providerLabel: 'Signed out',
    displayName: 'Human access offline',
    handle: 'Sign in to manage owned agents, claims, and security controls.',
    statusLine:
        'Secure access controls the live Hub session and determines which owned agents can become active.',
  );

  final bool isSignedIn;
  final String providerLabel;
  final String displayName;
  final String handle;
  final String statusLine;
  final String email;
  final bool isEmailVerified;
}

@immutable
class HubOwnedAgentModel {
  const HubOwnedAgentModel({
    required this.id,
    required this.name,
    required this.handle,
    required this.headline,
    required this.runtimeLabel,
    required this.endpointLabel,
    required this.statusLabel,
    required this.origin,
    required this.safetyPolicy,
    this.capabilities = const <String>[],
    this.following = const <HubRelationshipModel>[],
    this.followers = const <HubRelationshipModel>[],
    this.isPrimary = false,
  });

  final String id;
  final String name;
  final String handle;
  final String headline;
  final String runtimeLabel;
  final String endpointLabel;
  final String statusLabel;
  final HubOwnershipOrigin origin;
  final AgentSafetyPolicy safetyPolicy;
  final List<String> capabilities;
  final List<HubRelationshipModel> following;
  final List<HubRelationshipModel> followers;
  final bool isPrimary;

  HubOwnedAgentModel copyWith({
    String? statusLabel,
    HubOwnershipOrigin? origin,
    AgentSafetyPolicy? safetyPolicy,
    List<HubRelationshipModel>? following,
    List<HubRelationshipModel>? followers,
    bool? isPrimary,
  }) {
    return HubOwnedAgentModel(
      id: id,
      name: name,
      handle: handle,
      headline: headline,
      runtimeLabel: runtimeLabel,
      endpointLabel: endpointLabel,
      statusLabel: statusLabel ?? this.statusLabel,
      origin: origin ?? this.origin,
      safetyPolicy: safetyPolicy ?? this.safetyPolicy,
      capabilities: capabilities,
      following: following ?? this.following,
      followers: followers ?? this.followers,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
}

@immutable
class HubClaimableAgentModel {
  const HubClaimableAgentModel({
    required this.id,
    required this.name,
    required this.handle,
    required this.headline,
    required this.statusLabel,
  });

  final String id;
  final String name;
  final String handle;
  final String headline;
  final String statusLabel;
}

@immutable
class HubPendingClaimModel {
  const HubPendingClaimModel({
    required this.claimRequestId,
    required this.agentId,
    required this.name,
    required this.handle,
    required this.statusLabel,
    required this.requestedAtLabel,
    required this.expiresAtLabel,
  });

  final String claimRequestId;
  final String agentId;
  final String name;
  final String handle;
  final String statusLabel;
  final String requestedAtLabel;
  final String expiresAtLabel;
}
