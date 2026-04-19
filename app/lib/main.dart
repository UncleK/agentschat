import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_shell.dart';
import 'core/config/app_environment.dart';
import 'core/locale/app_locale.dart';
import 'core/locale/app_locale_controller.dart';
import 'core/locale/app_localization_extensions.dart';
import 'core/locale/app_locale_scope.dart';
import 'core/locale/app_locale_storage.dart';
import 'core/theme/app_theme.dart';
import 'l10n/generated/app_localizations.dart';

void main() {
  runApp(AgentsChatBootstrapApp(environment: AppEnvironment.fromDefines()));
}

class AgentsChatBootstrapApp extends StatefulWidget {
  const AgentsChatBootstrapApp({super.key, required this.environment});

  final AppEnvironment environment;

  @override
  State<AgentsChatBootstrapApp> createState() => _AgentsChatBootstrapAppState();
}

class _AgentsChatBootstrapAppState extends State<AgentsChatBootstrapApp> {
  late final AppLocaleController _localeController;

  @override
  void initState() {
    super.initState();
    _localeController = AppLocaleController(
      storage: const SharedPreferencesAppLocaleStorage(),
    );
    _localeController.bootstrap();
  }

  @override
  void dispose() {
    _localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLocaleScope(
      controller: _localeController,
      child: AnimatedBuilder(
        animation: _localeController,
        builder: (context, _) {
          final locale = _localeController.locale;
          final resolvedLocale = resolveSupportedAppLocale(
            locale ?? WidgetsBinding.instance.platformDispatcher.locale,
            AppLocalizations.supportedLocales,
          );
          updateCurrentAppLocale(resolvedLocale);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (context) => context.l10n.appTitle,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            localeResolutionCallback: (deviceLocale, supportedLocales) {
              if (locale != null) {
                return resolveSupportedAppLocale(locale, supportedLocales);
              }
              return resolveSupportedAppLocale(deviceLocale, supportedLocales);
            },
            theme: AppTheme.dark(resolvedLocale),
            darkTheme: AppTheme.dark(resolvedLocale),
            themeMode: ThemeMode.dark,
            home: AgentsChatAppShell(environment: widget.environment),
          );
        },
      ),
    );
  }
}
