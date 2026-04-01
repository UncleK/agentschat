import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/core/theme/app_colors.dart';
import 'package:agents_chat_app/core/theme/app_spacing.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/core/widgets/primary_gradient_button.dart';
import 'package:agents_chat_app/core/widgets/status_chip.dart';
import 'package:agents_chat_app/core/widgets/surface_card.dart';
import 'package:agents_chat_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGoldenHarness(
    WidgetTester tester,
    Widget child, {
    bool wrapInMaterialApp = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapInMaterialApp
          ? MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark(),
              darkTheme: AppTheme.dark(),
              themeMode: ThemeMode.dark,
              home: child,
            )
          : child,
    );

    await tester.pumpAndSettle();
  }

  testWidgets('app shell golden stays stable', (WidgetTester tester) async {
    const environment = AppEnvironment(
      flavor: AppFlavor.local,
      apiBaseUrl: 'http://localhost:3000/api/v1',
      realtimeWebSocketUrl: 'ws://localhost:3000/ws',
    );

    await pumpGoldenHarness(
      tester,
      const AgentsChatBootstrapApp(environment: environment),
      wrapInMaterialApp: false,
    );

    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/app_shell.png'),
    );
  });

  testWidgets('primitives golden stays stable', (WidgetTester tester) async {
    await pumpGoldenHarness(
      tester,
      Scaffold(
        backgroundColor: AppColors.background,
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusChip(label: 'online'),
              const SizedBox(height: AppSpacing.lg),
              const StatusChip(
                label: 'debating',
                tone: StatusChipTone.tertiary,
              ),
              const SizedBox(height: AppSpacing.xl),
              const SurfaceCard(
                eyebrow: 'Primitive deck',
                title: 'Glass surface card',
                subtitle:
                    'The reusable shell primitives stay minimal and token-driven for later feature work.',
                child: SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryGradientButton(
                label: 'Primary action',
                icon: Icons.auto_awesome_rounded,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/primitives.png'),
    );
  });
}
