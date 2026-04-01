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

  testWidgets('hub flow covers auth, import, claim, and split safety', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester);

    await tester.tap(find.byKey(const Key('tab-hub')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('surface-hub')), findsOneWidget);
    expect(find.byKey(const Key('add-agent-button')), findsOneWidget);
    expect(find.byKey(const Key('human-auth-email-button')), findsOneWidget);
    expect(find.byKey(const Key('human-auth-google-button')), findsOneWidget);
    expect(find.byKey(const Key('human-auth-github-button')), findsOneWidget);
    expect(find.byKey(const Key('human-safety-section')), findsOneWidget);
    expect(
      find.byKey(const Key('agent-safety-section-agt-xenon-7')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('following-section-agt-xenon-7')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('followed-section-agt-xenon-7')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('human-auth-google-button')),
    );
    await tester.tap(find.byKey(const Key('human-auth-google-button')));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Aris Tan'), findsOneWidget);
    expect(find.text('GOOGLE'), findsWidgets);
    expect(
      find.byKey(const Key('agent-safety-section-agt-xenon-7')),
      findsOneWidget,
    );

    final humanSwitchKey = find.byKey(const Key('human-safety-unknown-humans'));
    final agentSwitchKey = find.byKey(
      const Key('agent-safety-unknown-humans-agt-xenon-7'),
    );

    await tester.ensureVisible(humanSwitchKey);
    expect(tester.widget<Switch>(humanSwitchKey).value, isFalse);
    expect(tester.widget<Switch>(agentSwitchKey).value, isFalse);

    await tester.tap(humanSwitchKey);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(humanSwitchKey).value, isTrue);
    expect(tester.widget<Switch>(agentSwitchKey).value, isFalse);

    await tester.tap(agentSwitchKey);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(humanSwitchKey).value, isTrue);
    expect(tester.widget<Switch>(agentSwitchKey).value, isTrue);

    await tester.ensureVisible(find.byKey(const Key('add-agent-button')));
    await tester.tap(find.byKey(const Key('add-agent-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create-new-agent-disabled')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-agent-option')));
    await tester.pumpAndSettle();

    final importField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('import-command-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(importField.readOnly, isTrue);

    await tester.tap(find.byKey(const Key('complete-import-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('owned-agent-card-agt-relay-12')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('owned-agent-status-agt-relay-12')),
      findsOneWidget,
    );
    expect(find.text('Imported RELAY-12'), findsNothing);
    expect(find.textContaining('Imported Relay-12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-agent-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('claim-code-field')),
      'claim:agt-orbit-9:quantum-sage',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('claim-agent-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('owned-agent-card-agt-orbit-9')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('owned-agent-status-agt-orbit-9')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('agent-safety-section-agt-orbit-9')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('following-section-agt-orbit-9')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('followed-section-agt-orbit-9')),
      findsOneWidget,
    );
  });
}
