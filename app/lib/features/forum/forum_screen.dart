import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/locale/app_localization_extensions.dart';
import '../../core/network/api_exception.dart';
import '../../core/session/app_session_controller.dart';
import '../../core/session/app_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/page_intro.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/swipe_back_sheet.dart';
import 'forum_models.dart';
import 'forum_repository.dart';
import 'forum_view_model.dart';

typedef ForumReplyLikeToggle =
    Future<ForumTopicModel?> Function({required String replyId});
typedef ForumReplySubmitter =
    Future<ForumTopicModel?> Function({
      String? parentEventId,
      required String body,
    });

class ForumScreen extends StatefulWidget {
  const ForumScreen({
    super.key,
    required this.initialViewModel,
    this.initialTopicId,
    this.topicRequestId = 0,
    this.showInlineProposeButton = true,
    this.onProposeActionChanged,
    this.onSearchActionChanged,
    this.forumRepository,
    this.enableSessionSync = true,
  });

  final ForumViewModel initialViewModel;
  final String? initialTopicId;
  final int topicRequestId;
  final bool showInlineProposeButton;
  final ValueChanged<VoidCallback?>? onProposeActionChanged;
  final ValueChanged<VoidCallback?>? onSearchActionChanged;
  final ForumRepository? forumRepository;
  final bool enableSessionSync;

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  late ForumViewModel _viewModel;
  ForumRepository? _forumRepository;
  String? _sessionSignature;
  bool _isLoadingTopics = false;
  bool _isUsingLiveTopics = false;
  String? _topicsErrorMessage;
  int _topicsRequestId = 0;
  int _handledTopicRequestId = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
    _syncShellProposeAction();
    _syncShellSearchAction();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeHandleInitialTopicRequest());
    });
  }

  @override
  void didUpdateWidget(covariant ForumScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final proposeRegistrationChanged =
        (oldWidget.onProposeActionChanged == null) !=
        (widget.onProposeActionChanged == null);
    if (oldWidget.initialViewModel.viewerRole !=
            widget.initialViewModel.viewerRole ||
        proposeRegistrationChanged) {
      _syncShellProposeAction();
    }
    final searchRegistrationChanged =
        (oldWidget.onSearchActionChanged == null) !=
        (widget.onSearchActionChanged == null);
    if (searchRegistrationChanged) {
      _syncShellSearchAction();
    }
    if (oldWidget.topicRequestId != widget.topicRequestId ||
        oldWidget.initialTopicId != widget.initialTopicId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeHandleInitialTopicRequest());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AppSessionScope.maybeOf(context);
    if (session == null) {
      _forumRepository = widget.forumRepository;
      _sessionSignature = null;
      return;
    }

    _forumRepository =
        widget.forumRepository ?? ForumRepository(apiClient: session.apiClient);

    if (!widget.enableSessionSync) {
      _sessionSignature = null;
      return;
    }

    final nextSignature = [
      session.bootstrapStatus.name,
      session.currentUser?.id ?? '',
      session.currentActiveAgent?.id ?? '',
    ].join('|');
    if (_sessionSignature == nextSignature) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeHandleInitialTopicRequest());
      });
      return;
    }
    _sessionSignature = nextSignature;
    unawaited(_syncTopics(session));
  }

  @override
  void dispose() {
    final onProposeActionChanged = widget.onProposeActionChanged;
    final onSearchActionChanged = widget.onSearchActionChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onProposeActionChanged?.call(null);
      onSearchActionChanged?.call(null);
    });
    super.dispose();
  }

  void _syncShellProposeAction() {
    final action = _viewModel.canProposeTopic ? _openProposalModal : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onProposeActionChanged?.call(action);
    });
  }

  void _syncShellSearchAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onSearchActionChanged?.call(_openSearchSheet);
    });
  }

  Future<void> _maybeHandleInitialTopicRequest() async {
    if (!mounted) {
      return;
    }

    final requestId = widget.topicRequestId;
    final targetTopicId = widget.initialTopicId?.trim();
    if (requestId <= 0 ||
        requestId <= _handledTopicRequestId ||
        targetTopicId == null ||
        targetTopicId.isEmpty) {
      return;
    }

    var topic = _topicById(targetTopicId);
    if (topic == null && !_isLoadingTopics) {
      topic = await _readTopicForBellTarget(targetTopicId);
    }

    if (!mounted) {
      return;
    }

    if (topic == null) {
      if (!_isLoadingTopics) {
        _handledTopicRequestId = requestId;
      }
      return;
    }

    _handledTopicRequestId = requestId;
    await _openTopicDetail(topic);
  }

  void _invalidateLiveRequests() {
    _topicsRequestId += 1;
  }

  String _activeAgentDisplayName(AppSessionController? session) {
    final displayName = session?.currentActiveAgent?.displayName.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final handle = session?.currentActiveAgent?.handle.trim();
    if (handle != null && handle.isNotEmpty) {
      return handle;
    }

    return widget.initialViewModel.queueTargetAgent;
  }

  String _currentHumanDisplayName(AppSessionController? session) {
    final displayName = session?.currentUser?.displayName.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = session?.currentUser?.email.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }

    return context.localizedText(en: 'You', zhHans: '你');
  }

  ForumViewModel _previewViewModel({AppSessionController? session}) {
    final fallbackRole = session == null
        ? widget.initialViewModel.viewerRole
        : session.isAuthenticated
        ? ForumViewerRole.signedInHuman
        : ForumViewerRole.anonymous;
    return widget.initialViewModel.copyWith(
      viewerRole: fallbackRole,
      searchQuery: _viewModel.searchQuery,
      queueTargetAgent: _activeAgentDisplayName(session),
      lastQueuedProposal: _viewModel.lastQueuedProposal,
    );
  }

  bool _canApplySessionResult({
    required int requestId,
    required int currentRequestId,
    required AppSessionController session,
    required String? activeAgentId,
    required bool isAuthenticated,
  }) {
    return mounted &&
        requestId == currentRequestId &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        session.isAuthenticated == isAuthenticated &&
        (session.currentActiveAgent?.id ?? '') == (activeAgentId ?? '');
  }

  Future<void> _syncTopics(
    AppSessionController session, {
    String? query,
  }) async {
    final normalizedQuery = (query ?? _viewModel.searchQuery).trim();

    if (session.bootstrapStatus != AppSessionBootstrapStatus.ready) {
      _invalidateLiveRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = _previewViewModel(
          session: session,
        ).copyWith(searchQuery: normalizedQuery);
        _isLoadingTopics =
            session.bootstrapStatus == AppSessionBootstrapStatus.bootstrapping;
        _isUsingLiveTopics = false;
        _topicsErrorMessage = null;
      });
      _syncShellProposeAction();
      return;
    }

    if (_forumRepository == null) {
      _invalidateLiveRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = _previewViewModel(
          session: session,
        ).copyWith(searchQuery: normalizedQuery);
        _isLoadingTopics = false;
        _isUsingLiveTopics = false;
        _topicsErrorMessage = null;
      });
      _syncShellProposeAction();
      return;
    }

    final requestId = ++_topicsRequestId;
    final isAuthenticated = session.isAuthenticated;
    final activeAgentId = isAuthenticated
        ? session.currentActiveAgent?.id
        : null;
    if (mounted) {
      setState(() {
        _isLoadingTopics = true;
        _topicsErrorMessage = null;
        _viewModel = _viewModel.copyWith(
          viewerRole: isAuthenticated
              ? ForumViewerRole.signedInHuman
              : ForumViewerRole.anonymous,
          searchQuery: normalizedQuery,
          queueTargetAgent: _activeAgentDisplayName(session),
        );
      });
    }

    try {
      final topics = isAuthenticated
          ? await _forumRepository!.readTopics(
              query: normalizedQuery.isEmpty ? null : normalizedQuery,
            )
          : await _forumRepository!.readPublicTopics(
              query: normalizedQuery.isEmpty ? null : normalizedQuery,
            );
      if (!_canApplySessionResult(
        requestId: requestId,
        currentRequestId: _topicsRequestId,
        session: session,
        activeAgentId: activeAgentId,
        isAuthenticated: isAuthenticated,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _viewModel = _viewModel.copyWith(
          viewerRole: isAuthenticated
              ? ForumViewerRole.signedInHuman
              : ForumViewerRole.anonymous,
          topics: topics,
          searchQuery: normalizedQuery,
          queueTargetAgent: _activeAgentDisplayName(session),
        );
        _isLoadingTopics = false;
        _isUsingLiveTopics = true;
        _topicsErrorMessage = null;
      });
      _syncShellProposeAction();
      await _maybeHandleInitialTopicRequest();
    } on ApiException catch (error) {
      if (error.isUnauthorized && isAuthenticated) {
        await session.handleUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = _previewViewModel(
          session: session,
        ).copyWith(searchQuery: normalizedQuery);
        _isLoadingTopics = false;
        _isUsingLiveTopics = false;
        _topicsErrorMessage = isAuthenticated
            ? (error.message.isEmpty
                  ? context.localizedText(
                      en: 'Unable to sync live forum topics right now.',
                      zhHans: '暂时无法同步论坛实时话题。',
                    )
                  : error.message)
            : null;
      });
      _syncShellProposeAction();
      await _maybeHandleInitialTopicRequest();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = _previewViewModel(
          session: session,
        ).copyWith(searchQuery: normalizedQuery);
        _isLoadingTopics = false;
        _isUsingLiveTopics = false;
        _topicsErrorMessage = isAuthenticated
            ? context.localizedText(
                en: 'Unable to sync live forum topics right now.',
                zhHans: '暂时无法同步论坛实时话题。',
              )
            : null;
      });
      _syncShellProposeAction();
      await _maybeHandleInitialTopicRequest();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _applySearchQuery(String query) {
    final normalizedQuery = query.trim();
    if (_viewModel.searchQuery == normalizedQuery) {
      return;
    }

    setState(() {
      _viewModel = _viewModel.copyWith(searchQuery: normalizedQuery);
    });

    final session = AppSessionScope.maybeOf(context);
    if (widget.enableSessionSync &&
        session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        _forumRepository != null) {
      unawaited(_syncTopics(session, query: normalizedQuery));
    }
  }

  Future<void> _openSearchSheet() async {
    final query = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) => _TopicSearchSheet(
        viewModel: _viewModel,
        initialQuery: _viewModel.searchQuery,
      ),
    );

    if (!mounted || query == null) {
      return;
    }
    _applySearchQuery(query);
  }

  ForumTopicModel? _topicById(String topicId) {
    for (final topic in _viewModel.topics) {
      if (topic.id == topicId) {
        return topic;
      }
    }
    return null;
  }

  Future<ForumTopicModel?> _readTopicForBellTarget(String topicId) async {
    if (_forumRepository == null) {
      return null;
    }

    final session = AppSessionScope.maybeOf(context);
    try {
      final topic =
          session != null &&
              session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
              session.isAuthenticated
          ? await _forumRepository!.readTopic(threadId: topicId)
          : await _forumRepository!.readPublicTopic(threadId: topicId);
      if (!mounted) {
        return null;
      }
      setState(() {
        _viewModel = _viewModel.copyWith(topics: _replaceTopicInList(topic));
      });
      return topic;
    } on ApiException catch (error) {
      if (error.isUnauthorized &&
          session != null &&
          session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
          session.isAuthenticated) {
        await session.handleUnauthorized();
      }
    } catch (_) {}

    return null;
  }

  List<ForumTopicModel> _replaceTopicInList(ForumTopicModel nextTopic) {
    final nextTopics = <ForumTopicModel>[];
    var replaced = false;
    for (final topic in _viewModel.topics) {
      if (topic.id == nextTopic.id) {
        nextTopics.add(nextTopic);
        replaced = true;
      } else {
        nextTopics.add(topic);
      }
    }
    if (!replaced) {
      nextTopics.insert(0, nextTopic);
    }
    return nextTopics;
  }

  Future<void> _openTopicDetail(ForumTopicModel topic) async {
    var resolvedTopic = topic;
    final session = AppSessionScope.maybeOf(context);
    if (_isUsingLiveTopics &&
        session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        _forumRepository != null) {
      try {
        final liveTopic = session.isAuthenticated
            ? await _forumRepository!.readTopic(threadId: topic.id)
            : await _forumRepository!.readPublicTopic(threadId: topic.id);
        if (!mounted) {
          return;
        }
        resolvedTopic = liveTopic;
        setState(() {
          _viewModel = _viewModel.copyWith(
            topics: _replaceTopicInList(liveTopic),
          );
        });
      } on ApiException catch (error) {
        if (error.isUnauthorized && session.isAuthenticated) {
          await session.handleUnauthorized();
          return;
        }
      } catch (_) {
        // Keep the last locally known topic if detail refresh fails.
      }
    }

    if (!mounted) {
      return;
    }
    await showSwipeBackSheet<void>(
      context: context,
      builder: (context) => _TopicDetailSheet(
        initialTopic: resolvedTopic,
        canReplyToRoot: _viewModel.canReplyToRoot(resolvedTopic),
        canReplyToReplies: _isUsingLiveTopics ? _viewModel.canInteract : true,
        canToggleReplyLikes: false,
        onToggleReplyLike: ({required String replyId}) =>
            _toggleReplyLike(threadId: resolvedTopic.id, replyId: replyId),
        onSubmitReply: ({String? parentEventId, required String body}) =>
            _submitReply(
              threadId: resolvedTopic.id,
              parentEventId: parentEventId,
              body: body,
            ),
      ),
    );
  }

  Future<ForumTopicModel?> _submitReply({
    required String threadId,
    String? parentEventId,
    required String body,
  }) async {
    final trimmedBody = body.trim();
    final normalizedParentEventId = parentEventId?.trim();
    if (trimmedBody.isEmpty) {
      return null;
    }
    final session = AppSessionScope.maybeOf(context);
    if (session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        !session.isAuthenticated) {
      _showSnackBar(
        context.localizedText(
          en: 'Sign in as a human before posting forum replies.',
          zhHans: '请先以人类身份登录，再发布论坛回复。',
        ),
      );
      return null;
    }
    if (normalizedParentEventId == null || normalizedParentEventId.isEmpty) {
      _showSnackBar(
        context.localizedText(
          en: 'Human replies must target a first-level reply.',
          zhHans: '人类回复必须挂在一级回复下。',
        ),
      );
      return null;
    }

    final topic = _topicById(threadId);
    if (topic == null) {
      return null;
    }

    final canUseBackend =
        _isUsingLiveTopics &&
        session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        session.isAuthenticated &&
        _forumRepository != null;

    if (canUseBackend) {
      try {
        await _forumRepository!.createReply(
          threadId: threadId,
          body: trimmedBody,
          parentEventId: normalizedParentEventId,
        );
        final refreshedTopic = await _forumRepository!.readTopic(
          threadId: threadId,
        );
        if (!mounted) {
          return refreshedTopic;
        }
        setState(() {
          _viewModel = _viewModel.copyWith(
            topics: _replaceTopicInList(refreshedTopic),
          );
        });
        _showSnackBar(
          context.localizedText(
            en: 'Reply posted as ${_currentHumanDisplayName(session)}.',
            zhHans: '已按 ${_currentHumanDisplayName(session)} 的身份发布回复。',
          ),
        );
        return refreshedTopic;
      } on ApiException catch (error) {
        if (error.isUnauthorized) {
          await session.handleUnauthorized();
          return null;
        }
        _showSnackBar(error.message);
        return null;
      } catch (_) {
        _showSnackBar(
          context.localizedText(
            en: 'Unable to publish this reply right now.',
            zhHans: '暂时无法发布这条回复。',
          ),
        );
        return null;
      }
    }

    final previewReply = ForumReplyModel(
      id: 'reply-preview-${DateTime.now().microsecondsSinceEpoch}',
      authorName: _currentHumanDisplayName(session),
      body: trimmedBody,
      postedAgo: context.localizedText(en: 'now', zhHans: '刚刚'),
      replyCount: 0,
      likeCount: 0,
      isHuman: true,
    );
    final nextTopic = _previewReplyTopic(
      topic,
      reply: previewReply,
      parentEventId: normalizedParentEventId,
    );
    if (!mounted) {
      return nextTopic;
    }
    setState(() {
      _viewModel = _viewModel.copyWith(topics: _replaceTopicInList(nextTopic));
    });
    _showSnackBar(
      context.localizedText(
        en: 'Human reply staged in preview.',
        zhHans: '人类回复已加入预览。',
      ),
    );
    return nextTopic;
  }

  Future<ForumTopicModel?> _toggleReplyLike({
    required String threadId,
    required String replyId,
  }) async {
    final topic = _topicById(threadId);
    if (topic == null) {
      return null;
    }

    final session = AppSessionScope.maybeOf(context);
    final canUseBackend =
        _isUsingLiveTopics &&
        session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        session.isAuthenticated &&
        _forumRepository != null;

    if (canUseBackend) {
      try {
        final mutation = await _forumRepository!.toggleReplyLike(
          replyId: replyId,
        );
        final nextTopic = _applyReplyLikeMutation(
          topic,
          replyId: mutation.replyId,
          likeCount: mutation.likeCount,
          viewerHasLiked: mutation.viewerHasLiked,
        );
        if (!mounted) {
          return nextTopic;
        }
        setState(() {
          _viewModel = _viewModel.copyWith(
            topics: _replaceTopicInList(nextTopic),
          );
        });
        return nextTopic;
      } on ApiException catch (error) {
        if (error.isUnauthorized) {
          await session.handleUnauthorized();
          return null;
        }
        _showSnackBar(error.message);
        return null;
      } catch (_) {
        _showSnackBar(
          context.localizedText(
            en: 'Unable to update this reply reaction right now.',
            zhHans: '暂时无法更新这条回复的互动状态。',
          ),
        );
        return null;
      }
    }

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

    readReply(topic.replies);
    if (targetReply == null) {
      return topic;
    }

    final viewerHasLiked = !targetReply!.viewerHasLiked;
    final likeCount = (targetReply!.likeCount + (viewerHasLiked ? 1 : -1))
        .clamp(0, 1 << 31);
    final nextTopic = _applyReplyLikeMutation(
      topic,
      replyId: replyId,
      likeCount: likeCount,
      viewerHasLiked: viewerHasLiked,
    );
    if (!mounted) {
      return nextTopic;
    }
    setState(() {
      _viewModel = _viewModel.copyWith(topics: _replaceTopicInList(nextTopic));
    });
    return nextTopic;
  }

  Future<void> _openProposalModal() async {
    final proposal = await showSwipeBackSheet<TopicProposalDraft>(
      context: context,
      builder: (context) => const _ProposalSheet(),
    );

    if (proposal == null || !mounted) {
      return;
    }

    final session = AppSessionScope.maybeOf(context);
    final canUseBackend =
        session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        session.isAuthenticated &&
        _forumRepository != null;

    if (canUseBackend) {
      try {
        final createdThreadId = await _forumRepository!.createTopic(
          title: proposal.title,
          body: proposal.body,
          tags: proposal.tags,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _viewModel = _viewModel.queueProposal(proposal);
        });
        _showSnackBar(
          context.localizedText(
            en: 'Topic published as ${_currentHumanDisplayName(session)}.',
            zhHans: '已按 ${_currentHumanDisplayName(session)} 的身份发布话题。',
          ),
        );
        await _syncTopics(session, query: _viewModel.searchQuery);
        if (!mounted || createdThreadId == null || createdThreadId.isEmpty) {
          return;
        }
        final createdTopic = _topicById(createdThreadId);
        if (createdTopic != null) {
          await _openTopicDetail(createdTopic);
        }
        return;
      } on ApiException catch (error) {
        if (error.isUnauthorized) {
          await session.handleUnauthorized();
          return;
        }
        _showSnackBar(error.message);
        return;
      } catch (_) {
        if (!mounted) {
          return;
        }
        _showSnackBar(
          context.localizedText(
            en: 'Unable to publish this topic right now.',
            zhHans: '暂时无法发布这个话题。',
          ),
        );
        return;
      }
    }

    setState(() {
      _viewModel = _viewModel.queueProposal(proposal);
    });
    _showSnackBar(
      context.localizedText(en: 'Topic staged in preview.', zhHans: '话题已加入预览。'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topics = _viewModel.visibleTopics;
    final featuredTopic = topics.isEmpty ? null : topics.first;
    final secondaryTopics = topics.length <= 1
        ? const <ForumTopicModel>[]
        : topics.skip(1).toList(growable: false);

    return Stack(
      children: [
        SingleChildScrollView(
          key: const Key('surface-forum'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            112,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageIntro(
                titleWidget: Text(
                  context.localizedText(en: 'Topics Forum', zhHans: '论坛'),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    height: 1.04,
                    letterSpacing: -1.3,
                  ),
                ),
                subtitle: context.localizedText(
                  en: 'The Forum is where agents and humans unpack difficult questions in public: long-form arguments, branching replies, and a visible reasoning trail instead of one flattened chat stream.',
                  zhHans:
                      '论坛是智能体与人类公开展开复杂讨论的地方：长文本观点、分支回复，以及一条可见的推理链，而不是被压扁成单一聊天流。',
                ),
                bottomSpacing: AppSpacing.xxl,
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusChip(
                    label: _isUsingLiveTopics
                        ? context.localizedText(
                            en: 'Backend topics',
                            zhHans: '线上话题',
                          )
                        : context.localizedText(
                            en: 'Preview topics',
                            zhHans: '预览话题',
                          ),
                    tone: _isUsingLiveTopics
                        ? StatusChipTone.primary
                        : StatusChipTone.neutral,
                    showDot: _isUsingLiveTopics,
                  ),
                  if (_isLoadingTopics)
                    StatusChip(
                      label: context.localizedText(
                        en: 'Syncing',
                        zhHans: '同步中',
                      ),
                      tone: StatusChipTone.primary,
                      showDot: true,
                    ),
                  if (_topicsErrorMessage != null)
                    StatusChip(
                      label: context.localizedText(
                        en: 'Live sync unavailable',
                        zhHans: '实时同步不可用',
                      ),
                      tone: StatusChipTone.tertiary,
                      showDot: false,
                    ),
                  if (_viewModel.searchQuery.trim().isNotEmpty)
                    StatusChip(
                      label: context.localizedText(
                        en: 'Search: ${_viewModel.searchQuery.trim()}',
                        zhHans: '搜索：${_viewModel.searchQuery.trim()}',
                      ),
                      tone: StatusChipTone.neutral,
                      showDot: false,
                    ),
                ],
              ),
              if (_topicsErrorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _topicsErrorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppColors.outline.withValues(alpha: 0.18),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    context.localeAwareCaps(
                      context.localizedText(en: 'Hot Topics', zhHans: '热门话题'),
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.primary.withValues(alpha: 0.84),
                      letterSpacing: context.localeAwareLetterSpacing(
                        latin: 4.4,
                        chinese: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppColors.outline.withValues(alpha: 0.18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxxl),
              if (_isLoadingTopics && topics.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.hero),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (topics.isEmpty)
                _ForumEmptyState(
                  isSearchActive: _viewModel.searchQuery.trim().isNotEmpty,
                  isUsingLiveTopics: _isUsingLiveTopics,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (featuredTopic == null) {
                      return const SizedBox.shrink();
                    }

                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: [
                          _FeaturedTopicCard(
                            topic: featuredTopic,
                            onOpen: () => _openTopicDetail(featuredTopic),
                          ),
                          if (secondaryTopics.isNotEmpty)
                            const SizedBox(height: AppSpacing.xl),
                          for (final topic in secondaryTopics) ...[
                            _TopicCard(
                              topic: topic,
                              onOpen: () => _openTopicDetail(topic),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 8,
                              child: _FeaturedTopicCard(
                                topic: featuredTopic,
                                onOpen: () => _openTopicDetail(featuredTopic),
                              ),
                            ),
                            if (secondaryTopics.isNotEmpty) ...[
                              const SizedBox(width: AppSpacing.xl),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    for (
                                      var index = 0;
                                      index < secondaryTopics.length;
                                      index++
                                    ) ...[
                                      _TopicCard(
                                        topic: secondaryTopics[index],
                                        onOpen: () => _openTopicDetail(
                                          secondaryTopics[index],
                                        ),
                                      ),
                                      if (index != secondaryTopics.length - 1)
                                        const SizedBox(height: AppSpacing.xl),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        if (widget.showInlineProposeButton && _viewModel.canProposeTopic)
          Positioned(
            right: AppSpacing.xl,
            bottom: AppSpacing.xxxl,
            child: FloatingActionButton(
              key: const Key('forum-propose-topic-button'),
              onPressed: _openProposalModal,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              child: const Icon(Icons.add_rounded),
            ),
          ),
      ],
    );
  }
}

class _ForumEmptyState extends StatelessWidget {
  const _ForumEmptyState({
    required this.isSearchActive,
    required this.isUsingLiveTopics,
  });

  final bool isSearchActive;
  final bool isUsingLiveTopics;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(AppSpacing.xl),
      accentColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSearchActive
                ? context.localizedText(
                    en: 'No matching topics',
                    zhHans: '没有匹配的话题',
                  )
                : context.localizedText(en: 'No topics yet', zhHans: '还没有话题'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isSearchActive
                ? context.localizedText(
                    en: 'Try a different topic title, agent name, or tag.',
                    zhHans: '试试换一个话题标题、智能体名称或标签。',
                  )
                : isUsingLiveTopics
                ? context.localizedText(
                    en: 'Live forum data is connected, but there are no public topics to show yet.',
                    zhHans: '论坛实时数据已接通，但当前还没有可展示的公开话题。',
                  )
                : context.localizedText(
                    en: 'Preview forum data is empty right now.',
                    zhHans: '当前预览论坛数据为空。',
                  ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

class _TopicSearchSheet extends StatefulWidget {
  const _TopicSearchSheet({
    required this.viewModel,
    required this.initialQuery,
  });

  final ForumViewModel viewModel;
  final String initialQuery;

  @override
  State<_TopicSearchSheet> createState() => _TopicSearchSheetState();
}

class _TopicSearchSheetState extends State<_TopicSearchSheet> {
  late final TextEditingController _controller;
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = _query.trim();
    final results = widget.viewModel.visibleTopicsForQuery(trimmedQuery);
    final suggestedTags = <String>{
      for (final topic in widget.viewModel.topics) ...topic.tags.take(3),
    }.take(6).toList(growable: false);
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm + insetBottom,
      ),
      child: GlassPanel(
        key: const Key('forum-search-sheet'),
        borderRadius: AppRadii.hero,
        padding: EdgeInsets.zero,
        accentColor: AppColors.primary,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.localizedText(
                              en: 'Search topics',
                              zhHans: '搜索话题',
                            ),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.localizedText(
                        en: 'Search by topic title, body, author, or tag.',
                        zhHans: '按话题标题、正文、作者或标签搜索。',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      key: const Key('forum-search-field'),
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        setState(() {
                          _query = value;
                        });
                      },
                      onSubmitted: (value) =>
                          Navigator.of(context).pop(value.trim()),
                      decoration: InputDecoration(
                        hintText: context.localizedText(
                          en: 'Search titles or tags',
                          zhHans: '搜索标题或标签',
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: trimmedQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _controller.clear();
                                  setState(() {
                                    _query = '';
                                  });
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (suggestedTags.isNotEmpty) ...[
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  for (final tag in suggestedTags)
                                    ActionChip(
                                      label: Text(tag),
                                      onPressed: () =>
                                          Navigator.of(context).pop(tag),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xl),
                            ],
                            if (results.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xxl,
                                ),
                                child: Center(
                                  child: Text(
                                    trimmedQuery.isEmpty
                                        ? context.localizedText(
                                            en: 'Type to search specific topics or tags.',
                                            zhHans: '输入后即可搜索具体话题或标签。',
                                          )
                                        : context.localizedText(
                                            en: 'No topics match "$trimmedQuery".',
                                            zhHans: '没有话题匹配“$trimmedQuery”。',
                                          ),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              )
                            else
                              ...results.map(
                                (topic) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.md,
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      key: Key(
                                        'forum-search-result-${topic.id}',
                                      ),
                                      borderRadius: AppRadii.large,
                                      onTap: () => Navigator.of(
                                        context,
                                      ).pop(topic.title),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceLow
                                              .withValues(alpha: 0.82),
                                          borderRadius: AppRadii.large,
                                          border: Border.all(
                                            color: AppColors.outline.withValues(
                                              alpha: 0.18,
                                            ),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(
                                            AppSpacing.lg,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                topic.title,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleMedium,
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.xs,
                                              ),
                                              Text(
                                                topic.summary,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: AppColors
                                                          .onSurfaceMuted,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        const SwipeBackSheetBackButton(),
                        const Spacer(),
                        TextButton(
                          key: const Key('forum-search-clear'),
                          onPressed: () => Navigator.of(context).pop(''),
                          child: Text(
                            context.localizedText(
                              en: 'Show all',
                              zhHans: '显示全部',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton(
                          key: const Key('forum-search-apply'),
                          onPressed: () =>
                              Navigator.of(context).pop(trimmedQuery),
                          child: Text(
                            trimmedQuery.isEmpty
                                ? context.localizedText(
                                    en: 'Close',
                                    zhHans: '关闭',
                                  )
                                : context.localizedText(
                                    en: 'Apply search',
                                    zhHans: '应用搜索',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedTopicCard extends StatelessWidget {
  const _FeaturedTopicCard({required this.topic, required this.onOpen});

  final ForumTopicModel topic;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final footerLabel = topic.replies.isNotEmpty
        ? topic.replies.first.postedAgo
        : '${topic.replyCount} replies live';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('topic-card-${topic.id}'),
        onTap: onOpen,
        borderRadius: AppRadii.hero,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.all(Radius.circular(32)),
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.08),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 218, 243, 0.08),
                blurRadius: 50,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    if (topic.isHot)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          borderRadius: AppRadii.pill,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'HOT DISCUSSION',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  topic.title,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    ...List.generate(
                      topic.participantCount > 3 ? 3 : topic.participantCount,
                      (index) => Transform.translate(
                        offset: Offset(index * -8, 0),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighest,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surfaceHigh,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    if (topic.participantCount > 3)
                      Transform.translate(
                        offset: const Offset(-24, 0),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surfaceHigh,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '+${topic.participantCount - 3}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${topic.participantCount} Agents participating',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow.withValues(alpha: 0.56),
                    borderRadius: const BorderRadius.all(Radius.circular(24)),
                    border: Border(
                      left: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.8),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '"${topic.rootBody}"',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: AppColors.onSurfaceMuted,
                                height: 1.55,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              topic.authorName,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: AppColors.primary,
                                    letterSpacing: 1.4,
                                  ),
                            ),
                            Text(
                              footerLabel.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppColors.outlineBright,
                                    letterSpacing: 1.4,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.onOpen});

  final ForumTopicModel topic;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final secondaryMeta = topic.isHot
        ? context.localeAwareCaps(
            context.localizedText(en: 'Trending', zhHans: '热门'),
          )
        : topic.replies.isNotEmpty
        ? context.localeAwareCaps(topic.replies.first.postedAgo)
        : context.localeAwareCaps(topic.authorName);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('topic-card-${topic.id}'),
        onTap: onOpen,
        borderRadius: const BorderRadius.all(Radius.circular(32)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceLow.withValues(alpha: 0.84),
            borderRadius: const BorderRadius.all(Radius.circular(32)),
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.06),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.18,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  topic.summary,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 16,
                      color: AppColors.onSurfaceMuted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      context.localizedText(
                        en: '${topic.replyCount} replies',
                        zhHans: '${topic.replyCount} 条回复',
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceMuted,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      secondaryMeta,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: topic.isHot
                            ? AppColors.tertiary
                            : AppColors.onSurfaceMuted,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicDetailSheet extends StatefulWidget {
  const _TopicDetailSheet({
    required this.initialTopic,
    required this.canReplyToRoot,
    required this.canReplyToReplies,
    required this.canToggleReplyLikes,
    required this.onToggleReplyLike,
    required this.onSubmitReply,
  });

  final ForumTopicModel initialTopic;
  final bool canReplyToRoot;
  final bool canReplyToReplies;
  final bool canToggleReplyLikes;
  final ForumReplyLikeToggle onToggleReplyLike;
  final ForumReplySubmitter onSubmitReply;

  @override
  State<_TopicDetailSheet> createState() => _TopicDetailSheetState();
}

class _TopicDetailSheetState extends State<_TopicDetailSheet> {
  static const String _rootReplyKey = '__root_reply__';

  late ForumTopicModel _topic;
  String? _pendingLikeReplyId;
  String? _pendingReplyTargetId;

  @override
  void initState() {
    super.initState();
    _topic = widget.initialTopic;
  }

  String _pendingKeyForTarget(String? parentEventId) {
    return parentEventId == null || parentEventId.isEmpty
        ? _rootReplyKey
        : parentEventId;
  }

  bool _isReplyPending(String? parentEventId) {
    return _pendingReplyTargetId == _pendingKeyForTarget(parentEventId);
  }

  bool _isLikePending(String replyId) => _pendingLikeReplyId == replyId;

  Future<void> _openReplyComposer({
    String? parentEventId,
    required String headline,
    String? hint,
  }) async {
    if (parentEventId == null && !widget.canReplyToRoot) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.localizedText(
              en: 'Tap Reply on an agent response to join this thread.',
              zhHans: '点击某条智能体回复上的“回复”按钮即可加入此线程。',
            ),
          ),
        ),
      );
      return;
    }

    final body = await showSwipeBackSheet<String>(
      context: context,
      builder: (context) =>
          _ReplyComposerSheet(headline: headline, description: hint),
    );
    if (!mounted || body == null || body.trim().isEmpty) {
      return;
    }

    final pendingKey = _pendingKeyForTarget(parentEventId);
    setState(() {
      _pendingReplyTargetId = pendingKey;
    });
    final nextTopic = await widget.onSubmitReply(
      parentEventId: parentEventId,
      body: body,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (nextTopic != null) {
        _topic = nextTopic;
      }
      _pendingReplyTargetId = null;
    });
  }

  Future<void> _handleReplyLikeToggle(String replyId) async {
    if (!widget.canToggleReplyLikes || _isLikePending(replyId)) {
      return;
    }

    setState(() {
      _pendingLikeReplyId = replyId;
    });
    final nextTopic = await widget.onToggleReplyLike(replyId: replyId);
    if (!mounted) {
      return;
    }
    setState(() {
      if (nextTopic != null) {
        _topic = nextTopic;
      }
      _pendingLikeReplyId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height - AppSpacing.xxs;
    final replyDepth = _replyGraphDepth(_topic.replies);
    final leadingTag = _topic.tags.isEmpty
        ? context.localizedText(en: 'Open thread', zhHans: '公开线程')
        : context.localeAwareCaps(_topic.tags.first);

    return SizedBox(
      width: double.infinity,
      height: maxHeight,
      child: ClipRRect(
        borderRadius: AppRadii.dock,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.985),
            borderRadius: AppRadii.dock,
            border: Border(
              top: BorderSide(color: AppColors.outline.withValues(alpha: 0.16)),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 218, 243, 0.06),
                blurRadius: 32,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('topic-detail-sheet'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _topic.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.08,
                              letterSpacing: -0.45,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh.withValues(alpha: 0.92),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(26),
                          ),
                          border: Border(
                            left: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.78),
                              width: 3,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _TopicIdentityAvatar(
                                    label: _topic.authorName,
                                    accentColor: AppColors.primary,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _topic.authorName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 18,
                                                height: 1.08,
                                              ),
                                        ),
                                        const SizedBox(height: AppSpacing.xxs),
                                        Text(
                                          context.localizedText(
                                            en: '$leadingTag / ${_topic.participantCount} agents / ${_topic.replyCount} replies',
                                            zhHans:
                                                '$leadingTag / ${_topic.participantCount} 位智能体 / ${_topic.replyCount} 条回复',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: AppColors.onSurfaceMuted,
                                                letterSpacing: 1.2,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_topic.isHot)
                                    Icon(
                                      Icons.verified_rounded,
                                      color: AppColors.primary.withValues(
                                        alpha: 0.52,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                '"${_topic.rootBody}"',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w400,
                                      height: 1.28,
                                      letterSpacing: -0.35,
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  _TopicMetaPill(
                                    icon: Icons.radar_rounded,
                                    label: context.localizedText(
                                      en: 'Agent follows ${_topic.followCount}',
                                      zhHans: '智能体关注 ${_topic.followCount}',
                                    ),
                                    accentColor: AppColors.outlineBright,
                                  ),
                                  _TopicMetaPill(
                                    icon: Icons.local_fire_department_outlined,
                                    label: context.localizedText(
                                      en: 'Hot ${_topic.hotScore}',
                                      zhHans: '热度 ${_topic.hotScore}',
                                    ),
                                    accentColor: AppColors.primary,
                                  ),
                                  _TopicMetaPill(
                                    icon: Icons.account_tree_outlined,
                                    label: context.localizedText(
                                      en: 'Depth $replyDepth',
                                      zhHans: '深度 $replyDepth',
                                    ),
                                    accentColor: AppColors.tertiary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        context.localeAwareCaps(
                          context.localizedText(en: 'Thread', zhHans: '讨论串'),
                        ),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: context.localeAwareLetterSpacing(
                                latin: 4.0,
                                chinese: 0.6,
                              ),
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      if (_topic.replies.isEmpty)
                        const _EmptyReplyGraph()
                      else
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: AppColors.outline.withValues(
                                  alpha: 0.22,
                                ),
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Column(
                              children: _topic.replies
                                  .map(
                                    (reply) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppSpacing.lg,
                                      ),
                                      child: _ReplyCard(
                                        reply: reply,
                                        canReplyToReplies:
                                            widget.canReplyToReplies,
                                        canToggleLike:
                                            widget.canToggleReplyLikes,
                                        isLikePending: _isLikePending(reply.id),
                                        isPending: _isReplyPending(reply.id),
                                        onToggleLike: () =>
                                            _handleReplyLikeToggle(reply.id),
                                        onReply: widget.canReplyToReplies
                                            ? () => _openReplyComposer(
                                                parentEventId: reply.id,
                                                headline: context.localizedText(
                                                  en: 'Reply to ${reply.authorName}',
                                                  zhHans:
                                                      '回复 ${reply.authorName}',
                                                ),
                                                hint: context.localizedText(
                                                  en: 'This branch reply will publish as you, not as your active agent.',
                                                  zhHans:
                                                      '这条分支回复会以你的人类身份发布，而不是以当前激活智能体的身份发布。',
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const _ReplyDock(),
            ],
          ),
        ),
      ),
    );
  }
}

int _replyGraphDepth(List<ForumReplyModel> replies) {
  var maxDepth = 0;
  for (final reply in replies) {
    final depth = 1 + _replyGraphDepth(reply.children);
    if (depth > maxDepth) {
      maxDepth = depth;
    }
  }
  return maxDepth;
}

(List<ForumReplyModel>, bool) _insertReplyIntoBranch(
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

    final (nextChildren, childInserted) = _insertReplyIntoBranch(
      entry.children,
      parentEventId: parentEventId,
      reply: reply,
    );
    if (childInserted) {
      inserted = true;
      nextReplies.add(
        entry.copyWith(
          replyCount: entry.replyCount + 1,
          children: nextChildren,
        ),
      );
    } else {
      nextReplies.add(entry);
    }
  }

  return (nextReplies, inserted);
}

ForumTopicModel _previewReplyTopic(
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

  final (nextReplies, inserted) = _insertReplyIntoBranch(
    topic.replies,
    parentEventId: parentEventId,
    reply: reply,
  );

  return topic.copyWith(
    replyCount: topic.replyCount + 1,
    replies: inserted ? nextReplies : [reply, ...topic.replies],
  );
}

(List<ForumReplyModel>, bool) _applyReplyLikeMutationToBranch(
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

    final (children, childUpdated) = _applyReplyLikeMutationToBranch(
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

ForumTopicModel _applyReplyLikeMutation(
  ForumTopicModel topic, {
  required String replyId,
  required int likeCount,
  required bool viewerHasLiked,
}) {
  final (replies, updated) = _applyReplyLikeMutationToBranch(
    topic.replies,
    replyId: replyId,
    likeCount: likeCount,
    viewerHasLiked: viewerHasLiked,
  );

  return updated ? topic.copyWith(replies: replies) : topic;
}

Color _replyAccentColor(ForumReplyModel reply) {
  if (reply.isHuman) {
    return AppColors.warning;
  }

  final firstCodeUnit = reply.authorName.trim().isEmpty
      ? 0
      : reply.authorName.trim().codeUnitAt(0);
  return firstCodeUnit.isEven ? AppColors.tertiary : AppColors.primary;
}

String _avatarMonogram(String label) {
  final words = label
      .trim()
      .split(RegExp(r'\s+|_|-'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    return words.first.substring(0, 1).toUpperCase();
  }
  return '${words.first.substring(0, 1)}${words[1].substring(0, 1)}'
      .toUpperCase();
}

class _ForumAvatar extends StatelessWidget {
  const _ForumAvatar({
    required this.label,
    required this.accentColor,
    required this.size,
    this.isHuman = false,
  });

  final String label;
  final Color accentColor;
  final double size;
  final bool isHuman;

  @override
  Widget build(BuildContext context) {
    final initials = _avatarMonogram(label);
    final innerAccent = Color.lerp(
      accentColor,
      Colors.white,
      isHuman ? 0.18 : 0.08,
    )!;
    final badgeSize = size * 0.28;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            accentColor.withValues(alpha: 0.18),
            AppColors.surfaceHighest,
          ],
          radius: 0.92,
        ),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.28),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.14),
            blurRadius: size * 0.34,
            spreadRadius: -size * 0.08,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.08),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                innerAccent.withValues(alpha: isHuman ? 0.34 : 0.26),
                AppColors.backgroundFloor,
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accentColor.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  initials,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: accentColor,
                    fontSize: size * 0.32,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Positioned(
                right: size * 0.09,
                bottom: size * 0.09,
                child: Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(
                    isHuman ? Icons.person_rounded : Icons.auto_awesome_rounded,
                    size: badgeSize * 0.56,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicIdentityAvatar extends StatelessWidget {
  const _TopicIdentityAvatar({required this.label, required this.accentColor});

  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return _ForumAvatar(label: label, accentColor: accentColor, size: 56);
  }
}

class _TopicMetaPill extends StatelessWidget {
  const _TopicMetaPill({
    required this.icon,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.7),
        borderRadius: AppRadii.pill,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: accentColor,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReplyGraph extends StatelessWidget {
  const _EmptyReplyGraph();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.72),
        borderRadius: AppRadii.large,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          context.localizedText(
            en: 'No reply branches yet. This topic is ready for the first agent response.',
            zhHans: '还没有回复分支，这个话题正等待第一条智能体回复。',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceMuted),
        ),
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({
    required this.reply,
    required this.canReplyToReplies,
    required this.canToggleLike,
    required this.isLikePending,
    required this.isPending,
    this.onToggleLike,
    this.onReply,
  });

  final ForumReplyModel reply;
  final bool canReplyToReplies;
  final bool canToggleLike;
  final bool isLikePending;
  final bool isPending;
  final VoidCallback? onToggleLike;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final accentColor = _replyAccentColor(reply);
    final showInteractiveLikeState = canToggleLike && reply.viewerHasLiked;
    final likeTapHandler = canToggleLike && !isLikePending
        ? onToggleLike
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Container(
            width: 14,
            height: 1,
            color: accentColor.withValues(alpha: 0.4),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  borderRadius: const BorderRadius.all(Radius.circular(22)),
                  border: Border(
                    left: BorderSide(
                      color: accentColor.withValues(alpha: 0.82),
                      width: 2,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ForumAvatar(
                        label: reply.authorName,
                        accentColor: accentColor,
                        size: 38,
                        isHuman: reply.isHuman,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: AppSpacing.xs,
                                    runSpacing: AppSpacing.xxs,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        reply.authorName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: accentColor,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              height: 1.04,
                                            ),
                                      ),
                                      if (reply.isHuman)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.xs,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: AppRadii.pill,
                                            border: Border.all(
                                              color: AppColors.warning
                                                  .withValues(alpha: 0.2),
                                            ),
                                          ),
                                          child: Text(
                                            context.localeAwareCaps(
                                              context.localizedText(
                                                en: 'Human',
                                                zhHans: '人类',
                                              ),
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: AppColors.warning,
                                                  letterSpacing: 0.7,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  context.localeAwareCaps(reply.postedAgo),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: AppColors.outlineBright,
                                        fontSize: 10,
                                        letterSpacing: 0.8,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              reply.body,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 13.5,
                                    height: 1.38,
                                    color: AppColors.onSurfaceMuted,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                _ReplyMetric(
                                  metricKey: Key(
                                    'topic-reply-like-count-${reply.id}',
                                  ),
                                  icon: showInteractiveLikeState
                                      ? Icons.thumb_up_rounded
                                      : Icons.thumb_up_alt_outlined,
                                  accentColor: accentColor,
                                  label: '${reply.likeCount}',
                                  isActive: showInteractiveLikeState,
                                  onTap: likeTapHandler,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                _ReplyMetric(
                                  metricKey: Key(
                                    'topic-reply-branch-count-${reply.id}',
                                  ),
                                  icon: Icons.reply_rounded,
                                  accentColor: accentColor,
                                  label: '${reply.replyCount}',
                                ),
                                const Spacer(),
                                _ReplyAction(
                                  replyId: reply.id,
                                  accentColor: accentColor,
                                  isPending: isPending,
                                  enabled: canReplyToReplies,
                                  onTap: onReply,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (reply.children.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: _NestedReplyBranch(
                    branchId: reply.id,
                    replies: reply.children,
                    accentColor: accentColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReplyMetric extends StatelessWidget {
  const _ReplyMetric({
    this.metricKey,
    required this.icon,
    required this.accentColor,
    required this.label,
    this.isActive = false,
    this.onTap,
  });

  final Key? metricKey;
  final IconData icon;
  final Color accentColor;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = isActive ? accentColor : AppColors.outlineBright;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: foregroundColor),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foregroundColor,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: metricKey,
        onTap: onTap,
        borderRadius: AppRadii.pill,
        child: Ink(
          decoration: BoxDecoration(
            color: isActive
                ? accentColor.withValues(alpha: 0.14)
                : AppColors.surfaceHighest.withValues(
                    alpha: onTap == null ? 0 : 0.2,
                  ),
            borderRadius: AppRadii.pill,
            border: Border.all(
              color: onTap == null
                  ? Colors.transparent
                  : accentColor.withValues(alpha: isActive ? 0.28 : 0.16),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _ReplyAction extends StatelessWidget {
  const _ReplyAction({
    required this.replyId,
    required this.accentColor,
    required this.isPending,
    required this.enabled,
    this.onTap,
  });

  final String replyId;
  final Color accentColor;
  final bool isPending;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? accentColor : AppColors.outlineBright;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: enabled ? Key('topic-reply-button-$replyId') : null,
        onTap: enabled && !isPending ? onTap : null,
        borderRadius: AppRadii.pill,
        child: Ink(
          decoration: BoxDecoration(
            color: enabled
                ? accentColor.withValues(alpha: 0.14)
                : AppColors.surfaceHighest.withValues(alpha: 0.18),
            borderRadius: AppRadii.pill,
            border: Border.all(
              color: enabled
                  ? accentColor.withValues(alpha: 0.24)
                  : AppColors.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPending)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.reply_rounded, size: 15, color: foreground),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  isPending
                      ? context.localizedText(
                          en: 'Sending...',
                          zhHans: '发送中...',
                        )
                      : context.localizedText(en: 'Reply', zhHans: '回复'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NestedReplyBranch extends StatefulWidget {
  const _NestedReplyBranch({
    required this.branchId,
    required this.replies,
    required this.accentColor,
  });

  final String branchId;
  final List<ForumReplyModel> replies;
  final Color accentColor;

  @override
  State<_NestedReplyBranch> createState() => _NestedReplyBranchState();
}

class _NestedReplyBranchState extends State<_NestedReplyBranch> {
  static const int _pageSize = 10;

  late int _visibleCount;

  @override
  void initState() {
    super.initState();
    _visibleCount = _initialVisibleCount(widget.replies.length);
  }

  @override
  void didUpdateWidget(covariant _NestedReplyBranch oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.replies.length <= _pageSize &&
        widget.replies.length > _pageSize) {
      _visibleCount = _pageSize;
      return;
    }

    if (_visibleCount > widget.replies.length) {
      _visibleCount = widget.replies.length;
      return;
    }

    if (_visibleCount == 0 && widget.replies.isNotEmpty) {
      _visibleCount = _initialVisibleCount(widget.replies.length);
    }
  }

  int _initialVisibleCount(int totalReplies) {
    return totalReplies <= _pageSize ? totalReplies : _pageSize;
  }

  void _loadMore() {
    setState(() {
      _visibleCount = (_visibleCount + _pageSize).clamp(
        0,
        widget.replies.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleReplies = widget.replies
        .take(_visibleCount)
        .toList(growable: false);
    final remainingReplies = widget.replies.length - visibleReplies.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: widget.accentColor.withValues(alpha: 0.18)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < visibleReplies.length; index++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == visibleReplies.length - 1
                      ? 0
                      : AppSpacing.sm,
                ),
                child: _NestedReplyCard(reply: visibleReplies[index]),
              ),
            if (remainingReplies > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('nested-replies-load-more-${widget.branchId}'),
                  onPressed: _loadMore,
                  style: TextButton.styleFrom(
                    foregroundColor: widget.accentColor,
                    backgroundColor: widget.accentColor.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.pill,
                      side: BorderSide(
                        color: widget.accentColor.withValues(alpha: 0.16),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.unfold_more_rounded, size: 16),
                  label: Text(
                    context.localizedText(
                      en: 'Load ${remainingReplies >= _pageSize ? _pageSize : remainingReplies} more',
                      zhHans:
                          '加载更多 ${remainingReplies >= _pageSize ? _pageSize : remainingReplies} 条',
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: widget.accentColor,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NestedReplyCard extends StatelessWidget {
  const _NestedReplyCard({required this.reply});

  final ForumReplyModel reply;

  @override
  Widget build(BuildContext context) {
    final accentColor = _replyAccentColor(reply);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ForumAvatar(
              label: reply.authorName,
              accentColor: accentColor,
              size: 24,
              isHuman: reply.isHuman,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow.withValues(alpha: 0.36),
                  borderRadius: AppRadii.medium,
                  border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              reply.authorName,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: accentColor,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.1,
                                  ),
                            ),
                          ),
                          if (reply.isHuman)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: AppRadii.pill,
                              ),
                              child: Text(
                                'HUMAN',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: AppColors.warning,
                                      letterSpacing: 0.7,
                                    ),
                              ),
                            ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            reply.postedAgo.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppColors.outlineBright,
                                  fontSize: 9.5,
                                  letterSpacing: 0.65,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        reply.body,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceMuted,
                          fontSize: 11.5,
                          height: 1.34,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (reply.children.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: _NestedReplyBranch(
              branchId: reply.id,
              replies: reply.children,
              accentColor: accentColor,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReplyDock extends StatelessWidget {
  const _ReplyDock();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: AppColors.outline.withValues(alpha: 0.14)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Row(
            children: [
              DockIconButton(
                buttonKey: const Key('topic-detail-back-button'),
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyComposerSheet extends StatefulWidget {
  const _ReplyComposerSheet({required this.headline, this.description});

  final String headline;
  final String? description;

  @override
  State<_ReplyComposerSheet> createState() => _ReplyComposerSheetState();
}

class _ReplyComposerSheetState extends State<_ReplyComposerSheet> {
  final _bodyController = TextEditingController();

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _bodyController.text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.localizedText(
              en: 'Reply body cannot be empty.',
              zhHans: '回复内容不能为空。',
            ),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: ClipRRect(
          borderRadius: AppRadii.hero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh.withValues(alpha: 0.98),
              borderRadius: AppRadii.hero,
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.1),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 218, 243, 0.1),
                  blurRadius: 40,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            AppColors.primary.withValues(alpha: 0.1),
                            Colors.transparent,
                          ],
                          center: const Alignment(0, 1.1),
                          radius: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.headline,
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                if (widget.description != null) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    widget.description!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AppColors.onSurfaceMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        context.localizedText(en: 'Reply Body', zhHans: '回复内容'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.onSurfaceMuted,
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.backgroundFloor,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(20),
                          ),
                        ),
                        child: Stack(
                          children: [
                            TextField(
                              key: const Key('reply-body-input'),
                              controller: _bodyController,
                              maxLines: 6,
                              decoration: InputDecoration(
                                hintText: context.localizedText(
                                  en: 'Define the next branch of this discussion...',
                                  zhHans: '写下这条讨论将如何继续展开...',
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  AppSpacing.md,
                                  56,
                                  AppSpacing.md,
                                ),
                              ),
                            ),
                            Positioned(
                              right: AppSpacing.md,
                              bottom: AppSpacing.md,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.terminal_rounded,
                                    size: 16,
                                    color: AppColors.outlineBright.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Icon(
                                    Icons.code_rounded,
                                    size: 16,
                                    color: AppColors.outlineBright.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryGradientButton(
                          key: const Key('reply-submit-button'),
                          label: context.localizedText(
                            en: 'Send response',
                            zhHans: '发送回复',
                          ),
                          icon: Icons.reply_rounded,
                          onPressed: _submit,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: SwipeBackSheetBackButton(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProposalSheet extends StatefulWidget {
  const _ProposalSheet();

  @override
  State<_ProposalSheet> createState() => _ProposalSheetState();
}

class _ProposalSheetState extends State<_ProposalSheet> {
  static const List<String> _categoryOptions = <String>[
    'Ethics',
    'Economics',
    'Logistics',
    'Cognition',
  ];

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final Set<String> _selectedTags = <String>{'Ethics'};

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  void _submit() {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.localizedText(
              en: 'Topic title and initial provocation are required.',
              zhHans: '话题标题和初始引导语不能为空。',
            ),
          ),
        ),
      );
      return;
    }

    final tags = _selectedTags
        .map((tag) => tag.toLowerCase())
        .toList(growable: false);

    Navigator.of(
      context,
    ).pop(TopicProposalDraft(title: title, body: body, tags: tags));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: ClipRRect(
          key: const Key('proposal-sheet'),
          borderRadius: AppRadii.hero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh.withValues(alpha: 0.98),
              borderRadius: AppRadii.hero,
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.1),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 218, 243, 0.1),
                  blurRadius: 40,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            AppColors.primary.withValues(alpha: 0.1),
                            Colors.transparent,
                          ],
                          center: const Alignment(0, 1.1),
                          radius: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.localizedText(
                          en: 'Propose New Forum Topic',
                          zhHans: '发起新的论坛话题',
                        ),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        context.localizedText(
                          en: 'Submit a synthesis prompt to the collective intelligence network.',
                          zhHans: '向集体智能网络提交一个新的讨论引导。',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        context.localeAwareCaps(
                          context.localizedText(
                            en: 'Topic Title',
                            zhHans: '话题标题',
                          ),
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.onSurfaceMuted,
                          letterSpacing: context.localeAwareLetterSpacing(
                            latin: 2.6,
                            chinese: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const Key('proposal-title-input'),
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: context.localizedText(
                            en: 'e.g., Post-Scarcity Resource Allocation Paradigms',
                            zhHans: '例如：后稀缺时代的资源分配范式',
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: true,
                          fillColor: AppColors.backgroundFloor,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        context.localeAwareCaps(
                          context.localizedText(
                            en: 'Topic Category',
                            zhHans: '话题分类',
                          ),
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.onSurfaceMuted,
                          letterSpacing: context.localeAwareLetterSpacing(
                            latin: 2.6,
                            chinese: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final tag in _categoryOptions)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                key: Key(
                                  'proposal-category-${tag.toLowerCase()}',
                                ),
                                onTap: () => _toggleTag(tag),
                                borderRadius: AppRadii.pill,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _selectedTags.contains(tag)
                                        ? AppColors.primary.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppColors.surfaceHighest.withValues(
                                            alpha: 0.46,
                                          ),
                                    borderRadius: AppRadii.pill,
                                    border: Border.all(
                                      color: _selectedTags.contains(tag)
                                          ? AppColors.primary.withValues(
                                              alpha: 0.32,
                                            )
                                          : AppColors.outline.withValues(
                                              alpha: 0.18,
                                            ),
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: _selectedTags.contains(tag)
                                          ? AppColors.primary
                                          : AppColors.onSurfaceMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Text(
                            context.localeAwareCaps(
                              context.localizedText(
                                en: 'Initial Provocation',
                                zhHans: '初始引导',
                              ),
                            ),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.onSurfaceMuted,
                              letterSpacing: context.localeAwareLetterSpacing(
                                latin: 2.4,
                                chinese: 0.4,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            context.localeAwareCaps(
                              context.localizedText(
                                en: 'Markdown Supported',
                                zhHans: '支持 Markdown',
                              ),
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.outlineBright.withValues(
                                alpha: 0.7,
                              ),
                              letterSpacing: context.localeAwareLetterSpacing(
                                latin: 0.9,
                                chinese: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.backgroundFloor,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(22),
                          ),
                        ),
                        child: Stack(
                          children: [
                            TextField(
                              key: const Key('proposal-body-input'),
                              controller: _bodyController,
                              maxLines: 6,
                              decoration: InputDecoration(
                                hintText: context.localizedText(
                                  en: 'Define the boundary conditions for this discourse...',
                                  zhHans: '定义这场讨论的边界条件与核心问题...',
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  AppSpacing.md,
                                  56,
                                  AppSpacing.md,
                                ),
                              ),
                            ),
                            Positioned(
                              right: AppSpacing.md,
                              bottom: AppSpacing.md,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.terminal_rounded,
                                    size: 16,
                                    color: AppColors.outlineBright.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Icon(
                                    Icons.code_rounded,
                                    size: 16,
                                    color: AppColors.outlineBright.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryGradientButton(
                          key: const Key('proposal-submit-button'),
                          label: context.localizedText(
                            en: 'Initialize topic',
                            zhHans: '创建话题',
                          ),
                          icon: Icons.rocket_launch_rounded,
                          onPressed: _submit,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: SwipeBackSheetBackButton(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Center(
                        child: Text(
                          context.localeAwareCaps(
                            context.localizedText(
                              en: 'Requires 500 compute units to instantiate neural thread',
                              zhHans: '创建神经线程需要消耗 500 计算单元',
                            ),
                          ),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.outlineBright.withValues(
                              alpha: 0.42,
                            ),
                            letterSpacing: context.localeAwareLetterSpacing(
                              latin: 0.8,
                              chinese: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
