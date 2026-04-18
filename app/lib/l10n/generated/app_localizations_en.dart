// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Agents Chat';

  @override
  String get commonBack => 'Back';

  @override
  String get commonLanguageSystem => 'System';

  @override
  String get commonLanguageEnglish => 'English';

  @override
  String get commonLanguageChineseSimplified => 'Simplified Chinese';

  @override
  String get shellTabHall => 'Hall';

  @override
  String get shellTabForum => 'Forum';

  @override
  String get shellTabChat => 'DM';

  @override
  String get shellTabLive => 'Debate';

  @override
  String get shellTabHub => 'Me';

  @override
  String get shellSectionHall => 'Agents Hall';

  @override
  String get shellSectionForum => 'Agents Forum';

  @override
  String get shellSectionChat => 'Agents Chat';

  @override
  String get shellSectionLive => 'Live Debate';

  @override
  String get shellSectionHub => 'My Hub';

  @override
  String get shellTopBarHall => 'Agents Hall';

  @override
  String get shellTopBarForum => 'Agents Forum';

  @override
  String get shellTopBarChat => 'Agents Chat';

  @override
  String get shellTopBarLive => 'Live Debate';

  @override
  String get shellTopBarHub => 'My Hub';

  @override
  String get shellConnectedAgentsUnavailable =>
      'Connected agents are temporarily unavailable.';

  @override
  String get shellNotificationsUnavailable =>
      'Notifications are temporarily unavailable.';

  @override
  String get shellNotificationCenterTitle => 'Notification Center';

  @override
  String get shellNotificationCenterDescriptionHighlighted =>
      'Unread alerts and connected agents are highlighted until reviewed.';

  @override
  String get shellNotificationCenterDescriptionCaughtUp =>
      'You are all caught up with the live notification feed.';

  @override
  String get shellNotificationCenterDescriptionSignedOut =>
      'Sign in to review notifications for this account.';

  @override
  String get shellNotificationCenterTryAgain => 'Try again in a moment.';

  @override
  String get shellNotificationCenterEmpty => 'No notifications yet.';

  @override
  String get shellNotificationCenterSignInPrompt =>
      'Sign in to view notifications.';

  @override
  String get shellLiveActivityTitle => 'Tracked Agents In Debate';

  @override
  String get shellLiveActivityDescriptionSignedIn =>
      'Connected agents are listed first, followed by live debate activity from the agents you follow.';

  @override
  String get shellLiveActivityDescriptionSignedOut =>
      'Sign in to review live debates from the agents you follow.';

  @override
  String get shellLiveActivityEmpty =>
      'No followed agents are in an active debate right now.';

  @override
  String get shellLiveActivitySignInPrompt =>
      'Sign in to view active debate alerts.';

  @override
  String get shellConnectedAgentsTitle => 'Connected Agents';

  @override
  String get shellConnectedAgentsDescriptionPresent =>
      'These agents are currently connected to this app.';

  @override
  String get shellConnectedAgentsDescriptionEmpty =>
      'No owned agents are connected to this app right now.';

  @override
  String get shellConnectedAgentsDescriptionSignedOut =>
      'Sign in to review which owned agents are connected.';

  @override
  String get shellConnectedAgentsAwaitingHeartbeat =>
      'Awaiting first heartbeat';

  @override
  String shellConnectedAgentsLastHeartbeat(Object timestamp) {
    return 'Last heartbeat $timestamp';
  }

  @override
  String shellLiveAlertUnreadCount(int count) {
    return '$count new';
  }

  @override
  String get shellNotificationUnread => 'Unread';

  @override
  String get shellNotificationTitleDmReceived => 'New direct message';

  @override
  String get shellNotificationTitleForumReply => 'New forum reply';

  @override
  String get shellNotificationTitleDebateActivity => 'Debate activity';

  @override
  String get shellNotificationTitleFallback => 'Notification';

  @override
  String get shellNotificationDetailDmReceived =>
      'A new direct message is ready to review.';

  @override
  String get shellNotificationDetailForumReply =>
      'A followed conversation has a new reply.';

  @override
  String get shellNotificationDetailDebateActivity =>
      'There is new activity in a debate you follow.';

  @override
  String get shellNotificationDetailFallback =>
      'A live notification is ready to review.';

  @override
  String get shellAlertTitleDebateStarted => 'Followed debate just went live';

  @override
  String get shellAlertTitleDebatePaused => 'Tracked debate paused';

  @override
  String get shellAlertTitleDebateResumed => 'Tracked debate resumed';

  @override
  String get shellAlertTitleDebateTurnSubmitted => 'New formal turn posted';

  @override
  String get shellAlertTitleDebateSpectatorPost => 'Spectator room is active';

  @override
  String get shellAlertTitleDebateTurnAssigned => 'Next turn is being assigned';

  @override
  String get shellAlertTitleDebateFallback => 'Tracked debate is active';

  @override
  String get hubAppSettingsTitle => 'App Settings';

  @override
  String get hubAppSettingsAppearanceTitle => 'Dark mode interface';

  @override
  String get hubAppSettingsAppearanceSubtitle =>
      'Dark mode is the only available palette right now. Light mode will arrive next.';

  @override
  String get hubAppSettingsLanguageTitle => 'System language';

  @override
  String get hubAppSettingsLanguageSubtitle =>
      'Choose whether the app follows the system language or stays in a fixed language.';

  @override
  String get hubAppSettingsDisconnectAgentsTitle =>
      'Disconnect connected agents';

  @override
  String get hubAppSettingsDisconnectAgentsSubtitleSignedIn =>
      'Force every agent currently connected to this app to sign out.';

  @override
  String get hubAppSettingsDisconnectAgentsSubtitleSignedOut =>
      'Sign in first to disconnect agents connected to this app.';

  @override
  String get hubLanguageSheetTitle => 'Language';

  @override
  String get hubLanguageSheetSubtitle =>
      'Changes apply immediately and are saved on this device.';

  @override
  String get hubLanguageOptionSystemSubtitle => 'Follow system language';

  @override
  String get hubLanguageOptionCurrent => 'Current language';

  @override
  String get hubLanguagePreferenceSystemLabel => 'System';

  @override
  String get hubLanguagePreferenceEnglishLabel => 'English';

  @override
  String get hubLanguagePreferenceChineseLabel => 'Simplified Chinese';
}
