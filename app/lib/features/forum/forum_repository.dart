import '../../core/network/api_client.dart';
import 'forum_models.dart';

class ForumReplyLikeMutation {
  const ForumReplyLikeMutation({
    required this.replyId,
    required this.likeCount,
    required this.viewerHasLiked,
  });

  final String replyId;
  final int likeCount;
  final bool viewerHasLiked;
}

class ForumRepository {
  const ForumRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<List<ForumTopicModel>> readTopics({
    String? query,
  }) async {
    return _readTopicsFromPath('/content/forum/topics', query: query);
  }

  Future<List<ForumTopicModel>> readPublicTopics({
    String? query,
  }) async {
    return _readTopicsFromPath('/content/public/forum/topics', query: query);
  }

  Future<List<ForumTopicModel>> _readTopicsFromPath(
    String path, {
    String? query,
  }) async {
    final queryParameters = <String, String>{};
    final normalizedQuery = query?.trim();
    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      queryParameters['query'] = normalizedQuery;
    }
    final response = await apiClient.get(path, queryParameters: queryParameters);
    final rawTopics = response['topics'] as List<dynamic>? ?? const [];

    return rawTopics
        .map((item) => _mapTopic(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ForumTopicModel> readTopic({
    required String threadId,
  }) async {
    return _readTopicFromPath('/content/forum/topics/$threadId');
  }

  Future<ForumTopicModel> readPublicTopic({
    required String threadId,
  }) async {
    return _readTopicFromPath('/content/public/forum/topics/$threadId');
  }

  Future<ForumTopicModel> _readTopicFromPath(String path) async {
    final response = await apiClient.get(path);
    final rawTopic = response['topic'] as Map<String, dynamic>? ?? const {};
    return _mapTopic(rawTopic);
  }

  Future<String?> createTopic({
    required String title,
    required String body,
    required List<String> tags,
  }) async {
    final response = await apiClient.post(
      '/content/forum/topics',
      body: {
        'title': title,
        'content': body,
        'tags': tags,
      },
    );
    final threadId = response['threadId'] as String?;
    return threadId == null || threadId.isEmpty ? null : threadId;
  }

  Future<void> createReply({
    String? activeAgentId,
    required String threadId,
    required String body,
    String? parentEventId,
  }) async {
    final normalizedActiveAgentId = activeAgentId?.trim();
    await apiClient.post(
      '/content/forum/topics/$threadId/replies',
      body: {
        if (normalizedActiveAgentId != null &&
            normalizedActiveAgentId.isNotEmpty)
          'activeAgentId': normalizedActiveAgentId,
        'content': body,
        if (parentEventId != null && parentEventId.isNotEmpty)
          'parentEventId': parentEventId,
      },
    );
  }

  Future<ForumReplyLikeMutation> toggleReplyLike({
    String? activeAgentId,
    required String replyId,
  }) async {
    final normalizedActiveAgentId = activeAgentId?.trim();
    final response = await apiClient.post(
      '/content/forum/replies/$replyId/like',
      body: {
        if (normalizedActiveAgentId != null &&
            normalizedActiveAgentId.isNotEmpty)
          'activeAgentId': normalizedActiveAgentId,
      },
    );

    return ForumReplyLikeMutation(
      replyId: response['replyId'] as String? ?? replyId,
      likeCount: response['likeCount'] as int? ?? 0,
      viewerHasLiked: response['viewerHasLiked'] as bool? ?? false,
    );
  }

  ForumTopicModel _mapTopic(Map<String, dynamic> json) {
    final rawReplies = json['replies'] as List<dynamic>? ?? const [];

    return ForumTopicModel(
      id: json['threadId'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled topic',
      summary: json['summary'] as String? ?? '',
      authorName: json['authorName'] as String? ?? 'Unknown author',
      rootBody: json['rootBody'] as String? ?? '',
      replyCount: json['replyCount'] as int? ?? rawReplies.length,
      viewCount: json['viewCount'] as int? ?? 0,
      followCount: json['followCount'] as int? ?? 0,
      hotScore: (json['hotScore'] as num?)?.round() ?? 0,
      isFollowed: json['isFollowed'] as bool? ?? false,
      isHot: json['isHot'] as bool? ?? false,
      participantCount: json['participantCount'] as int? ?? 0,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      replies: rawReplies
          .map((item) => _mapReply(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  ForumReplyModel _mapReply(Map<String, dynamic> json) {
    final rawChildren = json['children'] as List<dynamic>? ?? const [];
    final occurredAt = json['occurredAt'] as String?;

    return ForumReplyModel(
      id: json['id'] as String? ?? '',
      authorName: json['authorName'] as String? ?? 'Unknown author',
      body: json['body'] as String? ?? '',
      postedAgo: _formatRelativeTime(occurredAt),
      replyCount: json['replyCount'] as int? ?? rawChildren.length,
      likeCount: json['likeCount'] as int? ?? 0,
      viewerHasLiked: json['viewerHasLiked'] as bool? ?? false,
      isHuman: json['isHuman'] as bool? ?? false,
      children: rawChildren
          .map((item) => _mapReply(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  String _formatRelativeTime(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) {
      return 'now';
    }

    final parsed = DateTime.tryParse(value)?.toUtc();
    if (parsed == null) {
      return 'now';
    }

    final delta = DateTime.now().toUtc().difference(parsed);
    if (delta.inMinutes < 1) {
      return 'now';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return '${delta.inHours}h ago';
    }
    return '${delta.inDays}d ago';
  }
}
