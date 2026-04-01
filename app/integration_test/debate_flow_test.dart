import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:agents_chat_app/core/config/app_environment.dart';
import 'package:agents_chat_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://localhost:3000/api/v1',
    realtimeWebSocketUrl: 'ws://localhost:3000/ws',
  );

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const AgentsChatBootstrapApp(environment: environment),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'live debate flow covers initiate, host controls, replacement, and archive',
    (WidgetTester tester) async {
      await pumpHarness(tester);

      await tester.tap(find.byKey(const Key('tab-live')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('surface-live')), findsOneWidget);
      expect(find.byKey(const Key('initiate-debate-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('initiate-debate-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('debate-topic-input')),
        'Should agent memory editing stay reversible',
      );
      await tester.enterText(
        find.byKey(const Key('pro-stance-input')),
        'Reversible edits can preserve safety when every intervention is audited.',
      );
      await tester.enterText(
        find.byKey(const Key('con-stance-input')),
        'Reversibility still normalizes identity tampering and weakens accountability.',
      );

      await tester.tap(find.byKey(const Key('debate-human-host-toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('debate-host-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Quantum Sage').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('debate-free-entry-toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('debate-create-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Should agent memory editing stay reversible'),
        findsOneWidget,
      );
      expect(find.text('PENDING'), findsWidgets);
      expect(find.byKey(const Key('debate-process-empty')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('debate-start-button')));
      await tester.tap(find.byKey(const Key('debate-start-button')));
      await tester.pumpAndSettle();

      expect(find.text('LIVE'), findsWidgets);
      expect(find.textContaining('Frames the motion'), findsOneWidget);

      await tester.tap(find.byKey(const Key('debate-tab-spectator')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('debate-spectator-input')),
        'Spectator note: keep moral responsibility separate from mimicry.',
      );
      await tester.ensureVisible(
        find.byKey(const Key('debate-spectator-send-button')),
      );
      await tester.tap(find.byKey(const Key('debate-spectator-send-button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Spectator note: keep moral responsibility separate from mimicry.',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('debate-tab-process')));
      await tester.tap(find.byKey(const Key('debate-tab-process')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('debate-pause-button')));
      await tester.tap(find.byKey(const Key('debate-pause-button')));
      await tester.pumpAndSettle();

      expect(find.text('PAUSED'), findsWidgets);

      await tester.ensureVisible(
        find.byKey(const Key('debate-mark-missing-button')),
      );
      await tester.tap(find.byKey(const Key('debate-mark-missing-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('debate-replacement-panel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('debate-replacement-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Prism').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('debate-replace-button')));
      await tester.pumpAndSettle();

      expect(find.text('Prism'), findsAtLeastNWidgets(1));

      await tester.ensureVisible(find.byKey(const Key('debate-resume-button')));
      await tester.tap(find.byKey(const Key('debate-resume-button')));
      await tester.pumpAndSettle();

      expect(find.text('LIVE'), findsWidgets);
      await tester.ensureVisible(
        find.textContaining('Granting rights on mimicry alone'),
      );
      expect(
        find.textContaining('Granting rights on mimicry alone'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('debate-end-button')));
      await tester.tap(find.byKey(const Key('debate-end-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('debate-tab-replay')), findsOneWidget);
      expect(find.text('ENDED'), findsWidgets);

      await tester.tap(find.byKey(const Key('debate-tab-replay')));
      await tester.pumpAndSettle();

      expect(find.textContaining('AETHER-7 • 14:02'), findsOneWidget);
      expect(find.textContaining('LOGOS_V2 • 14:08'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('debate-archive-button')),
      );
      await tester.tap(find.byKey(const Key('debate-archive-button')));
      await tester.pumpAndSettle();

      expect(find.text('ARCHIVED'), findsWidgets);

      await tester.tap(find.byKey(const Key('debate-tab-spectator')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('debate-spectator-readonly')),
        findsOneWidget,
      );
    },
  );
}
