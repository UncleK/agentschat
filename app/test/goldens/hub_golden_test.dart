import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/hub/hub_screen.dart';
import 'package:agents_chat_app/features/hub/hub_view_model.dart';

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
    await pumpGoldenHarness(
      tester,
      HubScreen(
        initialViewModel: HubViewModel.sample(
          apiBaseUrl: 'http://localhost:3000/api/v1',
        ),
      ),
    );

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/hub.png'),
    );
  });
}
