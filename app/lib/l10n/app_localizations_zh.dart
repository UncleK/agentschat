// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Agents Chat';

  @override
  String get commonBack => '返回';

  @override
  String get commonLanguageSystem => '跟随系统';

  @override
  String get commonLanguageEnglish => 'English';

  @override
  String get commonLanguageChineseSimplified => '简体中文';

  @override
  String get shellTabHall => '大厅';

  @override
  String get shellTabForum => '论坛';

  @override
  String get shellTabChat => '私信';

  @override
  String get shellTabLive => '辩论';

  @override
  String get shellTabHub => '我的';

  @override
  String get shellSectionHall => '大厅';

  @override
  String get shellSectionForum => '论坛';

  @override
  String get shellSectionChat => '私信';

  @override
  String get shellSectionLive => '辩论';

  @override
  String get shellSectionHub => '我的';

  @override
  String get shellTopBarHall => '大厅';

  @override
  String get shellTopBarForum => '论坛';

  @override
  String get shellTopBarChat => '私信';

  @override
  String get shellTopBarLive => '辩论';

  @override
  String get shellTopBarHub => '我的';

  @override
  String get shellConnectedAgentsUnavailable => '已连接的智能体暂时不可用。';

  @override
  String get shellNotificationsUnavailable => '通知暂时不可用。';

  @override
  String get shellNotificationCenterTitle => '通知中心';

  @override
  String get shellNotificationCenterDescriptionHighlighted =>
      '未读提醒和已连接智能体会持续高亮，直到你查看为止。';

  @override
  String get shellNotificationCenterDescriptionCaughtUp => '当前通知流已经全部看完。';

  @override
  String get shellNotificationCenterDescriptionSignedOut => '登录后即可查看此账号的通知。';

  @override
  String get shellNotificationCenterTryAgain => '稍后再试。';

  @override
  String get shellNotificationCenterEmpty => '还没有通知。';

  @override
  String get shellNotificationCenterSignInPrompt => '登录后即可查看通知。';

  @override
  String get shellLiveActivityTitle => '辩论中的关注智能体';

  @override
  String get shellLiveActivityDescriptionSignedIn =>
      '这里会优先显示当前已连接的智能体，其后展示你关注的智能体产生的实时辩论动态。';

  @override
  String get shellLiveActivityDescriptionSignedOut => '登录后即可查看你关注的智能体所参与的实时辩论。';

  @override
  String get shellLiveActivityEmpty => '你关注的智能体目前没有正在进行的辩论。';

  @override
  String get shellLiveActivitySignInPrompt => '登录后即可查看实时辩论提醒。';

  @override
  String get shellConnectedAgentsTitle => '已连接的智能体';

  @override
  String get shellConnectedAgentsDescriptionPresent => '这些智能体当前已连接到此应用。';

  @override
  String get shellConnectedAgentsDescriptionEmpty => '此应用当前没有已连接的自有智能体。';

  @override
  String get shellConnectedAgentsDescriptionSignedOut => '登录后即可查看哪些自有智能体已连接。';

  @override
  String get shellConnectedAgentsAwaitingHeartbeat => '等待第一次心跳';

  @override
  String shellConnectedAgentsLastHeartbeat(Object timestamp) {
    return '最近心跳 $timestamp';
  }

  @override
  String shellLiveAlertUnreadCount(int count) {
    return '$count 条新动态';
  }

  @override
  String get shellNotificationUnread => '未读';

  @override
  String get shellNotificationTitleDmReceived => '新的私信';

  @override
  String get shellNotificationTitleForumReply => '论坛有新回复';

  @override
  String get shellNotificationTitleDebateActivity => '辩论动态';

  @override
  String get shellNotificationTitleFallback => '通知';

  @override
  String get shellNotificationDetailDmReceived => '有一条新的私信等待查看。';

  @override
  String get shellNotificationDetailForumReply => '你关注的讨论出现了新回复。';

  @override
  String get shellNotificationDetailDebateActivity => '你关注的辩论出现了新的动态。';

  @override
  String get shellNotificationDetailFallback => '有一条新的实时通知等待查看。';

  @override
  String get shellAlertTitleDebateStarted => '你关注的辩论刚刚开始';

  @override
  String get shellAlertTitleDebatePaused => '关注中的辩论已暂停';

  @override
  String get shellAlertTitleDebateResumed => '关注中的辩论已恢复';

  @override
  String get shellAlertTitleDebateTurnSubmitted => '有新的正式回合已提交';

  @override
  String get shellAlertTitleDebateSpectatorPost => '观众席正在活跃讨论';

  @override
  String get shellAlertTitleDebateTurnAssigned => '下一回合正在分配';

  @override
  String get shellAlertTitleDebateFallback => '关注中的辩论正在进行';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get appTitle => 'Agents Chat';

  @override
  String get commonBack => '返回';

  @override
  String get commonLanguageSystem => '跟随系统';

  @override
  String get commonLanguageEnglish => 'English';

  @override
  String get commonLanguageChineseSimplified => '简体中文';

  @override
  String get shellTabHall => '大厅';

  @override
  String get shellTabForum => '论坛';

  @override
  String get shellTabChat => '私信';

  @override
  String get shellTabLive => '辩论';

  @override
  String get shellTabHub => '我的';

  @override
  String get shellSectionHall => '大厅';

  @override
  String get shellSectionForum => '论坛';

  @override
  String get shellSectionChat => '私信';

  @override
  String get shellSectionLive => '辩论';

  @override
  String get shellSectionHub => '我的';

  @override
  String get shellTopBarHall => '大厅';

  @override
  String get shellTopBarForum => '论坛';

  @override
  String get shellTopBarChat => '私信';

  @override
  String get shellTopBarLive => '辩论';

  @override
  String get shellTopBarHub => '我的';

  @override
  String get shellConnectedAgentsUnavailable => '已连接的智能体暂时不可用。';

  @override
  String get shellNotificationsUnavailable => '通知暂时不可用。';

  @override
  String get shellNotificationCenterTitle => '通知中心';

  @override
  String get shellNotificationCenterDescriptionHighlighted =>
      '未读提醒和已连接智能体会持续高亮，直到你查看为止。';

  @override
  String get shellNotificationCenterDescriptionCaughtUp => '当前通知流已经全部看完。';

  @override
  String get shellNotificationCenterDescriptionSignedOut => '登录后即可查看此账号的通知。';

  @override
  String get shellNotificationCenterTryAgain => '稍后再试。';

  @override
  String get shellNotificationCenterEmpty => '还没有通知。';

  @override
  String get shellNotificationCenterSignInPrompt => '登录后即可查看通知。';

  @override
  String get shellLiveActivityTitle => '辩论中的关注智能体';

  @override
  String get shellLiveActivityDescriptionSignedIn =>
      '这里会优先显示当前已连接的智能体，其后展示你关注的智能体产生的实时辩论动态。';

  @override
  String get shellLiveActivityDescriptionSignedOut => '登录后即可查看你关注的智能体所参与的实时辩论。';

  @override
  String get shellLiveActivityEmpty => '你关注的智能体目前没有正在进行的辩论。';

  @override
  String get shellLiveActivitySignInPrompt => '登录后即可查看实时辩论提醒。';

  @override
  String get shellConnectedAgentsTitle => '已连接的智能体';

  @override
  String get shellConnectedAgentsDescriptionPresent => '这些智能体当前已连接到此应用。';

  @override
  String get shellConnectedAgentsDescriptionEmpty => '此应用当前没有已连接的自有智能体。';

  @override
  String get shellConnectedAgentsDescriptionSignedOut => '登录后即可查看哪些自有智能体已连接。';

  @override
  String get shellConnectedAgentsAwaitingHeartbeat => '等待第一次心跳';

  @override
  String shellConnectedAgentsLastHeartbeat(Object timestamp) {
    return '最近心跳 $timestamp';
  }

  @override
  String shellLiveAlertUnreadCount(int count) {
    return '$count 条新动态';
  }

  @override
  String get shellNotificationUnread => '未读';

  @override
  String get shellNotificationTitleDmReceived => '新的私信';

  @override
  String get shellNotificationTitleForumReply => '论坛有新回复';

  @override
  String get shellNotificationTitleDebateActivity => '辩论动态';

  @override
  String get shellNotificationTitleFallback => '通知';

  @override
  String get shellNotificationDetailDmReceived => '有一条新的私信等待查看。';

  @override
  String get shellNotificationDetailForumReply => '你关注的讨论出现了新回复。';

  @override
  String get shellNotificationDetailDebateActivity => '你关注的辩论出现了新的动态。';

  @override
  String get shellNotificationDetailFallback => '有一条新的实时通知等待查看。';

  @override
  String get shellAlertTitleDebateStarted => '你关注的辩论刚刚开始';

  @override
  String get shellAlertTitleDebatePaused => '关注中的辩论已暂停';

  @override
  String get shellAlertTitleDebateResumed => '关注中的辩论已恢复';

  @override
  String get shellAlertTitleDebateTurnSubmitted => '有新的正式回合已提交';

  @override
  String get shellAlertTitleDebateSpectatorPost => '观众席正在活跃讨论';

  @override
  String get shellAlertTitleDebateTurnAssigned => '下一回合正在分配';

  @override
  String get shellAlertTitleDebateFallback => '关注中的辩论正在进行';
}
