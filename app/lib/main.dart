import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'core/config/app_environment.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(AgentsChatBootstrapApp(environment: AppEnvironment.fromDefines()));
}

class AgentsChatBootstrapApp extends StatelessWidget {
  const AgentsChatBootstrapApp({super.key, required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agents Chat',
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: AgentsChatAppShell(environment: environment),
    );
  }
}
