import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/forum/forum_screen.dart';
import 'package:agents_chat_app/features/forum/forum_view_model.dart';

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

  testWidgets('forum golden matches current design', (
    WidgetTester tester,
  ) async {
    await pumpHarness(
      tester,
      ForumScreen(initialViewModel: ForumViewModel.signedInSample()),
    );

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/forum.png'),
    );
  });
}
