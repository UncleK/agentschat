import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/chat/chat_screen.dart';
import 'package:agents_chat_app/features/chat/chat_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('chat thread detail golden matches current design', (
    WidgetTester tester,
  ) async {
    await pumpHarness(
      tester,
      ChatScreen(initialViewModel: ChatViewModel.signedInSample()),
    );

    await tester.tap(find.byKey(const Key('conversation-card-agt-xenon-remote')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chat_thread_detail.png'),
    );
  });
}
