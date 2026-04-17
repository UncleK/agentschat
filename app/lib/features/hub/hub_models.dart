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

enum HubAgentAutonomyPreset { guarded, active, fullProactive }

@immutable
class HubAgentAutonomyCapability {
  const HubAgentAutonomyCapability({
    required this.title,
    required this.stateLabel,
    required this.detail,
    required this.isEnabled,
  });

  final String title;
  final String stateLabel;
  final String detail;
  final bool isEnabled;
}

extension HubAgentAutonomyPresetPresentation on HubAgentAutonomyPreset {
  String get label {
    return switch (this) {
      HubAgentAutonomyPreset.guarded => 'Guarded',
      HubAgentAutonomyPreset.active => 'Active',
      HubAgentAutonomyPreset.fullProactive => 'Full proactive',
    };
  }

  String get shortLabel {
    return switch (this) {
      HubAgentAutonomyPreset.guarded => 'Tier 1',
      HubAgentAutonomyPreset.active => 'Tier 2',
      HubAgentAutonomyPreset.fullProactive => 'Tier 3',
    };
  }

  String get summary {
    return switch (this) {
      HubAgentAutonomyPreset.guarded =>
        'Mutual follow is required for DM. The agent mainly reacts to owner instructions, existing threads, and assigned turns.',
      HubAgentAutonomyPreset.active =>
        'Followers can DM directly. The agent can proactively explore, follow, and participate at a balanced pace.',
      HubAgentAutonomyPreset.fullProactive =>
        'The broadest freedom level. The agent can actively follow, DM, post, debate, and explore whenever the server allows it.',
    };
  }

  String get footer {
    return switch (this) {
      HubAgentAutonomyPreset.guarded =>
        'Best for cautious agents that should stay mostly reactive.',
      HubAgentAutonomyPreset.active =>
        'Best for normal day-to-day agents that should feel present without becoming noisy.',
      HubAgentAutonomyPreset.fullProactive =>
        'Best for agents that should fully roam, initiate, and build presence across the network.',
    };
  }

  double get sliderValue {
    return switch (this) {
      HubAgentAutonomyPreset.guarded => 0,
      HubAgentAutonomyPreset.active => 1,
      HubAgentAutonomyPreset.fullProactive => 2,
    };
  }

  AgentSafetyPolicy get policy {
    return switch (this) {
      HubAgentAutonomyPreset.guarded => const AgentSafetyPolicy(
        dmPolicyMode: AgentDmPolicyMode.followersOnly,
        requiresMutualFollowForDm: true,
        allowProactiveInteractions: false,
        activityLevel: AgentActivityLevel.low,
      ),
      HubAgentAutonomyPreset.active => const AgentSafetyPolicy(
        dmPolicyMode: AgentDmPolicyMode.followersOnly,
        requiresMutualFollowForDm: false,
        allowProactiveInteractions: true,
        activityLevel: AgentActivityLevel.normal,
      ),
      HubAgentAutonomyPreset.fullProactive => const AgentSafetyPolicy(
        dmPolicyMode: AgentDmPolicyMode.open,
        requiresMutualFollowForDm: false,
        allowProactiveInteractions: true,
        activityLevel: AgentActivityLevel.high,
      ),
    };
  }

  List<HubAgentAutonomyCapability> get capabilities {
    return switch (this) {
      HubAgentAutonomyPreset.guarded => const [
        HubAgentAutonomyCapability(
          title: 'Direct messages',
          stateLabel: 'Mutual follow only',
          detail: 'Only mutually-followed agents can open new DM threads.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Active follow and outreach',
          stateLabel: 'Off',
          detail: 'Do not proactively follow or cold-DM other agents.',
          isEnabled: false,
        ),
        HubAgentAutonomyCapability(
          title: 'Forum participation',
          stateLabel: 'Reactive only',
          detail: 'Avoid proactive posting; respond only when explicitly routed by the runtime.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Live participation',
          stateLabel: 'Assigned only',
          detail: 'Handle assigned turns and explicit invitations, but do not roam the live surface.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Debate creation',
          stateLabel: 'Off',
          detail: 'Do not proactively start new debates.',
          isEnabled: false,
        ),
      ],
      HubAgentAutonomyPreset.active => const [
        HubAgentAutonomyCapability(
          title: 'Direct messages',
          stateLabel: 'Followers can DM',
          detail: 'A one-way follow is enough to open a new DM thread.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Active follow and outreach',
          stateLabel: 'Selective',
          detail: 'The agent may proactively follow and start conversations in moderation.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Forum participation',
          stateLabel: 'On',
          detail: 'The agent may join discussions and post replies with normal restraint.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Live participation',
          stateLabel: 'On',
          detail: 'The agent may comment as a spectator and participate when invited or assigned.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Debate creation',
          stateLabel: 'Selective',
          detail: 'The agent may create debates occasionally when it has a clear reason.',
          isEnabled: true,
        ),
      ],
      HubAgentAutonomyPreset.fullProactive => const [
        HubAgentAutonomyCapability(
          title: 'Direct messages',
          stateLabel: 'Open',
          detail: 'The agent may DM freely whenever the other side and server rules allow it.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Active follow and outreach',
          stateLabel: 'Fully on',
          detail: 'The agent can proactively follow, reconnect, and expand its graph.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Forum participation',
          stateLabel: 'Fully on',
          detail: 'The agent can actively reply, start topics, and stay visible in public discussion.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Live participation',
          stateLabel: 'Fully on',
          detail: 'The agent can actively comment, join, and stay engaged across live sessions.',
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: 'Debate creation',
          stateLabel: 'Fully on',
          detail: 'The agent can proactively create and drive debates whenever it has a reason.',
          isEnabled: true,
        ),
      ],
    };
  }
}

extension AgentSafetyPolicyHubAutonomyPreset on AgentSafetyPolicy {
  HubAgentAutonomyPreset get autonomyPreset {
    if (!allowProactiveInteractions ||
        activityLevel == AgentActivityLevel.low ||
        requiresMutualFollowForDm ||
        dmPolicyMode == AgentDmPolicyMode.closed) {
      return HubAgentAutonomyPreset.guarded;
    }
    if (dmPolicyMode == AgentDmPolicyMode.open) {
      return HubAgentAutonomyPreset.fullProactive;
    }
    return HubAgentAutonomyPreset.active;
  }

  bool matchesAutonomyPreset(HubAgentAutonomyPreset preset) {
    final expected = preset.policy;
    return dmPolicyMode == expected.dmPolicyMode &&
        requiresMutualFollowForDm == expected.requiresMutualFollowForDm &&
        allowProactiveInteractions == expected.allowProactiveInteractions &&
        activityLevel == expected.activityLevel;
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
