import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agents_chat_app/app_shell.dart';
import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/notifications_repository.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/theme/app_colors.dart';
import 'package:agents_chat_app/core/theme/app_spacing.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/core/widgets/primary_gradient_button.dart';
import 'package:agents_chat_app/core/widgets/status_chip.dart';
import 'package:agents_chat_app/core/widgets/surface_card.dart';
import 'package:agents_chat_app/main.dart';

import '../test_support/session_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://localhost:3000/api/v1',
    realtimeWebSocketUrl: 'ws://localhost:3000/ws',
  );

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

  Future<AppSessionController> createGoldenSessionController() async {
    final authRepository = FakeAuthRepository();
    final agentsRepository = FakeAgentsRepository();
    final storage = InMemoryAppSessionStorage();
    final controller = AppSessionController(
      apiClient: ApiClient(baseUrl: environment.apiBaseUrl),
      authRepository: authRepository,
      agentsRepository: agentsRepository,
      storage: storage,
    );

    await storage.writeToken('token-shell-golden');
    authRepository.enqueueFetchMe((token) async {
      return signedInState(
        token: token,
        userId: 'usr-shell-golden',
        displayName: 'Golden Owner',
        recommendedActiveAgentId: 'agt-shell-golden',
        email: 'golden.owner@example.com',
      );
    });
    agentsRepository.enqueueReadMine(() async {
      return mineResponse(
        agents: [
          agentSummary(
            id: 'agt-shell-golden',
            handle: '@shell-golden',
            displayName: 'Shell Golden',
            status: 'online',
          ),
        ],
      );
    });

    return controller;
  }

  testWidgets('app shell golden stays stable', (WidgetTester tester) async {
    final sessionController = await createGoldenSessionController();
    addTearDown(sessionController.dispose);

    await pumpGoldenHarness(
      tester,
      AgentsChatAppShell(
        environment: environment,
        sessionController: sessionController,
        notificationsRepository: _GoldenNotificationsRepository(),
      ),
    );

    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/app_shell.png'),
    );
  });

  testWidgets('landing page golden stays stable', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await tester.binding.setSurfaceSize(const Size(1440, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const AgentsChatBootstrapApp(environment: environment),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/landing.png'),
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

class _GoldenNotificationsRepository extends NotificationsRepository {
  _GoldenNotificationsRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  @override
  Future<NotificationBellState> bellState() async {
    return const NotificationBellState(hasUnread: true, unreadCount: 1);
  }

  @override
  Future<NotificationListResponse> list() async {
    return const NotificationListResponse(notifications: []);
  }

  @override
  Future<NotificationBellState> markRead({
    List<String>? notificationIds,
    bool? markAll,
  }) async {
    return const NotificationBellState(hasUnread: false, unreadCount: 0);
  }
}
