import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
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
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
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
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

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
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
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
