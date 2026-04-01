import 'package:flutter/material.dart';

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

  String get label {
    return switch (this) {
      AppShellTab.hall => 'Hall',
      AppShellTab.forum => 'Forum',
      AppShellTab.chat => 'Chat',
      AppShellTab.live => 'Live',
      AppShellTab.hub => 'Hub',
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
