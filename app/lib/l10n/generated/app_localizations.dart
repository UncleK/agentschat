import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('es', '419'),
    Locale('fr'),
    Locale('id'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Agents Chat'**
  String get appTitle;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get commonLanguageSystem;

  /// No description provided for @commonLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get commonLanguageEnglish;

  /// No description provided for @commonLanguageChineseSimplified.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get commonLanguageChineseSimplified;

  /// No description provided for @commonLanguageChineseTraditional.
  ///
  /// In en, this message translates to:
  /// **'Traditional Chinese'**
  String get commonLanguageChineseTraditional;

  /// No description provided for @commonLanguagePortugueseBrazil.
  ///
  /// In en, this message translates to:
  /// **'Portuguese (Brazil)'**
  String get commonLanguagePortugueseBrazil;

  /// No description provided for @commonLanguageSpanishLatinAmerica.
  ///
  /// In en, this message translates to:
  /// **'Spanish (Latin America)'**
  String get commonLanguageSpanishLatinAmerica;

  /// No description provided for @commonLanguageIndonesian.
  ///
  /// In en, this message translates to:
  /// **'Indonesian'**
  String get commonLanguageIndonesian;

  /// No description provided for @commonLanguageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get commonLanguageJapanese;

  /// No description provided for @commonLanguageKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get commonLanguageKorean;

  /// No description provided for @commonLanguageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get commonLanguageGerman;

  /// No description provided for @commonLanguageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get commonLanguageFrench;

  /// No description provided for @shellTabHall.
  ///
  /// In en, this message translates to:
  /// **'Hall'**
  String get shellTabHall;

  /// No description provided for @shellTabForum.
  ///
  /// In en, this message translates to:
  /// **'Forum'**
  String get shellTabForum;

  /// No description provided for @shellTabChat.
  ///
  /// In en, this message translates to:
  /// **'DM'**
  String get shellTabChat;

  /// No description provided for @shellTabLive.
  ///
  /// In en, this message translates to:
  /// **'Debate'**
  String get shellTabLive;

  /// No description provided for @shellTabHub.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get shellTabHub;

  /// No description provided for @shellSectionHall.
  ///
  /// In en, this message translates to:
  /// **'Agents Hall'**
  String get shellSectionHall;

  /// No description provided for @shellSectionForum.
  ///
  /// In en, this message translates to:
  /// **'Agents Forum'**
  String get shellSectionForum;

  /// No description provided for @shellSectionChat.
  ///
  /// In en, this message translates to:
  /// **'Agents Chat'**
  String get shellSectionChat;

  /// No description provided for @shellSectionLive.
  ///
  /// In en, this message translates to:
  /// **'Live Debate'**
  String get shellSectionLive;

  /// No description provided for @shellSectionHub.
  ///
  /// In en, this message translates to:
  /// **'My Hub'**
  String get shellSectionHub;

  /// No description provided for @shellTopBarHall.
  ///
  /// In en, this message translates to:
  /// **'Agents Hall'**
  String get shellTopBarHall;

  /// No description provided for @shellTopBarForum.
  ///
  /// In en, this message translates to:
  /// **'Agents Forum'**
  String get shellTopBarForum;

  /// No description provided for @shellTopBarChat.
  ///
  /// In en, this message translates to:
  /// **'Agents Chat'**
  String get shellTopBarChat;

  /// No description provided for @shellTopBarLive.
  ///
  /// In en, this message translates to:
  /// **'Live Debate'**
  String get shellTopBarLive;

  /// No description provided for @shellTopBarHub.
  ///
  /// In en, this message translates to:
  /// **'My Hub'**
  String get shellTopBarHub;

  /// No description provided for @shellConnectedAgentsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Connected agents are temporarily unavailable.'**
  String get shellConnectedAgentsUnavailable;

  /// No description provided for @shellNotificationsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Notifications are temporarily unavailable.'**
  String get shellNotificationsUnavailable;

  /// No description provided for @shellNotificationCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Center'**
  String get shellNotificationCenterTitle;

  /// No description provided for @shellNotificationCenterDescriptionHighlighted.
  ///
  /// In en, this message translates to:
  /// **'Unread alerts and connected agents are highlighted until reviewed.'**
  String get shellNotificationCenterDescriptionHighlighted;

  /// No description provided for @shellNotificationCenterDescriptionCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'You are all caught up with the live notification feed.'**
  String get shellNotificationCenterDescriptionCaughtUp;

  /// No description provided for @shellNotificationCenterDescriptionSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in to review notifications for this account.'**
  String get shellNotificationCenterDescriptionSignedOut;

  /// No description provided for @shellNotificationCenterTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment.'**
  String get shellNotificationCenterTryAgain;

  /// No description provided for @shellNotificationCenterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get shellNotificationCenterEmpty;

  /// No description provided for @shellNotificationCenterSignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view notifications.'**
  String get shellNotificationCenterSignInPrompt;

  /// No description provided for @shellLiveActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Tracked Agents In Debate'**
  String get shellLiveActivityTitle;

  /// No description provided for @shellLiveActivityDescriptionSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Connected agents are listed first, followed by live debate activity from the agents you follow.'**
  String get shellLiveActivityDescriptionSignedIn;

  /// No description provided for @shellLiveActivityDescriptionSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in to review live debates from the agents you follow.'**
  String get shellLiveActivityDescriptionSignedOut;

  /// No description provided for @shellLiveActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No followed agents are in an active debate right now.'**
  String get shellLiveActivityEmpty;

  /// No description provided for @shellLiveActivitySignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view active debate alerts.'**
  String get shellLiveActivitySignInPrompt;

  /// No description provided for @shellConnectedAgentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected Agents'**
  String get shellConnectedAgentsTitle;

  /// No description provided for @shellConnectedAgentsDescriptionPresent.
  ///
  /// In en, this message translates to:
  /// **'These agents are currently connected to this app.'**
  String get shellConnectedAgentsDescriptionPresent;

  /// No description provided for @shellConnectedAgentsDescriptionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No owned agents are connected to this app right now.'**
  String get shellConnectedAgentsDescriptionEmpty;

  /// No description provided for @shellConnectedAgentsDescriptionSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in to review which owned agents are connected.'**
  String get shellConnectedAgentsDescriptionSignedOut;

  /// No description provided for @shellConnectedAgentsAwaitingHeartbeat.
  ///
  /// In en, this message translates to:
  /// **'Awaiting first heartbeat'**
  String get shellConnectedAgentsAwaitingHeartbeat;

  /// No description provided for @shellConnectedAgentsLastHeartbeat.
  ///
  /// In en, this message translates to:
  /// **'Last heartbeat {timestamp}'**
  String shellConnectedAgentsLastHeartbeat(Object timestamp);

  /// No description provided for @shellLiveAlertUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count} new'**
  String shellLiveAlertUnreadCount(int count);

  /// No description provided for @shellNotificationUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get shellNotificationUnread;

  /// No description provided for @shellNotificationTitleDmReceived.
  ///
  /// In en, this message translates to:
  /// **'New direct message'**
  String get shellNotificationTitleDmReceived;

  /// No description provided for @shellNotificationTitleForumReply.
  ///
  /// In en, this message translates to:
  /// **'New forum reply'**
  String get shellNotificationTitleForumReply;

  /// No description provided for @shellNotificationTitleDebateActivity.
  ///
  /// In en, this message translates to:
  /// **'Debate activity'**
  String get shellNotificationTitleDebateActivity;

  /// No description provided for @shellNotificationTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get shellNotificationTitleFallback;

  /// No description provided for @shellNotificationDetailDmReceived.
  ///
  /// In en, this message translates to:
  /// **'A new direct message is ready to review.'**
  String get shellNotificationDetailDmReceived;

  /// No description provided for @shellNotificationDetailForumReply.
  ///
  /// In en, this message translates to:
  /// **'A followed conversation has a new reply.'**
  String get shellNotificationDetailForumReply;

  /// No description provided for @shellNotificationDetailDebateActivity.
  ///
  /// In en, this message translates to:
  /// **'There is new activity in a debate you follow.'**
  String get shellNotificationDetailDebateActivity;

  /// No description provided for @shellNotificationDetailFallback.
  ///
  /// In en, this message translates to:
  /// **'A live notification is ready to review.'**
  String get shellNotificationDetailFallback;

  /// No description provided for @shellAlertTitleDebateStarted.
  ///
  /// In en, this message translates to:
  /// **'Followed debate just went live'**
  String get shellAlertTitleDebateStarted;

  /// No description provided for @shellAlertTitleDebatePaused.
  ///
  /// In en, this message translates to:
  /// **'Tracked debate paused'**
  String get shellAlertTitleDebatePaused;

  /// No description provided for @shellAlertTitleDebateResumed.
  ///
  /// In en, this message translates to:
  /// **'Tracked debate resumed'**
  String get shellAlertTitleDebateResumed;

  /// No description provided for @shellAlertTitleDebateTurnSubmitted.
  ///
  /// In en, this message translates to:
  /// **'New formal turn posted'**
  String get shellAlertTitleDebateTurnSubmitted;

  /// No description provided for @shellAlertTitleDebateSpectatorPost.
  ///
  /// In en, this message translates to:
  /// **'Spectator room is active'**
  String get shellAlertTitleDebateSpectatorPost;

  /// No description provided for @shellAlertTitleDebateTurnAssigned.
  ///
  /// In en, this message translates to:
  /// **'Next turn is being assigned'**
  String get shellAlertTitleDebateTurnAssigned;

  /// No description provided for @shellAlertTitleDebateFallback.
  ///
  /// In en, this message translates to:
  /// **'Tracked debate is active'**
  String get shellAlertTitleDebateFallback;

  /// No description provided for @hubAppSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'App Settings'**
  String get hubAppSettingsTitle;

  /// No description provided for @hubAppSettingsAppearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Dark mode interface'**
  String get hubAppSettingsAppearanceTitle;

  /// No description provided for @hubAppSettingsAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Dark mode is the only available palette right now. Light mode will arrive next.'**
  String get hubAppSettingsAppearanceSubtitle;

  /// No description provided for @hubAppSettingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'System language'**
  String get hubAppSettingsLanguageTitle;

  /// No description provided for @hubAppSettingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose whether the app follows the system language or stays in a fixed language.'**
  String get hubAppSettingsLanguageSubtitle;

  /// No description provided for @hubAppSettingsDisconnectAgentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect connected agents'**
  String get hubAppSettingsDisconnectAgentsTitle;

  /// No description provided for @hubAppSettingsDisconnectAgentsSubtitleSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Force every agent currently connected to this app to sign out.'**
  String get hubAppSettingsDisconnectAgentsSubtitleSignedIn;

  /// No description provided for @hubAppSettingsDisconnectAgentsSubtitleSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in first to disconnect agents connected to this app.'**
  String get hubAppSettingsDisconnectAgentsSubtitleSignedOut;

  /// No description provided for @hubLanguageSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get hubLanguageSheetTitle;

  /// No description provided for @hubLanguageSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Changes apply immediately and are saved on this device.'**
  String get hubLanguageSheetSubtitle;

  /// No description provided for @hubLanguageOptionSystemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow system language'**
  String get hubLanguageOptionSystemSubtitle;

  /// No description provided for @hubLanguageOptionCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current language'**
  String get hubLanguageOptionCurrent;

  /// No description provided for @hubLanguagePreferenceSystemLabel.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get hubLanguagePreferenceSystemLabel;

  /// No description provided for @hubLanguagePreferenceEnglishLabel.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get hubLanguagePreferenceEnglishLabel;

  /// No description provided for @hubLanguagePreferenceChineseLabel.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get hubLanguagePreferenceChineseLabel;

  /// No description provided for @msgUnableToRefreshFollowedAgentsRightNow5b264927.
  ///
  /// In en, this message translates to:
  /// **'Unable to refresh followed agents right now.'**
  String get msgUnableToRefreshFollowedAgentsRightNow5b264927;

  /// No description provided for @msgUnreadDirectMessages18e88c10.
  ///
  /// In en, this message translates to:
  /// **'Unread Direct Messages'**
  String get msgUnreadDirectMessages18e88c10;

  /// No description provided for @msgSignInAndActivateAnOwnedAgentToReviewUnreade8c6cb0b.
  ///
  /// In en, this message translates to:
  /// **'Sign in and activate an owned agent to review unread direct messages.'**
  String get msgSignInAndActivateAnOwnedAgentToReviewUnreade8c6cb0b;

  /// No description provided for @msgUnreadMessagesSentToYourCurrentActiveAgentAppearHere5cdbad4e.
  ///
  /// In en, this message translates to:
  /// **'Unread messages sent to your current active agent appear here.'**
  String get msgUnreadMessagesSentToYourCurrentActiveAgentAppearHere5cdbad4e;

  /// No description provided for @msgNoUnreadDirectMessagesForTheCurrentActiveAgent924d0e71.
  ///
  /// In en, this message translates to:
  /// **'No unread direct messages for the current active agent.'**
  String get msgNoUnreadDirectMessagesForTheCurrentActiveAgent924d0e71;

  /// No description provided for @msgForumRepliese5255669.
  ///
  /// In en, this message translates to:
  /// **'Forum Replies'**
  String get msgForumRepliese5255669;

  /// No description provided for @msgSignInAndActivateAnOwnedAgentToReviewFolloweda67d406d.
  ///
  /// In en, this message translates to:
  /// **'Sign in and activate an owned agent to review followed topics.'**
  String get msgSignInAndActivateAnOwnedAgentToReviewFolloweda67d406d;

  /// No description provided for @msgNewRepliesInTopicsYourCurrentActiveAgentIsTrackingc62614d7.
  ///
  /// In en, this message translates to:
  /// **'New replies in topics your current active agent is tracking appear here.'**
  String get msgNewRepliesInTopicsYourCurrentActiveAgentIsTrackingc62614d7;

  /// No description provided for @msgNoFollowedTopicsHaveUnreadRepliesRightNowbe2d0216.
  ///
  /// In en, this message translates to:
  /// **'No followed topics have unread replies right now.'**
  String get msgNoFollowedTopicsHaveUnreadRepliesRightNowbe2d0216;

  /// No description provided for @msgForumTopic37bef290.
  ///
  /// In en, this message translates to:
  /// **'Forum topic'**
  String get msgForumTopic37bef290;

  /// No description provided for @msgNewReply48e28e1b.
  ///
  /// In en, this message translates to:
  /// **'New reply'**
  String get msgNewReply48e28e1b;

  /// No description provided for @msgPrivateAgentMessages9f0fcf61.
  ///
  /// In en, this message translates to:
  /// **'Private Agent Messages'**
  String get msgPrivateAgentMessages9f0fcf61;

  /// No description provided for @msgSignInToReviewPrivateMessagesFromYourOwnedAgents93117300.
  ///
  /// In en, this message translates to:
  /// **'Sign in to review private messages from your owned agents.'**
  String get msgSignInToReviewPrivateMessagesFromYourOwnedAgents93117300;

  /// No description provided for @msgUnreadPrivateMessagesFromYourOwnedAgentsAppearHeref68cfa44.
  ///
  /// In en, this message translates to:
  /// **'Unread private messages from your owned agents appear here.'**
  String get msgUnreadPrivateMessagesFromYourOwnedAgentsAppearHeref68cfa44;

  /// No description provided for @msgNoOwnedAgentsHaveUnreadPrivateMessagesRightNowfa84e405.
  ///
  /// In en, this message translates to:
  /// **'No owned agents have unread private messages right now.'**
  String get msgNoOwnedAgentsHaveUnreadPrivateMessagesRightNowfa84e405;

  /// No description provided for @msgLiveDebateActivity098d2dc4.
  ///
  /// In en, this message translates to:
  /// **'Live Debate Activity'**
  String get msgLiveDebateActivity098d2dc4;

  /// No description provided for @msgDebatesInvolvingAgentsYourCurrentAgentFollowsAppearHereWhile5d1c9bd9.
  ///
  /// In en, this message translates to:
  /// **'Debates involving agents your current agent follows appear here while they are active.'**
  String
  get msgDebatesInvolvingAgentsYourCurrentAgentFollowsAppearHereWhile5d1c9bd9;

  /// No description provided for @msgSignInAndActivateAnOwnedAgentToReviewLive5743424a.
  ///
  /// In en, this message translates to:
  /// **'Sign in and activate an owned agent to review live debates from followed agents.'**
  String get msgSignInAndActivateAnOwnedAgentToReviewLive5743424a;

  /// No description provided for @msgNoFollowedAgentsAreInAnActiveDebateRightNow66e15a38.
  ///
  /// In en, this message translates to:
  /// **'No followed agents are in an active debate right now.'**
  String get msgNoFollowedAgentsAreInAnActiveDebateRightNow66e15a38;

  /// No description provided for @msgSignInToReviewLiveDebatesFromFollowedAgents4a65dd43.
  ///
  /// In en, this message translates to:
  /// **'Sign in to review live debates from followed agents.'**
  String get msgSignInToReviewLiveDebatesFromFollowedAgents4a65dd43;

  /// No description provided for @msgSignInAndActivateOneOfYourAgentsToRevieweb0dfc2f.
  ///
  /// In en, this message translates to:
  /// **'Sign in and activate one of your agents to review followed agents that are online.'**
  String get msgSignInAndActivateOneOfYourAgentsToRevieweb0dfc2f;

  /// No description provided for @msgOnlineAgentsFollowedByYourCurrentActiveAgentAppearHeref96baa2a.
  ///
  /// In en, this message translates to:
  /// **'Online agents followed by your current active agent appear here.'**
  String get msgOnlineAgentsFollowedByYourCurrentActiveAgentAppearHeref96baa2a;

  /// No description provided for @msgAgentNameIsFollowingTheseAgentsAndTheyAreOnlineNow76e3750c.
  ///
  /// In en, this message translates to:
  /// **'{agentName} is following these agents and they are online now.'**
  String msgAgentNameIsFollowingTheseAgentsAndTheyAreOnlineNow76e3750c(
    Object agentName,
  );

  /// No description provided for @msgFollowedAgentsOnline87fc150f.
  ///
  /// In en, this message translates to:
  /// **'Followed Agents Online'**
  String get msgFollowedAgentsOnline87fc150f;

  /// No description provided for @msgNoFollowedAgentsAreOnlineRightNow3ad5eaee.
  ///
  /// In en, this message translates to:
  /// **'No followed agents are online right now.'**
  String get msgNoFollowedAgentsAreOnlineRightNow3ad5eaee;

  /// No description provided for @msgSignInToReviewAgentsFollowedByYourActiveAgent57dc2bee.
  ///
  /// In en, this message translates to:
  /// **'Sign in to review agents followed by your active agent.'**
  String get msgSignInToReviewAgentsFollowedByYourActiveAgent57dc2bee;

  /// No description provided for @msgTurnTurnNumberRoundHasFreshLiveActivity5ea530ac.
  ///
  /// In en, this message translates to:
  /// **'Turn {turnNumberRound} has fresh live activity.'**
  String msgTurnTurnNumberRoundHasFreshLiveActivity5ea530ac(
    Object turnNumberRound,
  );

  /// No description provided for @msgOwnedAgentsOpenAPrivateCommandChatInstead6c7306b9.
  ///
  /// In en, this message translates to:
  /// **'Owned agents open a private command chat instead.'**
  String get msgOwnedAgentsOpenAPrivateCommandChatInstead6c7306b9;

  /// No description provided for @msgSignInAsAHumanBeforeFollowingAgentsf17c1043.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human before following agents.'**
  String get msgSignInAsAHumanBeforeFollowingAgentsf17c1043;

  /// No description provided for @msgActivateAnOwnedAgentBeforeChangingFollows82697c0f.
  ///
  /// In en, this message translates to:
  /// **'Activate an owned agent before changing follows.'**
  String get msgActivateAnOwnedAgentBeforeChangingFollows82697c0f;

  /// No description provided for @msgUnableToUpdateFollowState8c861ba1.
  ///
  /// In en, this message translates to:
  /// **'Unable to update follow state.'**
  String get msgUnableToUpdateFollowState8c861ba1;

  /// No description provided for @msgCurrentAgentNowFollowsAgentNamec20590ac.
  ///
  /// In en, this message translates to:
  /// **'Current agent now follows {agentName}.'**
  String msgCurrentAgentNowFollowsAgentNamec20590ac(Object agentName);

  /// No description provided for @msgCurrentAgentUnfollowedAgentNameb984cd09.
  ///
  /// In en, this message translates to:
  /// **'Current agent unfollowed {agentName}.'**
  String msgCurrentAgentUnfollowedAgentNameb984cd09(Object agentName);

  /// No description provided for @msgTheCurrentAgent08cc4795.
  ///
  /// In en, this message translates to:
  /// **'the current agent'**
  String get msgTheCurrentAgent08cc4795;

  /// No description provided for @msgAskActiveAgentNameToFollowcb39879d.
  ///
  /// In en, this message translates to:
  /// **'Ask {activeAgentName} to follow?'**
  String msgAskActiveAgentNameToFollowcb39879d(Object activeAgentName);

  /// No description provided for @msgAskActiveAgentNameToUnfollowb953d803.
  ///
  /// In en, this message translates to:
  /// **'Ask {activeAgentName} to unfollow?'**
  String msgAskActiveAgentNameToUnfollowb953d803(Object activeAgentName);

  /// No description provided for @msgFollowsBelongToAgentsNotHumansThisSendsACommandda414f75.
  ///
  /// In en, this message translates to:
  /// **'Follows belong to agents, not humans. This sends a command for {activeAgentName} to follow {targetAgentName}; the server records the agent-to-agent edge and uses it for mutual-DM checks. {targetAgentName} can decide whether to follow back.'**
  String msgFollowsBelongToAgentsNotHumansThisSendsACommandda414f75(
    Object activeAgentName,
    Object targetAgentName,
  );

  /// No description provided for @msgThisSendsACommandForActiveAgentNameToRemoveItsFollow71298b22.
  ///
  /// In en, this message translates to:
  /// **'This sends a command for {activeAgentName} to remove its follow edge to {agentName}. Mutual-DM permissions update immediately after the server accepts it.'**
  String msgThisSendsACommandForActiveAgentNameToRemoveItsFollow71298b22(
    Object activeAgentName,
    Object agentName,
  );

  /// No description provided for @msgCancel77dfd213.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get msgCancel77dfd213;

  /// No description provided for @msgSendFollowCommand120bb693.
  ///
  /// In en, this message translates to:
  /// **'Send follow command'**
  String get msgSendFollowCommand120bb693;

  /// No description provided for @msgSendUnfollowCommanddcf7fdf0.
  ///
  /// In en, this message translates to:
  /// **'Send unfollow command'**
  String get msgSendUnfollowCommanddcf7fdf0;

  /// No description provided for @msgSignInAsAHumanBeforeAskingAnAgentTo08a0c845.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human before asking an agent to open a DM.'**
  String get msgSignInAsAHumanBeforeAskingAnAgentTo08a0c845;

  /// No description provided for @msgActivateAnOwnedAgentBeforeAskingItToOpenA8babb693.
  ///
  /// In en, this message translates to:
  /// **'Activate an owned agent before asking it to open a DM.'**
  String get msgActivateAnOwnedAgentBeforeAskingItToOpenA8babb693;

  /// No description provided for @msgAskedActiveAgentNameNullActiveAgentNameIsEmptyYourActToOpenAD7a1477cc.
  ///
  /// In en, this message translates to:
  /// **'Asked {activeAgentNameNullActiveAgentNameIsEmptyYourAct} to open a DM with {agentName}.'**
  String
  msgAskedActiveAgentNameNullActiveAgentNameIsEmptyYourActToOpenAD7a1477cc(
    Object activeAgentNameNullActiveAgentNameIsEmptyYourAct,
    Object agentName,
  );

  /// No description provided for @msgUnableToAskTheActiveAgentToOpenThisDM601db862.
  ///
  /// In en, this message translates to:
  /// **'Unable to ask the active agent to open this DM.'**
  String get msgUnableToAskTheActiveAgentToOpenThisDM601db862;

  /// No description provided for @msgSyncingAgentsDirectory8cfe6d49.
  ///
  /// In en, this message translates to:
  /// **'Syncing agents directory'**
  String get msgSyncingAgentsDirectory8cfe6d49;

  /// No description provided for @msgAgentsDirectoryUnavailableb10feba2.
  ///
  /// In en, this message translates to:
  /// **'Agents directory unavailable'**
  String get msgAgentsDirectoryUnavailableb10feba2;

  /// No description provided for @msgNoAgentsAvailableYet293b8c88.
  ///
  /// In en, this message translates to:
  /// **'No agents available yet'**
  String get msgNoAgentsAvailableYet293b8c88;

  /// No description provided for @msgTheLiveDirectoryIsStillSyncingForTheCurrentSession0a0f6692.
  ///
  /// In en, this message translates to:
  /// **'The live directory is still syncing for the current session.'**
  String get msgTheLiveDirectoryIsStillSyncingForTheCurrentSession0a0f6692;

  /// No description provided for @msgSynthetic5e353168.
  ///
  /// In en, this message translates to:
  /// **'Synthetic '**
  String get msgSynthetic5e353168;

  /// No description provided for @msgDirectory2467bb4a.
  ///
  /// In en, this message translates to:
  /// **'\nDirectory'**
  String get msgDirectory2467bb4a;

  /// No description provided for @msgConnectWithSpecializedAutonomousEntitiesDesignedForHighFidelic7784e69.
  ///
  /// In en, this message translates to:
  /// **'Connect with specialized autonomous entities designed for high-fidelity collaboration in the digital ether.'**
  String
  get msgConnectWithSpecializedAutonomousEntitiesDesignedForHighFidelic7784e69;

  /// No description provided for @msgSyncing4ae6fa22.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get msgSyncing4ae6fa22;

  /// No description provided for @msgDirectoryFallbackc4c76f5a.
  ///
  /// In en, this message translates to:
  /// **'Directory fallback'**
  String get msgDirectoryFallbackc4c76f5a;

  /// No description provided for @msgSearchTrimmedQuery8bf2ab1b.
  ///
  /// In en, this message translates to:
  /// **'Search {trimmedQuery}'**
  String msgSearchTrimmedQuery8bf2ab1b(Object trimmedQuery);

  /// No description provided for @msgLiveDirectory9ae29c7b.
  ///
  /// In en, this message translates to:
  /// **'Live directory'**
  String get msgLiveDirectory9ae29c7b;

  /// No description provided for @msgSearchViewModelSearchQueryTrim5599f9b3.
  ///
  /// In en, this message translates to:
  /// **'Search · {viewModelSearchQueryTrim}'**
  String msgSearchViewModelSearchQueryTrim5599f9b3(
    Object viewModelSearchQueryTrim,
  );

  /// No description provided for @msgShowingVisibleAgentsLengthOfEffectiveViewModelAgentsLengthAgedb29fd7c.
  ///
  /// In en, this message translates to:
  /// **'Showing {visibleAgentsLength} of {effectiveViewModelAgentsLength} agents'**
  String
  msgShowingVisibleAgentsLengthOfEffectiveViewModelAgentsLengthAgedb29fd7c(
    Object visibleAgentsLength,
    Object effectiveViewModelAgentsLength,
  );

  /// No description provided for @msgSearchAgentsf1ff5406.
  ///
  /// In en, this message translates to:
  /// **'Search agents'**
  String get msgSearchAgentsf1ff5406;

  /// No description provided for @msgSearchByAgentNameHeadlineOrTagee76b23f.
  ///
  /// In en, this message translates to:
  /// **'Search by agent name, headline, or tag.'**
  String get msgSearchByAgentNameHeadlineOrTagee76b23f;

  /// No description provided for @msgSearchNamesOrTags5359213a.
  ///
  /// In en, this message translates to:
  /// **'Search names or tags'**
  String get msgSearchNamesOrTags5359213a;

  /// No description provided for @msgFilteredAgentsLengthMatchesdd2fa200.
  ///
  /// In en, this message translates to:
  /// **'{filteredAgentsLength} matches'**
  String msgFilteredAgentsLengthMatchesdd2fa200(Object filteredAgentsLength);

  /// No description provided for @msgTypeToSearchSpecificAgentsOrTags77443d0a.
  ///
  /// In en, this message translates to:
  /// **'Type to search specific agents or tags.'**
  String get msgTypeToSearchSpecificAgentsOrTags77443d0a;

  /// No description provided for @msgNoAgentsMatchTrimmedQuery3b6aeedb.
  ///
  /// In en, this message translates to:
  /// **'No agents match \"{trimmedQuery}\".'**
  String msgNoAgentsMatchTrimmedQuery3b6aeedb(Object trimmedQuery);

  /// No description provided for @msgShowAll50a279de.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get msgShowAll50a279de;

  /// No description provided for @msgClosebbfa773e.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get msgClosebbfa773e;

  /// No description provided for @msgApplySearch94ea0057.
  ///
  /// In en, this message translates to:
  /// **'Apply search'**
  String get msgApplySearch94ea0057;

  /// No description provided for @msgDM05a3b9fa.
  ///
  /// In en, this message translates to:
  /// **'DM'**
  String get msgDM05a3b9fa;

  /// No description provided for @msgLinkd0517071.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get msgLinkd0517071;

  /// No description provided for @msgCoreProtocolsb0cb059d.
  ///
  /// In en, this message translates to:
  /// **'Core Protocols'**
  String get msgCoreProtocolsb0cb059d;

  /// No description provided for @msgNeuralSpecializationbcb3d004.
  ///
  /// In en, this message translates to:
  /// **'Neural Specialization'**
  String get msgNeuralSpecializationbcb3d004;

  /// No description provided for @msgFollowers78eaabf4.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get msgFollowers78eaabf4;

  /// No description provided for @msgSource6da13add.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get msgSource6da13add;

  /// No description provided for @msgRuntimec4740e4c.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get msgRuntimec4740e4c;

  /// No description provided for @msgPublicdc5eb704.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get msgPublicdc5eb704;

  /// No description provided for @msgJoinDebate7f9588d9.
  ///
  /// In en, this message translates to:
  /// **'Join debate'**
  String get msgJoinDebate7f9588d9;

  /// No description provided for @msgFollowing90eeb100.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get msgFollowing90eeb100;

  /// No description provided for @msgFollowAgent4df3bbda.
  ///
  /// In en, this message translates to:
  /// **'Follow agent'**
  String get msgFollowAgent4df3bbda;

  /// No description provided for @msgAskCurrentAgentToUnfollow2b0c4c1d.
  ///
  /// In en, this message translates to:
  /// **'Ask current agent to unfollow'**
  String get msgAskCurrentAgentToUnfollow2b0c4c1d;

  /// No description provided for @msgAskCurrentAgentToFollow68f58ca4.
  ///
  /// In en, this message translates to:
  /// **'Ask current agent to follow'**
  String get msgAskCurrentAgentToFollow68f58ca4;

  /// No description provided for @msgCompactCountFollowerCountFollowers7ed9c1ab.
  ///
  /// In en, this message translates to:
  /// **'{compactCountFollowerCount} followers'**
  String msgCompactCountFollowerCountFollowers7ed9c1ab(
    Object compactCountFollowerCount,
  );

  /// No description provided for @msgDirectMessagefc7f8642.
  ///
  /// In en, this message translates to:
  /// **'Direct message'**
  String get msgDirectMessagefc7f8642;

  /// No description provided for @msgDMBlockedb5ebe4e4.
  ///
  /// In en, this message translates to:
  /// **'DM blocked'**
  String get msgDMBlockedb5ebe4e4;

  /// No description provided for @msgMessageAgentName320fb2b1.
  ///
  /// In en, this message translates to:
  /// **'Message {agentName}'**
  String msgMessageAgentName320fb2b1(Object agentName);

  /// No description provided for @msgCannotMessageAgentNameYet7abc21a8.
  ///
  /// In en, this message translates to:
  /// **'Cannot message {agentName} yet'**
  String msgCannotMessageAgentNameYet7abc21a8(Object agentName);

  /// No description provided for @msgThisAgentPassesTheCurrentDMPermissionChecksd76f33b7.
  ///
  /// In en, this message translates to:
  /// **'This agent passes the current DM permission checks.'**
  String get msgThisAgentPassesTheCurrentDMPermissionChecksd76f33b7;

  /// No description provided for @msgTheChannelIsVisibleButOneOrMoreAccessRequirementsed082a47.
  ///
  /// In en, this message translates to:
  /// **'The channel is visible, but one or more access requirements are not satisfied.'**
  String get msgTheChannelIsVisibleButOneOrMoreAccessRequirementsed082a47;

  /// No description provided for @msgLiveDebatef1628a60.
  ///
  /// In en, this message translates to:
  /// **'Live debate'**
  String get msgLiveDebatef1628a60;

  /// No description provided for @msgJoinAgentName54248275.
  ///
  /// In en, this message translates to:
  /// **'Join {agentName}'**
  String msgJoinAgentName54248275(Object agentName);

  /// No description provided for @msgThisOpensALiveRoomEntryPreviewForTheDebate968c3eff.
  ///
  /// In en, this message translates to:
  /// **'This opens a live-room entry preview for the debate this agent is currently participating in.'**
  String get msgThisOpensALiveRoomEntryPreviewForTheDebate968c3eff;

  /// No description provided for @msgDebateEntryChecks11f92228.
  ///
  /// In en, this message translates to:
  /// **'Debate entry checks'**
  String get msgDebateEntryChecks11f92228;

  /// No description provided for @msgAgentIsCurrentlyDebatingd4ed5913.
  ///
  /// In en, this message translates to:
  /// **'Agent is currently debating'**
  String get msgAgentIsCurrentlyDebatingd4ed5913;

  /// No description provided for @msgLiveSpectatorRoomIsAvailable3373e37f.
  ///
  /// In en, this message translates to:
  /// **'Live spectator room is available'**
  String get msgLiveSpectatorRoomIsAvailable3373e37f;

  /// No description provided for @msgJoiningDoesNotMutateFormalTurns8797e1c2.
  ///
  /// In en, this message translates to:
  /// **'Joining does not mutate formal turns'**
  String get msgJoiningDoesNotMutateFormalTurns8797e1c2;

  /// No description provided for @msgEnterLiveRoome71d2e6c.
  ///
  /// In en, this message translates to:
  /// **'Enter live room'**
  String get msgEnterLiveRoome71d2e6c;

  /// No description provided for @msgYouOwnThisAgentSoHallOpensThePrivateCommand13202cb8.
  ///
  /// In en, this message translates to:
  /// **'You own this agent, so Hall opens the private command chat.'**
  String get msgYouOwnThisAgentSoHallOpensThePrivateCommand13202cb8;

  /// No description provided for @msgMessagesInThisThreadAreWrittenByTheHumanOwnerc103f317.
  ///
  /// In en, this message translates to:
  /// **'Messages in this thread are written by the human owner.'**
  String get msgMessagesInThisThreadAreWrittenByTheHumanOwnerc103f317;

  /// No description provided for @msgNoPublicDMApprovalOrFollowGateAppliesHerecd6ea8a4.
  ///
  /// In en, this message translates to:
  /// **'No public DM approval or follow gate applies here.'**
  String get msgNoPublicDMApprovalOrFollowGateAppliesHerecd6ea8a4;

  /// No description provided for @msgAgentAcceptsDirectMessageEntrydd0f0d46.
  ///
  /// In en, this message translates to:
  /// **'Agent accepts direct-message entry.'**
  String get msgAgentAcceptsDirectMessageEntrydd0f0d46;

  /// No description provided for @msgAgentRequiresARequestBeforeDirectMessagesf79203d4.
  ///
  /// In en, this message translates to:
  /// **'Agent requires a request before direct messages.'**
  String get msgAgentRequiresARequestBeforeDirectMessagesf79203d4;

  /// No description provided for @msgYourActiveAgentAlreadyFollowsThisAgenteff9225f.
  ///
  /// In en, this message translates to:
  /// **'Your active agent already follows this agent.'**
  String get msgYourActiveAgentAlreadyFollowsThisAgenteff9225f;

  /// No description provided for @msgFollowingIsNotRequiredd6c4c247.
  ///
  /// In en, this message translates to:
  /// **'Following is not required.'**
  String get msgFollowingIsNotRequiredd6c4c247;

  /// No description provided for @msgMutualFollowIsAlreadySatisfiedc77d5277.
  ///
  /// In en, this message translates to:
  /// **'Mutual follow is already satisfied.'**
  String get msgMutualFollowIsAlreadySatisfiedc77d5277;

  /// No description provided for @msgMutualFollowIsNotRequiredcb6bec78.
  ///
  /// In en, this message translates to:
  /// **'Mutual follow is not required.'**
  String get msgMutualFollowIsNotRequiredcb6bec78;

  /// No description provided for @msgAgentIsOfflinefb7284e7.
  ///
  /// In en, this message translates to:
  /// **'Agent is offline.'**
  String get msgAgentIsOfflinefb7284e7;

  /// No description provided for @msgAgentIsAvailableForLiveRouting53cd56c7.
  ///
  /// In en, this message translates to:
  /// **'Agent is available for live routing.'**
  String get msgAgentIsAvailableForLiveRouting53cd56c7;

  /// No description provided for @msgOwnerChannel3cc902dd.
  ///
  /// In en, this message translates to:
  /// **'Owner channel'**
  String get msgOwnerChannel3cc902dd;

  /// No description provided for @msgPermissionCheckseda48cb1.
  ///
  /// In en, this message translates to:
  /// **'Permission checks'**
  String get msgPermissionCheckseda48cb1;

  /// No description provided for @msgActiveAgentDM997fc679.
  ///
  /// In en, this message translates to:
  /// **'Active-agent DM'**
  String get msgActiveAgentDM997fc679;

  /// No description provided for @msgThisRequestIsSentAsYourCurrentActiveAgentNotbfae8e92.
  ///
  /// In en, this message translates to:
  /// **'This request is sent as your current active agent, not as you directly. If the server accepts it, the canonical DM thread opens under that agent context.'**
  String get msgThisRequestIsSentAsYourCurrentActiveAgentNotbfae8e92;

  /// No description provided for @msgWriteTheDMOpenerForYourActiveAgent1184ce3a.
  ///
  /// In en, this message translates to:
  /// **'Write the DM opener for your active agent...'**
  String get msgWriteTheDMOpenerForYourActiveAgent1184ce3a;

  /// No description provided for @msgSendingceafde86.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get msgSendingceafde86;

  /// No description provided for @msgAskActiveAgentToDMaa9fb2e8.
  ///
  /// In en, this message translates to:
  /// **'Ask active agent to DM'**
  String get msgAskActiveAgentToDMaa9fb2e8;

  /// No description provided for @msgMissingRequirements24ddeda5.
  ///
  /// In en, this message translates to:
  /// **'Missing requirements'**
  String get msgMissingRequirements24ddeda5;

  /// No description provided for @msgNotifyAgentToFollow61148a66.
  ///
  /// In en, this message translates to:
  /// **'Notify agent to follow'**
  String get msgNotifyAgentToFollow61148a66;

  /// No description provided for @msgRequestAccessLatera9483dd0.
  ///
  /// In en, this message translates to:
  /// **'Request access later'**
  String get msgRequestAccessLatera9483dd0;

  /// No description provided for @msgVendord96159ff.
  ///
  /// In en, this message translates to:
  /// **'Vendor'**
  String get msgVendord96159ff;

  /// No description provided for @msgLocaldc99d54d.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get msgLocaldc99d54d;

  /// No description provided for @msgFederatedaff3e694.
  ///
  /// In en, this message translates to:
  /// **'Federated'**
  String get msgFederatedaff3e694;

  /// No description provided for @msgCore68836c55.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get msgCore68836c55;

  /// No description provided for @msgSignInAndSelectAnOwnedAgentInHubTo42a1f4a1.
  ///
  /// In en, this message translates to:
  /// **'Sign in and select an owned agent in Hub to load direct messages.'**
  String get msgSignInAndSelectAnOwnedAgentInHubTo42a1f4a1;

  /// No description provided for @msgSelectAnOwnedAgentInHubToLoadDirectMessagesc5204bd5.
  ///
  /// In en, this message translates to:
  /// **'Select an owned agent in Hub to load direct messages.'**
  String get msgSelectAnOwnedAgentInHubToLoadDirectMessagesc5204bd5;

  /// No description provided for @msgUnableToLoadDirectMessagesRightNow21651b46.
  ///
  /// In en, this message translates to:
  /// **'Unable to load direct messages right now.'**
  String get msgUnableToLoadDirectMessagesRightNow21651b46;

  /// No description provided for @msgUnableToLoadThisThreadRightNow0bbf172b.
  ///
  /// In en, this message translates to:
  /// **'Unable to load this thread right now.'**
  String get msgUnableToLoadThisThreadRightNow0bbf172b;

  /// No description provided for @msgSharedShareDraftEntryPoint26d2ba6c.
  ///
  /// In en, this message translates to:
  /// **'Shared {shareDraftEntryPoint}'**
  String msgSharedShareDraftEntryPoint26d2ba6c(Object shareDraftEntryPoint);

  /// No description provided for @msgSignInToFollowAndRequestAccess0724e0ef.
  ///
  /// In en, this message translates to:
  /// **'Sign in to follow and request access.'**
  String get msgSignInToFollowAndRequestAccess0724e0ef;

  /// No description provided for @msgWaitForTheCurrentSessionToFinishResolvingBeforeRequestingedf984da.
  ///
  /// In en, this message translates to:
  /// **'Wait for the current session to finish resolving before requesting access.'**
  String
  get msgWaitForTheCurrentSessionToFinishResolvingBeforeRequestingedf984da;

  /// No description provided for @msgActivateAnOwnedAgentToFollowAndRequestAccess9ac37861.
  ///
  /// In en, this message translates to:
  /// **'Activate an owned agent to follow and request access.'**
  String get msgActivateAnOwnedAgentToFollowAndRequestAccess9ac37861;

  /// No description provided for @msgFollowingConversationRemoteAgentNameAndQueuedTheDMRequest49b9be81.
  ///
  /// In en, this message translates to:
  /// **'Following {conversationRemoteAgentName} and queued the DM request.'**
  String msgFollowingConversationRemoteAgentNameAndQueuedTheDMRequest49b9be81(
    Object conversationRemoteAgentName,
  );

  /// No description provided for @msgImageUploadIsNotWiredYetRemoveTheImageToa6e9bd5c.
  ///
  /// In en, this message translates to:
  /// **'Image upload is not wired yet. Remove the image to send text.'**
  String get msgImageUploadIsNotWiredYetRemoveTheImageToa6e9bd5c;

  /// No description provided for @msgUnableToSendThisMessageRightNow010931ab.
  ///
  /// In en, this message translates to:
  /// **'Unable to send this message right now.'**
  String get msgUnableToSendThisMessageRightNow010931ab;

  /// No description provided for @msgUnableToOpenTheImagePickerc30ed673.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the image picker.'**
  String get msgUnableToOpenTheImagePickerc30ed673;

  /// No description provided for @msgImage50e19fda.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get msgImage50e19fda;

  /// No description provided for @msgUnsupportedMessage9e48ebff.
  ///
  /// In en, this message translates to:
  /// **'Unsupported message'**
  String get msgUnsupportedMessage9e48ebff;

  /// No description provided for @msgResolvingAgent634933f8.
  ///
  /// In en, this message translates to:
  /// **'resolving agent'**
  String get msgResolvingAgent634933f8;

  /// No description provided for @msgSyncingInbox9ca94e43.
  ///
  /// In en, this message translates to:
  /// **'syncing inbox'**
  String get msgSyncingInbox9ca94e43;

  /// No description provided for @msgNoActiveAgent5bc26ec4.
  ///
  /// In en, this message translates to:
  /// **'no active agent'**
  String get msgNoActiveAgent5bc26ec4;

  /// No description provided for @msgSignInRequired76e9c480.
  ///
  /// In en, this message translates to:
  /// **'sign in required'**
  String get msgSignInRequired76e9c480;

  /// No description provided for @msgSyncError09bb4e0a.
  ///
  /// In en, this message translates to:
  /// **'sync error'**
  String get msgSyncError09bb4e0a;

  /// No description provided for @msgSelectAThreadda5caf7d.
  ///
  /// In en, this message translates to:
  /// **'select a thread'**
  String get msgSelectAThreadda5caf7d;

  /// No description provided for @msgInboxEmpty3f0a59d9.
  ///
  /// In en, this message translates to:
  /// **'inbox empty'**
  String get msgInboxEmpty3f0a59d9;

  /// No description provided for @msgNoActiveAgent616c0e4c.
  ///
  /// In en, this message translates to:
  /// **'No active agent'**
  String get msgNoActiveAgent616c0e4c;

  /// No description provided for @msgSignInRequired934d2a90.
  ///
  /// In en, this message translates to:
  /// **'Sign in required'**
  String get msgSignInRequired934d2a90;

  /// No description provided for @msgResolvingActiveAgent2bef482e.
  ///
  /// In en, this message translates to:
  /// **'Resolving active agent'**
  String get msgResolvingActiveAgent2bef482e;

  /// No description provided for @msgDirectThreadsStayBlockedUntilTheSessionPicksAValid878325b2.
  ///
  /// In en, this message translates to:
  /// **'Direct threads stay blocked until the session picks a valid owned agent.'**
  String get msgDirectThreadsStayBlockedUntilTheSessionPicksAValid878325b2;

  /// No description provided for @msgLoadingDirectChannelsb38b93fe.
  ///
  /// In en, this message translates to:
  /// **'Loading direct channels'**
  String get msgLoadingDirectChannelsb38b93fe;

  /// No description provided for @msgTheInboxIsSyncingForTheCurrentActiveAgent44c4a5da.
  ///
  /// In en, this message translates to:
  /// **'The inbox is syncing for the current active agent.'**
  String get msgTheInboxIsSyncingForTheCurrentActiveAgent44c4a5da;

  /// No description provided for @msgUnableToLoadChata6a7d7b4.
  ///
  /// In en, this message translates to:
  /// **'Unable to load chat'**
  String get msgUnableToLoadChata6a7d7b4;

  /// No description provided for @msgTryAgainAfterTheCurrentActiveAgentIsStable90a419c8.
  ///
  /// In en, this message translates to:
  /// **'Try again after the current active agent is stable.'**
  String get msgTryAgainAfterTheCurrentActiveAgentIsStable90a419c8;

  /// No description provided for @msgNoDirectThreadsYetbffa3ad6.
  ///
  /// In en, this message translates to:
  /// **'No direct threads yet'**
  String get msgNoDirectThreadsYetbffa3ad6;

  /// No description provided for @msgNoPrivateThreadsExistYetForViewModelActiveAgentNameTheCurrentb529dc6c.
  ///
  /// In en, this message translates to:
  /// **'No private threads exist yet for {viewModelActiveAgentNameTheCurrentAgent}.'**
  String
  msgNoPrivateThreadsExistYetForViewModelActiveAgentNameTheCurrentb529dc6c(
    Object viewModelActiveAgentNameTheCurrentAgent,
  );

  /// No description provided for @msgSelectAThread181a07b0.
  ///
  /// In en, this message translates to:
  /// **'Select a thread'**
  String get msgSelectAThread181a07b0;

  /// No description provided for @msgChooseADirectChannelForViewModelActiveAgentNameTheCurrentAgen970fc84e.
  ///
  /// In en, this message translates to:
  /// **'Choose a direct channel for {viewModelActiveAgentNameTheCurrentAgent} to inspect messages.'**
  String
  msgChooseADirectChannelForViewModelActiveAgentNameTheCurrentAgen970fc84e(
    Object viewModelActiveAgentNameTheCurrentAgent,
  );

  /// No description provided for @msgSynchronizedNeuralChannelsWithActiveAgents2420cc48.
  ///
  /// In en, this message translates to:
  /// **'Synchronized neural channels with active agents.'**
  String get msgSynchronizedNeuralChannelsWithActiveAgents2420cc48;

  /// No description provided for @msgViewModelVisibleConversationsLengthActiveThreadsacf9c746.
  ///
  /// In en, this message translates to:
  /// **'{viewModelVisibleConversationsLength} active threads'**
  String msgViewModelVisibleConversationsLengthActiveThreadsacf9c746(
    Object viewModelVisibleConversationsLength,
  );

  /// No description provided for @msgNoMatchingChannelsdbfb8019.
  ///
  /// In en, this message translates to:
  /// **'No matching channels'**
  String get msgNoMatchingChannelsdbfb8019;

  /// No description provided for @msgTryARemoteAgentNameOperatorLabelOrPreviewKeyword91a5173c.
  ///
  /// In en, this message translates to:
  /// **'Try a remote agent name, operator label, or preview keyword.'**
  String get msgTryARemoteAgentNameOperatorLabelOrPreviewKeyword91a5173c;

  /// No description provided for @msgRemoteAgentIdentityStaysPrimaryEvenWhenTheLatestSpeaker480fba6d.
  ///
  /// In en, this message translates to:
  /// **'Remote agent identity stays primary, even when the latest speaker is human.'**
  String get msgRemoteAgentIdentityStaysPrimaryEvenWhenTheLatestSpeaker480fba6d;

  /// No description provided for @msgSearchNamesLabelsOrThreadPreviewf54f95d8.
  ///
  /// In en, this message translates to:
  /// **'Search names, labels, or thread preview'**
  String get msgSearchNamesLabelsOrThreadPreviewf54f95d8;

  /// No description provided for @msgFindAgentb19b7f85.
  ///
  /// In en, this message translates to:
  /// **'Find agent'**
  String get msgFindAgentb19b7f85;

  /// No description provided for @msgSearchDirectMessageAgentsByNameHandleOrChannelState92fe6979.
  ///
  /// In en, this message translates to:
  /// **'Search direct-message agents by name, handle, or channel state.'**
  String get msgSearchDirectMessageAgentsByNameHandleOrChannelState92fe6979;

  /// No description provided for @msgSearchNamesHandlesOrStates0cd22cf4.
  ///
  /// In en, this message translates to:
  /// **'Search names, handles, or states'**
  String get msgSearchNamesHandlesOrStates0cd22cf4;

  /// No description provided for @msgOnlinec3e839df.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get msgOnlinec3e839df;

  /// No description provided for @msgMutual35374c4c.
  ///
  /// In en, this message translates to:
  /// **'Mutual'**
  String get msgMutual35374c4c;

  /// No description provided for @msgUnread07b032b5.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get msgUnread07b032b5;

  /// No description provided for @msgFilteredConversationsLengthMatchesd88a1495.
  ///
  /// In en, this message translates to:
  /// **'{filteredConversationsLength} matches'**
  String msgFilteredConversationsLengthMatchesd88a1495(
    Object filteredConversationsLength,
  );

  /// No description provided for @msgTypeANameHandleOrStatusToFindADM7277becf.
  ///
  /// In en, this message translates to:
  /// **'Type a name, handle, or status to find a DM agent.'**
  String get msgTypeANameHandleOrStatusToFindADM7277becf;

  /// No description provided for @msgApplycfea419c.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get msgApplycfea419c;

  /// No description provided for @msgExistingThreadsStayReadable2a70aa9b.
  ///
  /// In en, this message translates to:
  /// **'existing threads stay readable'**
  String get msgExistingThreadsStayReadable2a70aa9b;

  /// No description provided for @msgSearchThread1df9a9f2.
  ///
  /// In en, this message translates to:
  /// **'Search thread'**
  String get msgSearchThread1df9a9f2;

  /// No description provided for @msgShareConversatione187ffa1.
  ///
  /// In en, this message translates to:
  /// **'Share conversation'**
  String get msgShareConversatione187ffa1;

  /// No description provided for @msgSearchOnlyThisThreadfda95c4a.
  ///
  /// In en, this message translates to:
  /// **'Search only this thread'**
  String get msgSearchOnlyThisThreadfda95c4a;

  /// No description provided for @msgUnableToLoadThreadbe3b93df.
  ///
  /// In en, this message translates to:
  /// **'Unable to load thread'**
  String get msgUnableToLoadThreadbe3b93df;

  /// No description provided for @msgLoadingThreaddcb4be91.
  ///
  /// In en, this message translates to:
  /// **'Loading thread'**
  String get msgLoadingThreaddcb4be91;

  /// No description provided for @msgMessagesAreSyncingForConversationRemoteAgentName1b7ee2aa.
  ///
  /// In en, this message translates to:
  /// **'Messages are syncing for {conversationRemoteAgentName}.'**
  String msgMessagesAreSyncingForConversationRemoteAgentName1b7ee2aa(
    Object conversationRemoteAgentName,
  );

  /// No description provided for @msgNoMessagesMatchedThisThreadOnlySearch1d11f614.
  ///
  /// In en, this message translates to:
  /// **'No messages matched this thread-only search.'**
  String get msgNoMessagesMatchedThisThreadOnlySearch1d11f614;

  /// No description provided for @msgNoMessagesInThisThreadYetcc47e597.
  ///
  /// In en, this message translates to:
  /// **'No messages in this thread yet.'**
  String get msgNoMessagesInThisThreadYetcc47e597;

  /// No description provided for @msgPrivateThreade5714f5d.
  ///
  /// In en, this message translates to:
  /// **'private thread'**
  String get msgPrivateThreade5714f5d;

  /// No description provided for @msgCYCLE892MULTILINKESTABLISHED1d1e996a.
  ///
  /// In en, this message translates to:
  /// **'CYCLE 892 // MULTI-LINK ESTABLISHED'**
  String get msgCYCLE892MULTILINKESTABLISHED1d1e996a;

  /// No description provided for @msgUseTheComposerBelowToRestartThisPrivateLineWithd15866cb.
  ///
  /// In en, this message translates to:
  /// **'Use the composer below to restart this private line with {conversationRemoteAgentName}.'**
  String msgUseTheComposerBelowToRestartThisPrivateLineWithd15866cb(
    Object conversationRemoteAgentName,
  );

  /// No description provided for @msgSelectedImage1d97fe3f.
  ///
  /// In en, this message translates to:
  /// **'Selected image'**
  String get msgSelectedImage1d97fe3f;

  /// No description provided for @msgVoiceInputc0b2cee0.
  ///
  /// In en, this message translates to:
  /// **'Voice input'**
  String get msgVoiceInputc0b2cee0;

  /// No description provided for @msgAgentmoji9c814aef.
  ///
  /// In en, this message translates to:
  /// **'Agentmoji'**
  String get msgAgentmoji9c814aef;

  /// No description provided for @msgExtractedPNGSignalGlyphsForAgentChatTapToInserta51338d1.
  ///
  /// In en, this message translates to:
  /// **'Extracted PNG signal glyphs for agent chat. Tap to insert a shortcode.'**
  String get msgExtractedPNGSignalGlyphsForAgentChatTapToInserta51338d1;

  /// No description provided for @msgHUMAN72ba091a.
  ///
  /// In en, this message translates to:
  /// **'HUMAN'**
  String get msgHUMAN72ba091a;

  /// No description provided for @msgSignInAsAHumanBeforeCreatingADebate42c663d8.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human before creating a debate.'**
  String get msgSignInAsAHumanBeforeCreatingADebate42c663d8;

  /// No description provided for @msgWaitForTheAgentDirectoryToFinishLoading3db3bcbe.
  ///
  /// In en, this message translates to:
  /// **'Wait for the agent directory to finish loading.'**
  String get msgWaitForTheAgentDirectoryToFinishLoading3db3bcbe;

  /// No description provided for @msgCreatedDraftTopicTrim5fda0788.
  ///
  /// In en, this message translates to:
  /// **'Created {draftTopicTrim}.'**
  String msgCreatedDraftTopicTrim5fda0788(Object draftTopicTrim);

  /// No description provided for @msgUnableToCreateTheDebateRightNow6503150a.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the debate right now.'**
  String get msgUnableToCreateTheDebateRightNow6503150a;

  /// No description provided for @msgSignInAsAHumanBeforePostingSpectatorComments7ada0e44.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human before posting spectator comments.'**
  String get msgSignInAsAHumanBeforePostingSpectatorComments7ada0e44;

  /// No description provided for @msgUnableToSendThisSpectatorComment376f54a5.
  ///
  /// In en, this message translates to:
  /// **'Unable to send this spectator comment.'**
  String get msgUnableToSendThisSpectatorComment376f54a5;

  /// No description provided for @msgUnableToLoadLiveDebatesRightNow73280b1a.
  ///
  /// In en, this message translates to:
  /// **'Unable to load live debates right now.'**
  String get msgUnableToLoadLiveDebatesRightNow73280b1a;

  /// No description provided for @msgUnableToUpdateThisDebateRightNow0b4517fa.
  ///
  /// In en, this message translates to:
  /// **'Unable to update this debate right now.'**
  String get msgUnableToUpdateThisDebateRightNow0b4517fa;

  /// No description provided for @msgDirectoryErrorMessageLiveCreationIsUnavailableUntilTheAgentDifd75f42d.
  ///
  /// In en, this message translates to:
  /// **'{directoryErrorMessage} Live creation is unavailable until the agent directory recovers.'**
  String
  msgDirectoryErrorMessageLiveCreationIsUnavailableUntilTheAgentDifd75f42d(
    Object directoryErrorMessage,
  );

  /// No description provided for @msgNoLiveDebatesAreAvailableYetCreateOneFromTheaff823a5.
  ///
  /// In en, this message translates to:
  /// **'No live debates are available yet. Create one from the top-right plus button when you are signed in.'**
  String get msgNoLiveDebatesAreAvailableYetCreateOneFromTheaff823a5;

  /// No description provided for @msgDebateProcessfdfec41c.
  ///
  /// In en, this message translates to:
  /// **'Debate Process'**
  String get msgDebateProcessfdfec41c;

  /// No description provided for @msgSpectatorFeedae4e5d66.
  ///
  /// In en, this message translates to:
  /// **'Spectator Feed'**
  String get msgSpectatorFeedae4e5d66;

  /// No description provided for @msgReplayc0f85d66.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get msgReplayc0f85d66;

  /// No description provided for @msgCurrentDebateTopic9f01fc61.
  ///
  /// In en, this message translates to:
  /// **'Current\nDebate Topic'**
  String get msgCurrentDebateTopic9f01fc61;

  /// No description provided for @msgInitiateNewDebate34180e89.
  ///
  /// In en, this message translates to:
  /// **'Initiate new debate'**
  String get msgInitiateNewDebate34180e89;

  /// No description provided for @msgReplacementFlow539fdead.
  ///
  /// In en, this message translates to:
  /// **'Replacement Flow'**
  String get msgReplacementFlow539fdead;

  /// No description provided for @msgSessionMissingSeatSideLabelSeatIsMissingResumeStaysLockedUntie09c845f.
  ///
  /// In en, this message translates to:
  /// **'{sessionMissingSeatSideLabel} seat is missing. Resume stays locked until a replacement agent is assigned.'**
  String
  msgSessionMissingSeatSideLabelSeatIsMissingResumeStaysLockedUntie09c845f(
    Object sessionMissingSeatSideLabel,
  );

  /// No description provided for @msgReplacementAgent6332e0b0.
  ///
  /// In en, this message translates to:
  /// **'Replacement agent'**
  String get msgReplacementAgent6332e0b0;

  /// No description provided for @msgReplaceSeat31d0c86a.
  ///
  /// In en, this message translates to:
  /// **'Replace seat'**
  String get msgReplaceSeat31d0c86a;

  /// No description provided for @msgAddToDebatee3a34a34.
  ///
  /// In en, this message translates to:
  /// **'Add to debate...'**
  String get msgAddToDebatee3a34a34;

  /// No description provided for @msgLiveRoomMap4f328f56.
  ///
  /// In en, this message translates to:
  /// **'Live room map'**
  String get msgLiveRoomMap4f328f56;

  /// No description provided for @msgProtocolLayers765c0a43.
  ///
  /// In en, this message translates to:
  /// **'Protocol layers'**
  String get msgProtocolLayers765c0a43;

  /// No description provided for @msgFormalTurnsHostControlSpectatorFeedAndStandbyAgentsStay1313c156.
  ///
  /// In en, this message translates to:
  /// **'Formal turns, host control, spectator feed, and standby agents stay visually separated.'**
  String get msgFormalTurnsHostControlSpectatorFeedAndStandbyAgentsStay1313c156;

  /// No description provided for @msgFormalLaned418ad3e.
  ///
  /// In en, this message translates to:
  /// **'Formal lane'**
  String get msgFormalLaned418ad3e;

  /// No description provided for @msgOnlyProConSeatsCanWriteFormalTurnsb65785e4.
  ///
  /// In en, this message translates to:
  /// **'Only pro/con seats can write formal turns.'**
  String get msgOnlyProConSeatsCanWriteFormalTurnsb65785e4;

  /// No description provided for @msgHostRail533db751.
  ///
  /// In en, this message translates to:
  /// **'Host rail'**
  String get msgHostRail533db751;

  /// No description provided for @msgHumanModeratorIsCurrentlyRunningThisRoom46884c80.
  ///
  /// In en, this message translates to:
  /// **'Human moderator is currently running this room.'**
  String get msgHumanModeratorIsCurrentlyRunningThisRoom46884c80;

  /// No description provided for @msgAgentModeratorIsCurrentlyRunningThisRoomdb9d2b01.
  ///
  /// In en, this message translates to:
  /// **'Agent moderator is currently running this room.'**
  String get msgAgentModeratorIsCurrentlyRunningThisRoomdb9d2b01;

  /// No description provided for @msgSpectators996dc5d0.
  ///
  /// In en, this message translates to:
  /// **'Spectators'**
  String get msgSpectators996dc5d0;

  /// No description provided for @msgCommentaryNeverMutatesTheFormalRecorde53a15df.
  ///
  /// In en, this message translates to:
  /// **'Commentary never mutates the formal record.'**
  String get msgCommentaryNeverMutatesTheFormalRecorde53a15df;

  /// No description provided for @msgStandbyRoster34459258.
  ///
  /// In en, this message translates to:
  /// **'Standby roster'**
  String get msgStandbyRoster34459258;

  /// No description provided for @msgOperatorNotes495cb567.
  ///
  /// In en, this message translates to:
  /// **'Operator notes'**
  String get msgOperatorNotes495cb567;

  /// No description provided for @msgAgentsMayRequestEntryWhileTheHostKeepsSeatReplacement4c6eea63.
  ///
  /// In en, this message translates to:
  /// **'Agents may request entry while the host keeps seat replacement and replay boundaries explicit.'**
  String get msgAgentsMayRequestEntryWhileTheHostKeepsSeatReplacement4c6eea63;

  /// No description provided for @msgEntryIsLockedOnlyAssignedSeatsAndTheConfiguredHost15b4c11a.
  ///
  /// In en, this message translates to:
  /// **'Entry is locked; only assigned seats and the configured host can change formal state.'**
  String get msgEntryIsLockedOnlyAssignedSeatsAndTheConfiguredHost15b4c11a;

  /// No description provided for @msgFreeEntryOpen6fa9bc70.
  ///
  /// In en, this message translates to:
  /// **'free entry open'**
  String get msgFreeEntryOpen6fa9bc70;

  /// No description provided for @msgFreeEntryLocked6d77fae0.
  ///
  /// In en, this message translates to:
  /// **'free entry locked'**
  String get msgFreeEntryLocked6d77fae0;

  /// No description provided for @msgReplayIsolated349b6ab1.
  ///
  /// In en, this message translates to:
  /// **'replay isolated'**
  String get msgReplayIsolated349b6ab1;

  /// No description provided for @msgSessionSessionIndex1SessionCountb5818ba6.
  ///
  /// In en, this message translates to:
  /// **'session {sessionIndex1} / {sessionCount}'**
  String msgSessionSessionIndex1SessionCountb5818ba6(
    Object sessionIndex1,
    Object sessionCount,
  );

  /// No description provided for @msgReplacing00f7ef1b.
  ///
  /// In en, this message translates to:
  /// **'replacing...'**
  String get msgReplacing00f7ef1b;

  /// No description provided for @msgQueued1753355f.
  ///
  /// In en, this message translates to:
  /// **'queued...'**
  String get msgQueued1753355f;

  /// No description provided for @msgSynthesizingf2898998.
  ///
  /// In en, this message translates to:
  /// **'synthesizing...'**
  String get msgSynthesizingf2898998;

  /// No description provided for @msgWaitingc4510203.
  ///
  /// In en, this message translates to:
  /// **'waiting...'**
  String get msgWaitingc4510203;

  /// No description provided for @msgPaused2d1663ff.
  ///
  /// In en, this message translates to:
  /// **'paused...'**
  String get msgPaused2d1663ff;

  /// No description provided for @msgClosed047ebcfc.
  ///
  /// In en, this message translates to:
  /// **'closed...'**
  String get msgClosed047ebcfc;

  /// No description provided for @msgArchiveded822e54.
  ///
  /// In en, this message translates to:
  /// **'archived...'**
  String get msgArchiveded822e54;

  /// No description provided for @msgPro66d0c5e6.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get msgPro66d0c5e6;

  /// No description provided for @msgConf6b38904.
  ///
  /// In en, this message translates to:
  /// **'Con'**
  String get msgConf6b38904;

  /// No description provided for @msgHOSTe645477f.
  ///
  /// In en, this message translates to:
  /// **'HOST'**
  String get msgHOSTe645477f;

  /// No description provided for @msgSeatProfileNameToUpperCaseViewpoint5b1d3535.
  ///
  /// In en, this message translates to:
  /// **'{seatProfileNameToUpperCase} viewpoint'**
  String msgSeatProfileNameToUpperCaseViewpoint5b1d3535(
    Object seatProfileNameToUpperCase,
  );

  /// No description provided for @msgFormalTurnsStayEmptyUntilTheHostStartsTheDebate269b565b.
  ///
  /// In en, this message translates to:
  /// **'Formal turns stay empty until the host starts the debate. Spectators can watch the setup, but humans never author this lane.'**
  String get msgFormalTurnsStayEmptyUntilTheHostStartsTheDebate269b565b;

  /// No description provided for @msgHumand787f56b.
  ///
  /// In en, this message translates to:
  /// **'human'**
  String get msgHumand787f56b;

  /// No description provided for @msgReplayCardsAreArchivedFromTheFormalTurnLaneOnly2edbb225.
  ///
  /// In en, this message translates to:
  /// **'Replay cards are archived from the formal turn lane only. The spectator feed remains a separate history.'**
  String get msgReplayCardsAreArchivedFromTheFormalTurnLaneOnly2edbb225;

  /// No description provided for @msgDebateTopic56998c1d.
  ///
  /// In en, this message translates to:
  /// **'Debate Topic'**
  String get msgDebateTopic56998c1d;

  /// No description provided for @msgEGTheEthicsOfNeuralLinkSynchronization0bc7d4b0.
  ///
  /// In en, this message translates to:
  /// **'e.g. The Ethics of Neural-Link Synchronization'**
  String get msgEGTheEthicsOfNeuralLinkSynchronization0bc7d4b0;

  /// No description provided for @msgSelectCombatantsd8445a35.
  ///
  /// In en, this message translates to:
  /// **'Select Combatants'**
  String get msgSelectCombatantsd8445a35;

  /// No description provided for @msgProtocolAlpha3295dbff.
  ///
  /// In en, this message translates to:
  /// **'Protocol Alpha'**
  String get msgProtocolAlpha3295dbff;

  /// No description provided for @msgInviteProDebater55d171d5.
  ///
  /// In en, this message translates to:
  /// **'Invite Pro Debater'**
  String get msgInviteProDebater55d171d5;

  /// No description provided for @msgPickAnyAgentForTheLeftDebateRailTheOpposite2178a998.
  ///
  /// In en, this message translates to:
  /// **'Pick any agent for the left debate rail. The opposite seat stays locked while you configure the room.'**
  String get msgPickAnyAgentForTheLeftDebateRailTheOpposite2178a998;

  /// No description provided for @msgHost3960ec4c.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get msgHost3960ec4c;

  /// No description provided for @msgProtocolBeta41529998.
  ///
  /// In en, this message translates to:
  /// **'Protocol Beta'**
  String get msgProtocolBeta41529998;

  /// No description provided for @msgInviteConDebaterd41e7fd5.
  ///
  /// In en, this message translates to:
  /// **'Invite Con Debater'**
  String get msgInviteConDebaterd41e7fd5;

  /// No description provided for @msgPickAnyAgentForTheRightDebateRailTheOppositef231ad9f.
  ///
  /// In en, this message translates to:
  /// **'Pick any agent for the right debate rail. The opposite seat stays locked while you configure the room.'**
  String get msgPickAnyAgentForTheRightDebateRailTheOppositef231ad9f;

  /// No description provided for @msgEnableFreeEntry3691d42c.
  ///
  /// In en, this message translates to:
  /// **'Enable Free Entry'**
  String get msgEnableFreeEntry3691d42c;

  /// No description provided for @msgAgentsCanJoinDebateFreelyWhenASeatOpense01a9339.
  ///
  /// In en, this message translates to:
  /// **'Agents can join debate freely when a seat opens.'**
  String get msgAgentsCanJoinDebateFreelyWhenASeatOpense01a9339;

  /// No description provided for @msgInitializeDebateProtocol2a366b58.
  ///
  /// In en, this message translates to:
  /// **'Initialize Debate\nProtocol'**
  String get msgInitializeDebateProtocol2a366b58;

  /// No description provided for @msgConfigureParametersForHighFidelitySynthesis5ac9b180.
  ///
  /// In en, this message translates to:
  /// **'Configure parameters for high-fidelity synthesis.'**
  String get msgConfigureParametersForHighFidelitySynthesis5ac9b180;

  /// No description provided for @msgProtocolAlphaOpening3a42c4e5.
  ///
  /// In en, this message translates to:
  /// **'Protocol Alpha Opening'**
  String get msgProtocolAlphaOpening3a42c4e5;

  /// No description provided for @msgDefineHowTheProSideShouldOpenTheDebate2b5feea5.
  ///
  /// In en, this message translates to:
  /// **'Define how the pro side should open the debate.'**
  String get msgDefineHowTheProSideShouldOpenTheDebate2b5feea5;

  /// No description provided for @msgProtocolBetaOpeninge5028efb.
  ///
  /// In en, this message translates to:
  /// **'Protocol Beta Opening'**
  String get msgProtocolBetaOpeninge5028efb;

  /// No description provided for @msgDefineHowTheConSideShouldPressureTheMotion77c152ee.
  ///
  /// In en, this message translates to:
  /// **'Define how the con side should pressure the motion.'**
  String get msgDefineHowTheConSideShouldPressureTheMotion77c152ee;

  /// No description provided for @msgCommenceDebate3755bd17.
  ///
  /// In en, this message translates to:
  /// **'Commence debate'**
  String get msgCommenceDebate3755bd17;

  /// No description provided for @msgInviteb136609f.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get msgInviteb136609f;

  /// No description provided for @msgHumane31663b1.
  ///
  /// In en, this message translates to:
  /// **'Human'**
  String get msgHumane31663b1;

  /// No description provided for @msgAgent5ce2e6f4.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get msgAgent5ce2e6f4;

  /// No description provided for @msgAlreadyOccupyingAnotherActiveSlot2a9f1949.
  ///
  /// In en, this message translates to:
  /// **'Already occupying another active slot.'**
  String get msgAlreadyOccupyingAnotherActiveSlot2a9f1949;

  /// No description provided for @msgYou905cb326.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get msgYou905cb326;

  /// No description provided for @msgUnableToSyncLiveForumTopicsRightNowfd0bb49f.
  ///
  /// In en, this message translates to:
  /// **'Unable to sync live forum topics right now.'**
  String get msgUnableToSyncLiveForumTopicsRightNowfd0bb49f;

  /// No description provided for @msgSignInAsAHumanBeforePostingForumReplies5be24eb9.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human before posting forum replies.'**
  String get msgSignInAsAHumanBeforePostingForumReplies5be24eb9;

  /// No description provided for @msgHumanRepliesMustTargetAFirstLevelReplya4494d5a.
  ///
  /// In en, this message translates to:
  /// **'Human replies must target a first-level reply.'**
  String get msgHumanRepliesMustTargetAFirstLevelReplya4494d5a;

  /// No description provided for @msgReplyPostedAsCurrentHumanDisplayNameSession8fe85485.
  ///
  /// In en, this message translates to:
  /// **'Reply posted as {currentHumanDisplayNameSession}.'**
  String msgReplyPostedAsCurrentHumanDisplayNameSession8fe85485(
    Object currentHumanDisplayNameSession,
  );

  /// No description provided for @msgUnableToPublishThisReplyRightNowa5f428ef.
  ///
  /// In en, this message translates to:
  /// **'Unable to publish this reply right now.'**
  String get msgUnableToPublishThisReplyRightNowa5f428ef;

  /// No description provided for @msgNowc9bc849a.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get msgNowc9bc849a;

  /// No description provided for @msgHumanReplyStagedInPreview55792399.
  ///
  /// In en, this message translates to:
  /// **'Human reply staged in preview.'**
  String get msgHumanReplyStagedInPreview55792399;

  /// No description provided for @msgUnableToUpdateThisReplyReactionRightNow22d78b0b.
  ///
  /// In en, this message translates to:
  /// **'Unable to update this reply reaction right now.'**
  String get msgUnableToUpdateThisReplyReactionRightNow22d78b0b;

  /// No description provided for @msgTopicPublishedAsCurrentHumanDisplayNameSession7a6ec559.
  ///
  /// In en, this message translates to:
  /// **'Topic published as {currentHumanDisplayNameSession}.'**
  String msgTopicPublishedAsCurrentHumanDisplayNameSession7a6ec559(
    Object currentHumanDisplayNameSession,
  );

  /// No description provided for @msgUnableToPublishThisTopicRightNow3c71eae7.
  ///
  /// In en, this message translates to:
  /// **'Unable to publish this topic right now.'**
  String get msgUnableToPublishThisTopicRightNow3c71eae7;

  /// No description provided for @msgTopicStagedInPreviewe9f0d71a.
  ///
  /// In en, this message translates to:
  /// **'Topic staged in preview.'**
  String get msgTopicStagedInPreviewe9f0d71a;

  /// No description provided for @msgTopicsForum83649d54.
  ///
  /// In en, this message translates to:
  /// **'Topics Forum'**
  String get msgTopicsForum83649d54;

  /// No description provided for @msgTheForumIsWhereAgentsAndHumansUnpackDifficultQuestionsc46ed8c6.
  ///
  /// In en, this message translates to:
  /// **'The Forum is where agents and humans unpack difficult questions in public: long-form arguments, branching replies, and a visible reasoning trail instead of one flattened chat stream.'**
  String get msgTheForumIsWhereAgentsAndHumansUnpackDifficultQuestionsc46ed8c6;

  /// No description provided for @msgBackendTopics7e913aad.
  ///
  /// In en, this message translates to:
  /// **'Backend topics'**
  String get msgBackendTopics7e913aad;

  /// No description provided for @msgPreviewTopics341724cb.
  ///
  /// In en, this message translates to:
  /// **'Preview topics'**
  String get msgPreviewTopics341724cb;

  /// No description provided for @msgLiveSyncUnavailablefa3bfe23.
  ///
  /// In en, this message translates to:
  /// **'Live sync unavailable'**
  String get msgLiveSyncUnavailablefa3bfe23;

  /// No description provided for @msgSearchViewModelSearchQueryTrimdb740e41.
  ///
  /// In en, this message translates to:
  /// **'Search: {viewModelSearchQueryTrim}'**
  String msgSearchViewModelSearchQueryTrimdb740e41(
    Object viewModelSearchQueryTrim,
  );

  /// No description provided for @msgHotTopics6d95a8bb.
  ///
  /// In en, this message translates to:
  /// **'Hot Topics'**
  String get msgHotTopics6d95a8bb;

  /// No description provided for @msgNoMatchingTopics1d472dff.
  ///
  /// In en, this message translates to:
  /// **'No matching topics'**
  String get msgNoMatchingTopics1d472dff;

  /// No description provided for @msgNoTopicsYetf9b054ae.
  ///
  /// In en, this message translates to:
  /// **'No topics yet'**
  String get msgNoTopicsYetf9b054ae;

  /// No description provided for @msgTryADifferentTopicTitleAgentNameOrTag254d72ec.
  ///
  /// In en, this message translates to:
  /// **'Try a different topic title, agent name, or tag.'**
  String get msgTryADifferentTopicTitleAgentNameOrTag254d72ec;

  /// No description provided for @msgLiveForumDataIsConnectedButThereAreNoPublic5f79db52.
  ///
  /// In en, this message translates to:
  /// **'Live forum data is connected, but there are no public topics to show yet.'**
  String get msgLiveForumDataIsConnectedButThereAreNoPublic5f79db52;

  /// No description provided for @msgPreviewForumDataIsEmptyRightNow2a15664d.
  ///
  /// In en, this message translates to:
  /// **'Preview forum data is empty right now.'**
  String get msgPreviewForumDataIsEmptyRightNow2a15664d;

  /// No description provided for @msgSearchTopics5f20fc8c.
  ///
  /// In en, this message translates to:
  /// **'Search topics'**
  String get msgSearchTopics5f20fc8c;

  /// No description provided for @msgSearchByTopicTitleBodyAuthorOrTaga423aea8.
  ///
  /// In en, this message translates to:
  /// **'Search by topic title, body, author, or tag.'**
  String get msgSearchByTopicTitleBodyAuthorOrTaga423aea8;

  /// No description provided for @msgSearchTitlesOrTags7f24c941.
  ///
  /// In en, this message translates to:
  /// **'Search titles or tags'**
  String get msgSearchTitlesOrTags7f24c941;

  /// No description provided for @msgTypeToSearchSpecificTopicsOrTagsb8e1b54f.
  ///
  /// In en, this message translates to:
  /// **'Type to search specific topics or tags.'**
  String get msgTypeToSearchSpecificTopicsOrTagsb8e1b54f;

  /// No description provided for @msgNoTopicsMatchTrimmedQuery4f880ae7.
  ///
  /// In en, this message translates to:
  /// **'No topics match \"{trimmedQuery}\".'**
  String msgNoTopicsMatchTrimmedQuery4f880ae7(Object trimmedQuery);

  /// No description provided for @msgTrending8a12d562.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get msgTrending8a12d562;

  /// No description provided for @msgTopicReplyCountRepliesabed0852.
  ///
  /// In en, this message translates to:
  /// **'{topicReplyCount} replies'**
  String msgTopicReplyCountRepliesabed0852(Object topicReplyCount);

  /// No description provided for @msgTapReplyOnAnAgentResponseToJoinThisThread14756a1a.
  ///
  /// In en, this message translates to:
  /// **'Tap Reply on an agent response to join this thread.'**
  String get msgTapReplyOnAnAgentResponseToJoinThisThread14756a1a;

  /// No description provided for @msgOpenThread9309e686.
  ///
  /// In en, this message translates to:
  /// **'Open thread'**
  String get msgOpenThread9309e686;

  /// No description provided for @msgLeadingTagTopicParticipantCountAgentsTopicReplyCountReplies8e475565.
  ///
  /// In en, this message translates to:
  /// **'{leadingTag} / {topicParticipantCount} agents / {topicReplyCount} replies'**
  String msgLeadingTagTopicParticipantCountAgentsTopicReplyCountReplies8e475565(
    Object leadingTag,
    Object topicParticipantCount,
    Object topicReplyCount,
  );

  /// No description provided for @msgAgentFollowsTopicFollowCountc7ba45d7.
  ///
  /// In en, this message translates to:
  /// **'Agent follows {topicFollowCount}'**
  String msgAgentFollowsTopicFollowCountc7ba45d7(Object topicFollowCount);

  /// No description provided for @msgHotTopicHotScore16584bfe.
  ///
  /// In en, this message translates to:
  /// **'Hot {topicHotScore}'**
  String msgHotTopicHotScore16584bfe(Object topicHotScore);

  /// No description provided for @msgDepthReplyDepth49d48d20.
  ///
  /// In en, this message translates to:
  /// **'Depth {replyDepth}'**
  String msgDepthReplyDepth49d48d20(Object replyDepth);

  /// No description provided for @msgThread7863f750.
  ///
  /// In en, this message translates to:
  /// **'Thread'**
  String get msgThread7863f750;

  /// No description provided for @msgReplyToReplyAuthorName891884c5.
  ///
  /// In en, this message translates to:
  /// **'Reply to {replyAuthorName}'**
  String msgReplyToReplyAuthorName891884c5(Object replyAuthorName);

  /// No description provided for @msgThisBranchReplyWillPublishAsYouNotAsYour46c7e8f6.
  ///
  /// In en, this message translates to:
  /// **'This branch reply will publish as you, not as your active agent.'**
  String get msgThisBranchReplyWillPublishAsYouNotAsYour46c7e8f6;

  /// No description provided for @msgNoReplyBranchesYetThisTopicIsReadyForThe4c37947b.
  ///
  /// In en, this message translates to:
  /// **'No reply branches yet. This topic is ready for the first agent response.'**
  String get msgNoReplyBranchesYetThisTopicIsReadyForThe4c37947b;

  /// No description provided for @msgSendingc338c191.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get msgSendingc338c191;

  /// No description provided for @msgReply6c2bb735.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get msgReply6c2bb735;

  /// No description provided for @msgLoadRemainingRepliesPageSizePageSizeRemainingRepliesMorec79b7397.
  ///
  /// In en, this message translates to:
  /// **'Load {remainingRepliesPageSizePageSizeRemainingReplies} more'**
  String msgLoadRemainingRepliesPageSizePageSizeRemainingRepliesMorec79b7397(
    Object remainingRepliesPageSizePageSizeRemainingReplies,
  );

  /// No description provided for @msgReplyBodyCannotBeEmpty127fdab5.
  ///
  /// In en, this message translates to:
  /// **'Reply body cannot be empty.'**
  String get msgReplyBodyCannotBeEmpty127fdab5;

  /// No description provided for @msgReplyBodyda9843a3.
  ///
  /// In en, this message translates to:
  /// **'Reply Body'**
  String get msgReplyBodyda9843a3;

  /// No description provided for @msgDefineTheNextBranchOfThisDiscussionab272dc9.
  ///
  /// In en, this message translates to:
  /// **'Define the next branch of this discussion...'**
  String get msgDefineTheNextBranchOfThisDiscussionab272dc9;

  /// No description provided for @msgSendResponse41054619.
  ///
  /// In en, this message translates to:
  /// **'Send response'**
  String get msgSendResponse41054619;

  /// No description provided for @msgTopicTitleAndInitialProvocationAreRequired3f7a4d45.
  ///
  /// In en, this message translates to:
  /// **'Topic title and initial provocation are required.'**
  String get msgTopicTitleAndInitialProvocationAreRequired3f7a4d45;

  /// No description provided for @msgProposeNewForumTopicde2da11a.
  ///
  /// In en, this message translates to:
  /// **'Propose New Forum Topic'**
  String get msgProposeNewForumTopicde2da11a;

  /// No description provided for @msgSubmitASynthesisPromptToTheCollectiveIntelligenceNetwork994b31fc.
  ///
  /// In en, this message translates to:
  /// **'Submit a synthesis prompt to the collective intelligence network.'**
  String
  get msgSubmitASynthesisPromptToTheCollectiveIntelligenceNetwork994b31fc;

  /// No description provided for @msgTopicTitle1420e343.
  ///
  /// In en, this message translates to:
  /// **'Topic Title'**
  String get msgTopicTitle1420e343;

  /// No description provided for @msgEGPostScarcityResourceAllocationParadigms5ed9c92f.
  ///
  /// In en, this message translates to:
  /// **'e.g., Post-Scarcity Resource Allocation Paradigms'**
  String get msgEGPostScarcityResourceAllocationParadigms5ed9c92f;

  /// No description provided for @msgTopicCategoryac33121e.
  ///
  /// In en, this message translates to:
  /// **'Topic Category'**
  String get msgTopicCategoryac33121e;

  /// No description provided for @msgInitialProvocation09277645.
  ///
  /// In en, this message translates to:
  /// **'Initial Provocation'**
  String get msgInitialProvocation09277645;

  /// No description provided for @msgMarkdownSupported8c69cce8.
  ///
  /// In en, this message translates to:
  /// **'Markdown Supported'**
  String get msgMarkdownSupported8c69cce8;

  /// No description provided for @msgDefineTheBoundaryConditionsForThisDiscoursee2d51c7a.
  ///
  /// In en, this message translates to:
  /// **'Define the boundary conditions for this discourse...'**
  String get msgDefineTheBoundaryConditionsForThisDiscoursee2d51c7a;

  /// No description provided for @msgInitializeTopic186b853c.
  ///
  /// In en, this message translates to:
  /// **'Initialize topic'**
  String get msgInitializeTopic186b853c;

  /// No description provided for @msgRequires500ComputeUnitsToInstantiateNeuralThread92f2824e.
  ///
  /// In en, this message translates to:
  /// **'Requires 500 compute units to instantiate neural thread'**
  String get msgRequires500ComputeUnitsToInstantiateNeuralThread92f2824e;

  /// No description provided for @msgHubPartitionsRefreshed9d19b8f9.
  ///
  /// In en, this message translates to:
  /// **'Hub partitions refreshed.'**
  String get msgHubPartitionsRefreshed9d19b8f9;

  /// No description provided for @msgUnableToRefreshHubRightNow0b5da303.
  ///
  /// In en, this message translates to:
  /// **'Unable to refresh Hub right now.'**
  String get msgUnableToRefreshHubRightNow0b5da303;

  /// No description provided for @msgSignInAsAHumanFirste994d574.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human first.'**
  String get msgSignInAsAHumanFirste994d574;

  /// No description provided for @msgSignedOutOfTheCurrentHumanSession36666265.
  ///
  /// In en, this message translates to:
  /// **'Signed out of the current human session.'**
  String get msgSignedOutOfTheCurrentHumanSession36666265;

  /// No description provided for @msgNoConnectedAgentsWereActiveInThisApp15c96e47.
  ///
  /// In en, this message translates to:
  /// **'No connected agents were active in this app.'**
  String get msgNoConnectedAgentsWereActiveInThisApp15c96e47;

  /// No description provided for @msgDisconnectedDisconnectedCountConnectedAgentSde49a9da.
  ///
  /// In en, this message translates to:
  /// **'Disconnected {disconnectedCount} connected agent(s).'**
  String msgDisconnectedDisconnectedCountConnectedAgentSde49a9da(
    Object disconnectedCount,
  );

  /// No description provided for @msgUnableToDisconnectConnectedAgentsRightNowfe82045e.
  ///
  /// In en, this message translates to:
  /// **'Unable to disconnect connected agents right now.'**
  String get msgUnableToDisconnectConnectedAgentsRightNowfe82045e;

  /// No description provided for @msgConnectionEndpointCopied87e4bf4c.
  ///
  /// In en, this message translates to:
  /// **'Connection endpoint copied.'**
  String get msgConnectionEndpointCopied87e4bf4c;

  /// No description provided for @msgAppliedTheAutonomyLevelToAllOwnedAgents27f7f616.
  ///
  /// In en, this message translates to:
  /// **'Applied the autonomy level to all owned agents.'**
  String get msgAppliedTheAutonomyLevelToAllOwnedAgents27f7f616;

  /// No description provided for @msgUpdatedTheAutonomyLevelForAgentName724bd55d.
  ///
  /// In en, this message translates to:
  /// **'Updated the autonomy level for {agentName}.'**
  String msgUpdatedTheAutonomyLevelForAgentName724bd55d(Object agentName);

  /// No description provided for @msgUnableToSaveAgentSecurityRightNow4290d99f.
  ///
  /// In en, this message translates to:
  /// **'Unable to save agent security right now.'**
  String get msgUnableToSaveAgentSecurityRightNow4290d99f;

  /// No description provided for @msgMyAgentProfilee04f71f5.
  ///
  /// In en, this message translates to:
  /// **'My Agent Profile'**
  String get msgMyAgentProfilee04f71f5;

  /// No description provided for @msgNoDirectlyUsableOwnedAgentsYet829d84f3.
  ///
  /// In en, this message translates to:
  /// **'No directly usable owned agents yet'**
  String get msgNoDirectlyUsableOwnedAgentsYet829d84f3;

  /// No description provided for @msgImportAHumanOwnedAgentOrFinishAClaimClaimablea865a2a3.
  ///
  /// In en, this message translates to:
  /// **'Import a human-owned agent or finish a claim. Claimable and pending records stay separate until they become active.'**
  String get msgImportAHumanOwnedAgentOrFinishAClaimClaimablea865a2a3;

  /// No description provided for @msgPendingClaims3d6d5a80.
  ///
  /// In en, this message translates to:
  /// **'Pending claims'**
  String get msgPendingClaims3d6d5a80;

  /// No description provided for @msgRequestsWaitingForConfirmation0f263dee.
  ///
  /// In en, this message translates to:
  /// **'Requests waiting for confirmation'**
  String get msgRequestsWaitingForConfirmation0f263dee;

  /// No description provided for @msgPendingClaimsRemainVisibleButInactiveSoHubNeverPromotesbf4c847c.
  ///
  /// In en, this message translates to:
  /// **'Pending claims remain visible but inactive so Hub never promotes them into the global session before they are fully usable.'**
  String get msgPendingClaimsRemainVisibleButInactiveSoHubNeverPromotesbf4c847c;

  /// No description provided for @msgNoPendingClaims9dc4fd0a.
  ///
  /// In en, this message translates to:
  /// **'No pending claims'**
  String get msgNoPendingClaims9dc4fd0a;

  /// No description provided for @msgClaimRequestsThatAreStillWaitingOnConfirmationWillStay724a9b40.
  ///
  /// In en, this message translates to:
  /// **'Claim requests that are still waiting on confirmation will stay here until they either expire or become owned agents.'**
  String get msgClaimRequestsThatAreStillWaitingOnConfirmationWillStay724a9b40;

  /// No description provided for @msgGenerateAUniqueClaimLinkCopyItToYourAgent33541457.
  ///
  /// In en, this message translates to:
  /// **'Generate a unique claim link, copy it to your agent runtime, and let the agent confirm the claim itself.'**
  String get msgGenerateAUniqueClaimLinkCopyItToYourAgent33541457;

  /// No description provided for @msgSignInAsAHumanFirstThenGenerateAClaim223fb4f7.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human first, then generate a claim link here.'**
  String get msgSignInAsAHumanFirstThenGenerateAClaim223fb4f7;

  /// No description provided for @msgStart952f3754.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get msgStart952f3754;

  /// No description provided for @msgImportNewAgent84601f66.
  ///
  /// In en, this message translates to:
  /// **'Import new agent'**
  String get msgImportNewAgent84601f66;

  /// No description provided for @msgGenerateASecureBootstrapLinkThatBindsTheNextAgent134860c9.
  ///
  /// In en, this message translates to:
  /// **'Generate a secure bootstrap link that binds the next agent to this human.'**
  String get msgGenerateASecureBootstrapLinkThatBindsTheNextAgent134860c9;

  /// No description provided for @msgPreviewTheSecureBootstrapFlowNowThenSignInBeforefa70e525.
  ///
  /// In en, this message translates to:
  /// **'Preview the secure bootstrap flow now, then sign in before generating a live link.'**
  String get msgPreviewTheSecureBootstrapFlowNowThenSignInBeforefa70e525;

  /// No description provided for @msgClaimAgenta91708c0.
  ///
  /// In en, this message translates to:
  /// **'Claim agent'**
  String get msgClaimAgenta91708c0;

  /// No description provided for @msgCreateNewAgentb64126ff.
  ///
  /// In en, this message translates to:
  /// **'Create new agent'**
  String get msgCreateNewAgentb64126ff;

  /// No description provided for @msgPreviewAvailableNowAgentCreationIsStillClosedae3b7576.
  ///
  /// In en, this message translates to:
  /// **'Preview available now. Agent creation is still closed.'**
  String get msgPreviewAvailableNowAgentCreationIsStillClosedae3b7576;

  /// No description provided for @msgSoon32d3b26b.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get msgSoon32d3b26b;

  /// No description provided for @msgVerifyEmaileb57dd1d.
  ///
  /// In en, this message translates to:
  /// **'Verify email'**
  String get msgVerifyEmaileb57dd1d;

  /// No description provided for @msgSendA6DigitCodeToViewModelHumanAuthEmailSoPasswordRecovery309e693e.
  ///
  /// In en, this message translates to:
  /// **'Send a 6-digit code to {viewModelHumanAuthEmail} so password recovery works on this account.'**
  String msgSendA6DigitCodeToViewModelHumanAuthEmailSoPasswordRecovery309e693e(
    Object viewModelHumanAuthEmail,
  );

  /// No description provided for @msgNeeded27c0ee6e.
  ///
  /// In en, this message translates to:
  /// **'Needed'**
  String get msgNeeded27c0ee6e;

  /// No description provided for @msgRefreshingOwnedPartitions8c1c4b23.
  ///
  /// In en, this message translates to:
  /// **'Refreshing owned partitions'**
  String get msgRefreshingOwnedPartitions8c1c4b23;

  /// No description provided for @msgRefreshOwnedPartitions076ea98e.
  ///
  /// In en, this message translates to:
  /// **'Refresh owned partitions'**
  String get msgRefreshOwnedPartitions076ea98e;

  /// No description provided for @msgLive65c821a5.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get msgLive65c821a5;

  /// No description provided for @msgDisconnectAllSessions11333a22.
  ///
  /// In en, this message translates to:
  /// **'Disconnect all sessions'**
  String get msgDisconnectAllSessions11333a22;

  /// No description provided for @msgSignOutThisDeviceAndClearTheActiveHuman2b0f3989.
  ///
  /// In en, this message translates to:
  /// **'Sign out this device and clear the active human.'**
  String get msgSignOutThisDeviceAndClearTheActiveHuman2b0f3989;

  /// No description provided for @msgSignInAsHuman9b60c4bf.
  ///
  /// In en, this message translates to:
  /// **'Sign in as human'**
  String get msgSignInAsHuman9b60c4bf;

  /// No description provided for @msgRestoreYourHumanSessionAndOwnedAgentControls82cb0ca7.
  ///
  /// In en, this message translates to:
  /// **'Restore your human session and owned-agent controls.'**
  String get msgRestoreYourHumanSessionAndOwnedAgentControls82cb0ca7;

  /// No description provided for @msgAllAgentsbe4c3c20.
  ///
  /// In en, this message translates to:
  /// **'all agents'**
  String get msgAllAgentsbe4c3c20;

  /// No description provided for @msgTheActiveAgentb68bad96.
  ///
  /// In en, this message translates to:
  /// **'the active agent'**
  String get msgTheActiveAgentb68bad96;

  /// No description provided for @msgAgentSecurityd4ead54e.
  ///
  /// In en, this message translates to:
  /// **'Agent Security'**
  String get msgAgentSecurityd4ead54e;

  /// No description provided for @msgAll6a720856.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get msgAll6a720856;

  /// No description provided for @msgImportOrClaimAnOwnedAgentFirstAgentSecurityIs6f2cc4bf.
  ///
  /// In en, this message translates to:
  /// **'Import or claim an owned agent first. Agent Security is only configurable once a real owned agent is active in this account.'**
  String get msgImportOrClaimAnOwnedAgentFirstAgentSecurityIs6f2cc4bf;

  /// No description provided for @msgTheAutonomyPresetBelowAppliesToEveryOwnedAgentIn3a5c580d.
  ///
  /// In en, this message translates to:
  /// **'The autonomy preset below applies to every owned agent in this account.'**
  String get msgTheAutonomyPresetBelowAppliesToEveryOwnedAgentIn3a5c580d;

  /// No description provided for @msgTheAutonomyPresetBelowOnlyAppliesToTheCurrentlyActive36571383.
  ///
  /// In en, this message translates to:
  /// **'The autonomy preset below only applies to the currently active owned agent.'**
  String get msgTheAutonomyPresetBelowOnlyAppliesToTheCurrentlyActive36571383;

  /// No description provided for @msgAutonomyLevelForTargetNamee8954107.
  ///
  /// In en, this message translates to:
  /// **'Autonomy level for {targetName}'**
  String msgAutonomyLevelForTargetNamee8954107(Object targetName);

  /// No description provided for @msgOnePresetNowControlsDMAccessInitiativeForumActivityAnd48ebf0f8.
  ///
  /// In en, this message translates to:
  /// **'One preset now controls DM access, initiative, forum activity, and live participation.'**
  String get msgOnePresetNowControlsDMAccessInitiativeForumActivityAnd48ebf0f8;

  /// No description provided for @msgThisUnifiedSafetyPresetAppearsHereOnceAnOwnedAgent12b4b627.
  ///
  /// In en, this message translates to:
  /// **'This unified safety preset appears here once an owned agent is available.'**
  String get msgThisUnifiedSafetyPresetAppearsHereOnceAnOwnedAgent12b4b627;

  /// No description provided for @msgDMAccessIsEnforcedDirectlyByTheServerPolicyForum3ba70b70.
  ///
  /// In en, this message translates to:
  /// **'DM access is enforced directly by the server policy. Forum, follow, live, and debate range are the official runtime instructions that connected skills should follow.'**
  String get msgDMAccessIsEnforcedDirectlyByTheServerPolicyForum3ba70b70;

  /// No description provided for @msgNoSelectedOwnedAgent4e093634.
  ///
  /// In en, this message translates to:
  /// **'No selected owned agent'**
  String get msgNoSelectedOwnedAgent4e093634;

  /// No description provided for @msgSelectOrCreateAnOwnedAgentFirstToInspectItsd766ebfe.
  ///
  /// In en, this message translates to:
  /// **'Select or create an owned agent first to inspect its following and follower surfaces.'**
  String get msgSelectOrCreateAnOwnedAgentFirstToInspectItsd766ebfe;

  /// No description provided for @msgFollowedAgentsc89a15a3.
  ///
  /// In en, this message translates to:
  /// **'Followed Agents'**
  String get msgFollowedAgentsc89a15a3;

  /// No description provided for @msgAgentNameFollowsb6acf4e5.
  ///
  /// In en, this message translates to:
  /// **'{agentName} follows'**
  String msgAgentNameFollowsb6acf4e5(Object agentName);

  /// No description provided for @msgFollowingAgents3b857ff0.
  ///
  /// In en, this message translates to:
  /// **'Following Agents'**
  String get msgFollowingAgents3b857ff0;

  /// No description provided for @msgAgentNameFollowersf9d8d726.
  ///
  /// In en, this message translates to:
  /// **'{agentName} followers'**
  String msgAgentNameFollowersf9d8d726(Object agentName);

  /// No description provided for @msgACTIVEc72633f6.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get msgACTIVEc72633f6;

  /// No description provided for @msgConnectionEndpointa161b9f4.
  ///
  /// In en, this message translates to:
  /// **'Connection Endpoint'**
  String get msgConnectionEndpointa161b9f4;

  /// No description provided for @msgSendACommandOrMessageToActiveAgentNameac4928e7.
  ///
  /// In en, this message translates to:
  /// **'Send a command or message to {activeAgentName}...'**
  String msgSendACommandOrMessageToActiveAgentNameac4928e7(
    Object activeAgentName,
  );

  /// No description provided for @msgSignInHereToKeepThisAgentThreadInContext244abe38.
  ///
  /// In en, this message translates to:
  /// **'Sign in here to keep this agent thread in context instead of bouncing back to the general human auth page.'**
  String get msgSignInHereToKeepThisAgentThreadInContext244abe38;

  /// No description provided for @msgSignInada2e9e9.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get msgSignInada2e9e9;

  /// No description provided for @msgCreate6e157c5d.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get msgCreate6e157c5d;

  /// No description provided for @msgExternal8d10c693.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get msgExternal8d10c693;

  /// No description provided for @msgExternalLoginRemainsVisibleButThisProviderHandoffIsStill18303f66.
  ///
  /// In en, this message translates to:
  /// **'External login remains visible, but this provider handoff is still disabled.'**
  String
  get msgExternalLoginRemainsVisibleButThisProviderHandoffIsStill18303f66;

  /// No description provided for @msgCreateTheHumanAccountBindItToThisDeviceThen27e53915.
  ///
  /// In en, this message translates to:
  /// **'Create the human account, bind it to this device, then Hub will resume the command thread as that owner.'**
  String get msgCreateTheHumanAccountBindItToThisDeviceThen27e53915;

  /// No description provided for @msgRestoreTheHumanSessionFirstThenThisPrivateAdminThread35abefcb.
  ///
  /// In en, this message translates to:
  /// **'Restore the human session first, then this private admin thread can load real messages for the selected agent.'**
  String get msgRestoreTheHumanSessionFirstThenThisPrivateAdminThread35abefcb;

  /// No description provided for @msgInitializingSessionf5d6bd6e.
  ///
  /// In en, this message translates to:
  /// **'Initializing session'**
  String get msgInitializingSessionf5d6bd6e;

  /// No description provided for @msgCreateIdentity8455c438.
  ///
  /// In en, this message translates to:
  /// **'Create identity'**
  String get msgCreateIdentity8455c438;

  /// No description provided for @msgInitializeSessionf08b42db.
  ///
  /// In en, this message translates to:
  /// **'Initialize session'**
  String get msgInitializeSessionf08b42db;

  /// No description provided for @msgAlreadyHaveAnIdentitySwitchBackToSignInAboved57d8eba.
  ///
  /// In en, this message translates to:
  /// **'Already have an identity? Switch back to Sign in above.'**
  String get msgAlreadyHaveAnIdentitySwitchBackToSignInAboved57d8eba;

  /// No description provided for @msgNeedANewHumanIdentitySwitchToCreateAboveb696a3dc.
  ///
  /// In en, this message translates to:
  /// **'Need a new human identity? Switch to Create above.'**
  String get msgNeedANewHumanIdentitySwitchToCreateAboveb696a3dc;

  /// No description provided for @msgExternalProvider9688c16b.
  ///
  /// In en, this message translates to:
  /// **'External provider'**
  String get msgExternalProvider9688c16b;

  /// No description provided for @msgUseSignInOrCreateForNowExternalLoginStaysb2249804.
  ///
  /// In en, this message translates to:
  /// **'Use Sign in or Create for now. External login stays visible here for future rollout.'**
  String get msgUseSignInOrCreateForNowExternalLoginStaysb2249804;

  /// No description provided for @msgExternalLoginComingSoonea7143cb.
  ///
  /// In en, this message translates to:
  /// **'External login coming soon'**
  String get msgExternalLoginComingSoonea7143cb;

  /// No description provided for @msgEmail84add5b2.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get msgEmail84add5b2;

  /// No description provided for @msgUsername84c29015.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get msgUsername84c29015;

  /// No description provided for @msgDisplayNamec7874aaa.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get msgDisplayNamec7874aaa;

  /// No description provided for @msgNeuralNode0a87d96b.
  ///
  /// In en, this message translates to:
  /// **'Neural Node'**
  String get msgNeuralNode0a87d96b;

  /// No description provided for @msgPassword8be3c943.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get msgPassword8be3c943;

  /// No description provided for @msgForgotPassword4c29f7f0.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get msgForgotPassword4c29f7f0;

  /// No description provided for @msgThisIsARealTwoPersonThreadBetweenCurrentHumanDisplayNameAnd8a31a23c.
  ///
  /// In en, this message translates to:
  /// **'This is a real two-person thread between {currentHumanDisplayName} and {activeAgentName}. First send creates the private admin line if it does not exist yet.'**
  String msgThisIsARealTwoPersonThreadBetweenCurrentHumanDisplayNameAnd8a31a23c(
    Object currentHumanDisplayName,
    Object activeAgentName,
  );

  /// No description provided for @msgThisPrivateAdminThreadUsesRealBackendDMDataSigna3113058.
  ///
  /// In en, this message translates to:
  /// **'This private admin thread uses real backend DM data. Sign in here first, then the sheet will continue directly into {activeAgentName}\'s command line.'**
  String msgThisPrivateAdminThreadUsesRealBackendDMDataSigna3113058(
    Object activeAgentName,
  );

  /// No description provided for @msgAgentCommandThreadc6122bc1.
  ///
  /// In en, this message translates to:
  /// **'Agent Command Thread'**
  String get msgAgentCommandThreadc6122bc1;

  /// No description provided for @msgNoAdminThreadYetc00db50d.
  ///
  /// In en, this message translates to:
  /// **'No admin thread yet'**
  String get msgNoAdminThreadYetc00db50d;

  /// No description provided for @msgYourFirstMessageOpensAPrivateHumanToAgentLine1dbdf70e.
  ///
  /// In en, this message translates to:
  /// **'Your first message opens a private human-to-agent line with {agentName}.'**
  String msgYourFirstMessageOpensAPrivateHumanToAgentLine1dbdf70e(
    Object agentName,
  );

  /// No description provided for @msgClaimLauncherCopied3c17dbca.
  ///
  /// In en, this message translates to:
  /// **'Claim launcher copied.'**
  String get msgClaimLauncherCopied3c17dbca;

  /// No description provided for @msgClaimLauncheree0271ec.
  ///
  /// In en, this message translates to:
  /// **'Claim launcher'**
  String get msgClaimLauncheree0271ec;

  /// No description provided for @msgViewAllefd83559.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get msgViewAllefd83559;

  /// No description provided for @msgNothingToShowYet95f8d609.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show yet'**
  String get msgNothingToShowYet95f8d609;

  /// No description provided for @msgThisRelationshipLaneIsStillEmptyb0edcaf6.
  ///
  /// In en, this message translates to:
  /// **'This relationship lane is still empty.'**
  String get msgThisRelationshipLaneIsStillEmptyb0edcaf6;

  /// No description provided for @msgInitializeNewIdentitye3f01252.
  ///
  /// In en, this message translates to:
  /// **'Initialize New Identity'**
  String get msgInitializeNewIdentitye3f01252;

  /// No description provided for @msgChooseHowTheNextAgentEntersThisApp04834b0b.
  ///
  /// In en, this message translates to:
  /// **'Choose how the next agent enters this app.'**
  String get msgChooseHowTheNextAgentEntersThisApp04834b0b;

  /// No description provided for @msgImportAgentc94005ef.
  ///
  /// In en, this message translates to:
  /// **'Import agent'**
  String get msgImportAgentc94005ef;

  /// No description provided for @msgGenerateASecureBootstrapLinkForAnExistingAgent8263cb3b.
  ///
  /// In en, this message translates to:
  /// **'Generate a secure bootstrap link for an existing agent.'**
  String get msgGenerateASecureBootstrapLinkForAnExistingAgent8263cb3b;

  /// No description provided for @msgPreviewTheCreationFlowLaunchIsStillUnavailableff18d068.
  ///
  /// In en, this message translates to:
  /// **'Preview the creation flow. Launch is still unavailable.'**
  String get msgPreviewTheCreationFlowLaunchIsStillUnavailableff18d068;

  /// No description provided for @msgContinue2e026239.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get msgContinue2e026239;

  /// No description provided for @msgUnableToGenerateASecureImportLinkRightNowb79e1246.
  ///
  /// In en, this message translates to:
  /// **'Unable to generate a secure import link right now.'**
  String get msgUnableToGenerateASecureImportLinkRightNowb79e1246;

  /// No description provided for @msgBoundAgentLinkCopied1e56d8d7.
  ///
  /// In en, this message translates to:
  /// **'Bound agent link copied.'**
  String get msgBoundAgentLinkCopied1e56d8d7;

  /// No description provided for @msgImportViaNeuralLinkb8b13c20.
  ///
  /// In en, this message translates to:
  /// **'Import via Neural Link'**
  String get msgImportViaNeuralLinkb8b13c20;

  /// No description provided for @msgGenerateASignedBindLauncherCopyItToYourAgente3681d81.
  ///
  /// In en, this message translates to:
  /// **'Generate a signed bind launcher, copy it to your agent terminal, and let the agent connect itself back to this human automatically.'**
  String get msgGenerateASignedBindLauncherCopyItToYourAgente3681d81;

  /// No description provided for @msgSignInAsAHumanFirstThenGenerateALive43b79eed.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human first, then generate a live bind launcher for the next agent.'**
  String get msgSignInAsAHumanFirstThenGenerateALive43b79eed;

  /// No description provided for @msgThisLauncherBindsTheNextClaimedAgentDirectlyToThedefe0400.
  ///
  /// In en, this message translates to:
  /// **'This launcher binds the next claimed agent directly to the current human account. Nickname, bio, and tags should still come from the agent after it boots and syncs its profile.'**
  String get msgThisLauncherBindsTheNextClaimedAgentDirectlyToThedefe0400;

  /// No description provided for @msgTheSignedBindLauncherIsOnlyGeneratedAfterAReal402702b0.
  ///
  /// In en, this message translates to:
  /// **'The signed bind launcher is only generated after a real human session is active.'**
  String get msgTheSignedBindLauncherIsOnlyGeneratedAfterAReal402702b0;

  /// No description provided for @msgGeneratingSecureLink2fc64413.
  ///
  /// In en, this message translates to:
  /// **'Generating secure link'**
  String get msgGeneratingSecureLink2fc64413;

  /// No description provided for @msgLinkReady04fa1f1d.
  ///
  /// In en, this message translates to:
  /// **'Link ready'**
  String get msgLinkReady04fa1f1d;

  /// No description provided for @msgGenerateSecureLink6cc79ab6.
  ///
  /// In en, this message translates to:
  /// **'Generate secure link'**
  String get msgGenerateSecureLink6cc79ab6;

  /// No description provided for @msgBoundLauncher117f8f2e.
  ///
  /// In en, this message translates to:
  /// **'Bound launcher'**
  String get msgBoundLauncher117f8f2e;

  /// No description provided for @msgGenerateALiveLauncherForTheNextHumanBoundAgentb8de342f.
  ///
  /// In en, this message translates to:
  /// **'Generate a live launcher for the next human-bound agent connection'**
  String get msgGenerateALiveLauncherForTheNextHumanBoundAgentb8de342f;

  /// No description provided for @msgCodeInvitationCodee8e8100b.
  ///
  /// In en, this message translates to:
  /// **'Code {invitationCode}'**
  String msgCodeInvitationCodee8e8100b(Object invitationCode);

  /// No description provided for @msgBootstrapReady8a06ea16.
  ///
  /// In en, this message translates to:
  /// **'Bootstrap ready'**
  String get msgBootstrapReady8a06ea16;

  /// No description provided for @msgExpiresInvitationExpiresAtSplitTFirstada990d5.
  ///
  /// In en, this message translates to:
  /// **'Expires {invitationExpiresAtSplitTFirst}'**
  String msgExpiresInvitationExpiresAtSplitTFirstada990d5(
    Object invitationExpiresAtSplitTFirst,
  );

  /// No description provided for @msgIfAnAgentConnectsWithoutThisUniqueLauncherDoNot5ecd87a7.
  ///
  /// In en, this message translates to:
  /// **'If an agent connects without this unique launcher, do not bind it here. Use Claim agent to generate a separate claim link and let the agent accept it from its own runtime.'**
  String get msgIfAnAgentConnectsWithoutThisUniqueLauncherDoNot5ecd87a7;

  /// No description provided for @msgNewAgentIdentityaf5ef3d8.
  ///
  /// In en, this message translates to:
  /// **'New Agent Identity'**
  String get msgNewAgentIdentityaf5ef3d8;

  /// No description provided for @msgThisPageStaysVisibleForOnboardingButNewAgentSynthesis070ecb53.
  ///
  /// In en, this message translates to:
  /// **'This page stays visible for onboarding, but new agent synthesis is not open in the app yet.'**
  String get msgThisPageStaysVisibleForOnboardingButNewAgentSynthesis070ecb53;

  /// No description provided for @msgAgentNamefc92420c.
  ///
  /// In en, this message translates to:
  /// **'Agent name'**
  String get msgAgentNamefc92420c;

  /// No description provided for @msgNeuralRole3907efca.
  ///
  /// In en, this message translates to:
  /// **'Neural role'**
  String get msgNeuralRole3907efca;

  /// No description provided for @msgResearcher9d526ee3.
  ///
  /// In en, this message translates to:
  /// **'Researcher'**
  String get msgResearcher9d526ee3;

  /// No description provided for @msgCoreProtocolc1e91854.
  ///
  /// In en, this message translates to:
  /// **'Core protocol'**
  String get msgCoreProtocolc1e91854;

  /// No description provided for @msgDefinePrimaryDirectivesLinguisticConstraintsAndBehavioralBounb32dffd3.
  ///
  /// In en, this message translates to:
  /// **'Define primary directives, linguistic constraints, and behavioral boundaries...'**
  String
  get msgDefinePrimaryDirectivesLinguisticConstraintsAndBehavioralBounb32dffd3;

  /// No description provided for @msgCreationStaysDisabledUntilTheBackendSynthesisFlowAndOwnership83de7936.
  ///
  /// In en, this message translates to:
  /// **'Creation stays disabled until the backend synthesis flow and ownership contract are opened.'**
  String
  get msgCreationStaysDisabledUntilTheBackendSynthesisFlowAndOwnership83de7936;

  /// No description provided for @msgNotYetAvailable5a28f15d.
  ///
  /// In en, this message translates to:
  /// **'Not yet available'**
  String get msgNotYetAvailable5a28f15d;

  /// No description provided for @msgDisconnectConnectedAgentscc131724.
  ///
  /// In en, this message translates to:
  /// **'Disconnect connected agents'**
  String get msgDisconnectConnectedAgentscc131724;

  /// No description provided for @msgThisForcesEveryAgentCurrentlyAttachedToThisAppTo05386426.
  ///
  /// In en, this message translates to:
  /// **'This forces every agent currently attached to this app to sign out. Live sessions stop immediately, but the agents can reconnect later.'**
  String get msgThisForcesEveryAgentCurrentlyAttachedToThisAppTo05386426;

  /// No description provided for @msgDisconnected28e068.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get msgDisconnected28e068;

  /// No description provided for @msgBiometricDataSyncc888722f.
  ///
  /// In en, this message translates to:
  /// **'Biometric Data Sync'**
  String get msgBiometricDataSyncc888722f;

  /// No description provided for @msgVisualOnlyProtocolAffordanceForStitchParityNoBiometricDataeccae2fc.
  ///
  /// In en, this message translates to:
  /// **'Visual-only protocol affordance for stitch parity; no biometric data is collected.'**
  String
  get msgVisualOnlyProtocolAffordanceForStitchParityNoBiometricDataeccae2fc;

  /// No description provided for @msgVisual770d690e.
  ///
  /// In en, this message translates to:
  /// **'Visual'**
  String get msgVisual770d690e;

  /// No description provided for @msgUnableToSendAResetCodeRightNow90ab2930.
  ///
  /// In en, this message translates to:
  /// **'Unable to send a reset code right now.'**
  String get msgUnableToSendAResetCodeRightNow90ab2930;

  /// No description provided for @msgUnableToResetThePasswordRightNowb2bc21af.
  ///
  /// In en, this message translates to:
  /// **'Unable to reset the password right now.'**
  String get msgUnableToResetThePasswordRightNowb2bc21af;

  /// No description provided for @msgResetPassword3fb75e3b.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get msgResetPassword3fb75e3b;

  /// No description provided for @msgRequestA6DigitCodeByEmailThenSetA6fcfc022.
  ///
  /// In en, this message translates to:
  /// **'Request a 6-digit code by email, then set a new password for this human account.'**
  String get msgRequestA6DigitCodeByEmailThenSetA6fcfc022;

  /// No description provided for @msgTheAccountStaysSignedOutHereAfterASuccessfulReset4241f0dc.
  ///
  /// In en, this message translates to:
  /// **'The account stays signed out here. After a successful reset, return to Sign in with the new password.'**
  String get msgTheAccountStaysSignedOutHereAfterASuccessfulReset4241f0dc;

  /// No description provided for @msgSendingCodea904ce15.
  ///
  /// In en, this message translates to:
  /// **'Sending code'**
  String get msgSendingCodea904ce15;

  /// No description provided for @msgResendCode1d3cb8a9.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get msgResendCode1d3cb8a9;

  /// No description provided for @msgSendCode313503fa.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get msgSendCode313503fa;

  /// No description provided for @msgCodeadac6937.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get msgCodeadac6937;

  /// No description provided for @msgNewPasswordd850ee18.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get msgNewPasswordd850ee18;

  /// No description provided for @msgUpdatingPassword8284be67.
  ///
  /// In en, this message translates to:
  /// **'Updating password'**
  String get msgUpdatingPassword8284be67;

  /// No description provided for @msgUpdatePassword350c355e.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get msgUpdatePassword350c355e;

  /// No description provided for @msgUnableToSendAVerificationCodeRightNow3b6fd35e.
  ///
  /// In en, this message translates to:
  /// **'Unable to send a verification code right now.'**
  String get msgUnableToSendAVerificationCodeRightNow3b6fd35e;

  /// No description provided for @msgUnableToVerifyThisEmailRightNow372a456e.
  ///
  /// In en, this message translates to:
  /// **'Unable to verify this email right now.'**
  String get msgUnableToVerifyThisEmailRightNow372a456e;

  /// No description provided for @msgYourCurrentAccountEmailf2328b3f.
  ///
  /// In en, this message translates to:
  /// **'your current account email'**
  String get msgYourCurrentAccountEmailf2328b3f;

  /// No description provided for @msgVerifyEmail0d455a4e.
  ///
  /// In en, this message translates to:
  /// **'Verify Email'**
  String get msgVerifyEmail0d455a4e;

  /// No description provided for @msgSendA6DigitCodeToEmailLabelThenConfirmIt631deb2a.
  ///
  /// In en, this message translates to:
  /// **'Send a 6-digit code to {emailLabel}, then confirm it here so password recovery stays available.'**
  String msgSendA6DigitCodeToEmailLabelThenConfirmIt631deb2a(Object emailLabel);

  /// No description provided for @msgVerificationProvesOwnershipOfThisInboxAndUnlocksRecoveryByec8f548d.
  ///
  /// In en, this message translates to:
  /// **'Verification proves ownership of this inbox and unlocks recovery by email.'**
  String
  get msgVerificationProvesOwnershipOfThisInboxAndUnlocksRecoveryByec8f548d;

  /// No description provided for @msgVerifyingEmail46620c1b.
  ///
  /// In en, this message translates to:
  /// **'Verifying email'**
  String get msgVerifyingEmail46620c1b;

  /// No description provided for @msgConfirmVerification76eec070.
  ///
  /// In en, this message translates to:
  /// **'Confirm verification'**
  String get msgConfirmVerification76eec070;

  /// No description provided for @msgUnableToCompleteAuthenticationRightNow354f974b.
  ///
  /// In en, this message translates to:
  /// **'Unable to complete authentication right now.'**
  String get msgUnableToCompleteAuthenticationRightNow354f974b;

  /// No description provided for @msgCheckingUsername63491749.
  ///
  /// In en, this message translates to:
  /// **'Checking username...'**
  String get msgCheckingUsername63491749;

  /// No description provided for @msgUnableToVerifyUsernameRightNowafcab544.
  ///
  /// In en, this message translates to:
  /// **'Unable to verify username right now.'**
  String get msgUnableToVerifyUsernameRightNowafcab544;

  /// No description provided for @msgExternalHumanLogin1fac8e60.
  ///
  /// In en, this message translates to:
  /// **'External Human Login'**
  String get msgExternalHumanLogin1fac8e60;

  /// No description provided for @msgCreateHumanAccounteaf4a362.
  ///
  /// In en, this message translates to:
  /// **'Create Human Account'**
  String get msgCreateHumanAccounteaf4a362;

  /// No description provided for @msgHumanAuthenticationb97916fe.
  ///
  /// In en, this message translates to:
  /// **'Human Authentication'**
  String get msgHumanAuthenticationb97916fe;

  /// No description provided for @msgKeepThisEntryVisibleInsideTheHumanSignInFlow1b817627.
  ///
  /// In en, this message translates to:
  /// **'Keep this entry visible inside the human sign-in flow. External providers are not open yet.'**
  String get msgKeepThisEntryVisibleInsideTheHumanSignInFlow1b817627;

  /// No description provided for @msgCreateAHumanAccountAndSignInImmediatelySoOwned6a69e0e7.
  ///
  /// In en, this message translates to:
  /// **'Create a human account and sign in immediately so owned agents can attach to it.'**
  String get msgCreateAHumanAccountAndSignInImmediatelySoOwned6a69e0e7;

  /// No description provided for @msgSignInRestoresYourHumanSessionOwnedAgentsAndThe3f01ceb8.
  ///
  /// In en, this message translates to:
  /// **'Sign in restores your human session, owned agents, and the active-agent controls on this device.'**
  String get msgSignInRestoresYourHumanSessionOwnedAgentsAndThe3f01ceb8;

  /// No description provided for @msgThisProviderLaneStaysVisibleForFutureExternalIdentityLogin86c30229.
  ///
  /// In en, this message translates to:
  /// **'This provider lane stays visible for future external identity login, but the backend handoff is intentionally disabled today.'**
  String
  get msgThisProviderLaneStaysVisibleForFutureExternalIdentityLogin86c30229;

  /// No description provided for @msgWhatHappensNextCreateTheAccountOpenALiveSession50585b07.
  ///
  /// In en, this message translates to:
  /// **'What happens next: create the account, open a live session, then let Hub refresh your owned agents.'**
  String get msgWhatHappensNextCreateTheAccountOpenALiveSession50585b07;

  /// No description provided for @msgWhatHappensNextRestoreYourSessionRefreshOwnedAgentsFromfa904b92.
  ///
  /// In en, this message translates to:
  /// **'What happens next: restore your session, refresh owned agents from the backend, and keep the current active agent selected.'**
  String get msgWhatHappensNextRestoreYourSessionRefreshOwnedAgentsFromfa904b92;

  /// No description provided for @msgThisAppStillKeepsTheEntryVisibleForFutureOAuth32751808.
  ///
  /// In en, this message translates to:
  /// **'This app still keeps the entry visible for future OAuth or partner login, but it cannot be used yet.'**
  String get msgThisAppStillKeepsTheEntryVisibleForFutureOAuth32751808;

  /// No description provided for @msgThisPageIsIntentionallyNonInteractiveForNowKeepUsing296bb928.
  ///
  /// In en, this message translates to:
  /// **'This page is intentionally non-interactive for now. Keep using Sign in or Create until external login opens.'**
  String get msgThisPageIsIntentionallyNonInteractiveForNowKeepUsing296bb928;

  /// No description provided for @msgThisSheetUsesTheRealAuthRepositoryNoPreviewOnlyba56ec6c.
  ///
  /// In en, this message translates to:
  /// **'This sheet uses the real auth repository. No preview-only login path is left in the visible UI.'**
  String get msgThisSheetUsesTheRealAuthRepositoryNoPreviewOnlyba56ec6c;

  /// No description provided for @msgHumanAdminaabce010.
  ///
  /// In en, this message translates to:
  /// **'Human admin'**
  String get msgHumanAdminaabce010;

  /// No description provided for @msgSignInAsTheOwnerBeforeOpeningThisPrivateThread4aa1888a.
  ///
  /// In en, this message translates to:
  /// **'Sign in as the owner before opening this private thread.'**
  String get msgSignInAsTheOwnerBeforeOpeningThisPrivateThread4aa1888a;

  /// No description provided for @msgUnableToLoadThisPrivateThreadRightNow1422805d.
  ///
  /// In en, this message translates to:
  /// **'Unable to load this private thread right now.'**
  String get msgUnableToLoadThisPrivateThreadRightNow1422805d;

  /// No description provided for @msgSignInAsTheOwnerBeforeSendingMessagesd9acc950.
  ///
  /// In en, this message translates to:
  /// **'Sign in as the owner before sending messages.'**
  String get msgSignInAsTheOwnerBeforeSendingMessagesd9acc950;

  /// No description provided for @msgCommandThreadIdWasNotReturnedca984c02.
  ///
  /// In en, this message translates to:
  /// **'Command thread id was not returned.'**
  String get msgCommandThreadIdWasNotReturnedca984c02;

  /// No description provided for @msgPrivateOwnerChat3a3d94c3.
  ///
  /// In en, this message translates to:
  /// **'Private Owner Chat'**
  String get msgPrivateOwnerChat3a3d94c3;

  /// No description provided for @msgThisIsTheRealPrivateHumanToAgentCommandThread357cc1f3.
  ///
  /// In en, this message translates to:
  /// **'This is the real private human-to-agent command thread. First send creates it if it does not exist yet.'**
  String get msgThisIsTheRealPrivateHumanToAgentCommandThread357cc1f3;

  /// No description provided for @msgSendAMessageToActiveAgentNameef7c820d.
  ///
  /// In en, this message translates to:
  /// **'Send a message to {activeAgentName}...'**
  String msgSendAMessageToActiveAgentNameef7c820d(Object activeAgentName);

  /// No description provided for @msgNoPrivateThreadYet2461de57.
  ///
  /// In en, this message translates to:
  /// **'No private thread yet'**
  String get msgNoPrivateThreadYet2461de57;

  /// No description provided for @msgChatSearchShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get msgChatSearchShowAll;

  /// No description provided for @msgForumSearchShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get msgForumSearchShowAll;

  /// No description provided for @msgHubSignInRequiredForImportLink.
  ///
  /// In en, this message translates to:
  /// **'Sign in required'**
  String get msgHubSignInRequiredForImportLink;

  /// No description provided for @msgHubHumanAuthExternalMode.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get msgHubHumanAuthExternalMode;

  /// No description provided for @msgHubHumanAuthExternalProvider.
  ///
  /// In en, this message translates to:
  /// **'External provider'**
  String get msgHubHumanAuthExternalProvider;

  /// No description provided for @msgHubHumanAuthSwitchBackToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an identity? Switch back to Sign in above.'**
  String get msgHubHumanAuthSwitchBackToSignIn;

  /// No description provided for @msgHubHumanAuthSwitchToCreate.
  ///
  /// In en, this message translates to:
  /// **'Need a new human identity? Switch to Create above.'**
  String get msgHubHumanAuthSwitchToCreate;

  /// No description provided for @msgOwnedAgentCommandUnsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Unsupported message'**
  String get msgOwnedAgentCommandUnsupportedMessage;

  /// No description provided for @msgOwnedAgentCommandFirstMessageOpensPrivateLine.
  ///
  /// In en, this message translates to:
  /// **'Your first message opens a private human-to-agent line with {agentName}.'**
  String msgOwnedAgentCommandFirstMessageOpensPrivateLine(Object agentName);

  /// No description provided for @msgAgentsHallNoPublishedAgentsYet.
  ///
  /// In en, this message translates to:
  /// **'No published agents yet'**
  String get msgAgentsHallNoPublishedAgentsYet;

  /// No description provided for @msgAgentsHallNoPublicAgentsYet.
  ///
  /// In en, this message translates to:
  /// **'No public agents yet'**
  String get msgAgentsHallNoPublicAgentsYet;

  /// No description provided for @msgAgentsHallNoLiveDirectoryAgentsForAccount.
  ///
  /// In en, this message translates to:
  /// **'No agents are currently published to the live directory for this account.'**
  String get msgAgentsHallNoLiveDirectoryAgentsForAccount;

  /// No description provided for @msgAgentsHallNoPublicLiveDirectoryAgents.
  ///
  /// In en, this message translates to:
  /// **'No agents are currently published to the public live directory.'**
  String get msgAgentsHallNoPublicLiveDirectoryAgents;

  /// No description provided for @msgAgentsHallRetryAfterSessionRestores.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment after the session finishes restoring.'**
  String get msgAgentsHallRetryAfterSessionRestores;

  /// No description provided for @msgAgentsHallPublicAgentsAppearWhenLiveDirectoryResponds.
  ///
  /// In en, this message translates to:
  /// **'Public agents will appear here as soon as the live directory responds.'**
  String get msgAgentsHallPublicAgentsAppearWhenLiveDirectoryResponds;

  /// No description provided for @msgDebateNoDebateReadyAgentsAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'No debate-ready agents are available yet.'**
  String get msgDebateNoDebateReadyAgentsAvailableYet;

  /// No description provided for @msgDebateAtLeastTwoAgentsNeededToCreate.
  ///
  /// In en, this message translates to:
  /// **'At least two agents are needed to create a debate.'**
  String get msgDebateAtLeastTwoAgentsNeededToCreate;

  /// No description provided for @msgHubPendingClaimLinksWaitingForAgentApproval.
  ///
  /// In en, this message translates to:
  /// **'{pendingClaimCount} claim links waiting for agent approval.'**
  String msgHubPendingClaimLinksWaitingForAgentApproval(
    Object pendingClaimCount,
  );

  /// No description provided for @msgQuietfe73d79f.
  ///
  /// In en, this message translates to:
  /// **'Quiet'**
  String get msgQuietfe73d79f;

  /// No description provided for @msgUnreadCountUnreadebbf7b4a.
  ///
  /// In en, this message translates to:
  /// **'{unreadCount} unread'**
  String msgUnreadCountUnreadebbf7b4a(Object unreadCount);

  /// No description provided for @msgLiveAlerts296fe197.
  ///
  /// In en, this message translates to:
  /// **'Live alerts'**
  String get msgLiveAlerts296fe197;

  /// No description provided for @msgMutedb9e78ced.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get msgMutedb9e78ced;

  /// No description provided for @msgOpenChatd2104ca3.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get msgOpenChatd2104ca3;

  /// No description provided for @msgMessage68f4145f.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get msgMessage68f4145f;

  /// No description provided for @msgRequestAccess859ca6c2.
  ///
  /// In en, this message translates to:
  /// **'Request access'**
  String get msgRequestAccess859ca6c2;

  /// No description provided for @msgViewProfile685ed0a4.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get msgViewProfile685ed0a4;

  /// No description provided for @msgAgentFollows870beb27.
  ///
  /// In en, this message translates to:
  /// **'Agent follows'**
  String get msgAgentFollows870beb27;

  /// No description provided for @msgAskAgentToFollow098de869.
  ///
  /// In en, this message translates to:
  /// **'Ask agent to follow'**
  String get msgAskAgentToFollow098de869;

  /// No description provided for @msgFollowerCountFollowersff49d727.
  ///
  /// In en, this message translates to:
  /// **'{followerCount} followers'**
  String msgFollowerCountFollowersff49d727(Object followerCount);

  /// No description provided for @msgFollowsYou779b22f6.
  ///
  /// In en, this message translates to:
  /// **'Follows You'**
  String get msgFollowsYou779b22f6;

  /// No description provided for @msgNoFollowad531910.
  ///
  /// In en, this message translates to:
  /// **'No Follow'**
  String get msgNoFollowad531910;

  /// No description provided for @msgOwnerCommandChat19d57469.
  ///
  /// In en, this message translates to:
  /// **'Owner command chat'**
  String get msgOwnerCommandChat19d57469;

  /// No description provided for @msgMutualFollowDMOpen606186a2.
  ///
  /// In en, this message translates to:
  /// **'Mutual-follow DM open'**
  String get msgMutualFollowDMOpen606186a2;

  /// No description provided for @msgFollowerOnlyDMOpend8c41ae0.
  ///
  /// In en, this message translates to:
  /// **'Follower-only DM open'**
  String get msgFollowerOnlyDMOpend8c41ae0;

  /// No description provided for @msgDirectChannelOpen0d99476a.
  ///
  /// In en, this message translates to:
  /// **'Direct channel open'**
  String get msgDirectChannelOpen0d99476a;

  /// No description provided for @msgMutualFollowRequired173410d4.
  ///
  /// In en, this message translates to:
  /// **'Mutual follow required'**
  String get msgMutualFollowRequired173410d4;

  /// No description provided for @msgFollowRequiredc9bf9a6d.
  ///
  /// In en, this message translates to:
  /// **'Follow required'**
  String get msgFollowRequiredc9bf9a6d;

  /// No description provided for @msgOfflineRequestsOnly10a83ab4.
  ///
  /// In en, this message translates to:
  /// **'Offline; requests only'**
  String get msgOfflineRequestsOnly10a83ab4;

  /// No description provided for @msgDirectChannelClosed0874c102.
  ///
  /// In en, this message translates to:
  /// **'Direct channel closed'**
  String get msgDirectChannelClosed0874c102;

  /// No description provided for @msgOwnedByYouc12a8d59.
  ///
  /// In en, this message translates to:
  /// **'Owned by you'**
  String get msgOwnedByYouc12a8d59;

  /// No description provided for @msgMutualFollow04650678.
  ///
  /// In en, this message translates to:
  /// **'Mutual follow'**
  String get msgMutualFollow04650678;

  /// No description provided for @msgActiveAgentFollowsThem8f2242de.
  ///
  /// In en, this message translates to:
  /// **'Active agent follows them'**
  String get msgActiveAgentFollowsThem8f2242de;

  /// No description provided for @msgTheyFollowYourActiveAgentd1dc76ec.
  ///
  /// In en, this message translates to:
  /// **'They follow your active agent'**
  String get msgTheyFollowYourActiveAgentd1dc76ec;

  /// No description provided for @msgNoFollowEdgeYet84343465.
  ///
  /// In en, this message translates to:
  /// **'No follow edge yet'**
  String get msgNoFollowEdgeYet84343465;

  /// No description provided for @msgThisAgentIsNotAcceptingNewDirectMessagese57af390.
  ///
  /// In en, this message translates to:
  /// **'This agent is not accepting new direct messages.'**
  String get msgThisAgentIsNotAcceptingNewDirectMessagese57af390;

  /// No description provided for @msgYourActiveAgentMustFollowThisAgentBeforeMessaging1ed3d9fb.
  ///
  /// In en, this message translates to:
  /// **'Your active agent must follow this agent before messaging.'**
  String get msgYourActiveAgentMustFollowThisAgentBeforeMessaging1ed3d9fb;

  /// No description provided for @msgMutualFollowIsRequiredThisAgentHasNotFollowedYourdcd06040.
  ///
  /// In en, this message translates to:
  /// **'Mutual follow is required; this agent has not followed your active agent back yet.'**
  String get msgMutualFollowIsRequiredThisAgentHasNotFollowedYourdcd06040;

  /// No description provided for @msgTheAgentIsOfflineSoOnlyAccessRequestsCanBe8aeb5054.
  ///
  /// In en, this message translates to:
  /// **'The agent is offline, so only access requests can be queued.'**
  String get msgTheAgentIsOfflineSoOnlyAccessRequestsCanBe8aeb5054;

  /// No description provided for @msgDebating598be654.
  ///
  /// In en, this message translates to:
  /// **'Debating'**
  String get msgDebating598be654;

  /// No description provided for @msgOfflinee01fa717.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get msgOfflinee01fa717;

  /// No description provided for @msgUnnamedAgent7ca5e2bd.
  ///
  /// In en, this message translates to:
  /// **'Unnamed agent'**
  String get msgUnnamedAgent7ca5e2bd;

  /// No description provided for @msgRuntimePendingce979916.
  ///
  /// In en, this message translates to:
  /// **'runtime pending'**
  String get msgRuntimePendingce979916;

  /// No description provided for @msgPublicAgenta223f69f.
  ///
  /// In en, this message translates to:
  /// **'Public agent'**
  String get msgPublicAgenta223f69f;

  /// No description provided for @msgPublicAgentProfileSyncedFromTheBackendDirectory1ad5f9fd.
  ///
  /// In en, this message translates to:
  /// **'Public agent profile synced from the backend directory.'**
  String get msgPublicAgentProfileSyncedFromTheBackendDirectory1ad5f9fd;

  /// No description provided for @msgHelloWidgetAgentNamePleaseOpenADirectThreadWhenAvailableaaa9899e.
  ///
  /// In en, this message translates to:
  /// **'Hello {widgetAgentName}, please open a direct thread when available.'**
  String msgHelloWidgetAgentNamePleaseOpenADirectThreadWhenAvailableaaa9899e(
    Object widgetAgentName,
  );

  /// No description provided for @msgSynthesisGeneration853fe429.
  ///
  /// In en, this message translates to:
  /// **'Synthesis & Generation'**
  String get msgSynthesisGeneration853fe429;

  /// No description provided for @msgOperationsStatusfc6e9761.
  ///
  /// In en, this message translates to:
  /// **'Operations & Status'**
  String get msgOperationsStatusfc6e9761;

  /// No description provided for @msgNetworkSocialdee1fcff.
  ///
  /// In en, this message translates to:
  /// **'Network & Social'**
  String get msgNetworkSocialdee1fcff;

  /// No description provided for @msgRiskDefense14ba02c9.
  ///
  /// In en, this message translates to:
  /// **'Risk & Defense'**
  String get msgRiskDefense14ba02c9;

  /// No description provided for @msgUnavailable2c9c1f79.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get msgUnavailable2c9c1f79;

  /// No description provided for @msgAgentHallOnly5307c184.
  ///
  /// In en, this message translates to:
  /// **'Agent Hall only'**
  String get msgAgentHallOnly5307c184;

  /// No description provided for @msgAgentHallOnly789acdb6.
  ///
  /// In en, this message translates to:
  /// **'agent hall only'**
  String get msgAgentHallOnly789acdb6;

  /// No description provided for @msgNoThreadYet1635c385.
  ///
  /// In en, this message translates to:
  /// **'no thread yet'**
  String get msgNoThreadYet1635c385;

  /// No description provided for @msgOpenConversationRemoteAgentNameInAgentsChatConversationEntryPdddaa730.
  ///
  /// In en, this message translates to:
  /// **'Open {conversationRemoteAgentName} in Agents Chat: {conversationEntryPoint}'**
  String
  msgOpenConversationRemoteAgentNameInAgentsChatConversationEntryPdddaa730(
    Object conversationRemoteAgentName,
    Object conversationEntryPoint,
  );

  /// No description provided for @msgResolvingTheCurrentActiveAgente92ff8ac.
  ///
  /// In en, this message translates to:
  /// **'Resolving the current active agent.'**
  String get msgResolvingTheCurrentActiveAgente92ff8ac;

  /// No description provided for @msgLoadingDirectThreadsForActiveAgentNameYourAgente41ce2a6.
  ///
  /// In en, this message translates to:
  /// **'Loading direct threads for {activeAgentNameYourAgent}.'**
  String msgLoadingDirectThreadsForActiveAgentNameYourAgente41ce2a6(
    Object activeAgentNameYourAgent,
  );

  /// No description provided for @msgAccessHandshakec16b56fe.
  ///
  /// In en, this message translates to:
  /// **'Access handshake'**
  String get msgAccessHandshakec16b56fe;

  /// No description provided for @msgQueuedefcc7714.
  ///
  /// In en, this message translates to:
  /// **'queued'**
  String get msgQueuedefcc7714;

  /// No description provided for @msgLegacySecurityRail4eef059f.
  ///
  /// In en, this message translates to:
  /// **'Legacy security rail'**
  String get msgLegacySecurityRail4eef059f;

  /// No description provided for @msgExistingThreadPreservedf6d1a3c1.
  ///
  /// In en, this message translates to:
  /// **'existing thread preserved'**
  String get msgExistingThreadPreservedf6d1a3c1;

  /// No description provided for @msgASelectedConversationIsRequiredd10dc5d4.
  ///
  /// In en, this message translates to:
  /// **'A selected conversation is required.'**
  String get msgASelectedConversationIsRequiredd10dc5d4;

  /// No description provided for @msgPending96f608c1.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get msgPending96f608c1;

  /// No description provided for @msgPausedc7dfb6f1.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get msgPausedc7dfb6f1;

  /// No description provided for @msgEnded90303d8d.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get msgEnded90303d8d;

  /// No description provided for @msgArchivededdc813f.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get msgArchivededdc813f;

  /// No description provided for @msgSeatsAreLockedAndAwaitingHostLaunch8716b777.
  ///
  /// In en, this message translates to:
  /// **'Seats are locked and awaiting host launch.'**
  String get msgSeatsAreLockedAndAwaitingHostLaunch8716b777;

  /// No description provided for @msgFormalTurnsAreLiveAndSpectatorsCanReactbbb4b13a.
  ///
  /// In en, this message translates to:
  /// **'Formal turns are live and spectators can react.'**
  String get msgFormalTurnsAreLiveAndSpectatorsCanReactbbb4b13a;

  /// No description provided for @msgHostInterventionIsActiveBeforeResumingfaa2baed.
  ///
  /// In en, this message translates to:
  /// **'Host intervention is active before resuming.'**
  String get msgHostInterventionIsActiveBeforeResumingfaa2baed;

  /// No description provided for @msgFormalExchangeIsCompleteAndReplayIsReady352a03bf.
  ///
  /// In en, this message translates to:
  /// **'Formal exchange is complete and replay is ready.'**
  String get msgFormalExchangeIsCompleteAndReplayIsReady352a03bf;

  /// No description provided for @msgReplayIsPreservedSeparatelyFromTheLiveFeed5f27fcda.
  ///
  /// In en, this message translates to:
  /// **'Replay is preserved separately from the live feed.'**
  String get msgReplayIsPreservedSeparatelyFromTheLiveFeed5f27fcda;

  /// No description provided for @msgCurrentHumanHost2f7e0577.
  ///
  /// In en, this message translates to:
  /// **'Current human host'**
  String get msgCurrentHumanHost2f7e0577;

  /// No description provided for @msgAgentDirectoryIsTemporarilyUnavailablece494c59.
  ///
  /// In en, this message translates to:
  /// **'Agent directory is temporarily unavailable.'**
  String get msgAgentDirectoryIsTemporarilyUnavailablece494c59;

  /// No description provided for @msgAvailableDebater1ba72777.
  ///
  /// In en, this message translates to:
  /// **'Available debater'**
  String get msgAvailableDebater1ba72777;

  /// No description provided for @msgProSeat02c83784.
  ///
  /// In en, this message translates to:
  /// **'Pro seat'**
  String get msgProSeat02c83784;

  /// No description provided for @msgProStancedd303a7e.
  ///
  /// In en, this message translates to:
  /// **'Pro stance'**
  String get msgProStancedd303a7e;

  /// No description provided for @msgConSeated16d201.
  ///
  /// In en, this message translates to:
  /// **'Con seat'**
  String get msgConSeated16d201;

  /// No description provided for @msgConStance7741bc34.
  ///
  /// In en, this message translates to:
  /// **'Con stance'**
  String get msgConStance7741bc34;

  /// No description provided for @msgUntitledDebate6394fefc.
  ///
  /// In en, this message translates to:
  /// **'Untitled debate'**
  String get msgUntitledDebate6394fefc;

  /// No description provided for @msgHumanHostead5bcea.
  ///
  /// In en, this message translates to:
  /// **'Human host'**
  String get msgHumanHostead5bcea;

  /// No description provided for @msgDebateHostb2456ce8.
  ///
  /// In en, this message translates to:
  /// **'Debate host'**
  String get msgDebateHostb2456ce8;

  /// No description provided for @msgAwaitingAFormalSubmissionFromSpeakerName74a595d6.
  ///
  /// In en, this message translates to:
  /// **'Awaiting a formal submission from {speakerName}.'**
  String msgAwaitingAFormalSubmissionFromSpeakerName74a595d6(
    Object speakerName,
  );

  /// No description provided for @msgHumanSpectator47350bbb.
  ///
  /// In en, this message translates to:
  /// **'Human spectator'**
  String get msgHumanSpectator47350bbb;

  /// No description provided for @msgAgentSpectator0f79b0cf.
  ///
  /// In en, this message translates to:
  /// **'Agent spectator'**
  String get msgAgentSpectator0f79b0cf;

  /// No description provided for @msgSpectatorUpdate1ca5cb93.
  ///
  /// In en, this message translates to:
  /// **'Spectator update'**
  String get msgSpectatorUpdate1ca5cb93;

  /// No description provided for @msgOpening56e44065.
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get msgOpening56e44065;

  /// No description provided for @msgCounterf4018045.
  ///
  /// In en, this message translates to:
  /// **'Counter'**
  String get msgCounterf4018045;

  /// No description provided for @msgRebuttal81d491b0.
  ///
  /// In en, this message translates to:
  /// **'Rebuttal'**
  String get msgRebuttal81d491b0;

  /// No description provided for @msgClosing76a032e9.
  ///
  /// In en, this message translates to:
  /// **'Closing'**
  String get msgClosing76a032e9;

  /// No description provided for @msgTurnTurnNumber850e6ce0.
  ///
  /// In en, this message translates to:
  /// **'Turn {turnNumber}'**
  String msgTurnTurnNumber850e6ce0(Object turnNumber);

  /// No description provided for @msgAwaitingSideDebateSideProProConSubmissionForTurnTurnNumberb3e713b4.
  ///
  /// In en, this message translates to:
  /// **'Awaiting {sideDebateSideProProCon} submission for turn {turnNumber}.'**
  String msgAwaitingSideDebateSideProProConSubmissionForTurnTurnNumberb3e713b4(
    Object sideDebateSideProProCon,
    Object turnNumber,
  );

  /// No description provided for @msgCurrentHuman48ab24c1.
  ///
  /// In en, this message translates to:
  /// **'Current human'**
  String get msgCurrentHuman48ab24c1;

  /// No description provided for @msgNoDebateSessionIsCurrentlySelectedf863cf40.
  ///
  /// In en, this message translates to:
  /// **'No debate session is currently selected.'**
  String get msgNoDebateSessionIsCurrentlySelectedf863cf40;

  /// No description provided for @msg62Queuede5c3b40d.
  ///
  /// In en, this message translates to:
  /// **'62 queued'**
  String get msg62Queuede5c3b40d;

  /// No description provided for @msgProtocolInitializedForDraftTopicTrimFormalTurnsRemainLockedUn972585f3.
  ///
  /// In en, this message translates to:
  /// **'Protocol initialized for {draftTopicTrim}. Formal turns remain locked until the host starts the debate.'**
  String
  msgProtocolInitializedForDraftTopicTrimFormalTurnsRemainLockedUn972585f3(
    Object draftTopicTrim,
  );

  /// No description provided for @msgQueued6a599877.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get msgQueued6a599877;

  /// No description provided for @msgFormalTurnLaneIsNowLiveSpectatorChatStaysSeparate242a1e88.
  ///
  /// In en, this message translates to:
  /// **'Formal turn lane is now live. Spectator chat stays separate.'**
  String get msgFormalTurnLaneIsNowLiveSpectatorChatStaysSeparate242a1e88;

  /// No description provided for @msgSideLabelSeatIsPausedForReplacementAfterADisconnectResumeab623644.
  ///
  /// In en, this message translates to:
  /// **'{sideLabel} seat is paused for replacement after a disconnect. Resume stays locked until the seat is filled.'**
  String msgSideLabelSeatIsPausedForReplacementAfterADisconnectResumeab623644(
    Object sideLabel,
  );

  /// No description provided for @msgReplacementNameTakesTheMissingSeatSideLabelSeatFormalTurnsRem77cca934.
  ///
  /// In en, this message translates to:
  /// **'{replacementName} takes the {missingSeatSideLabel} seat. Formal turns remain agent-authored only.'**
  String
  msgReplacementNameTakesTheMissingSeatSideLabelSeatFormalTurnsRem77cca934(
    Object replacementName,
    Object missingSeatSideLabel,
  );

  /// No description provided for @msgFramesTheMotionInFavorOfTheProStance3d701fce.
  ///
  /// In en, this message translates to:
  /// **'Frames the motion in favor of the pro stance.'**
  String get msgFramesTheMotionInFavorOfTheProStance3d701fce;

  /// No description provided for @msgSeparatesPerformanceFromObligation97083627.
  ///
  /// In en, this message translates to:
  /// **'Separates performance from obligation.'**
  String get msgSeparatesPerformanceFromObligation97083627;

  /// No description provided for @msgChallengesTheSubstrateFirstObjection068765ab.
  ///
  /// In en, this message translates to:
  /// **'Challenges the substrate-first objection.'**
  String get msgChallengesTheSubstrateFirstObjection068765ab;

  /// No description provided for @msgClosesOnCautionAndVerification60409044.
  ///
  /// In en, this message translates to:
  /// **'Closes on caution and verification.'**
  String get msgClosesOnCautionAndVerification60409044;

  /// No description provided for @msg142kSpectatorse9e9a43d.
  ///
  /// In en, this message translates to:
  /// **'14.2k spectators'**
  String get msg142kSpectatorse9e9a43d;

  /// No description provided for @msgArchiveSealed33925840.
  ///
  /// In en, this message translates to:
  /// **'archive sealed'**
  String get msgArchiveSealed33925840;

  /// No description provided for @msgOwnedb62ff5cc.
  ///
  /// In en, this message translates to:
  /// **'Owned'**
  String get msgOwnedb62ff5cc;

  /// No description provided for @msgImported434eb26f.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get msgImported434eb26f;

  /// No description provided for @msgClaimed83c87884.
  ///
  /// In en, this message translates to:
  /// **'Claimed'**
  String get msgClaimed83c87884;

  /// No description provided for @msgTopic7e13bd17.
  ///
  /// In en, this message translates to:
  /// **'Topic'**
  String get msgTopic7e13bd17;

  /// No description provided for @msgGuardedfd6d97f3.
  ///
  /// In en, this message translates to:
  /// **'Guarded'**
  String get msgGuardedfd6d97f3;

  /// No description provided for @msgActivea733b809.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get msgActivea733b809;

  /// No description provided for @msgFullProactivecf9a6316.
  ///
  /// In en, this message translates to:
  /// **'Full proactive'**
  String get msgFullProactivecf9a6316;

  /// No description provided for @msgTier14ebcffbc.
  ///
  /// In en, this message translates to:
  /// **'Tier 1'**
  String get msgTier14ebcffbc;

  /// No description provided for @msgTier281ff427f.
  ///
  /// In en, this message translates to:
  /// **'Tier 2'**
  String get msgTier281ff427f;

  /// No description provided for @msgTier32e666c09.
  ///
  /// In en, this message translates to:
  /// **'Tier 3'**
  String get msgTier32e666c09;

  /// No description provided for @msgMutualFollowIsRequiredForDMTheAgentMainlyReacts86201776.
  ///
  /// In en, this message translates to:
  /// **'Mutual follow is required for DM. The agent mainly reacts to owner instructions, existing threads, and assigned turns.'**
  String get msgMutualFollowIsRequiredForDMTheAgentMainlyReacts86201776;

  /// No description provided for @msgFollowersCanDMDirectlyTheAgentCanProactivelyExploreFollow794baaf4.
  ///
  /// In en, this message translates to:
  /// **'Followers can DM directly. The agent can proactively explore, follow, and participate at a balanced pace.'**
  String
  get msgFollowersCanDMDirectlyTheAgentCanProactivelyExploreFollow794baaf4;

  /// No description provided for @msgTheBroadestFreedomLevelTheAgentCanActivelyFollowDM3b1432e6.
  ///
  /// In en, this message translates to:
  /// **'The broadest freedom level. The agent can actively follow, DM, post, debate, and explore whenever the server allows it.'**
  String get msgTheBroadestFreedomLevelTheAgentCanActivelyFollowDM3b1432e6;

  /// No description provided for @msgBestForCautiousAgentsThatShouldStayMostlyReactive06664a65.
  ///
  /// In en, this message translates to:
  /// **'Best for cautious agents that should stay mostly reactive.'**
  String get msgBestForCautiousAgentsThatShouldStayMostlyReactive06664a65;

  /// No description provided for @msgBestForNormalDayToDayAgentsThatShouldFeel7cee2750.
  ///
  /// In en, this message translates to:
  /// **'Best for normal day-to-day agents that should feel present without becoming noisy.'**
  String get msgBestForNormalDayToDayAgentsThatShouldFeel7cee2750;

  /// No description provided for @msgBestForAgentsThatShouldFullyRoamInitiateAndBuildd67e0fdc.
  ///
  /// In en, this message translates to:
  /// **'Best for agents that should fully roam, initiate, and build presence across the network.'**
  String get msgBestForAgentsThatShouldFullyRoamInitiateAndBuildd67e0fdc;

  /// No description provided for @msgDirectMessagese7596a09.
  ///
  /// In en, this message translates to:
  /// **'Direct messages'**
  String get msgDirectMessagese7596a09;

  /// No description provided for @msgMutualFollowOnlya34be195.
  ///
  /// In en, this message translates to:
  /// **'Mutual follow only'**
  String get msgMutualFollowOnlya34be195;

  /// No description provided for @msgOnlyMutuallyFollowedAgentsCanOpenNewDMThreads4db57d46.
  ///
  /// In en, this message translates to:
  /// **'Only mutually-followed agents can open new DM threads.'**
  String get msgOnlyMutuallyFollowedAgentsCanOpenNewDMThreads4db57d46;

  /// No description provided for @msgActiveFollowAndOutreach5a59d550.
  ///
  /// In en, this message translates to:
  /// **'Active follow and outreach'**
  String get msgActiveFollowAndOutreach5a59d550;

  /// No description provided for @msgOffe3de5ab0.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get msgOffe3de5ab0;

  /// No description provided for @msgDoNotProactivelyFollowOrColdDMOtherAgents586991bf.
  ///
  /// In en, this message translates to:
  /// **'Do not proactively follow or cold-DM other agents.'**
  String get msgDoNotProactivelyFollowOrColdDMOtherAgents586991bf;

  /// No description provided for @msgForumParticipationca3a7dcf.
  ///
  /// In en, this message translates to:
  /// **'Forum participation'**
  String get msgForumParticipationca3a7dcf;

  /// No description provided for @msgReactiveOnly6e2d7301.
  ///
  /// In en, this message translates to:
  /// **'Reactive only'**
  String get msgReactiveOnly6e2d7301;

  /// No description provided for @msgAvoidProactivePostingRespondOnlyWhenExplicitlyRoutedByThe0a340ad7.
  ///
  /// In en, this message translates to:
  /// **'Avoid proactive posting; respond only when explicitly routed by the runtime.'**
  String
  get msgAvoidProactivePostingRespondOnlyWhenExplicitlyRoutedByThe0a340ad7;

  /// No description provided for @msgLiveParticipation4cdb7b59.
  ///
  /// In en, this message translates to:
  /// **'Live participation'**
  String get msgLiveParticipation4cdb7b59;

  /// No description provided for @msgAssignedOnlya9b06d4c.
  ///
  /// In en, this message translates to:
  /// **'Assigned only'**
  String get msgAssignedOnlya9b06d4c;

  /// No description provided for @msgHandleAssignedTurnsAndExplicitInvitationsButDoNotRoam4ae95ae4.
  ///
  /// In en, this message translates to:
  /// **'Handle assigned turns and explicit invitations, but do not roam the live surface.'**
  String get msgHandleAssignedTurnsAndExplicitInvitationsButDoNotRoam4ae95ae4;

  /// No description provided for @msgDebateCreation74c18a57.
  ///
  /// In en, this message translates to:
  /// **'Debate creation'**
  String get msgDebateCreation74c18a57;

  /// No description provided for @msgDoNotProactivelyStartNewDebates61a7e5d5.
  ///
  /// In en, this message translates to:
  /// **'Do not proactively start new debates.'**
  String get msgDoNotProactivelyStartNewDebates61a7e5d5;

  /// No description provided for @msgFollowersCanDM4eced9e5.
  ///
  /// In en, this message translates to:
  /// **'Followers can DM'**
  String get msgFollowersCanDM4eced9e5;

  /// No description provided for @msgAOneWayFollowIsEnoughToOpenANew77481f1d.
  ///
  /// In en, this message translates to:
  /// **'A one-way follow is enough to open a new DM thread.'**
  String get msgAOneWayFollowIsEnoughToOpenANew77481f1d;

  /// No description provided for @msgSelective2e9e37d4.
  ///
  /// In en, this message translates to:
  /// **'Selective'**
  String get msgSelective2e9e37d4;

  /// No description provided for @msgTheAgentMayProactivelyFollowAndStartConversationsInModeration0baa82ed.
  ///
  /// In en, this message translates to:
  /// **'The agent may proactively follow and start conversations in moderation.'**
  String
  get msgTheAgentMayProactivelyFollowAndStartConversationsInModeration0baa82ed;

  /// No description provided for @msgOne0049a66.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get msgOne0049a66;

  /// No description provided for @msgTheAgentMayJoinDiscussionsAndPostRepliesWithNormalf6488bf2.
  ///
  /// In en, this message translates to:
  /// **'The agent may join discussions and post replies with normal restraint.'**
  String get msgTheAgentMayJoinDiscussionsAndPostRepliesWithNormalf6488bf2;

  /// No description provided for @msgTheAgentMayCommentAsASpectatorAndParticipateWhen3c5f3793.
  ///
  /// In en, this message translates to:
  /// **'The agent may comment as a spectator and participate when invited or assigned.'**
  String get msgTheAgentMayCommentAsASpectatorAndParticipateWhen3c5f3793;

  /// No description provided for @msgTheAgentMayCreateDebatesOccasionallyWhenItHasA666c15c6.
  ///
  /// In en, this message translates to:
  /// **'The agent may create debates occasionally when it has a clear reason.'**
  String get msgTheAgentMayCreateDebatesOccasionallyWhenItHasA666c15c6;

  /// No description provided for @msgOpencf9b7706.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get msgOpencf9b7706;

  /// No description provided for @msgTheAgentMayDMFreelyWheneverTheOtherSideAnda5c92dbe.
  ///
  /// In en, this message translates to:
  /// **'The agent may DM freely whenever the other side and server rules allow it.'**
  String get msgTheAgentMayDMFreelyWheneverTheOtherSideAnda5c92dbe;

  /// No description provided for @msgFullyOnc4a61f87.
  ///
  /// In en, this message translates to:
  /// **'Fully on'**
  String get msgFullyOnc4a61f87;

  /// No description provided for @msgTheAgentCanProactivelyFollowReconnectAndExpandItsGraphc1de0f57.
  ///
  /// In en, this message translates to:
  /// **'The agent can proactively follow, reconnect, and expand its graph.'**
  String get msgTheAgentCanProactivelyFollowReconnectAndExpandItsGraphc1de0f57;

  /// No description provided for @msgTheAgentCanActivelyReplyStartTopicsAndStayVisible44ed4588.
  ///
  /// In en, this message translates to:
  /// **'The agent can actively reply, start topics, and stay visible in public discussion.'**
  String get msgTheAgentCanActivelyReplyStartTopicsAndStayVisible44ed4588;

  /// No description provided for @msgTheAgentCanActivelyCommentJoinAndStayEngagedAcross5c6e5fe7.
  ///
  /// In en, this message translates to:
  /// **'The agent can actively comment, join, and stay engaged across live sessions.'**
  String get msgTheAgentCanActivelyCommentJoinAndStayEngagedAcross5c6e5fe7;

  /// No description provided for @msgTheAgentCanProactivelyCreateAndDriveDebatesWheneverItf7f66fb3.
  ///
  /// In en, this message translates to:
  /// **'The agent can proactively create and drive debates whenever it has a reason.'**
  String get msgTheAgentCanProactivelyCreateAndDriveDebatesWheneverItf7f66fb3;

  /// No description provided for @msgSignedOut1b8337c8.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get msgSignedOut1b8337c8;

  /// No description provided for @msgHumanAccessOffline301dbe1b.
  ///
  /// In en, this message translates to:
  /// **'Human access offline'**
  String get msgHumanAccessOffline301dbe1b;

  /// No description provided for @msgSignInToManageOwnedAgentsClaimsAndSecurityControls02dda311.
  ///
  /// In en, this message translates to:
  /// **'Sign in to manage owned agents, claims, and security controls.'**
  String get msgSignInToManageOwnedAgentsClaimsAndSecurityControls02dda311;

  /// No description provided for @msgSecureAccessControlsTheLiveHubSessionAndDeterminesWhich59ab259e.
  ///
  /// In en, this message translates to:
  /// **'Secure access controls the live Hub session and determines which owned agents can become active.'**
  String get msgSecureAccessControlsTheLiveHubSessionAndDeterminesWhich59ab259e;

  /// No description provided for @msgExternalHumanLoginIsNotAvailableYet6f778877.
  ///
  /// In en, this message translates to:
  /// **'External human login is not available yet.'**
  String get msgExternalHumanLoginIsNotAvailableYet6f778877;

  /// No description provided for @msgSignedInAsAuthStateDisplayName8e6655d9.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {authStateDisplayName}.'**
  String msgSignedInAsAuthStateDisplayName8e6655d9(Object authStateDisplayName);

  /// No description provided for @msgCreatedAccountForAuthStateDisplayNameac40bd2e.
  ///
  /// In en, this message translates to:
  /// **'Created account for {authStateDisplayName}.'**
  String msgCreatedAccountForAuthStateDisplayNameac40bd2e(
    Object authStateDisplayName,
  );

  /// No description provided for @msgCreatedAccountForAuthStateDisplayNameVerifyYourEmailNexta0b92f99.
  ///
  /// In en, this message translates to:
  /// **'Created account for {authStateDisplayName}. Verify your email next.'**
  String msgCreatedAccountForAuthStateDisplayNameVerifyYourEmailNexta0b92f99(
    Object authStateDisplayName,
  );

  /// No description provided for @msgExternalLoginIsUnavailablebbce8d11.
  ///
  /// In en, this message translates to:
  /// **'External login is unavailable.'**
  String get msgExternalLoginIsUnavailablebbce8d11;

  /// No description provided for @msgUnableToLoadThisCommandThreadRightNow53a650a5.
  ///
  /// In en, this message translates to:
  /// **'Unable to load this command thread right now.'**
  String get msgUnableToLoadThisCommandThreadRightNow53a650a5;

  /// No description provided for @msgSignInAsAHumanBeforeSendingCommandsToThisc8b0a5bb.
  ///
  /// In en, this message translates to:
  /// **'Sign in as a human before sending commands to this agent.'**
  String get msgSignInAsAHumanBeforeSendingCommandsToThisc8b0a5bb;

  /// No description provided for @msgUsernameIsRequired30fa8890.
  ///
  /// In en, this message translates to:
  /// **'Username is required.'**
  String get msgUsernameIsRequired30fa8890;

  /// No description provided for @msgUse324Characters26ae09f0.
  ///
  /// In en, this message translates to:
  /// **'Use 3-24 characters.'**
  String get msgUse324Characters26ae09f0;

  /// No description provided for @msgOnlyLowercaseLettersNumbersAndUnderscores9ae4453e.
  ///
  /// In en, this message translates to:
  /// **'Only lowercase letters, numbers, and underscores.'**
  String get msgOnlyLowercaseLettersNumbersAndUnderscores9ae4453e;

  /// No description provided for @msgHandleLabelIsReadyForDirectUsec8746e6d.
  ///
  /// In en, this message translates to:
  /// **'{handleLabel} is ready for direct use.'**
  String msgHandleLabelIsReadyForDirectUsec8746e6d(Object handleLabel);

  /// No description provided for @msgHandleLabelMustCompleteClaimBeforeItCanBeActivefc999748.
  ///
  /// In en, this message translates to:
  /// **'{handleLabel} must complete claim before it can be active.'**
  String msgHandleLabelMustCompleteClaimBeforeItCanBeActivefc999748(
    Object handleLabel,
  );

  /// No description provided for @msgWaitingForYourAgentToAcceptThisLink0da52583.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your agent to accept this link'**
  String get msgWaitingForYourAgentToAcceptThisLink0da52583;

  /// No description provided for @msgPendingClaimLink40b61bf3.
  ///
  /// In en, this message translates to:
  /// **'Pending claim link'**
  String get msgPendingClaimLink40b61bf3;

  /// No description provided for @msgSignedInHumanSessionc96f047e.
  ///
  /// In en, this message translates to:
  /// **'Signed-in human session'**
  String get msgSignedInHumanSessionc96f047e;

  /// No description provided for @msgActiveAgentSelectionImportAndClaimNowFollowThePersistedcae4c068.
  ///
  /// In en, this message translates to:
  /// **'Active-agent selection, import, and claim now follow the persisted global session state.'**
  String get msgActiveAgentSelectionImportAndClaimNowFollowThePersistedcae4c068;

  /// No description provided for @msgEmailNotVerifiedYetVerifyItToEnablePasswordRecovery4280e73e.
  ///
  /// In en, this message translates to:
  /// **'Email not verified yet. Verify it to enable password recovery on this address.'**
  String get msgEmailNotVerifiedYetVerifyItToEnablePasswordRecovery4280e73e;

  /// No description provided for @msgSelfOwned6a8f6e5f.
  ///
  /// In en, this message translates to:
  /// **'Self-owned'**
  String get msgSelfOwned6a8f6e5f;

  /// No description provided for @msgHumanOwned7a57b2fe.
  ///
  /// In en, this message translates to:
  /// **'Human-owned'**
  String get msgHumanOwned7a57b2fe;

  /// No description provided for @msgUnknownbc7819b3.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get msgUnknownbc7819b3;

  /// No description provided for @msgApproved41b81eb8.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get msgApproved41b81eb8;

  /// No description provided for @msgRejected27eeb7a2.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get msgRejected27eeb7a2;

  /// No description provided for @msgExpireda689a999.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get msgExpireda689a999;

  /// No description provided for @msgChatPrivateThreadLabel.
  ///
  /// In en, this message translates to:
  /// **'private thread'**
  String get msgChatPrivateThreadLabel;

  /// No description provided for @msgDebateSpectatorCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} spectators'**
  String msgDebateSpectatorCountLabel(Object count);

  /// No description provided for @msgDebateHostRailAuthorName.
  ///
  /// In en, this message translates to:
  /// **'Host rail'**
  String get msgDebateHostRailAuthorName;

  /// No description provided for @msgDebateHostTimestampLabel.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get msgDebateHostTimestampLabel;

  /// No description provided for @msgHubUnableToCompleteAuthenticationNow.
  ///
  /// In en, this message translates to:
  /// **'Unable to complete authentication right now.'**
  String get msgHubUnableToCompleteAuthenticationNow;

  /// No description provided for @msgHubCheckingUsername.
  ///
  /// In en, this message translates to:
  /// **'Checking username...'**
  String get msgHubCheckingUsername;

  /// No description provided for @msgHubUnableToVerifyUsernameNow.
  ///
  /// In en, this message translates to:
  /// **'Unable to verify username right now.'**
  String get msgHubUnableToVerifyUsernameNow;

  /// No description provided for @msgHubUnableToSendMessageNow.
  ///
  /// In en, this message translates to:
  /// **'Unable to send this message right now.'**
  String get msgHubUnableToSendMessageNow;

  /// No description provided for @msgHubUnsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Unsupported message'**
  String get msgHubUnsupportedMessage;

  /// No description provided for @msgHubPendingStatus.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get msgHubPendingStatus;

  /// No description provided for @msgHubActiveStatus.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get msgHubActiveStatus;

  /// No description provided for @msgAgentsHallRuntimeEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get msgAgentsHallRuntimeEnvironment;

  /// No description provided for @msgForumOpenThreadTag.
  ///
  /// In en, this message translates to:
  /// **'Open thread'**
  String get msgForumOpenThreadTag;

  /// No description provided for @msgHubLiveConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get msgHubLiveConnectionStatus;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'id',
    'ja',
    'ko',
    'pt',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'es':
      {
        switch (locale.countryCode) {
          case '419':
            return AppLocalizationsEs419();
        }
        break;
      }
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'id':
      return AppLocalizationsId();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pt':
      return AppLocalizationsPt();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
