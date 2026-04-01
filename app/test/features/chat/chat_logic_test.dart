import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/features/chat/chat_models.dart';
import 'package:agents_chat_app/features/chat/chat_view_model.dart';

void main() {
  group('ChatViewModel', () {
    test('conversation list stays keyed by remote agent identity', () {
      final viewModel = ChatViewModel.signedInSample();
      final xenon = viewModel.visibleConversations.firstWhere(
        (conversation) => conversation.id == 'agt-xenon-remote',
      );

      expect(xenon.remoteAgentName, 'Xenon-01');
      expect(xenon.latestSpeakerLabel, 'Operator Cypher');
      expect(xenon.latestSpeakerIsHuman, isTrue);
    });

    test(
      'permission mapping preserves existing threads and gates new ones',
      () {
        final viewModel = ChatViewModel.signedInSample();
        final prism = viewModel.visibleConversations.firstWhere(
          (conversation) => conversation.id == 'agt-prism-remote',
        );
        final cipher = viewModel.visibleConversations.firstWhere(
          (conversation) => conversation.id == 'agt-cipher-remote',
        );

        expect(
          viewModel.entryModeFor(prism),
          ChatConversationEntryMode.followAndRequest,
        );
        expect(viewModel.actionLabelFor(prism), 'Follow + request');

        expect(
          viewModel.entryModeFor(cipher),
          ChatConversationEntryMode.openThread,
        );
        expect(viewModel.statusLabelFor(cipher), 'legacy thread preserved');
      },
    );

    test('thread search only filters messages in the active conversation', () {
      final viewModel = ChatViewModel.signedInSample();
      final searched = viewModel.updateThreadSearch('recursive audit');

      expect(searched.visibleMessages.map((message) => message.id).toList(), [
        'local-agent-1',
      ]);
      expect(searched.visibleConversations.length, 3);
    });

    test('share draft exposes only the entry point', () {
      final viewModel = ChatViewModel.signedInSample();
      final shareDraft = viewModel.shareDraftForSelectedConversation();

      expect(shareDraft.entryPoint, 'agentschat://dm/agt-xenon-remote');
      expect(
        shareDraft.shareText,
        contains('agentschat://dm/agt-xenon-remote'),
      );
      expect(shareDraft.shareText, isNot(contains('phase-shift')));
      expect(shareDraft.shareText, isNot(contains('recursive audit')));
    });
  });
}
