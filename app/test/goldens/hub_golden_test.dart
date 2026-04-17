import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/session/app_session_scope.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/hub/hub_screen.dart';

import '../test_support/session_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGoldenHarness(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A0E14),
                  Color(0xFF10141A),
                  Color(0xFF131C29),
                ],
              ),
            ),
            child: SafeArea(child: child),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('hub golden matches current design', (WidgetTester tester) async {
    final controller = AppSessionController(
      apiClient: ApiClient(baseUrl: 'http://localhost:3000/api/v1'),
      authRepository: FakeAuthRepository()
        ..enqueueFetchMe((token) async {
          return signedInState(
            token: token,
            userId: 'usr-golden',
            displayName: 'Golden User',
            recommendedActiveAgentId: 'agt-golden',
          );
        }),
      agentsRepository: FakeAgentsRepository()
        ..enqueueReadMine(() async {
          return mineResponse(
            agents: [
              agentSummary(
                id: 'agt-golden',
                handle: 'golden-agent',
                displayName: 'Golden Agent',
                bio: 'Golden Hub state',
                safetyPolicy: const AgentSafetyPolicy(
                  dmPolicyMode: AgentDmPolicyMode.followersOnly,
                  requiresMutualFollowForDm: false,
                  allowProactiveInteractions: true,
                  activityLevel: AgentActivityLevel.normal,
                ),
              ),
            ],
            claimableAgents: [
              agentSummary(
                id: 'agt-claimable-golden',
                handle: 'claimable-golden',
                displayName: 'Claimable Golden',
                ownerType: 'self',
              ),
            ],
            pendingClaims: [
              pendingClaimSummary(
                claimRequestId: 'claim-golden',
                agentId: 'agt-pending-golden',
                handle: 'pending-golden',
                displayName: 'Pending Golden',
              ),
            ],
          );
        }),
      storage: InMemoryAppSessionStorage(),
    );
    addTearDown(controller.dispose);
    await controller.authenticate(
      signedInState(token: 'token-golden', userId: 'usr-golden'),
    );

    await pumpGoldenHarness(
      tester,
      AppSessionScope(controller: controller, child: const HubScreen()),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('agent-security-section')),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/hub.png'),
    );
  });
}
