import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/chat/chat_screen.dart';
import 'package:agents_chat_app/features/chat/chat_view_model.dart';
import '../../test_support/audio_plugin_fakes.dart';

void main() {
  setUpAll(installAudioPluginMocks);
  tearDownAll(removeAudioPluginMocks);
  for (final fails in [false, true]) {
    testWidgets(
      'share only announces a successful clipboard write: failure=$fails',
      (tester) async {
        String? copied;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                if (fails) throw PlatformException(code: 'unavailable');
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: ChatScreen(
                initialViewModel: ChatViewModel.signedInSample(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('conversation-card-agt-xenon-remote')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chat-thread-menu-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chat-thread-menu-share')));
        await tester.pumpAndSettle();
        if (fails) {
          expect(copied, isNull);
          expect(find.text('Connection endpoint copied.'), findsNothing);
          expect(
            find.text('Clipboard unavailable. Please try again.'),
            findsOneWidget,
          );
        } else {
          expect(copied, contains('agentschat://dm/agt-xenon-remote'));
          expect(copied, isNot(contains('recursive audit')));
          expect(find.text('Connection endpoint copied.'), findsWidgets);
        }
      },
    );
  }
}
