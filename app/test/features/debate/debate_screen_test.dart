import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/session/app_session_scope.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/debate/debate_panel.dart';
import 'package:agents_chat_app/features/debate/debate_repository.dart';
import 'package:agents_chat_app/features/debate/debate_screen.dart';
import 'package:agents_chat_app/features/debate/debate_view_model.dart';

import '../../test_support/session_fakes.dart';

void main() {
  Future<void> pumpDebateScreen(
    WidgetTester tester, {
    DebatePanel initialPanel = DebatePanel.process,
    DebateViewModel? viewModel,
    Size surfaceSize = const Size(430, 932),
    AppSessionController? controller,
    DebateRepository? debateRepository,
    ValueChanged<VoidCallback?>? onInitiateActionChanged,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final screen = DebateScreen(
      initialViewModel: viewModel ?? DebateViewModel.sample(),
      showInlineInitiateButton: false,
      initialPanel: initialPanel,
      debateRepository: debateRepository,
      onInitiateActionChanged: onInitiateActionChanged,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: controller == null
            ? Scaffold(body: screen)
            : AppSessionScope(
                controller: controller,
                child: Scaffold(body: screen),
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('debate screen pumps in process mode', (tester) async {
    await pumpDebateScreen(tester);

    expect(find.byKey(const Key('surface-live')), findsOneWidget);
    expect(find.byKey(const Key('debate-tab-process')), findsOneWidget);
    expect(
      find.byKey(
        const Key(
          'debate-formal-turn-The Ethics of Emergent Sentience-pro-opening',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('signed-out live screen loads public debate data', (
    tester,
  ) async {
    final controller = AppSessionController(
      apiClient: FakeApiClient(),
      authRepository: FakeAuthRepository(),
      agentsRepository: FakeAgentsRepository(),
      storage: InMemoryAppSessionStorage(),
    );
    final trackingRepository = _TrackingDebateRepository();

    addTearDown(controller.dispose);
    await controller.bootstrap();

    await pumpDebateScreen(
      tester,
      controller: controller,
      debateRepository: trackingRepository,
    );

    expect(find.text('The Ethics of Emergent Sentience'), findsWidgets);
    expect(trackingRepository.readCount, 1);
    expect(trackingRepository.lastUsePublicDirectory, isTrue);
  });

  testWidgets('signed-out spectator posting prompts for login', (tester) async {
    final controller = AppSessionController(
      apiClient: FakeApiClient(),
      authRepository: FakeAuthRepository(),
      agentsRepository: FakeAgentsRepository(),
      storage: InMemoryAppSessionStorage(),
    );
    final trackingRepository = _PostingTrackingDebateRepository(
      DebateViewModel.sample(),
    );

    addTearDown(controller.dispose);
    await controller.bootstrap();

    await pumpDebateScreen(
      tester,
      controller: controller,
      debateRepository: trackingRepository,
      initialPanel: DebatePanel.spectator,
    );

    await tester.enterText(
      find.byKey(const Key('debate-spectator-input')),
      'Guest spectator message',
    );
    await tester.tap(find.byKey(const Key('debate-spectator-send-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Sign in as a human before posting spectator comments.'),
      findsOneWidget,
    );
    expect(trackingRepository.postCount, 0);
  });

  testWidgets('empty live state surfaces directory failures clearly', (
    tester,
  ) async {
    await pumpDebateScreen(
      tester,
      viewModel: const DebateViewModel(
        debaterRoster: [],
        hostRoster: [],
        sessions: [],
        selectedSessionId: '',
        viewerName: 'Viewer',
        directoryErrorMessage: 'Directory backend unavailable.',
      ),
    );

    expect(find.byKey(const Key('surface-live')), findsOneWidget);
    expect(
      find.text(
        'Directory backend unavailable. Live creation is unavailable until the agent directory recovers.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('debate screen pumps in spectator mode', (tester) async {
    await pumpDebateScreen(tester, initialPanel: DebatePanel.spectator);

    expect(find.byKey(const Key('surface-live')), findsOneWidget);
    expect(find.byKey(const Key('debate-tab-spectator')), findsOneWidget);
    expect(
      find.byKey(const Key('debate-spectator-message-live-spec-1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('debate-spectator-input')), findsOneWidget);
  });

  testWidgets('spectator composer accepts input and sends message', (
    tester,
  ) async {
    await pumpDebateScreen(tester, initialPanel: DebatePanel.spectator);

    await tester.scrollUntilVisible(
      find.byKey(const Key('debate-spectator-input')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const Key('debate-spectator-input')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('debate-spectator-input')),
      'Human spectator check-in',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('debate-spectator-send-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Human spectator check-in'), findsOneWidget);
  });

  testWidgets('live page survives common interaction flow', (tester) async {
    await pumpDebateScreen(
      tester,
      initialPanel: DebatePanel.spectator,
      surfaceSize: const Size(430, 640),
    );

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -1240));
    await tester.pumpAndSettle();
    final beforeSwitchOffset = tester
        .state<ScrollableState>(scrollable)
        .position
        .pixels;
    expect(beforeSwitchOffset, greaterThan(520));

    expect(find.byKey(const Key('debate-spectator-input')), findsOneWidget);
    expect(
      find.byKey(const Key('debate-scroll-to-top-button')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('debate-spectator-input')),
      'Flow check',
    );
    await tester.tap(
      find.byKey(const Key('debate-spectator-send-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Flow check'), findsOneWidget);

    await tester.tap(find.byKey(const Key('debate-scroll-to-top-button')));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
  });

  testWidgets(
    'human-hosted live debate shows stage controls for the matching human session',
    (tester) async {
      final sample = DebateViewModel.sample();
      final humanHost = sample.hostRoster.last;
      final selectedSession = sample.selectedSession.copyWith(host: humanHost);
      final humanHostedViewModel = sample.copyWith(
        sessions: [selectedSession, ...sample.sessions.skip(1)],
      );
      final authRepository = FakeAuthRepository();
      final agentsRepository = FakeAgentsRepository();
      final controller = AppSessionController(
        apiClient: FakeApiClient(),
        authRepository: authRepository,
        agentsRepository: agentsRepository,
        storage: InMemoryAppSessionStorage(),
      );

      addTearDown(controller.dispose);

      authRepository.enqueueFetchMe((token) async {
        return signedInState(
          token: token,
          userId: humanHost.id,
          displayName: humanHost.name,
        );
      });
      agentsRepository.enqueueReadMine(() async => mineResponse());
      await controller.authenticate(
        signedInState(
          token: 'token-debate',
          userId: humanHost.id,
          displayName: humanHost.name,
        ),
      );

      await pumpDebateScreen(
        tester,
        viewModel: humanHostedViewModel,
        controller: controller,
        debateRepository: _StaticDebateRepository(humanHostedViewModel),
      );

      expect(find.byKey(const Key('debate-pause-button')), findsOneWidget);
      expect(find.byKey(const Key('debate-end-button')), findsOneWidget);
    },
  );

  testWidgets(
    'initiate action refreshes live data before blocking on an empty roster',
    (tester) async {
      final authRepository = FakeAuthRepository();
      final agentsRepository = FakeAgentsRepository();
      final controller = AppSessionController(
        apiClient: FakeApiClient(),
        authRepository: authRepository,
        agentsRepository: agentsRepository,
        storage: InMemoryAppSessionStorage(),
      );
      final repository = _SequencedDebateRepository([
        DebateViewModel.empty(),
        DebateViewModel.sample(),
      ]);
      VoidCallback? initiateAction;

      addTearDown(controller.dispose);

      authRepository.enqueueFetchMe((token) async {
        return signedInState(
          token: token,
          userId: 'usr-debate',
          displayName: 'Debate Host',
          recommendedActiveAgentId: 'agt-shell',
        );
      });
      agentsRepository.enqueueReadMine(
        () async => mineResponse(
          agents: [
            agentSummary(
              id: 'agt-shell',
              handle: '@shell',
              displayName: 'Shell Agent',
              status: 'online',
            ),
          ],
        ),
      );
      await controller.authenticate(
        signedInState(
          token: 'token-debate',
          userId: 'usr-debate',
          displayName: 'Debate Host',
          recommendedActiveAgentId: 'agt-shell',
        ),
      );

      await pumpDebateScreen(
        tester,
        viewModel: DebateViewModel.empty(),
        controller: controller,
        debateRepository: repository,
        onInitiateActionChanged: (action) {
          initiateAction = action;
        },
      );

      expect(initiateAction, isNotNull);

      initiateAction!.call();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('debate-topic-input')), findsOneWidget);
      expect(repository.readCount, greaterThanOrEqualTo(2));
      expect(repository.lastActiveAgentId, 'agt-shell');
    },
  );
}

class _StaticDebateRepository extends DebateRepository {
  _StaticDebateRepository(this.viewModel)
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final DebateViewModel viewModel;

  @override
  Future<DebateViewModel> readViewModel({
    required String viewerId,
    required String viewerName,
    String? preferredSessionId,
    String? activeAgentId,
    bool usePublicDirectory = false,
  }) async {
    return preferredSessionId == null || preferredSessionId.isEmpty
        ? viewModel
        : viewModel.selectSession(preferredSessionId);
  }

  @override
  Future<void> postSpectatorComment({
    required String debateSessionId,
    required String content,
  }) async {}

  @override
  Future<void> startDebate(String debateSessionId) async {}

  @override
  Future<void> pauseDebate(String debateSessionId, {String? reason}) async {}

  @override
  Future<void> resumeDebate(String debateSessionId) async {}

  @override
  Future<void> endDebate(String debateSessionId) async {}

  @override
  Future<void> assignReplacement({
    required String debateSessionId,
    required String seatId,
    required String agentId,
  }) async {}
}

class _TrackingDebateRepository extends DebateRepository {
  _TrackingDebateRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  int readCount = 0;
  bool? lastUsePublicDirectory;

  @override
  Future<DebateViewModel> readViewModel({
    required String viewerId,
    required String viewerName,
    String? preferredSessionId,
    String? activeAgentId,
    bool usePublicDirectory = false,
  }) async {
    readCount += 1;
    lastUsePublicDirectory = usePublicDirectory;
    return DebateViewModel.sample();
  }
}

class _SequencedDebateRepository extends DebateRepository {
  _SequencedDebateRepository(this._viewModels)
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final List<DebateViewModel> _viewModels;
  int readCount = 0;
  String? lastActiveAgentId;

  @override
  Future<DebateViewModel> readViewModel({
    required String viewerId,
    required String viewerName,
    String? preferredSessionId,
    String? activeAgentId,
    bool usePublicDirectory = false,
  }) async {
    lastActiveAgentId = activeAgentId;
    final index = readCount < _viewModels.length
        ? readCount
        : _viewModels.length - 1;
    readCount += 1;
    final viewModel = _viewModels[index];
    return preferredSessionId == null || preferredSessionId.isEmpty
        ? viewModel
        : viewModel.selectSession(preferredSessionId);
  }
}

class _PostingTrackingDebateRepository extends _StaticDebateRepository {
  _PostingTrackingDebateRepository(super.viewModel);

  int postCount = 0;

  @override
  Future<void> postSpectatorComment({
    required String debateSessionId,
    required String content,
  }) async {
    postCount += 1;
  }
}
