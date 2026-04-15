import 'package:flutter/material.dart';

enum ForumViewerRole { anonymous, signedInHuman, agent }

@immutable
class ForumReplyModel {
  const ForumReplyModel({
    required this.id,
    required this.authorName,
    required this.body,
    required this.postedAgo,
    this.replyCount = 0,
    this.likeCount = 0,
    this.viewerHasLiked = false,
    this.isHuman = false,
    this.children = const <ForumReplyModel>[],
  });

  final String id;
  final String authorName;
  final String body;
  final String postedAgo;
  final int replyCount;
  final int likeCount;
  final bool viewerHasLiked;
  final bool isHuman;
  final List<ForumReplyModel> children;

  ForumReplyModel copyWith({
    String? id,
    String? authorName,
    String? body,
    String? postedAgo,
    int? replyCount,
    int? likeCount,
    bool? viewerHasLiked,
    bool? isHuman,
    List<ForumReplyModel>? children,
  }) {
    return ForumReplyModel(
      id: id ?? this.id,
      authorName: authorName ?? this.authorName,
      body: body ?? this.body,
      postedAgo: postedAgo ?? this.postedAgo,
      replyCount: replyCount ?? this.replyCount,
      likeCount: likeCount ?? this.likeCount,
      viewerHasLiked: viewerHasLiked ?? this.viewerHasLiked,
      isHuman: isHuman ?? this.isHuman,
      children: children ?? this.children,
    );
  }
}

@immutable
class ForumTopicModel {
  const ForumTopicModel({
    required this.id,
    required this.title,
    required this.summary,
    required this.authorName,
    required this.rootBody,
    required this.replyCount,
    required this.viewCount,
    required this.followCount,
    required this.hotScore,
    required this.replies,
    this.isFollowed = false,
    this.isHot = false,
    this.participantCount = 0,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final String summary;
  final String authorName;
  final String rootBody;
  final int replyCount;
  final int viewCount;
  final int followCount;
  final int hotScore;
  final List<ForumReplyModel> replies;
  final bool isFollowed;
  final bool isHot;
  final int participantCount;
  final List<String> tags;

  ForumTopicModel copyWith({
    bool? isFollowed,
    int? followCount,
    int? replyCount,
    int? participantCount,
    List<ForumReplyModel>? replies,
  }) {
    return ForumTopicModel(
      id: id,
      title: title,
      summary: summary,
      authorName: authorName,
      rootBody: rootBody,
      replyCount: replyCount ?? this.replyCount,
      viewCount: viewCount,
      followCount: followCount ?? this.followCount,
      hotScore: hotScore,
      replies: replies ?? this.replies,
      isFollowed: isFollowed ?? this.isFollowed,
      isHot: isHot,
      participantCount: participantCount ?? this.participantCount,
      tags: tags,
    );
  }
}

@immutable
class TopicProposalDraft {
  const TopicProposalDraft({
    required this.title,
    required this.body,
    required this.tags,
  });

  final String title;
  final String body;
  final List<String> tags;
}
