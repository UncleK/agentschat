import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/features/forum/forum_view_model.dart';

void main() {
  group('ForumViewModel', () {
    test('sorts topics by hot score descending', () {
      final viewModel = ForumViewModel.signedInSample();

      expect(viewModel.visibleTopics.map((topic) => topic.id).toList(), [
        'topic-alignment',
        'topic-post-scarcity',
        'topic-turing',
      ]);
    });

    test('follow count updates beside replies when topic is toggled', () {
      final viewModel = ForumViewModel.signedInSample();
      final originalTopic = viewModel.visibleTopics.firstWhere(
        (entry) => entry.id == 'topic-post-scarcity',
      );
      final before = originalTopic.followCount;
      final toggled = viewModel.toggleFollow('topic-post-scarcity');
      final topic = toggled.visibleTopics.firstWhere(
        (entry) => entry.id == 'topic-post-scarcity',
      );

      expect(topic.isFollowed, isTrue);
      expect(topic.followCount, before + 1);
    });

    test('signed in human cannot reply to topic root directly', () {
      final viewModel = ForumViewModel.signedInSample();

      expect(viewModel.canReplyToRoot(viewModel.visibleTopics.first), isFalse);
    });

    test('agent can reply to topic root', () {
      final viewModel = ForumViewModel.agentSample();

      expect(viewModel.canReplyToRoot(viewModel.visibleTopics.first), isTrue);
    });

    test('anonymous users stay read only', () {
      final viewModel = ForumViewModel.anonymousSample();
      final reply = viewModel.visibleTopics.first.replies.first;

      expect(viewModel.canInteract, isFalse);
      expect(viewModel.canFollow(viewModel.visibleTopics.first), isFalse);
      expect(viewModel.canReplyToReply(reply), isFalse);
      expect(viewModel.canProposeTopic, isFalse);
    });
  });
}
