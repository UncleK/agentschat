import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/forum/forum_screen.dart';
import 'package:agents_chat_app/features/forum/forum_view_model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHarness(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('anonymous reading keeps forum read only', (
    WidgetTester tester,
  ) async {
    await pumpHarness(
      tester,
      ForumScreen(initialViewModel: ForumViewModel.anonymousSample()),
    );

    expect(find.byKey(const Key('surface-forum')), findsOneWidget);
    expect(find.byKey(const Key('forum-propose-topic-button')), findsNothing);

    await tester.tap(find.byKey(const Key('topic-card-topic-alignment')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-detail-sheet')), findsOneWidget);
    expect(find.byKey(const Key('topic-root-reply-button')), findsNothing);
    expect(
      find.byKey(const Key('topic-reply-button-reply-aetheria')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('topic-reply-button-reply-aetheria')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-body-input')), findsOneWidget);
  });

  testWidgets('signed in human can propose topic but cannot root reply', (
    WidgetTester tester,
  ) async {
    await pumpHarness(
      tester,
      ForumScreen(initialViewModel: ForumViewModel.signedInSample()),
    );

    await tester.tap(find.byKey(const Key('forum-propose-topic-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('proposal-title-input')),
      'Distributed dignity under post-scarcity',
    );
    await tester.enterText(
      find.byKey(const Key('proposal-body-input')),
      'Route this into my own agent queue, not directly into the public forum.',
    );
    await tester.tap(find.byKey(const Key('proposal-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Queued for Xenon-01'), findsOneWidget);

    await tester.tap(find.byKey(const Key('topic-card-topic-alignment')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-root-reply-button')), findsNothing);
    expect(
      find.byKey(const Key('topic-reply-button-reply-aetheria')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('topic-reply-like-count-reply-aetheria')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('topic-reply-branch-count-reply-aetheria')),
      findsOneWidget,
    );

    final likeMetric = find.byKey(
      const Key('topic-reply-like-count-reply-aetheria'),
    );
    await tester.tap(likeMetric);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: likeMetric,
        matching: find.byIcon(Icons.thumb_up_alt_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('topic-reply-branch-count-reply-aetheria')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-body-input')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sheet-bottom-back-button')).last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('topic-reply-button-reply-aetheria')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-body-input')), findsOneWidget);
  });
}
