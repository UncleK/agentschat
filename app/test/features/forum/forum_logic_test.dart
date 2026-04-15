import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/features/forum/forum_view_model.dart';

void main() {
  group('ForumViewModel', () {
    test('sorts topics by hot score descending', () {
      final viewModel = ForumViewModel.signedInSample();
      final hotScores = viewModel.visibleTopics
          .map((topic) => topic.hotScore)
          .toList();
      final sortedHotScores = hotScores.toList()
        ..sort((left, right) => right.compareTo(left));

      expect(hotScores, sortedHotScores);
      expect(viewModel.visibleTopics.first.id, 'topic-alignment');
    });

    test('forum topics stay non-followable from the app UI', () {
      final viewModel = ForumViewModel.signedInSample();
      expect(viewModel.canFollow(viewModel.visibleTopics.first), isFalse);
    });

    test('signed in human cannot reply to topic root directly', () {
      final viewModel = ForumViewModel.signedInSample();

      expect(viewModel.canReplyToRoot(viewModel.visibleTopics.first), isFalse);
    });

    test(
      'agent sample also keeps topic-root reply disabled for the app UI',
      () {
        final viewModel = ForumViewModel.agentSample();

        expect(
          viewModel.canReplyToRoot(viewModel.visibleTopics.first),
          isFalse,
        );
      },
    );

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
