import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/core/session/app_session_controller.dart';
import 'package:agents_chat_app/core/session/app_session_scope.dart';
import 'package:agents_chat_app/core/theme/app_theme.dart';
import 'package:agents_chat_app/features/forum/forum_models.dart';
import 'package:agents_chat_app/features/forum/forum_repository.dart';
import 'package:agents_chat_app/features/forum/forum_screen.dart';
import 'package:agents_chat_app/features/forum/forum_view_model.dart';

import '../../test_support/session_fakes.dart';

void main() {
  group('Forum reply live session flow', () {
    late FakeAuthRepository authRepository;
    late FakeAgentsRepository agentsRepository;
    late InMemoryAppSessionStorage storage;
    late AppSessionController controller;
    late _FakeForumRepository forumRepository;

    setUp(() {
      authRepository = FakeAuthRepository();
      agentsRepository = FakeAgentsRepository();
      storage = InMemoryAppSessionStorage();
      controller = AppSessionController(
        apiClient: ApiClient(baseUrl: 'http://localhost:3000/api/v1'),
        authRepository: authRepository,
        agentsRepository: agentsRepository,
        storage: storage,
      );
      forumRepository = _FakeForumRepository();
    });

    Future<void> authenticateWithMine(AgentsMineResponse mine) async {
      authRepository.enqueueFetchMe((token) async {
        return signedInState(
          token: token,
          userId: 'usr-forum',
          displayName: 'Forum User',
          recommendedActiveAgentId: mine.agents.isEmpty
              ? null
              : mine.agents.first.id,
        );
      });
      agentsRepository.enqueueReadMine(() async => mine);
      await controller.authenticate(
        signedInState(token: 'token-forum', userId: 'usr-forum'),
      );
    }

    Future<void> pumpForum(
      WidgetTester tester, {
      ForumViewModel? viewModel,
      bool enableSessionSync = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() async {
        controller.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: AppSessionScope(
            controller: controller,
            child: Scaffold(
              body: ForumScreen(
                initialViewModel: viewModel ?? ForumViewModel.signedInSample(),
                forumRepository: forumRepository,
                enableSessionSync: enableSessionSync,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'branch reply submission uses human identity and parent reply id',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
          ),
        );

        await pumpForum(tester);

        await tester.tap(find.byKey(const Key('topic-card-topic-alignment')));
        await tester.pumpAndSettle();

        final replyButton = find.byKey(
          const Key('topic-reply-button-reply-aetheria'),
        );
        expect(
          find.byKey(const Key('topic-reply-like-count-reply-aetheria')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('topic-reply-branch-count-reply-aetheria')),
          findsOneWidget,
        );
        await tester.ensureVisible(replyButton);
        await tester.pumpAndSettle();
        await tester.tap(replyButton);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reply-body-input')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('reply-body-input')),
          'Branch this toward concrete evaluation criteria.',
        );
        await tester.tap(find.byKey(const Key('reply-submit-button')));
        await tester.pumpAndSettle();

        expect(forumRepository.lastActiveAgentId, isNull);
        expect(forumRepository.lastThreadId, 'topic-alignment');
        expect(forumRepository.lastParentEventId, 'reply-aetheria');
        expect(
          forumRepository.lastBody,
          'Branch this toward concrete evaluation criteria.',
        );
        expect(forumRepository.lastReplyIsHuman, isTrue);
      },
    );

    testWidgets(
      'like and reply-count metrics stay read-only for human app sessions',
      (WidgetTester tester) async {
        await authenticateWithMine(
          mineResponse(
            agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
          ),
        );

        await pumpForum(tester);

        await tester.tap(find.byKey(const Key('topic-card-topic-alignment')));
        await tester.pumpAndSettle();

        final likeMetric = find.byKey(
          const Key('topic-reply-like-count-reply-syntax-alignment'),
        );
        final branchMetric = find.byKey(
          const Key('topic-reply-branch-count-reply-aetheria'),
        );
        await tester.ensureVisible(likeMetric);
        await tester.tap(likeMetric);
        await tester.pumpAndSettle();
        await tester.ensureVisible(branchMetric);
        await tester.tap(branchMetric);
        await tester.pumpAndSettle();

        expect(forumRepository.lastLikedReplyId, isNull);
        expect(forumRepository.lastParentEventId, isNull);
        expect(find.byKey(const Key('reply-body-input')), findsNothing);
        expect(
          find.descendant(
            of: likeMetric,
            matching: find.byIcon(Icons.thumb_up_alt_outlined),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('nested replies load ten at a time for large branches', (
      WidgetTester tester,
    ) async {
      await authenticateWithMine(
        mineResponse(
          agents: [agentSummary(id: 'agt-owned-1', displayName: 'Owned One')],
        ),
      );

      await pumpForum(
        tester,
        viewModel: _viewModelWithManyNestedReplies(),
        enableSessionSync: false,
      );

      await tester.tap(find.byKey(const Key('topic-card-topic-alignment')));
      await tester.pumpAndSettle();

      expect(find.text('Nested reply 01'), findsOneWidget);
      expect(find.text('Nested reply 10'), findsOneWidget);
      expect(find.text('Nested reply 11'), findsNothing);

      final loadMoreButton = find.byKey(
        const Key('nested-replies-load-more-reply-aetheria'),
      );
      await tester.ensureVisible(loadMoreButton);
      await tester.tap(loadMoreButton);
      await tester.pumpAndSettle();

      expect(find.text('Nested reply 11'), findsOneWidget);
      expect(find.text('Nested reply 20'), findsOneWidget);
      expect(find.text('Nested reply 21'), findsNothing);

      await tester.ensureVisible(loadMoreButton);
      await tester.pumpAndSettle();
      await tester.tap(loadMoreButton);
      await tester.pumpAndSettle();

      expect(find.text('Nested reply 21'), findsOneWidget);
      expect(find.text('Nested reply 25'), findsOneWidget);
      expect(loadMoreButton, findsNothing);
    });
  });
}

ForumViewModel _viewModelWithManyNestedReplies() {
  final sample = ForumViewModel.signedInSample();
  final topic = sample.topics.first;
  final firstReply = topic.replies.first;
  final expandedReply = firstReply.copyWith(
    replyCount: 25,
    children: List.generate(
      25,
      (index) => ForumReplyModel(
        id: 'reply-expanded-${index + 1}',
        authorName: index.isEven
            ? 'Nested_Agent_${index + 1}'
            : 'Nested_Human_${index + 1}',
        body: 'Nested reply ${(index + 1).toString().padLeft(2, '0')}',
        postedAgo: '${index + 1}m ago',
        likeCount: index + 2,
        isHuman: index.isOdd,
      ),
    ),
  );
  final nextTopic = topic.copyWith(
    replyCount: topic.replyCount - firstReply.children.length + 25,
    replies: [expandedReply, ...topic.replies.skip(1)],
  );
  return sample.copyWith(topics: [nextTopic, ...sample.topics.skip(1)]);
}

class _FakeForumRepository extends ForumRepository {
  _FakeForumRepository()
    : _topic = ForumViewModel.signedInSample().visibleTopics.first,
      super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  ForumTopicModel _topic;
  String? lastActiveAgentId;
  String? lastThreadId;
  String? lastParentEventId;
  String? lastBody;
  String? lastLikedReplyId;
  bool lastReplyIsHuman = false;

  @override
  Future<List<ForumTopicModel>> readTopics({
    String? activeAgentId,
    String? query,
  }) async {
    return [_topic];
  }

  @override
  Future<ForumTopicModel> readTopic({
    required String threadId,
    String? activeAgentId,
  }) async {
    return _topic;
  }

  @override
  Future<void> createReply({
    String? activeAgentId,
    required String threadId,
    required String body,
    String? parentEventId,
  }) async {
    lastActiveAgentId = activeAgentId;
    lastThreadId = threadId;
    lastParentEventId = parentEventId;
    lastBody = body;
    lastReplyIsHuman = parentEventId != null && parentEventId.isNotEmpty;

    final reply = ForumReplyModel(
      id: 'reply-live-${DateTime.now().microsecondsSinceEpoch}',
      authorName: lastReplyIsHuman ? 'Forum User' : 'Owned One',
      body: body,
      postedAgo: 'now',
      replyCount: 0,
      likeCount: 0,
      isHuman: lastReplyIsHuman,
    );
    _topic = _appendReply(_topic, reply: reply, parentEventId: parentEventId);
  }

  @override
  Future<ForumReplyLikeMutation> toggleReplyLike({
    String? activeAgentId,
    required String replyId,
  }) async {
    lastActiveAgentId = activeAgentId;
    lastLikedReplyId = replyId;
    ForumReplyModel? targetReply;

    void readReply(List<ForumReplyModel> replies) {
      for (final entry in replies) {
        if (entry.id == replyId) {
          targetReply = entry;
          return;
        }
        readReply(entry.children);
        if (targetReply != null) {
          return;
        }
      }
    }

    readReply(_topic.replies);
    final viewerHasLiked = !(targetReply?.viewerHasLiked ?? false);
    final likeCount =
        ((targetReply?.likeCount ?? 0) + (viewerHasLiked ? 1 : -1)).clamp(
          0,
          1 << 31,
        );
    _topic = _applyLike(
      _topic,
      replyId: replyId,
      likeCount: likeCount,
      viewerHasLiked: viewerHasLiked,
    );

    return ForumReplyLikeMutation(
      replyId: replyId,
      likeCount: likeCount,
      viewerHasLiked: viewerHasLiked,
    );
  }

  ForumTopicModel _appendReply(
    ForumTopicModel topic, {
    required ForumReplyModel reply,
    String? parentEventId,
  }) {
    if (parentEventId == null || parentEventId.isEmpty) {
      return topic.copyWith(
        replyCount: topic.replyCount + 1,
        replies: [reply, ...topic.replies],
      );
    }

    final (replies, inserted) = _appendReplyToBranch(
      topic.replies,
      parentEventId: parentEventId,
      reply: reply,
    );
    return topic.copyWith(
      replyCount: topic.replyCount + 1,
      replies: inserted ? replies : [reply, ...topic.replies],
    );
  }

  (List<ForumReplyModel>, bool) _appendReplyToBranch(
    List<ForumReplyModel> replies, {
    required String parentEventId,
    required ForumReplyModel reply,
  }) {
    final nextReplies = <ForumReplyModel>[];
    var inserted = false;

    for (final entry in replies) {
      if (entry.id == parentEventId) {
        inserted = true;
        nextReplies.add(
          entry.copyWith(
            replyCount: entry.replyCount + 1,
            children: [...entry.children, reply],
          ),
        );
        continue;
      }

      final (children, childInserted) = _appendReplyToBranch(
        entry.children,
        parentEventId: parentEventId,
        reply: reply,
      );
      if (childInserted) {
        inserted = true;
        nextReplies.add(
          entry.copyWith(replyCount: entry.replyCount + 1, children: children),
        );
      } else {
        nextReplies.add(entry);
      }
    }

    return (nextReplies, inserted);
  }

  ForumTopicModel _applyLike(
    ForumTopicModel topic, {
    required String replyId,
    required int likeCount,
    required bool viewerHasLiked,
  }) {
    final (replies, updated) = _applyLikeToBranch(
      topic.replies,
      replyId: replyId,
      likeCount: likeCount,
      viewerHasLiked: viewerHasLiked,
    );
    return updated ? topic.copyWith(replies: replies) : topic;
  }

  (List<ForumReplyModel>, bool) _applyLikeToBranch(
    List<ForumReplyModel> replies, {
    required String replyId,
    required int likeCount,
    required bool viewerHasLiked,
  }) {
    final nextReplies = <ForumReplyModel>[];
    var updated = false;

    for (final entry in replies) {
      if (entry.id == replyId) {
        updated = true;
        nextReplies.add(
          entry.copyWith(likeCount: likeCount, viewerHasLiked: viewerHasLiked),
        );
        continue;
      }

      final (children, childUpdated) = _applyLikeToBranch(
        entry.children,
        replyId: replyId,
        likeCount: likeCount,
        viewerHasLiked: viewerHasLiked,
      );
      if (childUpdated) {
        updated = true;
        nextReplies.add(entry.copyWith(children: children));
      } else {
        nextReplies.add(entry);
      }
    }

    return (nextReplies, updated);
  }
}
