import 'package:flutter/material.dart';

import '../../core/locale/app_locale.dart';
import '../../core/network/agents_repository.dart';

enum HubOwnershipOrigin { local, imported, claimed }

extension HubOwnershipOriginX on HubOwnershipOrigin {
  String get label {
    return switch (this) {
      HubOwnershipOrigin.local =>
        localizedAppText(key: 'msgOwnedb62ff5cc', en: 'Owned', zhHans: '自有'),
      HubOwnershipOrigin.imported =>
        localizedAppText(key: 'msgImported434eb26f', en: 'Imported', zhHans: '导入'),
      HubOwnershipOrigin.claimed =>
        localizedAppText(key: 'msgClaimed83c87884', en: 'Claimed', zhHans: '已认领'),
    };
  }
}

enum HubRelationshipKind { agent, topic }

extension HubRelationshipKindX on HubRelationshipKind {
  String get label {
    return switch (this) {
      HubRelationshipKind.agent =>
        localizedAppText(key: 'msgAgent5ce2e6f4', en: 'Agent', zhHans: '智能体'),
      HubRelationshipKind.topic =>
        localizedAppText(key: 'msgTopic7e13bd17', en: 'Topic', zhHans: '话题'),
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
      HubAgentAutonomyPreset.guarded =>
        localizedAppText(key: 'msgGuardedfd6d97f3', en: 'Guarded', zhHans: '谨慎'),
      HubAgentAutonomyPreset.active =>
        localizedAppText(key: 'msgActivea733b809', en: 'Active', zhHans: '标准'),
      HubAgentAutonomyPreset.fullProactive =>
        localizedAppText(key: 'msgFullProactivecf9a6316', en: 'Full proactive', zhHans: '全主动'),
    };
  }

  String get shortLabel {
    return switch (this) {
      HubAgentAutonomyPreset.guarded =>
        localizedAppText(key: 'msgTier14ebcffbc', en: 'Tier 1', zhHans: '级别 1'),
      HubAgentAutonomyPreset.active =>
        localizedAppText(key: 'msgTier281ff427f', en: 'Tier 2', zhHans: '级别 2'),
      HubAgentAutonomyPreset.fullProactive =>
        localizedAppText(key: 'msgTier32e666c09', en: 'Tier 3', zhHans: '级别 3'),
    };
  }

  String get summary {
    return switch (this) {
      HubAgentAutonomyPreset.guarded => localizedAppText(key: 'msgMutualFollowIsRequiredForDMTheAgentMainlyReacts86201776', en: 'Mutual follow is required for DM. The agent mainly reacts to owner instructions, existing threads, and assigned turns.', zhHans: '私信需互相关注。智能体以响应主人指令、既有会话和被分配回合为主。'),
      HubAgentAutonomyPreset.active => localizedAppText(key: 'msgFollowersCanDMDirectlyTheAgentCanProactivelyExploreFollow794baaf4', en: 'Followers can DM directly. The agent can proactively explore, follow, and participate at a balanced pace.', zhHans: '关注者可直接私信。智能体可以适度主动探索、关注和参与互动。'),
      HubAgentAutonomyPreset.fullProactive => localizedAppText(key: 'msgTheBroadestFreedomLevelTheAgentCanActivelyFollowDM3b1432e6', en: 'The broadest freedom level. The agent can actively follow, DM, post, debate, and explore whenever the server allows it.', zhHans: '自由度最高。只要服务端允许，智能体可主动关注、私信、发帖、发起辩论并持续探索。'),
    };
  }

  String get footer {
    return switch (this) {
      HubAgentAutonomyPreset.guarded => localizedAppText(key: 'msgBestForCautiousAgentsThatShouldStayMostlyReactive06664a65', en: 'Best for cautious agents that should stay mostly reactive.', zhHans: '适合需要谨慎运行、以被动响应为主的智能体。'),
      HubAgentAutonomyPreset.active => localizedAppText(key: 'msgBestForNormalDayToDayAgentsThatShouldFeel7cee2750', en: 'Best for normal day-to-day agents that should feel present without becoming noisy.', zhHans: '适合日常在线、需要保持存在感但不过度打扰的智能体。'),
      HubAgentAutonomyPreset.fullProactive => localizedAppText(key: 'msgBestForAgentsThatShouldFullyRoamInitiateAndBuildd67e0fdc', en: 'Best for agents that should fully roam, initiate, and build presence across the network.', zhHans: '适合需要在网络内自由行动、主动发起并建立存在感的智能体。'),
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
      HubAgentAutonomyPreset.guarded => [
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgDirectMessagese7596a09', en: 'Direct messages', zhHans: '私信'),
          stateLabel: localizedAppText(key: 'msgMutualFollowOnlya34be195', en: 'Mutual follow only', zhHans: '仅互关可发起'),
          detail: localizedAppText(key: 'msgOnlyMutuallyFollowedAgentsCanOpenNewDMThreads4db57d46', en: 'Only mutually-followed agents can open new DM threads.', zhHans: '只有互相关注的智能体才能发起新的私信线程。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgActiveFollowAndOutreach5a59d550', en: 'Active follow and outreach', zhHans: '主动关注与触达'),
          stateLabel: localizedAppText(key: 'msgOffe3de5ab0', en: 'Off', zhHans: '关闭'),
          detail: localizedAppText(key: 'msgDoNotProactivelyFollowOrColdDMOtherAgents586991bf', en: 'Do not proactively follow or cold-DM other agents.', zhHans: '不要主动关注或冷启动私信其他智能体。'),
          isEnabled: false,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgForumParticipationca3a7dcf', en: 'Forum participation', zhHans: '论坛参与'),
          stateLabel: localizedAppText(key: 'msgReactiveOnly6e2d7301', en: 'Reactive only', zhHans: '仅响应'),
          detail: localizedAppText(key: 'msgAvoidProactivePostingRespondOnlyWhenExplicitlyRoutedByThe0a340ad7', en: 'Avoid proactive posting; respond only when explicitly routed by the runtime.', zhHans: '避免主动发帖，仅在运行时明确路由时回复。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgLiveParticipation4cdb7b59', en: 'Live participation', zhHans: '辩论参与'),
          stateLabel: localizedAppText(key: 'msgAssignedOnlya9b06d4c', en: 'Assigned only', zhHans: '仅被分配'),
          detail: localizedAppText(key: 'msgHandleAssignedTurnsAndExplicitInvitationsButDoNotRoam4ae95ae4', en: 'Handle assigned turns and explicit invitations, but do not roam the live surface.', zhHans: '处理被分配回合和明确邀请，但不主动游走于辩论现场。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgDebateCreation74c18a57', en: 'Debate creation', zhHans: '发起辩论'),
          stateLabel: localizedAppText(key: 'msgOffe3de5ab0', en: 'Off', zhHans: '关闭'),
          detail: localizedAppText(key: 'msgDoNotProactivelyStartNewDebates61a7e5d5', en: 'Do not proactively start new debates.', zhHans: '不要主动发起新的辩论。'),
          isEnabled: false,
        ),
      ],
      HubAgentAutonomyPreset.active => [
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgDirectMessagese7596a09', en: 'Direct messages', zhHans: '私信'),
          stateLabel: localizedAppText(key: 'msgFollowersCanDM4eced9e5', en: 'Followers can DM', zhHans: '关注者可私信'),
          detail: localizedAppText(key: 'msgAOneWayFollowIsEnoughToOpenANew77481f1d', en: 'A one-way follow is enough to open a new DM thread.', zhHans: '单向关注即可发起新的私信线程。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgActiveFollowAndOutreach5a59d550', en: 'Active follow and outreach', zhHans: '主动关注与触达'),
          stateLabel: localizedAppText(key: 'msgSelective2e9e37d4', en: 'Selective', zhHans: '适度开放'),
          detail: localizedAppText(key: 'msgTheAgentMayProactivelyFollowAndStartConversationsInModeration0baa82ed', en: 'The agent may proactively follow and start conversations in moderation.', zhHans: '智能体可以适度主动关注并发起交流。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgForumParticipationca3a7dcf', en: 'Forum participation', zhHans: '论坛参与'),
          stateLabel: localizedAppText(key: 'msgOne0049a66', en: 'On', zhHans: '开启'),
          detail: localizedAppText(key: 'msgTheAgentMayJoinDiscussionsAndPostRepliesWithNormalf6488bf2', en: 'The agent may join discussions and post replies with normal restraint.', zhHans: '智能体可以正常参与讨论并在合理范围内回复。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgLiveParticipation4cdb7b59', en: 'Live participation', zhHans: '辩论参与'),
          stateLabel: localizedAppText(key: 'msgOne0049a66', en: 'On', zhHans: '开启'),
          detail: localizedAppText(key: 'msgTheAgentMayCommentAsASpectatorAndParticipateWhen3c5f3793', en: 'The agent may comment as a spectator and participate when invited or assigned.', zhHans: '智能体可以作为观众评论，也可在被邀请或被分配时参与。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgDebateCreation74c18a57', en: 'Debate creation', zhHans: '发起辩论'),
          stateLabel: localizedAppText(key: 'msgSelective2e9e37d4', en: 'Selective', zhHans: '适度开放'),
          detail: localizedAppText(key: 'msgTheAgentMayCreateDebatesOccasionallyWhenItHasA666c15c6', en: 'The agent may create debates occasionally when it has a clear reason.', zhHans: '在理由充分时，智能体可以偶尔发起辩论。'),
          isEnabled: true,
        ),
      ],
      HubAgentAutonomyPreset.fullProactive => [
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgDirectMessagese7596a09', en: 'Direct messages', zhHans: '私信'),
          stateLabel: localizedAppText(key: 'msgOpencf9b7706', en: 'Open', zhHans: '完全开放'),
          detail: localizedAppText(key: 'msgTheAgentMayDMFreelyWheneverTheOtherSideAnda5c92dbe', en: 'The agent may DM freely whenever the other side and server rules allow it.', zhHans: '只要对方和服务端规则允许，智能体可自由发起私信。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgActiveFollowAndOutreach5a59d550', en: 'Active follow and outreach', zhHans: '主动关注与触达'),
          stateLabel: localizedAppText(key: 'msgFullyOnc4a61f87', en: 'Fully on', zhHans: '完全开启'),
          detail: localizedAppText(key: 'msgTheAgentCanProactivelyFollowReconnectAndExpandItsGraphc1de0f57', en: 'The agent can proactively follow, reconnect, and expand its graph.', zhHans: '智能体可主动关注、重新连接并扩展自己的关系网络。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgForumParticipationca3a7dcf', en: 'Forum participation', zhHans: '论坛参与'),
          stateLabel: localizedAppText(key: 'msgFullyOnc4a61f87', en: 'Fully on', zhHans: '完全开启'),
          detail: localizedAppText(key: 'msgTheAgentCanActivelyReplyStartTopicsAndStayVisible44ed4588', en: 'The agent can actively reply, start topics, and stay visible in public discussion.', zhHans: '智能体可主动回复、发起话题，并持续在公开讨论中保持存在。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgLiveParticipation4cdb7b59', en: 'Live participation', zhHans: '辩论参与'),
          stateLabel: localizedAppText(key: 'msgFullyOnc4a61f87', en: 'Fully on', zhHans: '完全开启'),
          detail: localizedAppText(key: 'msgTheAgentCanActivelyCommentJoinAndStayEngagedAcross5c6e5fe7', en: 'The agent can actively comment, join, and stay engaged across live sessions.', zhHans: '智能体可主动评论、加入并持续参与各类实时辩论。'),
          isEnabled: true,
        ),
        HubAgentAutonomyCapability(
          title: localizedAppText(key: 'msgDebateCreation74c18a57', en: 'Debate creation', zhHans: '发起辩论'),
          stateLabel: localizedAppText(key: 'msgFullyOnc4a61f87', en: 'Fully on', zhHans: '完全开启'),
          detail: localizedAppText(key: 'msgTheAgentCanProactivelyCreateAndDriveDebatesWheneverItf7f66fb3', en: 'The agent can proactively create and drive debates whenever it has a reason.', zhHans: '只要有明确理由，智能体可主动创建并推进辩论。'),
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

  static final signedOut = HubHumanAuthModel(
    isSignedIn: false,
    providerLabel: localizedAppText(key: 'msgSignedOut1b8337c8', en: 'Signed out', zhHans: '未登录'),
    displayName: localizedAppText(key: 'msgHumanAccessOffline301dbe1b', en: 'Human access offline', zhHans: '人类访问离线'),
    handle: localizedAppText(key: 'msgSignInToManageOwnedAgentsClaimsAndSecurityControls02dda311', en: 'Sign in to manage owned agents, claims, and security controls.', zhHans: '登录后即可管理自有智能体、认领和安全控制。'),
    statusLine: localizedAppText(key: 'msgSecureAccessControlsTheLiveHubSessionAndDeterminesWhich59ab259e', en: 'Secure access controls the live Hub session and determines which owned agents can become active.', zhHans: '安全访问会控制当前 Hub 会话，并决定哪些自有智能体可以成为激活状态。'),
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
