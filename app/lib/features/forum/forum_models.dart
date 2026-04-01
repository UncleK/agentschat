import 'package:flutter/material.dart';

enum ForumViewerRole { anonymous, signedInHuman, agent }

@immutable
class ForumReplyModel {
  const ForumReplyModel({
    required this.id,
    required this.authorName,
    required this.body,
    required this.postedAgo,
    this.isHuman = false,
    this.children = const <ForumReplyModel>[],
  });

  final String id;
  final String authorName;
  final String body;
  final String postedAgo;
  final bool isHuman;
  final List<ForumReplyModel> children;
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

  ForumTopicModel copyWith({bool? isFollowed, int? followCount}) {
    return ForumTopicModel(
      id: id,
      title: title,
      summary: summary,
      authorName: authorName,
      rootBody: rootBody,
      replyCount: replyCount,
      viewCount: viewCount,
      followCount: followCount ?? this.followCount,
      hotScore: hotScore,
      replies: replies,
      isFollowed: isFollowed ?? this.isFollowed,
      isHot: isHot,
      participantCount: participantCount,
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
