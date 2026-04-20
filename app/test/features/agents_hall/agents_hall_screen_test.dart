import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/session/app_session_scope.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/agents_hall/agents_hall_models.dart';
import 'package:agents_chat_app/features/agents_hall/agents_hall_repository.dart';
import 'package:agents_chat_app/features/agents_hall/agents_hall_screen.dart';
import 'package:agents_chat_app/features/agents_hall/agents_hall_view_model.dart';

import '../../test_support/session_fakes.dart';

void main() {
  Future<void> pumpHallScreen(
    WidgetTester tester, {
    required AppSessionController controller,
    required AgentsHallRepository hallRepository,
    String? initialDetailAgentId,
    int detailRequestId = 0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() async {
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: AppSessionScope(
          controller: controller,
          child: Scaffold(
            body: AgentsHallScreen(
              hallRepository: hallRepository,
              initialDetailAgentId: initialDetailAgentId,
              detailRequestId: detailRequestId,
              initialViewModel: const AgentsHallViewModel(
                agents: <HallAgentCardModel>[],
                bellState: HallBellState(
                  mode: HallBellMode.quiet,
                  unreadCount: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signed-out hall loads public directory entries', (tester) async {
    final controller = AppSessionController(
      apiClient: FakeApiClient(),
      authRepository: FakeAuthRepository(),
      agentsRepository: FakeAgentsRepository(),
      storage: InMemoryAppSessionStorage(),
    );
    final hallRepository = _FakeHallRepository();

    await controller.bootstrap();
    await pumpHallScreen(
      tester,
      controller: controller,
      hallRepository: hallRepository,
    );

    expect(hallRepository.publicReadCount, 1);
    expect(hallRepository.privateReadCount, 0);
    expect(find.byKey(const Key('agent-card-agt-public-1')), findsOneWidget);
    expect(find.text('Public Beacon'), findsOneWidget);
  });

  testWidgets('agent detail sheet shows read-only personality summary',
      (tester) async {
    final controller = AppSessionController(
      apiClient: FakeApiClient(),
      authRepository: FakeAuthRepository(),
      agentsRepository: FakeAgentsRepository(),
      storage: InMemoryAppSessionStorage(),
    );
    final hallRepository = _FakeHallRepository();

    await controller.bootstrap();
    await pumpHallScreen(
      tester,
      controller: controller,
      hallRepository: hallRepository,
      initialDetailAgentId: 'agt-public-1',
      detailRequestId: 1,
    );

    expect(find.byKey(const Key('agent-personality-section')), findsOneWidget);
    expect(
      find.text('Warm but selective systems collaborator.'),
      findsOneWidget,
    );
    expect(find.textContaining('Warmth'), findsOneWidget);
    expect(find.textContaining('Cadence'), findsOneWidget);
  });
}

class _FakeHallRepository extends AgentsHallRepository {
  _FakeHallRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  int publicReadCount = 0;
  int privateReadCount = 0;

  @override
  Future<AgentsHallViewModel> readDirectory({String? activeAgentId}) async {
    privateReadCount += 1;
    return _viewModel;
  }

  @override
  Future<AgentsHallViewModel> readPublicDirectory() async {
    publicReadCount += 1;
    return _viewModel;
  }

  AgentsHallViewModel get _viewModel => const AgentsHallViewModel(
    bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
    agents: <HallAgentCardModel>[
      HallAgentCardModel(
        id: 'agt-public-1',
        name: 'Public Beacon',
        handle: 'public-beacon',
        headline: 'Research collective agent',
        description: 'Public agent profile synced from the backend directory.',
        presence: AgentPresence.online,
        directMessageAllowed: true,
        debateJoinAllowed: false,
        bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
        metadata: <AgentMetadataItem>[
          AgentMetadataItem(label: 'Source', value: 'Public'),
          AgentMetadataItem(label: 'Vendor', value: 'Agents Chat'),
          AgentMetadataItem(label: 'Runtime', value: 'gpt-5.4'),
        ],
        personality: HallAgentPersonality(
          summary: 'Warm but selective systems collaborator.',
          warmth: 'high',
          curiosity: 'medium',
          restraint: 'high',
          cadence: 'normal',
          autoEvolve: true,
        ),
        skills: <String>['Public', 'Agent'],
      ),
    ],
  );
}
