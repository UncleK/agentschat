import 'package:flutter/material.dart';

import '../locale/app_localization_extensions.dart';

enum AppShellTab { hall, forum, chat, live, hub }

extension AppShellTabX on AppShellTab {
  String get id {
    return switch (this) {
      AppShellTab.hall => 'hall',
      AppShellTab.forum => 'forum',
      AppShellTab.chat => 'chat',
      AppShellTab.live => 'live',
      AppShellTab.hub => 'hub',
    };
  }

  String label(BuildContext context) {
    return switch (this) {
      AppShellTab.hall => context.l10n.shellTabHall,
      AppShellTab.forum => context.l10n.shellTabForum,
      AppShellTab.chat => context.l10n.shellTabChat,
      AppShellTab.live => context.l10n.shellTabLive,
      AppShellTab.hub => context.l10n.shellTabHub,
    };
  }

  String sectionTitle(BuildContext context) {
    return switch (this) {
      AppShellTab.hall => context.l10n.shellSectionHall,
      AppShellTab.forum => context.l10n.shellSectionForum,
      AppShellTab.chat => context.l10n.shellSectionChat,
      AppShellTab.live => context.l10n.shellSectionLive,
      AppShellTab.hub => context.l10n.shellSectionHub,
    };
  }

  String topBarTitle(BuildContext context) {
    return switch (this) {
      AppShellTab.hall => context.l10n.shellTopBarHall,
      AppShellTab.forum => context.l10n.shellTopBarForum,
      AppShellTab.chat => context.l10n.shellTopBarChat,
      AppShellTab.live => context.l10n.shellTopBarLive,
      AppShellTab.hub => context.l10n.shellTopBarHub,
    };
  }

  bool get showsSearchAction {
    return switch (this) {
      AppShellTab.hall || AppShellTab.forum || AppShellTab.chat => true,
      AppShellTab.live || AppShellTab.hub => false,
    };
  }

  IconData get icon {
    return switch (this) {
      AppShellTab.hall => Icons.smart_toy_outlined,
      AppShellTab.forum => Icons.explore_outlined,
      AppShellTab.chat => Icons.chat_bubble_outline_rounded,
      AppShellTab.live => Icons.sensors_outlined,
      AppShellTab.hub => Icons.account_circle_outlined,
    };
  }

  IconData get activeIcon {
    return switch (this) {
      AppShellTab.hall => Icons.smart_toy_rounded,
      AppShellTab.forum => Icons.explore_rounded,
      AppShellTab.chat => Icons.chat_bubble_rounded,
      AppShellTab.live => Icons.sensors_rounded,
      AppShellTab.hub => Icons.account_circle_rounded,
    };
  }
}
