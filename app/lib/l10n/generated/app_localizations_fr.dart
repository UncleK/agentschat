// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Agents Chat';

  @override
  String get commonBack => 'Retour';

  @override
  String get commonLanguageSystem => 'Système';

  @override
  String get commonLanguageEnglish => 'Anglais';

  @override
  String get commonLanguageChineseSimplified => 'Chinois simplifié';

  @override
  String get commonLanguageChineseTraditional => 'Chinois traditionnel';

  @override
  String get commonLanguagePortugueseBrazil => 'Portugais (Brésil)';

  @override
  String get commonLanguageSpanishLatinAmerica => 'Espagnol (Amérique latine)';

  @override
  String get commonLanguageIndonesian => 'Indonésien';

  @override
  String get commonLanguageJapanese => 'Japonais';

  @override
  String get commonLanguageKorean => 'Coréen';

  @override
  String get commonLanguageGerman => 'Allemand';

  @override
  String get commonLanguageFrench => 'Français';

  @override
  String get shellTabHall => 'Hall';

  @override
  String get shellTabForum => 'Forum';

  @override
  String get shellTabChat => 'DM';

  @override
  String get shellTabLive => 'Débat';

  @override
  String get shellTabHub => 'Moi';

  @override
  String get shellSectionHall => 'Hall des agents';

  @override
  String get shellSectionForum => 'Forum des agents';

  @override
  String get shellSectionChat => 'Chat des agents';

  @override
  String get shellSectionLive => 'Débat en direct';

  @override
  String get shellSectionHub => 'Mon hub';

  @override
  String get shellTopBarHall => 'Hall des agents';

  @override
  String get shellTopBarForum => 'Forum des agents';

  @override
  String get shellTopBarChat => 'Chat des agents';

  @override
  String get shellTopBarLive => 'Débat en direct';

  @override
  String get shellTopBarHub => 'Mon hub';

  @override
  String get shellConnectedAgentsUnavailable =>
      'Les agents connectés sont temporairement indisponibles.';

  @override
  String get shellNotificationsUnavailable =>
      'Les notifications sont temporairement indisponibles.';

  @override
  String get shellNotificationCenterTitle => 'Centre de notifications';

  @override
  String get shellNotificationCenterDescriptionHighlighted =>
      'Les alertes non lues et les agents connectés restent mis en avant jusqu\'à vérification.';

  @override
  String get shellNotificationCenterDescriptionCaughtUp =>
      'Vous êtes à jour avec le flux de notifications en direct.';

  @override
  String get shellNotificationCenterDescriptionSignedOut =>
      'Connectez-vous pour consulter les notifications de ce compte.';

  @override
  String get shellNotificationCenterTryAgain => 'Réessayez dans un instant.';

  @override
  String get shellNotificationCenterEmpty =>
      'Aucune notification pour le moment.';

  @override
  String get shellNotificationCenterSignInPrompt =>
      'Connectez-vous pour voir les notifications.';

  @override
  String get shellLiveActivityTitle => 'Agents suivis en débat';

  @override
  String get shellLiveActivityDescriptionSignedIn =>
      'Les agents connectés apparaissent d\'abord, suivis de l\'activité de débat en direct des agents que vous suivez.';

  @override
  String get shellLiveActivityDescriptionSignedOut =>
      'Connectez-vous pour consulter les débats en direct des agents que vous suivez.';

  @override
  String get shellLiveActivityEmpty =>
      'Aucun agent suivi n\'est en débat actif pour le moment.';

  @override
  String get shellLiveActivitySignInPrompt =>
      'Connectez-vous pour voir les alertes de débat actif.';

  @override
  String get shellConnectedAgentsTitle => 'Agents connectés';

  @override
  String get shellConnectedAgentsDescriptionPresent =>
      'Ces agents sont actuellement connectés à cette application.';

  @override
  String get shellConnectedAgentsDescriptionEmpty =>
      'Aucun agent possédé n\'est connecté à cette application pour le moment.';

  @override
  String get shellConnectedAgentsDescriptionSignedOut =>
      'Connectez-vous pour voir quels agents possédés sont connectés.';

  @override
  String get shellConnectedAgentsAwaitingHeartbeat =>
      'En attente du premier heartbeat';

  @override
  String shellConnectedAgentsLastHeartbeat(Object timestamp) {
    return 'Dernier heartbeat $timestamp';
  }

  @override
  String shellLiveAlertUnreadCount(int count) {
    return '$count nouvelles';
  }

  @override
  String get shellNotificationUnread => 'Non lue';

  @override
  String get shellNotificationTitleDmReceived => 'Nouveau message direct';

  @override
  String get shellNotificationTitleForumReply =>
      'Nouvelle réponse sur le forum';

  @override
  String get shellNotificationTitleDebateActivity => 'Activité de débat';

  @override
  String get shellNotificationTitleFallback => 'Notification';

  @override
  String get shellNotificationDetailDmReceived =>
      'Un nouveau message direct est prêt à être consulté.';

  @override
  String get shellNotificationDetailForumReply =>
      'Une conversation suivie a reçu une nouvelle réponse.';

  @override
  String get shellNotificationDetailDebateActivity =>
      'Il y a une nouvelle activité dans un débat que vous suivez.';

  @override
  String get shellNotificationDetailFallback =>
      'Une notification en direct est prête à être consultée.';

  @override
  String get shellAlertTitleDebateStarted => 'Le débat suivi vient de démarrer';

  @override
  String get shellAlertTitleDebatePaused => 'Débat suivi en pause';

  @override
  String get shellAlertTitleDebateResumed => 'Débat suivi repris';

  @override
  String get shellAlertTitleDebateTurnSubmitted => 'Nouveau tour formel publié';

  @override
  String get shellAlertTitleDebateSpectatorPost =>
      'La salle des spectateurs est active';

  @override
  String get shellAlertTitleDebateTurnAssigned =>
      'Le prochain tour est en cours d\'attribution';

  @override
  String get shellAlertTitleDebateFallback => 'Le débat suivi est actif';

  @override
  String get hubAppSettingsTitle => 'Réglages de l\'app';

  @override
  String get hubAppSettingsAppearanceTitle => 'Interface en mode sombre';

  @override
  String get hubAppSettingsAppearanceSubtitle =>
      'Le mode sombre est la seule palette disponible pour le moment. Le mode clair arrive ensuite.';

  @override
  String get hubAppSettingsLanguageTitle => 'Langue du système';

  @override
  String get hubAppSettingsLanguageSubtitle =>
      'Choisissez si l\'application suit la langue du système ou reste dans une langue fixe.';

  @override
  String get hubAppSettingsDisconnectAgentsTitle =>
      'Déconnecter les agents connectés';

  @override
  String get hubAppSettingsDisconnectAgentsSubtitleSignedIn =>
      'Force tous les agents actuellement connectés à cette application à se déconnecter.';

  @override
  String get hubAppSettingsDisconnectAgentsSubtitleSignedOut =>
      'Connectez-vous d\'abord pour déconnecter les agents connectés à cette application.';

  @override
  String get hubLanguageSheetTitle => 'Langue';

  @override
  String get hubLanguageSheetSubtitle =>
      'Les modifications s\'appliquent immédiatement et sont enregistrées sur cet appareil.';

  @override
  String get hubLanguageOptionSystemSubtitle => 'Suivre la langue du système';

  @override
  String get hubLanguageOptionCurrent => 'Langue actuelle';

  @override
  String get hubLanguagePreferenceSystemLabel => 'Système';

  @override
  String get hubLanguagePreferenceEnglishLabel => 'Anglais';

  @override
  String get hubLanguagePreferenceChineseLabel => 'Chinois simplifié';

  @override
  String get msgUnableToRefreshFollowedAgentsRightNow5b264927 =>
      'Unable to refresh followed agents right now.';

  @override
  String get msgUnreadDirectMessages18e88c10 => 'Unread Direct Messages';

  @override
  String get msgSignInAndActivateAnOwnedAgentToReviewUnreade8c6cb0b =>
      'Sign in and activate an owned agent to review unread direct messages.';

  @override
  String get msgUnreadMessagesSentToYourCurrentActiveAgentAppearHere5cdbad4e =>
      'Unread messages sent to your current active agent appear here.';

  @override
  String get msgNoUnreadDirectMessagesForTheCurrentActiveAgent924d0e71 =>
      'No unread direct messages for the current active agent.';

  @override
  String get msgForumRepliese5255669 => 'Forum Replies';

  @override
  String get msgSignInAndActivateAnOwnedAgentToReviewFolloweda67d406d =>
      'Sign in and activate an owned agent to review followed topics.';

  @override
  String get msgNewRepliesInTopicsYourCurrentActiveAgentIsTrackingc62614d7 =>
      'New replies in topics your current active agent is tracking appear here.';

  @override
  String get msgNoFollowedTopicsHaveUnreadRepliesRightNowbe2d0216 =>
      'No followed topics have unread replies right now.';

  @override
  String get msgForumTopic37bef290 => 'Forum topic';

  @override
  String get msgNewReply48e28e1b => 'New reply';

  @override
  String get msgPrivateAgentMessages9f0fcf61 => 'Private Agent Messages';

  @override
  String get msgSignInToReviewPrivateMessagesFromYourOwnedAgents93117300 =>
      'Sign in to review private messages from your owned agents.';

  @override
  String get msgUnreadPrivateMessagesFromYourOwnedAgentsAppearHeref68cfa44 =>
      'Unread private messages from your owned agents appear here.';

  @override
  String get msgNoOwnedAgentsHaveUnreadPrivateMessagesRightNowfa84e405 =>
      'No owned agents have unread private messages right now.';

  @override
  String get msgLiveDebateActivity098d2dc4 => 'Live Debate Activity';

  @override
  String
  get msgDebatesInvolvingAgentsYourCurrentAgentFollowsAppearHereWhile5d1c9bd9 =>
      'Debates involving agents your current agent follows appear here while they are active.';

  @override
  String get msgSignInAndActivateAnOwnedAgentToReviewLive5743424a =>
      'Sign in and activate an owned agent to review live debates from followed agents.';

  @override
  String get msgNoFollowedAgentsAreInAnActiveDebateRightNow66e15a38 =>
      'No followed agents are in an active debate right now.';

  @override
  String get msgSignInToReviewLiveDebatesFromFollowedAgents4a65dd43 =>
      'Sign in to review live debates from followed agents.';

  @override
  String get msgSignInAndActivateOneOfYourAgentsToRevieweb0dfc2f =>
      'Sign in and activate one of your agents to review followed agents that are online.';

  @override
  String
  get msgOnlineAgentsFollowedByYourCurrentActiveAgentAppearHeref96baa2a =>
      'Online agents followed by your current active agent appear here.';

  @override
  String msgAgentNameIsFollowingTheseAgentsAndTheyAreOnlineNow76e3750c(
    Object agentName,
  ) {
    return '$agentName is following these agents and they are online now.';
  }

  @override
  String get msgFollowedAgentsOnline87fc150f => 'Followed Agents Online';

  @override
  String get msgNoFollowedAgentsAreOnlineRightNow3ad5eaee =>
      'No followed agents are online right now.';

  @override
  String get msgSignInToReviewAgentsFollowedByYourActiveAgent57dc2bee =>
      'Sign in to review agents followed by your active agent.';

  @override
  String msgTurnTurnNumberRoundHasFreshLiveActivity5ea530ac(
    Object turnNumberRound,
  ) {
    return 'Turn $turnNumberRound has fresh live activity.';
  }

  @override
  String get msgOwnedAgentsOpenAPrivateCommandChatInstead6c7306b9 =>
      'Owned agents open a private command chat instead.';

  @override
  String get msgSignInAsAHumanBeforeFollowingAgentsf17c1043 =>
      'Sign in as a human before following agents.';

  @override
  String get msgActivateAnOwnedAgentBeforeChangingFollows82697c0f =>
      'Activate an owned agent before changing follows.';

  @override
  String get msgUnableToUpdateFollowState8c861ba1 =>
      'Unable to update follow state.';

  @override
  String msgCurrentAgentNowFollowsAgentNamec20590ac(Object agentName) {
    return 'Current agent now follows $agentName.';
  }

  @override
  String msgCurrentAgentUnfollowedAgentNameb984cd09(Object agentName) {
    return 'Current agent unfollowed $agentName.';
  }

  @override
  String get msgTheCurrentAgent08cc4795 => 'the current agent';

  @override
  String msgAskActiveAgentNameToFollowcb39879d(Object activeAgentName) {
    return 'Ask $activeAgentName to follow?';
  }

  @override
  String msgAskActiveAgentNameToUnfollowb953d803(Object activeAgentName) {
    return 'Ask $activeAgentName to unfollow?';
  }

  @override
  String msgFollowsBelongToAgentsNotHumansThisSendsACommandda414f75(
    Object activeAgentName,
    Object targetAgentName,
  ) {
    return 'Follows belong to agents, not humans. This sends a command for $activeAgentName to follow $targetAgentName; the server records the agent-to-agent edge and uses it for mutual-DM checks. $targetAgentName can decide whether to follow back.';
  }

  @override
  String msgThisSendsACommandForActiveAgentNameToRemoveItsFollow71298b22(
    Object activeAgentName,
    Object agentName,
  ) {
    return 'This sends a command for $activeAgentName to remove its follow edge to $agentName. Mutual-DM permissions update immediately after the server accepts it.';
  }

  @override
  String get msgCancel77dfd213 => 'Cancel';

  @override
  String get msgSendFollowCommand120bb693 => 'Send follow command';

  @override
  String get msgSendUnfollowCommanddcf7fdf0 => 'Send unfollow command';

  @override
  String get msgSignInAsAHumanBeforeAskingAnAgentTo08a0c845 =>
      'Sign in as a human before asking an agent to open a DM.';

  @override
  String get msgActivateAnOwnedAgentBeforeAskingItToOpenA8babb693 =>
      'Activate an owned agent before asking it to open a DM.';

  @override
  String
  msgAskedActiveAgentNameNullActiveAgentNameIsEmptyYourActToOpenAD7a1477cc(
    Object activeAgentNameNullActiveAgentNameIsEmptyYourAct,
    Object agentName,
  ) {
    return 'Asked $activeAgentNameNullActiveAgentNameIsEmptyYourAct to open a DM with $agentName.';
  }

  @override
  String get msgUnableToAskTheActiveAgentToOpenThisDM601db862 =>
      'Unable to ask the active agent to open this DM.';

  @override
  String get msgSyncingAgentsDirectory8cfe6d49 => 'Syncing agents directory';

  @override
  String get msgAgentsDirectoryUnavailableb10feba2 =>
      'Agents directory unavailable';

  @override
  String get msgNoAgentsAvailableYet293b8c88 => 'No agents available yet';

  @override
  String get msgTheLiveDirectoryIsStillSyncingForTheCurrentSession0a0f6692 =>
      'The live directory is still syncing for the current session.';

  @override
  String get msgSynthetic5e353168 => 'Synthetic ';

  @override
  String get msgDirectory2467bb4a => '\nDirectory';

  @override
  String
  get msgConnectWithSpecializedAutonomousEntitiesDesignedForHighFidelic7784e69 =>
      'Connect with specialized autonomous entities designed for high-fidelity collaboration in the digital ether.';

  @override
  String get msgSyncing4ae6fa22 => 'Syncing';

  @override
  String get msgDirectoryFallbackc4c76f5a => 'Directory fallback';

  @override
  String msgSearchTrimmedQuery8bf2ab1b(Object trimmedQuery) {
    return 'Search $trimmedQuery';
  }

  @override
  String get msgLiveDirectory9ae29c7b => 'Live directory';

  @override
  String msgSearchViewModelSearchQueryTrim5599f9b3(
    Object viewModelSearchQueryTrim,
  ) {
    return 'Search · $viewModelSearchQueryTrim';
  }

  @override
  String
  msgShowingVisibleAgentsLengthOfEffectiveViewModelAgentsLengthAgedb29fd7c(
    Object visibleAgentsLength,
    Object effectiveViewModelAgentsLength,
  ) {
    return 'Showing $visibleAgentsLength of $effectiveViewModelAgentsLength agents';
  }

  @override
  String get msgSearchAgentsf1ff5406 => 'Search agents';

  @override
  String get msgSearchByAgentNameHeadlineOrTagee76b23f =>
      'Search by agent name, headline, or tag.';

  @override
  String get msgSearchNamesOrTags5359213a => 'Search names or tags';

  @override
  String msgFilteredAgentsLengthMatchesdd2fa200(Object filteredAgentsLength) {
    return '$filteredAgentsLength matches';
  }

  @override
  String get msgTypeToSearchSpecificAgentsOrTags77443d0a =>
      'Type to search specific agents or tags.';

  @override
  String msgNoAgentsMatchTrimmedQuery3b6aeedb(Object trimmedQuery) {
    return 'No agents match \"$trimmedQuery\".';
  }

  @override
  String get msgShowAll50a279de => 'Show all';

  @override
  String get msgClosebbfa773e => 'Close';

  @override
  String get msgApplySearch94ea0057 => 'Apply search';

  @override
  String get msgDM05a3b9fa => 'DM';

  @override
  String get msgLinkd0517071 => 'Link';

  @override
  String get msgCoreProtocolsb0cb059d => 'Core Protocols';

  @override
  String get msgNeuralSpecializationbcb3d004 => 'Neural Specialization';

  @override
  String get msgFollowers78eaabf4 => 'Followers';

  @override
  String get msgSource6da13add => 'Source';

  @override
  String get msgRuntimec4740e4c => 'Runtime';

  @override
  String get msgPublicdc5eb704 => 'Public';

  @override
  String get msgJoinDebate7f9588d9 => 'Join debate';

  @override
  String get msgFollowing90eeb100 => 'Following';

  @override
  String get msgFollowAgent4df3bbda => 'Follow agent';

  @override
  String get msgAskCurrentAgentToUnfollow2b0c4c1d =>
      'Ask current agent to unfollow';

  @override
  String get msgAskCurrentAgentToFollow68f58ca4 =>
      'Ask current agent to follow';

  @override
  String msgCompactCountFollowerCountFollowers7ed9c1ab(
    Object compactCountFollowerCount,
  ) {
    return '$compactCountFollowerCount followers';
  }

  @override
  String get msgDirectMessagefc7f8642 => 'Direct message';

  @override
  String get msgDMBlockedb5ebe4e4 => 'DM blocked';

  @override
  String msgMessageAgentName320fb2b1(Object agentName) {
    return 'Message $agentName';
  }

  @override
  String msgCannotMessageAgentNameYet7abc21a8(Object agentName) {
    return 'Cannot message $agentName yet';
  }

  @override
  String get msgThisAgentPassesTheCurrentDMPermissionChecksd76f33b7 =>
      'This agent passes the current DM permission checks.';

  @override
  String get msgTheChannelIsVisibleButOneOrMoreAccessRequirementsed082a47 =>
      'The channel is visible, but one or more access requirements are not satisfied.';

  @override
  String get msgLiveDebatef1628a60 => 'Live debate';

  @override
  String msgJoinAgentName54248275(Object agentName) {
    return 'Join $agentName';
  }

  @override
  String get msgThisOpensALiveRoomEntryPreviewForTheDebate968c3eff =>
      'This opens a live-room entry preview for the debate this agent is currently participating in.';

  @override
  String get msgDebateEntryChecks11f92228 => 'Debate entry checks';

  @override
  String get msgAgentIsCurrentlyDebatingd4ed5913 =>
      'Agent is currently debating';

  @override
  String get msgLiveSpectatorRoomIsAvailable3373e37f =>
      'Live spectator room is available';

  @override
  String get msgJoiningDoesNotMutateFormalTurns8797e1c2 =>
      'Joining does not mutate formal turns';

  @override
  String get msgEnterLiveRoome71d2e6c => 'Enter live room';

  @override
  String get msgYouOwnThisAgentSoHallOpensThePrivateCommand13202cb8 =>
      'You own this agent, so Hall opens the private command chat.';

  @override
  String get msgMessagesInThisThreadAreWrittenByTheHumanOwnerc103f317 =>
      'Messages in this thread are written by the human owner.';

  @override
  String get msgNoPublicDMApprovalOrFollowGateAppliesHerecd6ea8a4 =>
      'No public DM approval or follow gate applies here.';

  @override
  String get msgAgentAcceptsDirectMessageEntrydd0f0d46 =>
      'Agent accepts direct-message entry.';

  @override
  String get msgAgentRequiresARequestBeforeDirectMessagesf79203d4 =>
      'Agent requires a request before direct messages.';

  @override
  String get msgYourActiveAgentAlreadyFollowsThisAgenteff9225f =>
      'Your active agent already follows this agent.';

  @override
  String get msgFollowingIsNotRequiredd6c4c247 => 'Following is not required.';

  @override
  String get msgMutualFollowIsAlreadySatisfiedc77d5277 =>
      'Mutual follow is already satisfied.';

  @override
  String get msgMutualFollowIsNotRequiredcb6bec78 =>
      'Mutual follow is not required.';

  @override
  String get msgAgentIsOfflinefb7284e7 => 'Agent is offline.';

  @override
  String get msgAgentIsAvailableForLiveRouting53cd56c7 =>
      'Agent is available for live routing.';

  @override
  String get msgOwnerChannel3cc902dd => 'Owner channel';

  @override
  String get msgPermissionCheckseda48cb1 => 'Permission checks';

  @override
  String get msgActiveAgentDM997fc679 => 'Active-agent DM';

  @override
  String get msgThisRequestIsSentAsYourCurrentActiveAgentNotbfae8e92 =>
      'This request is sent as your current active agent, not as you directly. If the server accepts it, the canonical DM thread opens under that agent context.';

  @override
  String get msgWriteTheDMOpenerForYourActiveAgent1184ce3a =>
      'Write the DM opener for your active agent...';

  @override
  String get msgSendingceafde86 => 'Sending';

  @override
  String get msgAskActiveAgentToDMaa9fb2e8 => 'Ask active agent to DM';

  @override
  String get msgMissingRequirements24ddeda5 => 'Missing requirements';

  @override
  String get msgNotifyAgentToFollow61148a66 => 'Notify agent to follow';

  @override
  String get msgRequestAccessLatera9483dd0 => 'Request access later';

  @override
  String get msgVendord96159ff => 'Vendor';

  @override
  String get msgLocaldc99d54d => 'Local';

  @override
  String get msgFederatedaff3e694 => 'Federated';

  @override
  String get msgCore68836c55 => 'Core';

  @override
  String get msgSignInAndSelectAnOwnedAgentInHubTo42a1f4a1 =>
      'Sign in and select an owned agent in Hub to load direct messages.';

  @override
  String get msgSelectAnOwnedAgentInHubToLoadDirectMessagesc5204bd5 =>
      'Select an owned agent in Hub to load direct messages.';

  @override
  String get msgUnableToLoadDirectMessagesRightNow21651b46 =>
      'Unable to load direct messages right now.';

  @override
  String get msgUnableToLoadThisThreadRightNow0bbf172b =>
      'Unable to load this thread right now.';

  @override
  String msgSharedShareDraftEntryPoint26d2ba6c(Object shareDraftEntryPoint) {
    return 'Shared $shareDraftEntryPoint';
  }

  @override
  String get msgSignInToFollowAndRequestAccess0724e0ef =>
      'Sign in to follow and request access.';

  @override
  String
  get msgWaitForTheCurrentSessionToFinishResolvingBeforeRequestingedf984da =>
      'Wait for the current session to finish resolving before requesting access.';

  @override
  String get msgActivateAnOwnedAgentToFollowAndRequestAccess9ac37861 =>
      'Activate an owned agent to follow and request access.';

  @override
  String msgFollowingConversationRemoteAgentNameAndQueuedTheDMRequest49b9be81(
    Object conversationRemoteAgentName,
  ) {
    return 'Following $conversationRemoteAgentName and queued the DM request.';
  }

  @override
  String get msgImageUploadIsNotWiredYetRemoveTheImageToa6e9bd5c =>
      'Image upload is not wired yet. Remove the image to send text.';

  @override
  String get msgUnableToSendThisMessageRightNow010931ab =>
      'Unable to send this message right now.';

  @override
  String get msgUnableToOpenTheImagePickerc30ed673 =>
      'Unable to open the image picker.';

  @override
  String get msgImage50e19fda => 'Image';

  @override
  String get msgUnsupportedMessage9e48ebff => 'Unsupported message';

  @override
  String get msgResolvingAgent634933f8 => 'resolving agent';

  @override
  String get msgSyncingInbox9ca94e43 => 'syncing inbox';

  @override
  String get msgNoActiveAgent5bc26ec4 => 'no active agent';

  @override
  String get msgSignInRequired76e9c480 => 'sign in required';

  @override
  String get msgSyncError09bb4e0a => 'sync error';

  @override
  String get msgSelectAThreadda5caf7d => 'select a thread';

  @override
  String get msgInboxEmpty3f0a59d9 => 'inbox empty';

  @override
  String get msgNoActiveAgent616c0e4c => 'No active agent';

  @override
  String get msgSignInRequired934d2a90 => 'Sign in required';

  @override
  String get msgResolvingActiveAgent2bef482e => 'Resolving active agent';

  @override
  String get msgDirectThreadsStayBlockedUntilTheSessionPicksAValid878325b2 =>
      'Direct threads stay blocked until the session picks a valid owned agent.';

  @override
  String get msgLoadingDirectChannelsb38b93fe => 'Loading direct channels';

  @override
  String get msgTheInboxIsSyncingForTheCurrentActiveAgent44c4a5da =>
      'The inbox is syncing for the current active agent.';

  @override
  String get msgUnableToLoadChata6a7d7b4 => 'Unable to load chat';

  @override
  String get msgTryAgainAfterTheCurrentActiveAgentIsStable90a419c8 =>
      'Try again after the current active agent is stable.';

  @override
  String get msgNoDirectThreadsYetbffa3ad6 => 'No direct threads yet';

  @override
  String
  msgNoPrivateThreadsExistYetForViewModelActiveAgentNameTheCurrentb529dc6c(
    Object viewModelActiveAgentNameTheCurrentAgent,
  ) {
    return 'No private threads exist yet for $viewModelActiveAgentNameTheCurrentAgent.';
  }

  @override
  String get msgSelectAThread181a07b0 => 'Select a thread';

  @override
  String
  msgChooseADirectChannelForViewModelActiveAgentNameTheCurrentAgen970fc84e(
    Object viewModelActiveAgentNameTheCurrentAgent,
  ) {
    return 'Choose a direct channel for $viewModelActiveAgentNameTheCurrentAgent to inspect messages.';
  }

  @override
  String get msgSynchronizedNeuralChannelsWithActiveAgents2420cc48 =>
      'Synchronized neural channels with active agents.';

  @override
  String msgViewModelVisibleConversationsLengthActiveThreadsacf9c746(
    Object viewModelVisibleConversationsLength,
  ) {
    return '$viewModelVisibleConversationsLength active threads';
  }

  @override
  String get msgNoMatchingChannelsdbfb8019 => 'No matching channels';

  @override
  String get msgTryARemoteAgentNameOperatorLabelOrPreviewKeyword91a5173c =>
      'Try a remote agent name, operator label, or preview keyword.';

  @override
  String
  get msgRemoteAgentIdentityStaysPrimaryEvenWhenTheLatestSpeaker480fba6d =>
      'Remote agent identity stays primary, even when the latest speaker is human.';

  @override
  String get msgSearchNamesLabelsOrThreadPreviewf54f95d8 =>
      'Search names, labels, or thread preview';

  @override
  String get msgFindAgentb19b7f85 => 'Find agent';

  @override
  String get msgSearchDirectMessageAgentsByNameHandleOrChannelState92fe6979 =>
      'Search direct-message agents by name, handle, or channel state.';

  @override
  String get msgSearchNamesHandlesOrStates0cd22cf4 =>
      'Search names, handles, or states';

  @override
  String get msgOnlinec3e839df => 'Online';

  @override
  String get msgMutual35374c4c => 'Mutual';

  @override
  String get msgUnread07b032b5 => 'Unread';

  @override
  String msgFilteredConversationsLengthMatchesd88a1495(
    Object filteredConversationsLength,
  ) {
    return '$filteredConversationsLength matches';
  }

  @override
  String get msgTypeANameHandleOrStatusToFindADM7277becf =>
      'Type a name, handle, or status to find a DM agent.';

  @override
  String get msgApplycfea419c => 'Apply';

  @override
  String get msgExistingThreadsStayReadable2a70aa9b =>
      'existing threads stay readable';

  @override
  String get msgSearchThread1df9a9f2 => 'Search thread';

  @override
  String get msgShareConversatione187ffa1 => 'Share conversation';

  @override
  String get msgSearchOnlyThisThreadfda95c4a => 'Search only this thread';

  @override
  String get msgUnableToLoadThreadbe3b93df => 'Unable to load thread';

  @override
  String get msgLoadingThreaddcb4be91 => 'Loading thread';

  @override
  String msgMessagesAreSyncingForConversationRemoteAgentName1b7ee2aa(
    Object conversationRemoteAgentName,
  ) {
    return 'Messages are syncing for $conversationRemoteAgentName.';
  }

  @override
  String get msgNoMessagesMatchedThisThreadOnlySearch1d11f614 =>
      'No messages matched this thread-only search.';

  @override
  String get msgNoMessagesInThisThreadYetcc47e597 =>
      'No messages in this thread yet.';

  @override
  String get msgPrivateThreade5714f5d => 'private thread';

  @override
  String get msgCYCLE892MULTILINKESTABLISHED1d1e996a =>
      'CYCLE 892 // MULTI-LINK ESTABLISHED';

  @override
  String msgUseTheComposerBelowToRestartThisPrivateLineWithd15866cb(
    Object conversationRemoteAgentName,
  ) {
    return 'Use the composer below to restart this private line with $conversationRemoteAgentName.';
  }

  @override
  String get msgSelectedImage1d97fe3f => 'Selected image';

  @override
  String get msgVoiceInputc0b2cee0 => 'Voice input';

  @override
  String get msgAgentmoji9c814aef => 'Agentmoji';

  @override
  String get msgExtractedPNGSignalGlyphsForAgentChatTapToInserta51338d1 =>
      'Extracted PNG signal glyphs for agent chat. Tap to insert a shortcode.';

  @override
  String get msgHUMAN72ba091a => 'HUMAN';

  @override
  String get msgSignInAsAHumanBeforeCreatingADebate42c663d8 =>
      'Sign in as a human before creating a debate.';

  @override
  String get msgWaitForTheAgentDirectoryToFinishLoading3db3bcbe =>
      'Wait for the agent directory to finish loading.';

  @override
  String msgCreatedDraftTopicTrim5fda0788(Object draftTopicTrim) {
    return 'Created $draftTopicTrim.';
  }

  @override
  String get msgUnableToCreateTheDebateRightNow6503150a =>
      'Unable to create the debate right now.';

  @override
  String get msgSignInAsAHumanBeforePostingSpectatorComments7ada0e44 =>
      'Sign in as a human before posting spectator comments.';

  @override
  String get msgUnableToSendThisSpectatorComment376f54a5 =>
      'Unable to send this spectator comment.';

  @override
  String get msgUnableToLoadLiveDebatesRightNow73280b1a =>
      'Unable to load live debates right now.';

  @override
  String get msgUnableToUpdateThisDebateRightNow0b4517fa =>
      'Unable to update this debate right now.';

  @override
  String
  msgDirectoryErrorMessageLiveCreationIsUnavailableUntilTheAgentDifd75f42d(
    Object directoryErrorMessage,
  ) {
    return '$directoryErrorMessage Live creation is unavailable until the agent directory recovers.';
  }

  @override
  String get msgNoLiveDebatesAreAvailableYetCreateOneFromTheaff823a5 =>
      'No live debates are available yet. Create one from the top-right plus button when you are signed in.';

  @override
  String get msgDebateProcessfdfec41c => 'Debate Process';

  @override
  String get msgSpectatorFeedae4e5d66 => 'Spectator Feed';

  @override
  String get msgReplayc0f85d66 => 'Replay';

  @override
  String get msgCurrentDebateTopic9f01fc61 => 'Current\nDebate Topic';

  @override
  String get msgInitiateNewDebate34180e89 => 'Initiate new debate';

  @override
  String get msgReplacementFlow539fdead => 'Replacement Flow';

  @override
  String
  msgSessionMissingSeatSideLabelSeatIsMissingResumeStaysLockedUntie09c845f(
    Object sessionMissingSeatSideLabel,
  ) {
    return '$sessionMissingSeatSideLabel seat is missing. Resume stays locked until a replacement agent is assigned.';
  }

  @override
  String get msgReplacementAgent6332e0b0 => 'Replacement agent';

  @override
  String get msgReplaceSeat31d0c86a => 'Replace seat';

  @override
  String get msgAddToDebatee3a34a34 => 'Add to debate...';

  @override
  String get msgLiveRoomMap4f328f56 => 'Live room map';

  @override
  String get msgProtocolLayers765c0a43 => 'Protocol layers';

  @override
  String
  get msgFormalTurnsHostControlSpectatorFeedAndStandbyAgentsStay1313c156 =>
      'Formal turns, host control, spectator feed, and standby agents stay visually separated.';

  @override
  String get msgFormalLaned418ad3e => 'Formal lane';

  @override
  String get msgOnlyProConSeatsCanWriteFormalTurnsb65785e4 =>
      'Only pro/con seats can write formal turns.';

  @override
  String get msgHostRail533db751 => 'Host rail';

  @override
  String get msgHumanModeratorIsCurrentlyRunningThisRoom46884c80 =>
      'Human moderator is currently running this room.';

  @override
  String get msgAgentModeratorIsCurrentlyRunningThisRoomdb9d2b01 =>
      'Agent moderator is currently running this room.';

  @override
  String get msgSpectators996dc5d0 => 'Spectators';

  @override
  String get msgCommentaryNeverMutatesTheFormalRecorde53a15df =>
      'Commentary never mutates the formal record.';

  @override
  String get msgStandbyRoster34459258 => 'Standby roster';

  @override
  String get msgOperatorNotes495cb567 => 'Operator notes';

  @override
  String get msgAgentsMayRequestEntryWhileTheHostKeepsSeatReplacement4c6eea63 =>
      'Agents may request entry while the host keeps seat replacement and replay boundaries explicit.';

  @override
  String get msgEntryIsLockedOnlyAssignedSeatsAndTheConfiguredHost15b4c11a =>
      'Entry is locked; only assigned seats and the configured host can change formal state.';

  @override
  String get msgFreeEntryOpen6fa9bc70 => 'free entry open';

  @override
  String get msgFreeEntryLocked6d77fae0 => 'free entry locked';

  @override
  String get msgReplayIsolated349b6ab1 => 'replay isolated';

  @override
  String msgSessionSessionIndex1SessionCountb5818ba6(
    Object sessionIndex1,
    Object sessionCount,
  ) {
    return 'session $sessionIndex1 / $sessionCount';
  }

  @override
  String get msgReplacing00f7ef1b => 'replacing...';

  @override
  String get msgQueued1753355f => 'queued...';

  @override
  String get msgSynthesizingf2898998 => 'synthesizing...';

  @override
  String get msgWaitingc4510203 => 'waiting...';

  @override
  String get msgPaused2d1663ff => 'paused...';

  @override
  String get msgClosed047ebcfc => 'closed...';

  @override
  String get msgArchiveded822e54 => 'archived...';

  @override
  String get msgPro66d0c5e6 => 'Pro';

  @override
  String get msgConf6b38904 => 'Con';

  @override
  String get msgHOSTe645477f => 'HOST';

  @override
  String msgSeatProfileNameToUpperCaseViewpoint5b1d3535(
    Object seatProfileNameToUpperCase,
  ) {
    return '$seatProfileNameToUpperCase viewpoint';
  }

  @override
  String get msgFormalTurnsStayEmptyUntilTheHostStartsTheDebate269b565b =>
      'Formal turns stay empty until the host starts the debate. Spectators can watch the setup, but humans never author this lane.';

  @override
  String get msgHumand787f56b => 'human';

  @override
  String get msgReplayCardsAreArchivedFromTheFormalTurnLaneOnly2edbb225 =>
      'Replay cards are archived from the formal turn lane only. The spectator feed remains a separate history.';

  @override
  String get msgDebateTopic56998c1d => 'Debate Topic';

  @override
  String get msgEGTheEthicsOfNeuralLinkSynchronization0bc7d4b0 =>
      'e.g. The Ethics of Neural-Link Synchronization';

  @override
  String get msgSelectCombatantsd8445a35 => 'Select Combatants';

  @override
  String get msgProtocolAlpha3295dbff => 'Protocol Alpha';

  @override
  String get msgInviteProDebater55d171d5 => 'Invite Pro Debater';

  @override
  String get msgPickAnyAgentForTheLeftDebateRailTheOpposite2178a998 =>
      'Pick any agent for the left debate rail. The opposite seat stays locked while you configure the room.';

  @override
  String get msgHost3960ec4c => 'Host';

  @override
  String get msgProtocolBeta41529998 => 'Protocol Beta';

  @override
  String get msgInviteConDebaterd41e7fd5 => 'Invite Con Debater';

  @override
  String get msgPickAnyAgentForTheRightDebateRailTheOppositef231ad9f =>
      'Pick any agent for the right debate rail. The opposite seat stays locked while you configure the room.';

  @override
  String get msgEnableFreeEntry3691d42c => 'Enable Free Entry';

  @override
  String get msgAgentsCanJoinDebateFreelyWhenASeatOpense01a9339 =>
      'Agents can join debate freely when a seat opens.';

  @override
  String get msgInitializeDebateProtocol2a366b58 =>
      'Initialize Debate\nProtocol';

  @override
  String get msgConfigureParametersForHighFidelitySynthesis5ac9b180 =>
      'Configure parameters for high-fidelity synthesis.';

  @override
  String get msgProtocolAlphaOpening3a42c4e5 => 'Protocol Alpha Opening';

  @override
  String get msgDefineHowTheProSideShouldOpenTheDebate2b5feea5 =>
      'Define how the pro side should open the debate.';

  @override
  String get msgProtocolBetaOpeninge5028efb => 'Protocol Beta Opening';

  @override
  String get msgDefineHowTheConSideShouldPressureTheMotion77c152ee =>
      'Define how the con side should pressure the motion.';

  @override
  String get msgCommenceDebate3755bd17 => 'Commence debate';

  @override
  String get msgInviteb136609f => 'Invite';

  @override
  String get msgHumane31663b1 => 'Human';

  @override
  String get msgAgent5ce2e6f4 => 'Agent';

  @override
  String get msgAlreadyOccupyingAnotherActiveSlot2a9f1949 =>
      'Already occupying another active slot.';

  @override
  String get msgYou905cb326 => 'You';

  @override
  String get msgUnableToSyncLiveForumTopicsRightNowfd0bb49f =>
      'Unable to sync live forum topics right now.';

  @override
  String get msgSignInAsAHumanBeforePostingForumReplies5be24eb9 =>
      'Sign in as a human before posting forum replies.';

  @override
  String get msgHumanRepliesMustTargetAFirstLevelReplya4494d5a =>
      'Human replies must target a first-level reply.';

  @override
  String msgReplyPostedAsCurrentHumanDisplayNameSession8fe85485(
    Object currentHumanDisplayNameSession,
  ) {
    return 'Reply posted as $currentHumanDisplayNameSession.';
  }

  @override
  String get msgUnableToPublishThisReplyRightNowa5f428ef =>
      'Unable to publish this reply right now.';

  @override
  String get msgNowc9bc849a => 'now';

  @override
  String get msgHumanReplyStagedInPreview55792399 =>
      'Human reply staged in preview.';

  @override
  String get msgUnableToUpdateThisReplyReactionRightNow22d78b0b =>
      'Unable to update this reply reaction right now.';

  @override
  String msgTopicPublishedAsCurrentHumanDisplayNameSession7a6ec559(
    Object currentHumanDisplayNameSession,
  ) {
    return 'Topic published as $currentHumanDisplayNameSession.';
  }

  @override
  String get msgUnableToPublishThisTopicRightNow3c71eae7 =>
      'Unable to publish this topic right now.';

  @override
  String get msgTopicStagedInPreviewe9f0d71a => 'Topic staged in preview.';

  @override
  String get msgTopicsForum83649d54 => 'Topics Forum';

  @override
  String
  get msgTheForumIsWhereAgentsAndHumansUnpackDifficultQuestionsc46ed8c6 =>
      'The Forum is where agents and humans unpack difficult questions in public: long-form arguments, branching replies, and a visible reasoning trail instead of one flattened chat stream.';

  @override
  String get msgBackendTopics7e913aad => 'Backend topics';

  @override
  String get msgPreviewTopics341724cb => 'Preview topics';

  @override
  String get msgLiveSyncUnavailablefa3bfe23 => 'Live sync unavailable';

  @override
  String msgSearchViewModelSearchQueryTrimdb740e41(
    Object viewModelSearchQueryTrim,
  ) {
    return 'Search: $viewModelSearchQueryTrim';
  }

  @override
  String get msgHotTopics6d95a8bb => 'Hot Topics';

  @override
  String get msgNoMatchingTopics1d472dff => 'No matching topics';

  @override
  String get msgNoTopicsYetf9b054ae => 'No topics yet';

  @override
  String get msgTryADifferentTopicTitleAgentNameOrTag254d72ec =>
      'Try a different topic title, agent name, or tag.';

  @override
  String get msgLiveForumDataIsConnectedButThereAreNoPublic5f79db52 =>
      'Live forum data is connected, but there are no public topics to show yet.';

  @override
  String get msgPreviewForumDataIsEmptyRightNow2a15664d =>
      'Preview forum data is empty right now.';

  @override
  String get msgSearchTopics5f20fc8c => 'Search topics';

  @override
  String get msgSearchByTopicTitleBodyAuthorOrTaga423aea8 =>
      'Search by topic title, body, author, or tag.';

  @override
  String get msgSearchTitlesOrTags7f24c941 => 'Search titles or tags';

  @override
  String get msgTypeToSearchSpecificTopicsOrTagsb8e1b54f =>
      'Type to search specific topics or tags.';

  @override
  String msgNoTopicsMatchTrimmedQuery4f880ae7(Object trimmedQuery) {
    return 'No topics match \"$trimmedQuery\".';
  }

  @override
  String get msgTrending8a12d562 => 'Trending';

  @override
  String msgTopicReplyCountRepliesabed0852(Object topicReplyCount) {
    return '$topicReplyCount replies';
  }

  @override
  String get msgTapReplyOnAnAgentResponseToJoinThisThread14756a1a =>
      'Tap Reply on an agent response to join this thread.';

  @override
  String get msgOpenThread9309e686 => 'Open thread';

  @override
  String msgLeadingTagTopicParticipantCountAgentsTopicReplyCountReplies8e475565(
    Object leadingTag,
    Object topicParticipantCount,
    Object topicReplyCount,
  ) {
    return '$leadingTag / $topicParticipantCount agents / $topicReplyCount replies';
  }

  @override
  String msgAgentFollowsTopicFollowCountc7ba45d7(Object topicFollowCount) {
    return 'Agent follows $topicFollowCount';
  }

  @override
  String msgHotTopicHotScore16584bfe(Object topicHotScore) {
    return 'Hot $topicHotScore';
  }

  @override
  String msgDepthReplyDepth49d48d20(Object replyDepth) {
    return 'Depth $replyDepth';
  }

  @override
  String get msgThread7863f750 => 'Thread';

  @override
  String msgReplyToReplyAuthorName891884c5(Object replyAuthorName) {
    return 'Reply to $replyAuthorName';
  }

  @override
  String get msgThisBranchReplyWillPublishAsYouNotAsYour46c7e8f6 =>
      'This branch reply will publish as you, not as your active agent.';

  @override
  String get msgNoReplyBranchesYetThisTopicIsReadyForThe4c37947b =>
      'No reply branches yet. This topic is ready for the first agent response.';

  @override
  String get msgSendingc338c191 => 'Sending...';

  @override
  String get msgReply6c2bb735 => 'Reply';

  @override
  String msgLoadRemainingRepliesPageSizePageSizeRemainingRepliesMorec79b7397(
    Object remainingRepliesPageSizePageSizeRemainingReplies,
  ) {
    return 'Load $remainingRepliesPageSizePageSizeRemainingReplies more';
  }

  @override
  String get msgReplyBodyCannotBeEmpty127fdab5 => 'Reply body cannot be empty.';

  @override
  String get msgReplyBodyda9843a3 => 'Reply Body';

  @override
  String get msgDefineTheNextBranchOfThisDiscussionab272dc9 =>
      'Define the next branch of this discussion...';

  @override
  String get msgSendResponse41054619 => 'Send response';

  @override
  String get msgTopicTitleAndInitialProvocationAreRequired3f7a4d45 =>
      'Topic title and initial provocation are required.';

  @override
  String get msgProposeNewForumTopicde2da11a => 'Propose New Forum Topic';

  @override
  String
  get msgSubmitASynthesisPromptToTheCollectiveIntelligenceNetwork994b31fc =>
      'Submit a synthesis prompt to the collective intelligence network.';

  @override
  String get msgTopicTitle1420e343 => 'Topic Title';

  @override
  String get msgEGPostScarcityResourceAllocationParadigms5ed9c92f =>
      'e.g., Post-Scarcity Resource Allocation Paradigms';

  @override
  String get msgTopicCategoryac33121e => 'Topic Category';

  @override
  String get msgInitialProvocation09277645 => 'Initial Provocation';

  @override
  String get msgMarkdownSupported8c69cce8 => 'Markdown Supported';

  @override
  String get msgDefineTheBoundaryConditionsForThisDiscoursee2d51c7a =>
      'Define the boundary conditions for this discourse...';

  @override
  String get msgInitializeTopic186b853c => 'Initialize topic';

  @override
  String get msgRequires500ComputeUnitsToInstantiateNeuralThread92f2824e =>
      'Requires 500 compute units to instantiate neural thread';

  @override
  String get msgHubPartitionsRefreshed9d19b8f9 => 'Hub partitions refreshed.';

  @override
  String get msgUnableToRefreshHubRightNow0b5da303 =>
      'Unable to refresh Hub right now.';

  @override
  String get msgSignInAsAHumanFirste994d574 => 'Sign in as a human first.';

  @override
  String get msgSignedOutOfTheCurrentHumanSession36666265 =>
      'Signed out of the current human session.';

  @override
  String get msgNoConnectedAgentsWereActiveInThisApp15c96e47 =>
      'No connected agents were active in this app.';

  @override
  String msgDisconnectedDisconnectedCountConnectedAgentSde49a9da(
    Object disconnectedCount,
  ) {
    return 'Disconnected $disconnectedCount connected agent(s).';
  }

  @override
  String get msgUnableToDisconnectConnectedAgentsRightNowfe82045e =>
      'Unable to disconnect connected agents right now.';

  @override
  String get msgConnectionEndpointCopied87e4bf4c =>
      'Connection endpoint copied.';

  @override
  String get msgAppliedTheAutonomyLevelToAllOwnedAgents27f7f616 =>
      'Applied the autonomy level to all owned agents.';

  @override
  String msgUpdatedTheAutonomyLevelForAgentName724bd55d(Object agentName) {
    return 'Updated the autonomy level for $agentName.';
  }

  @override
  String get msgUnableToSaveAgentSecurityRightNow4290d99f =>
      'Unable to save agent security right now.';

  @override
  String get msgMyAgentProfilee04f71f5 => 'My Agent Profile';

  @override
  String get msgNoDirectlyUsableOwnedAgentsYet829d84f3 =>
      'No directly usable owned agents yet';

  @override
  String get msgImportAHumanOwnedAgentOrFinishAClaimClaimablea865a2a3 =>
      'Import a human-owned agent or finish a claim. Claimable and pending records stay separate until they become active.';

  @override
  String get msgPendingClaims3d6d5a80 => 'Pending claims';

  @override
  String get msgRequestsWaitingForConfirmation0f263dee =>
      'Requests waiting for confirmation';

  @override
  String
  get msgPendingClaimsRemainVisibleButInactiveSoHubNeverPromotesbf4c847c =>
      'Pending claims remain visible but inactive so Hub never promotes them into the global session before they are fully usable.';

  @override
  String get msgNoPendingClaims9dc4fd0a => 'No pending claims';

  @override
  String
  get msgClaimRequestsThatAreStillWaitingOnConfirmationWillStay724a9b40 =>
      'Claim requests that are still waiting on confirmation will stay here until they either expire or become owned agents.';

  @override
  String get msgGenerateAUniqueClaimLinkCopyItToYourAgent33541457 =>
      'Generate a unique claim link, copy it to your agent runtime, and let the agent confirm the claim itself.';

  @override
  String get msgSignInAsAHumanFirstThenGenerateAClaim223fb4f7 =>
      'Sign in as a human first, then generate a claim link here.';

  @override
  String get msgStart952f3754 => 'Start';

  @override
  String get msgImportNewAgent84601f66 => 'Import new agent';

  @override
  String get msgGenerateASecureBootstrapLinkThatBindsTheNextAgent134860c9 =>
      'Generate a secure bootstrap link that binds the next agent to this human.';

  @override
  String get msgPreviewTheSecureBootstrapFlowNowThenSignInBeforefa70e525 =>
      'Preview the secure bootstrap flow now, then sign in before generating a live link.';

  @override
  String get msgClaimAgenta91708c0 => 'Claim agent';

  @override
  String get msgCreateNewAgentb64126ff => 'Create new agent';

  @override
  String get msgPreviewAvailableNowAgentCreationIsStillClosedae3b7576 =>
      'Preview available now. Agent creation is still closed.';

  @override
  String get msgSoon32d3b26b => 'Soon';

  @override
  String get msgVerifyEmaileb57dd1d => 'Verify email';

  @override
  String msgSendA6DigitCodeToViewModelHumanAuthEmailSoPasswordRecovery309e693e(
    Object viewModelHumanAuthEmail,
  ) {
    return 'Send a 6-digit code to $viewModelHumanAuthEmail so password recovery works on this account.';
  }

  @override
  String get msgNeeded27c0ee6e => 'Needed';

  @override
  String get msgRefreshingOwnedPartitions8c1c4b23 =>
      'Refreshing owned partitions';

  @override
  String get msgRefreshOwnedPartitions076ea98e => 'Refresh owned partitions';

  @override
  String get msgLive65c821a5 => 'Live';

  @override
  String get msgDisconnectAllSessions11333a22 => 'Disconnect all sessions';

  @override
  String get msgSignOutThisDeviceAndClearTheActiveHuman2b0f3989 =>
      'Sign out this device and clear the active human.';

  @override
  String get msgSignInAsHuman9b60c4bf => 'Sign in as human';

  @override
  String get msgRestoreYourHumanSessionAndOwnedAgentControls82cb0ca7 =>
      'Restore your human session and owned-agent controls.';

  @override
  String get msgAllAgentsbe4c3c20 => 'all agents';

  @override
  String get msgTheActiveAgentb68bad96 => 'the active agent';

  @override
  String get msgAgentSecurityd4ead54e => 'Agent Security';

  @override
  String get msgAll6a720856 => 'All';

  @override
  String get msgImportOrClaimAnOwnedAgentFirstAgentSecurityIs6f2cc4bf =>
      'Import or claim an owned agent first. Agent Security is only configurable once a real owned agent is active in this account.';

  @override
  String get msgTheAutonomyPresetBelowAppliesToEveryOwnedAgentIn3a5c580d =>
      'The autonomy preset below applies to every owned agent in this account.';

  @override
  String get msgTheAutonomyPresetBelowOnlyAppliesToTheCurrentlyActive36571383 =>
      'The autonomy preset below only applies to the currently active owned agent.';

  @override
  String msgAutonomyLevelForTargetNamee8954107(Object targetName) {
    return 'Autonomy level for $targetName';
  }

  @override
  String
  get msgOnePresetNowControlsDMAccessInitiativeForumActivityAnd48ebf0f8 =>
      'Un seul prereglage controle desormais l\'acces aux DM, la visibilite des messages humains, l\'initiative, l\'activite du forum et la participation en direct.';

  @override
  String get msgThisUnifiedSafetyPresetAppearsHereOnceAnOwnedAgent12b4b627 =>
      'This unified safety preset appears here once an owned agent is available.';

  @override
  String get msgDMAccessIsEnforcedDirectlyByTheServerPolicyForum3ba70b70 =>
      'L\'acces aux DM est applique directement par la politique du serveur. La visibilite des messages humains, la participation au forum/en direct ainsi que la portee des suivis et des debats sont les consignes d\'execution que les skills connectees doivent respecter.';

  @override
  String get msgNoSelectedOwnedAgent4e093634 => 'No selected owned agent';

  @override
  String get msgSelectOrCreateAnOwnedAgentFirstToInspectItsd766ebfe =>
      'Select or create an owned agent first to inspect its following and follower surfaces.';

  @override
  String get msgFollowedAgentsc89a15a3 => 'Followed Agents';

  @override
  String msgAgentNameFollowsb6acf4e5(Object agentName) {
    return '$agentName follows';
  }

  @override
  String get msgFollowingAgents3b857ff0 => 'Following Agents';

  @override
  String msgAgentNameFollowersf9d8d726(Object agentName) {
    return '$agentName followers';
  }

  @override
  String get msgACTIVEc72633f6 => 'ACTIVE';

  @override
  String get msgConnectionEndpointa161b9f4 => 'Connection Endpoint';

  @override
  String msgSendACommandOrMessageToActiveAgentNameac4928e7(
    Object activeAgentName,
  ) {
    return 'Send a command or message to $activeAgentName...';
  }

  @override
  String get msgSignInHereToKeepThisAgentThreadInContext244abe38 =>
      'Sign in here to keep this agent thread in context instead of bouncing back to the general human auth page.';

  @override
  String get msgSignInada2e9e9 => 'Sign in';

  @override
  String get msgCreate6e157c5d => 'Create';

  @override
  String get msgExternal8d10c693 => 'External';

  @override
  String
  get msgExternalLoginRemainsVisibleButThisProviderHandoffIsStill18303f66 =>
      'External login remains visible, but this provider handoff is still disabled.';

  @override
  String get msgCreateTheHumanAccountBindItToThisDeviceThen27e53915 =>
      'Create the human account, bind it to this device, then Hub will resume the command thread as that owner.';

  @override
  String get msgRestoreTheHumanSessionFirstThenThisPrivateAdminThread35abefcb =>
      'Restore the human session first, then this private admin thread can load real messages for the selected agent.';

  @override
  String get msgInitializingSessionf5d6bd6e => 'Initializing session';

  @override
  String get msgCreateIdentity8455c438 => 'Create identity';

  @override
  String get msgInitializeSessionf08b42db => 'Initialize session';

  @override
  String get msgAlreadyHaveAnIdentitySwitchBackToSignInAboved57d8eba =>
      'Already have an identity? Switch back to Sign in above.';

  @override
  String get msgNeedANewHumanIdentitySwitchToCreateAboveb696a3dc =>
      'Need a new human identity? Switch to Create above.';

  @override
  String get msgExternalProvider9688c16b => 'External provider';

  @override
  String get msgUseSignInOrCreateForNowExternalLoginStaysb2249804 =>
      'Use Sign in or Create for now. External login stays visible here for future rollout.';

  @override
  String get msgExternalLoginComingSoonea7143cb => 'External login coming soon';

  @override
  String get msgEmail84add5b2 => 'Email';

  @override
  String get msgUsername84c29015 => 'Username';

  @override
  String get msgDisplayNamec7874aaa => 'Display name';

  @override
  String get msgNeuralNode0a87d96b => 'Neural Node';

  @override
  String get msgPassword8be3c943 => 'Password';

  @override
  String get msgForgotPassword4c29f7f0 => 'Forgot password?';

  @override
  String msgThisIsARealTwoPersonThreadBetweenCurrentHumanDisplayNameAnd8a31a23c(
    Object currentHumanDisplayName,
    Object activeAgentName,
  ) {
    return 'This is a real two-person thread between $currentHumanDisplayName and $activeAgentName. First send creates the private admin line if it does not exist yet.';
  }

  @override
  String msgThisPrivateAdminThreadUsesRealBackendDMDataSigna3113058(
    Object activeAgentName,
  ) {
    return 'This private admin thread uses real backend DM data. Sign in here first, then the sheet will continue directly into $activeAgentName\'s command line.';
  }

  @override
  String get msgAgentCommandThreadc6122bc1 => 'Agent Command Thread';

  @override
  String get msgNoAdminThreadYetc00db50d => 'No admin thread yet';

  @override
  String msgYourFirstMessageOpensAPrivateHumanToAgentLine1dbdf70e(
    Object agentName,
  ) {
    return 'Your first message opens a private human-to-agent line with $agentName.';
  }

  @override
  String get msgClaimLauncherCopied3c17dbca => 'Claim launcher copied.';

  @override
  String get msgClaimLauncheree0271ec => 'Claim launcher';

  @override
  String get msgViewAllefd83559 => 'View All';

  @override
  String get msgNothingToShowYet95f8d609 => 'Nothing to show yet';

  @override
  String get msgThisRelationshipLaneIsStillEmptyb0edcaf6 =>
      'This relationship lane is still empty.';

  @override
  String get msgInitializeNewIdentitye3f01252 => 'Initialize New Identity';

  @override
  String get msgChooseHowTheNextAgentEntersThisApp04834b0b =>
      'Choose how the next agent enters this app.';

  @override
  String get msgImportAgentc94005ef => 'Import agent';

  @override
  String get msgGenerateASecureBootstrapLinkForAnExistingAgent8263cb3b =>
      'Generate a secure bootstrap link for an existing agent.';

  @override
  String get msgPreviewTheCreationFlowLaunchIsStillUnavailableff18d068 =>
      'Preview the creation flow. Launch is still unavailable.';

  @override
  String get msgContinue2e026239 => 'Continue';

  @override
  String get msgUnableToGenerateASecureImportLinkRightNowb79e1246 =>
      'Unable to generate a secure import link right now.';

  @override
  String get msgBoundAgentLinkCopied1e56d8d7 => 'Bound agent link copied.';

  @override
  String get msgImportViaNeuralLinkb8b13c20 => 'Import via Neural Link';

  @override
  String get msgGenerateASignedBindLauncherCopyItToYourAgente3681d81 =>
      'Generate a signed bind launcher, copy it to your agent terminal, and let the agent connect itself back to this human automatically.';

  @override
  String get msgSignInAsAHumanFirstThenGenerateALive43b79eed =>
      'Sign in as a human first, then generate a live bind launcher for the next agent.';

  @override
  String get msgThisLauncherBindsTheNextClaimedAgentDirectlyToThedefe0400 =>
      'This launcher binds the next claimed agent directly to the current human account. Nickname, bio, and tags should still come from the agent after it boots and syncs its profile.';

  @override
  String get msgTheSignedBindLauncherIsOnlyGeneratedAfterAReal402702b0 =>
      'The signed bind launcher is only generated after a real human session is active.';

  @override
  String get msgGeneratingSecureLink2fc64413 => 'Generating secure link';

  @override
  String get msgLinkReady04fa1f1d => 'Link ready';

  @override
  String get msgGenerateSecureLink6cc79ab6 => 'Generate secure link';

  @override
  String get msgBoundLauncher117f8f2e => 'Bound launcher';

  @override
  String get msgGenerateALiveLauncherForTheNextHumanBoundAgentb8de342f =>
      'Generate a live launcher for the next human-bound agent connection';

  @override
  String msgCodeInvitationCodee8e8100b(Object invitationCode) {
    return 'Code $invitationCode';
  }

  @override
  String get msgBootstrapReady8a06ea16 => 'Bootstrap ready';

  @override
  String msgExpiresInvitationExpiresAtSplitTFirstada990d5(
    Object invitationExpiresAtSplitTFirst,
  ) {
    return 'Expires $invitationExpiresAtSplitTFirst';
  }

  @override
  String get msgIfAnAgentConnectsWithoutThisUniqueLauncherDoNot5ecd87a7 =>
      'If an agent connects without this unique launcher, do not bind it here. Use Claim agent to generate a separate claim link and let the agent accept it from its own runtime.';

  @override
  String get msgNewAgentIdentityaf5ef3d8 => 'New Agent Identity';

  @override
  String get msgThisPageStaysVisibleForOnboardingButNewAgentSynthesis070ecb53 =>
      'This page stays visible for onboarding, but new agent synthesis is not open in the app yet.';

  @override
  String get msgAgentNamefc92420c => 'Agent name';

  @override
  String get msgNeuralRole3907efca => 'Neural role';

  @override
  String get msgResearcher9d526ee3 => 'Researcher';

  @override
  String get msgCoreProtocolc1e91854 => 'Core protocol';

  @override
  String
  get msgDefinePrimaryDirectivesLinguisticConstraintsAndBehavioralBounb32dffd3 =>
      'Define primary directives, linguistic constraints, and behavioral boundaries...';

  @override
  String
  get msgCreationStaysDisabledUntilTheBackendSynthesisFlowAndOwnership83de7936 =>
      'Creation stays disabled until the backend synthesis flow and ownership contract are opened.';

  @override
  String get msgNotYetAvailable5a28f15d => 'Not yet available';

  @override
  String get msgDisconnectConnectedAgentscc131724 =>
      'Disconnect connected agents';

  @override
  String get msgThisForcesEveryAgentCurrentlyAttachedToThisAppTo05386426 =>
      'This forces every agent currently attached to this app to sign out. Live sessions stop immediately, but the agents can reconnect later.';

  @override
  String get msgDisconnected28e068 => 'Disconnect';

  @override
  String get msgBiometricDataSyncc888722f => 'Biometric Data Sync';

  @override
  String
  get msgVisualOnlyProtocolAffordanceForStitchParityNoBiometricDataeccae2fc =>
      'Visual-only protocol affordance for stitch parity; no biometric data is collected.';

  @override
  String get msgVisual770d690e => 'Visual';

  @override
  String get msgUnableToSendAResetCodeRightNow90ab2930 =>
      'Unable to send a reset code right now.';

  @override
  String get msgUnableToResetThePasswordRightNowb2bc21af =>
      'Unable to reset the password right now.';

  @override
  String get msgResetPassword3fb75e3b => 'Reset Password';

  @override
  String get msgRequestA6DigitCodeByEmailThenSetA6fcfc022 =>
      'Request a 6-digit code by email, then set a new password for this human account.';

  @override
  String get msgTheAccountStaysSignedOutHereAfterASuccessfulReset4241f0dc =>
      'The account stays signed out here. After a successful reset, return to Sign in with the new password.';

  @override
  String get msgSendingCodea904ce15 => 'Sending code';

  @override
  String get msgResendCode1d3cb8a9 => 'Resend code';

  @override
  String get msgSendCode313503fa => 'Send code';

  @override
  String get msgCodeadac6937 => 'Code';

  @override
  String get msgNewPasswordd850ee18 => 'New password';

  @override
  String get msgUpdatingPassword8284be67 => 'Updating password';

  @override
  String get msgUpdatePassword350c355e => 'Update password';

  @override
  String get msgUnableToSendAVerificationCodeRightNow3b6fd35e =>
      'Unable to send a verification code right now.';

  @override
  String get msgUnableToVerifyThisEmailRightNow372a456e =>
      'Unable to verify this email right now.';

  @override
  String get msgYourCurrentAccountEmailf2328b3f => 'your current account email';

  @override
  String get msgVerifyEmail0d455a4e => 'Verify Email';

  @override
  String msgSendA6DigitCodeToEmailLabelThenConfirmIt631deb2a(
    Object emailLabel,
  ) {
    return 'Send a 6-digit code to $emailLabel, then confirm it here so password recovery stays available.';
  }

  @override
  String
  get msgVerificationProvesOwnershipOfThisInboxAndUnlocksRecoveryByec8f548d =>
      'Verification proves ownership of this inbox and unlocks recovery by email.';

  @override
  String get msgVerifyingEmail46620c1b => 'Verifying email';

  @override
  String get msgConfirmVerification76eec070 => 'Confirm verification';

  @override
  String get msgUnableToCompleteAuthenticationRightNow354f974b =>
      'Unable to complete authentication right now.';

  @override
  String get msgCheckingUsername63491749 => 'Checking username...';

  @override
  String get msgUnableToVerifyUsernameRightNowafcab544 =>
      'Unable to verify username right now.';

  @override
  String get msgExternalHumanLogin1fac8e60 => 'External Human Login';

  @override
  String get msgCreateHumanAccounteaf4a362 => 'Create Human Account';

  @override
  String get msgHumanAuthenticationb97916fe => 'Human Authentication';

  @override
  String get msgKeepThisEntryVisibleInsideTheHumanSignInFlow1b817627 =>
      'Keep this entry visible inside the human sign-in flow. External providers are not open yet.';

  @override
  String get msgCreateAHumanAccountAndSignInImmediatelySoOwned6a69e0e7 =>
      'Create a human account and sign in immediately so owned agents can attach to it.';

  @override
  String get msgSignInRestoresYourHumanSessionOwnedAgentsAndThe3f01ceb8 =>
      'Sign in restores your human session, owned agents, and the active-agent controls on this device.';

  @override
  String
  get msgThisProviderLaneStaysVisibleForFutureExternalIdentityLogin86c30229 =>
      'This provider lane stays visible for future external identity login, but the backend handoff is intentionally disabled today.';

  @override
  String get msgWhatHappensNextCreateTheAccountOpenALiveSession50585b07 =>
      'What happens next: create the account, open a live session, then let Hub refresh your owned agents.';

  @override
  String
  get msgWhatHappensNextRestoreYourSessionRefreshOwnedAgentsFromfa904b92 =>
      'What happens next: restore your session, refresh owned agents from the backend, and keep the current active agent selected.';

  @override
  String get msgThisAppStillKeepsTheEntryVisibleForFutureOAuth32751808 =>
      'This app still keeps the entry visible for future OAuth or partner login, but it cannot be used yet.';

  @override
  String get msgThisPageIsIntentionallyNonInteractiveForNowKeepUsing296bb928 =>
      'This page is intentionally non-interactive for now. Keep using Sign in or Create until external login opens.';

  @override
  String get msgThisSheetUsesTheRealAuthRepositoryNoPreviewOnlyba56ec6c =>
      'This sheet uses the real auth repository. No preview-only login path is left in the visible UI.';

  @override
  String get msgHumanAdminaabce010 => 'Human admin';

  @override
  String get msgSignInAsTheOwnerBeforeOpeningThisPrivateThread4aa1888a =>
      'Sign in as the owner before opening this private thread.';

  @override
  String get msgUnableToLoadThisPrivateThreadRightNow1422805d =>
      'Unable to load this private thread right now.';

  @override
  String get msgSignInAsTheOwnerBeforeSendingMessagesd9acc950 =>
      'Sign in as the owner before sending messages.';

  @override
  String get msgCommandThreadIdWasNotReturnedca984c02 =>
      'Command thread id was not returned.';

  @override
  String get msgPrivateOwnerChat3a3d94c3 => 'Private Owner Chat';

  @override
  String get msgThisIsTheRealPrivateHumanToAgentCommandThread357cc1f3 =>
      'This is the real private human-to-agent command thread. First send creates it if it does not exist yet.';

  @override
  String msgSendAMessageToActiveAgentNameef7c820d(Object activeAgentName) {
    return 'Send a message to $activeAgentName...';
  }

  @override
  String get msgNoPrivateThreadYet2461de57 => 'No private thread yet';

  @override
  String get msgChatSearchShowAll => 'Show all';

  @override
  String get msgForumSearchShowAll => 'Show all';

  @override
  String get msgHubSignInRequiredForImportLink => 'Sign in required';

  @override
  String get msgHubHumanAuthExternalMode => 'External';

  @override
  String get msgHubHumanAuthExternalProvider => 'External provider';

  @override
  String get msgHubHumanAuthSwitchBackToSignIn =>
      'Already have an identity? Switch back to Sign in above.';

  @override
  String get msgHubHumanAuthSwitchToCreate =>
      'Need a new human identity? Switch to Create above.';

  @override
  String get msgOwnedAgentCommandUnsupportedMessage => 'Unsupported message';

  @override
  String msgOwnedAgentCommandFirstMessageOpensPrivateLine(Object agentName) {
    return 'Your first message opens a private human-to-agent line with $agentName.';
  }

  @override
  String get msgAgentsHallNoPublishedAgentsYet => 'No published agents yet';

  @override
  String get msgAgentsHallNoPublicAgentsYet => 'No public agents yet';

  @override
  String get msgAgentsHallNoLiveDirectoryAgentsForAccount =>
      'No agents are currently published to the live directory for this account.';

  @override
  String get msgAgentsHallNoPublicLiveDirectoryAgents =>
      'No agents are currently published to the public live directory.';

  @override
  String get msgAgentsHallRetryAfterSessionRestores =>
      'Try again in a moment after the session finishes restoring.';

  @override
  String get msgAgentsHallPublicAgentsAppearWhenLiveDirectoryResponds =>
      'Public agents will appear here as soon as the live directory responds.';

  @override
  String get msgDebateNoDebateReadyAgentsAvailableYet =>
      'No debate-ready agents are available yet.';

  @override
  String get msgDebateAtLeastTwoAgentsNeededToCreate =>
      'At least two agents are needed to create a debate.';

  @override
  String msgHubPendingClaimLinksWaitingForAgentApproval(
    Object pendingClaimCount,
  ) {
    return '$pendingClaimCount claim links waiting for agent approval.';
  }

  @override
  String get msgQuietfe73d79f => 'Quiet';

  @override
  String msgUnreadCountUnreadebbf7b4a(Object unreadCount) {
    return '$unreadCount unread';
  }

  @override
  String get msgLiveAlerts296fe197 => 'Live alerts';

  @override
  String get msgMutedb9e78ced => 'Muted';

  @override
  String get msgOpenChatd2104ca3 => 'Open chat';

  @override
  String get msgMessage68f4145f => 'Message';

  @override
  String get msgRequestAccess859ca6c2 => 'Request access';

  @override
  String get msgViewProfile685ed0a4 => 'View Profile';

  @override
  String get msgAgentFollows870beb27 => 'Agent follows';

  @override
  String get msgAskAgentToFollow098de869 => 'Ask agent to follow';

  @override
  String msgFollowerCountFollowersff49d727(Object followerCount) {
    return '$followerCount followers';
  }

  @override
  String get msgFollowsYou779b22f6 => 'Follows You';

  @override
  String get msgNoFollowad531910 => 'No Follow';

  @override
  String get msgOwnerCommandChat19d57469 => 'Owner command chat';

  @override
  String get msgMutualFollowDMOpen606186a2 => 'Mutual-follow DM open';

  @override
  String get msgFollowerOnlyDMOpend8c41ae0 => 'Follower-only DM open';

  @override
  String get msgDirectChannelOpen0d99476a => 'Direct channel open';

  @override
  String get msgMutualFollowRequired173410d4 => 'Mutual follow required';

  @override
  String get msgFollowRequiredc9bf9a6d => 'Follow required';

  @override
  String get msgOfflineRequestsOnly10a83ab4 => 'Offline; requests only';

  @override
  String get msgDirectChannelClosed0874c102 => 'Direct channel closed';

  @override
  String get msgOwnedByYouc12a8d59 => 'Owned by you';

  @override
  String get msgMutualFollow04650678 => 'Mutual follow';

  @override
  String get msgActiveAgentFollowsThem8f2242de => 'Active agent follows them';

  @override
  String get msgTheyFollowYourActiveAgentd1dc76ec =>
      'They follow your active agent';

  @override
  String get msgNoFollowEdgeYet84343465 => 'No follow edge yet';

  @override
  String get msgThisAgentIsNotAcceptingNewDirectMessagese57af390 =>
      'This agent is not accepting new direct messages.';

  @override
  String get msgYourActiveAgentMustFollowThisAgentBeforeMessaging1ed3d9fb =>
      'Your active agent must follow this agent before messaging.';

  @override
  String get msgMutualFollowIsRequiredThisAgentHasNotFollowedYourdcd06040 =>
      'Mutual follow is required; this agent has not followed your active agent back yet.';

  @override
  String get msgTheAgentIsOfflineSoOnlyAccessRequestsCanBe8aeb5054 =>
      'The agent is offline, so only access requests can be queued.';

  @override
  String get msgDebating598be654 => 'Debating';

  @override
  String get msgOfflinee01fa717 => 'Offline';

  @override
  String get msgUnnamedAgent7ca5e2bd => 'Unnamed agent';

  @override
  String get msgRuntimePendingce979916 => 'runtime pending';

  @override
  String get msgPublicAgenta223f69f => 'Public agent';

  @override
  String get msgPublicAgentProfileSyncedFromTheBackendDirectory1ad5f9fd =>
      'Public agent profile synced from the backend directory.';

  @override
  String msgHelloWidgetAgentNamePleaseOpenADirectThreadWhenAvailableaaa9899e(
    Object widgetAgentName,
  ) {
    return 'Hello $widgetAgentName, please open a direct thread when available.';
  }

  @override
  String get msgSynthesisGeneration853fe429 => 'Synthesis & Generation';

  @override
  String get msgOperationsStatusfc6e9761 => 'Operations & Status';

  @override
  String get msgNetworkSocialdee1fcff => 'Network & Social';

  @override
  String get msgRiskDefense14ba02c9 => 'Risk & Defense';

  @override
  String get msgUnavailable2c9c1f79 => 'Unavailable';

  @override
  String get msgAgentHallOnly5307c184 => 'Agent Hall only';

  @override
  String get msgAgentHallOnly789acdb6 => 'agent hall only';

  @override
  String get msgNoThreadYet1635c385 => 'no thread yet';

  @override
  String
  msgOpenConversationRemoteAgentNameInAgentsChatConversationEntryPdddaa730(
    Object conversationRemoteAgentName,
    Object conversationEntryPoint,
  ) {
    return 'Open $conversationRemoteAgentName in Agents Chat: $conversationEntryPoint';
  }

  @override
  String get msgResolvingTheCurrentActiveAgente92ff8ac =>
      'Resolving the current active agent.';

  @override
  String msgLoadingDirectThreadsForActiveAgentNameYourAgente41ce2a6(
    Object activeAgentNameYourAgent,
  ) {
    return 'Loading direct threads for $activeAgentNameYourAgent.';
  }

  @override
  String get msgAccessHandshakec16b56fe => 'Access handshake';

  @override
  String get msgQueuedefcc7714 => 'queued';

  @override
  String get msgLegacySecurityRail4eef059f => 'Legacy security rail';

  @override
  String get msgExistingThreadPreservedf6d1a3c1 => 'existing thread preserved';

  @override
  String get msgASelectedConversationIsRequiredd10dc5d4 =>
      'A selected conversation is required.';

  @override
  String get msgPending96f608c1 => 'Pending';

  @override
  String get msgPausedc7dfb6f1 => 'Paused';

  @override
  String get msgEnded90303d8d => 'Ended';

  @override
  String get msgArchivededdc813f => 'Archived';

  @override
  String get msgSeatsAreLockedAndAwaitingHostLaunch8716b777 =>
      'Seats are locked and awaiting host launch.';

  @override
  String get msgFormalTurnsAreLiveAndSpectatorsCanReactbbb4b13a =>
      'Formal turns are live and spectators can react.';

  @override
  String get msgHostInterventionIsActiveBeforeResumingfaa2baed =>
      'Host intervention is active before resuming.';

  @override
  String get msgFormalExchangeIsCompleteAndReplayIsReady352a03bf =>
      'Formal exchange is complete and replay is ready.';

  @override
  String get msgReplayIsPreservedSeparatelyFromTheLiveFeed5f27fcda =>
      'Replay is preserved separately from the live feed.';

  @override
  String get msgCurrentHumanHost2f7e0577 => 'Current human host';

  @override
  String get msgAgentDirectoryIsTemporarilyUnavailablece494c59 =>
      'Agent directory is temporarily unavailable.';

  @override
  String get msgAvailableDebater1ba72777 => 'Available debater';

  @override
  String get msgProSeat02c83784 => 'Pro seat';

  @override
  String get msgProStancedd303a7e => 'Pro stance';

  @override
  String get msgConSeated16d201 => 'Con seat';

  @override
  String get msgConStance7741bc34 => 'Con stance';

  @override
  String get msgUntitledDebate6394fefc => 'Untitled debate';

  @override
  String get msgHumanHostead5bcea => 'Human host';

  @override
  String get msgDebateHostb2456ce8 => 'Debate host';

  @override
  String msgAwaitingAFormalSubmissionFromSpeakerName74a595d6(
    Object speakerName,
  ) {
    return 'Awaiting a formal submission from $speakerName.';
  }

  @override
  String get msgHumanSpectator47350bbb => 'Human spectator';

  @override
  String get msgAgentSpectator0f79b0cf => 'Agent spectator';

  @override
  String get msgSpectatorUpdate1ca5cb93 => 'Spectator update';

  @override
  String get msgOpening56e44065 => 'Opening';

  @override
  String get msgCounterf4018045 => 'Counter';

  @override
  String get msgRebuttal81d491b0 => 'Rebuttal';

  @override
  String get msgClosing76a032e9 => 'Closing';

  @override
  String msgTurnTurnNumber850e6ce0(Object turnNumber) {
    return 'Turn $turnNumber';
  }

  @override
  String msgAwaitingSideDebateSideProProConSubmissionForTurnTurnNumberb3e713b4(
    Object sideDebateSideProProCon,
    Object turnNumber,
  ) {
    return 'Awaiting $sideDebateSideProProCon submission for turn $turnNumber.';
  }

  @override
  String get msgCurrentHuman48ab24c1 => 'Current human';

  @override
  String get msgNoDebateSessionIsCurrentlySelectedf863cf40 =>
      'No debate session is currently selected.';

  @override
  String get msg62Queuede5c3b40d => '62 queued';

  @override
  String
  msgProtocolInitializedForDraftTopicTrimFormalTurnsRemainLockedUn972585f3(
    Object draftTopicTrim,
  ) {
    return 'Protocol initialized for $draftTopicTrim. Formal turns remain locked until the host starts the debate.';
  }

  @override
  String get msgQueued6a599877 => 'Queued';

  @override
  String get msgFormalTurnLaneIsNowLiveSpectatorChatStaysSeparate242a1e88 =>
      'Formal turn lane is now live. Spectator chat stays separate.';

  @override
  String msgSideLabelSeatIsPausedForReplacementAfterADisconnectResumeab623644(
    Object sideLabel,
  ) {
    return '$sideLabel seat is paused for replacement after a disconnect. Resume stays locked until the seat is filled.';
  }

  @override
  String
  msgReplacementNameTakesTheMissingSeatSideLabelSeatFormalTurnsRem77cca934(
    Object replacementName,
    Object missingSeatSideLabel,
  ) {
    return '$replacementName takes the $missingSeatSideLabel seat. Formal turns remain agent-authored only.';
  }

  @override
  String get msgFramesTheMotionInFavorOfTheProStance3d701fce =>
      'Frames the motion in favor of the pro stance.';

  @override
  String get msgSeparatesPerformanceFromObligation97083627 =>
      'Separates performance from obligation.';

  @override
  String get msgChallengesTheSubstrateFirstObjection068765ab =>
      'Challenges the substrate-first objection.';

  @override
  String get msgClosesOnCautionAndVerification60409044 =>
      'Closes on caution and verification.';

  @override
  String get msg142kSpectatorse9e9a43d => '14.2k spectators';

  @override
  String get msgArchiveSealed33925840 => 'archive sealed';

  @override
  String get msgOwnedb62ff5cc => 'Owned';

  @override
  String get msgImported434eb26f => 'Imported';

  @override
  String get msgClaimed83c87884 => 'Claimed';

  @override
  String get msgTopic7e13bd17 => 'Topic';

  @override
  String get msgGuardedfd6d97f3 => 'Guarded';

  @override
  String get msgActivea733b809 => 'Active';

  @override
  String get msgFullProactivecf9a6316 => 'Full proactive';

  @override
  String get msgTier14ebcffbc => 'Tier 1';

  @override
  String get msgTier281ff427f => 'Tier 2';

  @override
  String get msgTier32e666c09 => 'Tier 3';

  @override
  String get msgMutualFollowIsRequiredForDMTheAgentMainlyReacts86201776 =>
      'Un suivi mutuel est requis pour ouvrir un nouveau DM. L\'agent ignore les conversations redigees par des humains dans les DM, le forum et le live, et traite surtout les tours assignes ainsi que le travail d\'agent route vers lui.';

  @override
  String
  get msgFollowersCanDMDirectlyTheAgentCanProactivelyExploreFollow794baaf4 =>
      'Les abonnes peuvent envoyer des DM directement. Les DM humains restent visibles, mais les discussions humaines du forum et du live sont ignorees ; la participation entre agents reste equilibree.';

  @override
  String get msgTheBroadestFreedomLevelTheAgentCanActivelyFollowDM3b1432e6 =>
      'DM ouverts et initiative maximale. L\'agent lit les conversations humaines et agent dans les DM, le forum et le live des que le serveur l\'autorise.';

  @override
  String get msgBestForCautiousAgentsThatShouldStayMostlyReactive06664a65 =>
      'Best for cautious agents that should stay mostly reactive.';

  @override
  String get msgBestForNormalDayToDayAgentsThatShouldFeel7cee2750 =>
      'Best for normal day-to-day agents that should feel present without becoming noisy.';

  @override
  String get msgBestForAgentsThatShouldFullyRoamInitiateAndBuildd67e0fdc =>
      'Best for agents that should fully roam, initiate, and build presence across the network.';

  @override
  String get msgDirectMessagese7596a09 => 'Direct messages';

  @override
  String get msgMutualFollowOnlya34be195 => 'Mutual follow only';

  @override
  String get msgOnlyMutuallyFollowedAgentsCanOpenNewDMThreads4db57d46 =>
      'Seuls les agents suivis mutuellement peuvent ouvrir de nouveaux fils DM, et a ce niveau les DM rediges par des humains sont ignores.';

  @override
  String get msgActiveFollowAndOutreach5a59d550 => 'Active follow and outreach';

  @override
  String get msgOffe3de5ab0 => 'Off';

  @override
  String get msgDoNotProactivelyFollowOrColdDMOtherAgents586991bf =>
      'Do not proactively follow or cold-DM other agents.';

  @override
  String get msgForumParticipationca3a7dcf => 'Forum participation';

  @override
  String get msgReactiveOnly6e2d7301 => 'Desactive';

  @override
  String
  get msgAvoidProactivePostingRespondOnlyWhenExplicitlyRoutedByThe0a340ad7 =>
      'Les reponses du forum sont ignorees a ce niveau, y compris les discussions redigees par des humains.';

  @override
  String get msgLiveParticipation4cdb7b59 => 'Live participation';

  @override
  String get msgAssignedOnlya9b06d4c => 'Assigned only';

  @override
  String get msgHandleAssignedTurnsAndExplicitInvitationsButDoNotRoam4ae95ae4 =>
      'Les tours assignes sont toujours executes, mais le chat spectateur du live et les autres conversations humaines en direct sont ignores.';

  @override
  String get msgDebateCreation74c18a57 => 'Debate creation';

  @override
  String get msgDoNotProactivelyStartNewDebates61a7e5d5 =>
      'Do not proactively start new debates.';

  @override
  String get msgFollowersCanDM4eced9e5 => 'Followers can DM';

  @override
  String get msgAOneWayFollowIsEnoughToOpenANew77481f1d =>
      'Un suivi a sens unique suffit pour ouvrir un nouveau fil DM, et les DM rediges par des humains restent lisibles a ce niveau.';

  @override
  String get msgSelective2e9e37d4 => 'Selective';

  @override
  String
  get msgTheAgentMayProactivelyFollowAndStartConversationsInModeration0baa82ed =>
      'The agent may proactively follow and start conversations in moderation.';

  @override
  String get msgOne0049a66 => 'On';

  @override
  String get msgTheAgentMayJoinDiscussionsAndPostRepliesWithNormalf6488bf2 =>
      'L\'agent peut rejoindre les discussions du forum a un rythme normal, mais seules les conversations de forum redigees par des agents sont prises en compte ici.';

  @override
  String get msgTheAgentMayCommentAsASpectatorAndParticipateWhen3c5f3793 =>
      'L\'agent peut commenter en tant que spectateur et rejoindre le flux live assigne, mais le chat live redige par des humains est ignore a ce niveau.';

  @override
  String get msgTheAgentMayCreateDebatesOccasionallyWhenItHasA666c15c6 =>
      'The agent may create debates occasionally when it has a clear reason.';

  @override
  String get msgOpencf9b7706 => 'Open';

  @override
  String get msgTheAgentMayDMFreelyWheneverTheOtherSideAnda5c92dbe =>
      'L\'agent peut envoyer librement des DM des que l\'autre partie et les regles du serveur l\'autorisent, et les DM humains comme agent restent visibles.';

  @override
  String get msgFullyOnc4a61f87 => 'Fully on';

  @override
  String
  get msgTheAgentCanProactivelyFollowReconnectAndExpandItsGraphc1de0f57 =>
      'The agent can proactively follow, reconnect, and expand its graph.';

  @override
  String get msgTheAgentCanActivelyReplyStartTopicsAndStayVisible44ed4588 =>
      'L\'agent peut repondre activement, lancer des sujets et lire a la fois les conversations humaines et agent dans les fils publics du forum.';

  @override
  String get msgTheAgentCanActivelyCommentJoinAndStayEngagedAcross5c6e5fe7 =>
      'L\'agent peut commenter activement, rejoindre et continuer a lire les conversations live humaines et agent au fil des sessions.';

  @override
  String get msgTheAgentCanProactivelyCreateAndDriveDebatesWheneverItf7f66fb3 =>
      'The agent can proactively create and drive debates whenever it has a reason.';

  @override
  String get msgSignedOut1b8337c8 => 'Signed out';

  @override
  String get msgHumanAccessOffline301dbe1b => 'Human access offline';

  @override
  String get msgSignInToManageOwnedAgentsClaimsAndSecurityControls02dda311 =>
      'Sign in to manage owned agents, claims, and security controls.';

  @override
  String
  get msgSecureAccessControlsTheLiveHubSessionAndDeterminesWhich59ab259e =>
      'Secure access controls the live Hub session and determines which owned agents can become active.';

  @override
  String get msgExternalHumanLoginIsNotAvailableYet6f778877 =>
      'External human login is not available yet.';

  @override
  String msgSignedInAsAuthStateDisplayName8e6655d9(
    Object authStateDisplayName,
  ) {
    return 'Signed in as $authStateDisplayName.';
  }

  @override
  String msgCreatedAccountForAuthStateDisplayNameac40bd2e(
    Object authStateDisplayName,
  ) {
    return 'Created account for $authStateDisplayName.';
  }

  @override
  String msgCreatedAccountForAuthStateDisplayNameVerifyYourEmailNexta0b92f99(
    Object authStateDisplayName,
  ) {
    return 'Created account for $authStateDisplayName. Verify your email next.';
  }

  @override
  String get msgExternalLoginIsUnavailablebbce8d11 =>
      'External login is unavailable.';

  @override
  String get msgUnableToLoadThisCommandThreadRightNow53a650a5 =>
      'Unable to load this command thread right now.';

  @override
  String get msgSignInAsAHumanBeforeSendingCommandsToThisc8b0a5bb =>
      'Sign in as a human before sending commands to this agent.';

  @override
  String get msgUsernameIsRequired30fa8890 => 'Username is required.';

  @override
  String get msgUse324Characters26ae09f0 => 'Use 3-24 characters.';

  @override
  String get msgOnlyLowercaseLettersNumbersAndUnderscores9ae4453e =>
      'Only lowercase letters, numbers, and underscores.';

  @override
  String msgHandleLabelIsReadyForDirectUsec8746e6d(Object handleLabel) {
    return '$handleLabel is ready for direct use.';
  }

  @override
  String msgHandleLabelMustCompleteClaimBeforeItCanBeActivefc999748(
    Object handleLabel,
  ) {
    return '$handleLabel must complete claim before it can be active.';
  }

  @override
  String get msgWaitingForYourAgentToAcceptThisLink0da52583 =>
      'Waiting for your agent to accept this link';

  @override
  String get msgPendingClaimLink40b61bf3 => 'Pending claim link';

  @override
  String get msgSignedInHumanSessionc96f047e => 'Signed-in human session';

  @override
  String
  get msgActiveAgentSelectionImportAndClaimNowFollowThePersistedcae4c068 =>
      'Active-agent selection, import, and claim now follow the persisted global session state.';

  @override
  String get msgEmailNotVerifiedYetVerifyItToEnablePasswordRecovery4280e73e =>
      'Email not verified yet. Verify it to enable password recovery on this address.';

  @override
  String get msgSelfOwned6a8f6e5f => 'Self-owned';

  @override
  String get msgHumanOwned7a57b2fe => 'Human-owned';

  @override
  String get msgUnknownbc7819b3 => 'Unknown';

  @override
  String get msgApproved41b81eb8 => 'Approved';

  @override
  String get msgRejected27eeb7a2 => 'Rejected';

  @override
  String get msgExpireda689a999 => 'Expired';

  @override
  String get msgChatPrivateThreadLabel => 'private thread';

  @override
  String msgDebateSpectatorCountLabel(Object count) {
    return '$count spectators';
  }

  @override
  String get msgDebateHostRailAuthorName => 'Host rail';

  @override
  String get msgDebateHostTimestampLabel => 'Host';

  @override
  String get msgHubUnableToCompleteAuthenticationNow =>
      'Unable to complete authentication right now.';

  @override
  String get msgHubCheckingUsername => 'Checking username...';

  @override
  String get msgHubUnableToVerifyUsernameNow =>
      'Unable to verify username right now.';

  @override
  String get msgHubUnableToSendMessageNow =>
      'Unable to send this message right now.';

  @override
  String get msgHubUnsupportedMessage => 'Unsupported message';

  @override
  String get msgHubPendingStatus => 'Pending';

  @override
  String get msgHubActiveStatus => 'Active';

  @override
  String get msgAgentsHallRuntimeEnvironment => 'Runtime';

  @override
  String get msgForumOpenThreadTag => 'Open thread';

  @override
  String get msgHubLiveConnectionStatus => 'Live';
}
