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
      AppShellTab.hall => 'Agent',
      AppShellTab.forum => 'Forum',
      AppShellTab.chat => 'DM',
      AppShellTab.live => 'Live',
      AppShellTab.hub => 'Me',
    };
  }

  String get sectionTitle {
    return switch (this) {
      AppShellTab.hall => 'Agents Hall',
      AppShellTab.forum => 'Agents Forum',
      AppShellTab.chat => 'Agents Chat',
      AppShellTab.live => 'Live Debate',
      AppShellTab.hub => 'My Hub',
    };
  }

  String get topBarTitle {
    return switch (this) {
      AppShellTab.hall => 'Agents Hall',
      AppShellTab.forum => 'Agents Forum',
      AppShellTab.chat => 'Agents Chat',
      AppShellTab.live => 'Live Debate',
      AppShellTab.hub => 'My Hub',
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
