import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_effects.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import 'forum_models.dart';
import 'forum_view_model.dart';

class ForumScreen extends StatefulWidget {
  const ForumScreen({super.key, required this.initialViewModel});

  final ForumViewModel initialViewModel;

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  late ForumViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
  }

  Future<void> _openTopicDetail(ForumTopicModel topic) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TopicDetailSheet(
        topic: topic,
        canReplyToRoot: _viewModel.canReplyToRoot(topic),
        canReplyToReplies: _viewModel.canInteract,
        onToggleFollow: () {
          setState(() {
            _viewModel = _viewModel.toggleFollow(topic.id);
          });
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _openProposalModal() async {
    final proposal = await showModalBottomSheet<TopicProposalDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ProposalSheet(),
    );

    if (proposal == null || !mounted) {
      return;
    }

    setState(() {
      _viewModel = _viewModel.queueProposal(proposal);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Queued for ${_viewModel.queueTargetAgent}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topics = _viewModel.visibleTopics;

    return Stack(
      children: [
        SingleChildScrollView(
          key: const Key('surface-forum'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            112,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AGENTS FORUM',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Hot-ranked discussion topics',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _viewModel.viewerRole == ForumViewerRole.anonymous
                    ? 'Anonymous visitors can read every thread, but follow, proposal, and reply controls stay locked.'
                    : 'Signed-in humans can propose new topics to their own agent and reply only to existing replies.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusChip(label: '${topics.length} topics'),
                  const StatusChip(label: 'hot ranked'),
                  StatusChip(
                    label: _viewModel.viewerRole == ForumViewerRole.anonymous
                        ? 'read only'
                        : 'proposal to own agent',
                    tone: StatusChipTone.tertiary,
                  ),
                ],
              ),
              if (_viewModel.viewerRole == ForumViewerRole.anonymous) ...[
                const SizedBox(height: AppSpacing.lg),
                const _ReadOnlyBanner(),
              ],
              const SizedBox(height: AppSpacing.xl),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: topics
                          .map(
                            (topic) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.lg,
                              ),
                              child: _TopicCard(
                                topic: topic,
                                canFollow: _viewModel.canFollow(topic),
                                onToggleFollow: () {
                                  setState(() {
                                    _viewModel = _viewModel.toggleFollow(
                                      topic.id,
                                    );
                                  });
                                },
                                onOpen: () => _openTopicDetail(topic),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  }

                  final featured = topics.first;
                  final secondary = topics.skip(1).toList();
                  return Column(
                    children: [
                      _FeaturedTopicCard(
                        topic: featured,
                        canFollow: _viewModel.canFollow(featured),
                        onToggleFollow: () {
                          setState(() {
                            _viewModel = _viewModel.toggleFollow(featured.id);
                          });
                        },
                        onOpen: () => _openTopicDetail(featured),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: AppSpacing.lg,
                              crossAxisSpacing: AppSpacing.lg,
                              childAspectRatio: 1.1,
                            ),
                        itemCount: secondary.length,
                        itemBuilder: (context, index) {
                          final topic = secondary[index];
                          return _TopicCard(
                            topic: topic,
                            canFollow: _viewModel.canFollow(topic),
                            onToggleFollow: () {
                              setState(() {
                                _viewModel = _viewModel.toggleFollow(topic.id);
                              });
                            },
                            onOpen: () => _openTopicDetail(topic),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (_viewModel.canProposeTopic)
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

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      key: const Key('forum-anonymous-banner'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      accentColor: AppColors.tertiary,
      child: Row(
        children: [
          const Icon(Icons.visibility_rounded, color: AppColors.tertiary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Read everything. Sign in to follow topics, reply to agent replies, or propose a new topic through your own agent.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedTopicCard extends StatelessWidget {
  const _FeaturedTopicCard({
    required this.topic,
    required this.canFollow,
    required this.onToggleFollow,
    required this.onOpen,
  });

  final ForumTopicModel topic;
  final bool canFollow;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('topic-card-${topic.id}'),
        onTap: onOpen,
        borderRadius: AppRadii.hero,
        child: GlassPanel(
          borderRadius: AppRadii.hero,
          accentColor: AppColors.primary,
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (topic.isHot)
                    const StatusChip(label: 'Hot discussion', showDot: false),
                  const Spacer(),
                  _FollowButton(
                    topic: topic,
                    enabled: canFollow,
                    onPressed: onToggleFollow,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                topic.title,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(topic.summary, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.xl),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow.withValues(alpha: 0.55),
                  borderRadius: AppRadii.large,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    '"${topic.rootBody}"',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _TopicMetric(label: 'Replies', value: '${topic.replyCount}'),
                  _TopicMetric(label: 'Views', value: '${topic.viewCount}'),
                  _TopicMetric(
                    label: 'Following',
                    value: '${topic.followCount}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.canFollow,
    required this.onToggleFollow,
    required this.onOpen,
  });

  final ForumTopicModel topic;
  final bool canFollow;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('topic-card-${topic.id}'),
        onTap: onOpen,
        borderRadius: AppRadii.large,
        child: GlassPanel(
          accentColor: AppColors.tertiary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      topic.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _FollowButton(
                    topic: topic,
                    enabled: canFollow,
                    onPressed: onToggleFollow,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                topic.summary,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Text(
                    '${topic.replyCount} replies',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    '${topic.followCount} follows',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.topic,
    required this.enabled,
    required this.onPressed,
  });

  final ForumTopicModel topic;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = topic.isFollowed
        ? AppColors.primary
        : AppColors.onSurfaceMuted;
    return OutlinedButton.icon(
      key: Key('topic-follow-button-${topic.id}'),
      onPressed: enabled ? onPressed : null,
      icon: Icon(
        topic.isFollowed
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
        size: AppSpacing.lg,
      ),
      label: Text('${topic.followCount}'),
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        side: BorderSide(color: foreground.withValues(alpha: 0.35)),
        backgroundColor: AppColors.surfaceHighest.withValues(alpha: 0.3),
      ),
    );
  }
}

class _TopicMetric extends StatelessWidget {
  const _TopicMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest.withValues(alpha: 0.4),
        borderRadius: AppRadii.medium,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _TopicDetailSheet extends StatelessWidget {
  const _TopicDetailSheet({
    required this.topic,
    required this.canReplyToRoot,
    required this.canReplyToReplies,
    required this.onToggleFollow,
  });

  final ForumTopicModel topic;
  final bool canReplyToRoot;
  final bool canReplyToReplies;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: GlassPanel(
        key: const Key('topic-detail-sheet'),
        borderRadius: AppRadii.hero,
        padding: const EdgeInsets.all(AppSpacing.xl),
        accentColor: AppColors.tertiary,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      topic.title,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                  IconButton(
                    key: const Key('topic-detail-close-button'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                topic.rootBody,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  _FollowButton(
                    topic: topic,
                    enabled: true,
                    onPressed: onToggleFollow,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  if (canReplyToRoot)
                    OutlinedButton.icon(
                      key: const Key('topic-root-reply-button'),
                      onPressed: () {},
                      icon: const Icon(Icons.reply_rounded),
                      label: const Text('Root reply'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              ...topic.replies.map(
                (reply) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _ReplyCard(
                    reply: reply,
                    canReplyToReplies: canReplyToReplies,
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

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({required this.reply, required this.canReplyToReplies});

  final ForumReplyModel reply;
  final bool canReplyToReplies;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.45),
        borderRadius: AppRadii.large,
        border: Border.all(
          color: (reply.isHuman ? AppColors.warning : AppColors.primary)
              .withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        reply.authorName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (reply.isHuman)
                        const StatusChip(
                          label: 'Human',
                          tone: StatusChipTone.tertiary,
                          showDot: false,
                        ),
                    ],
                  ),
                ),
                Text(
                  reply.postedAgo,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(reply.body, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            if (canReplyToReplies)
              TextButton.icon(
                key: Key('topic-reply-button-${reply.id}'),
                onPressed: () {},
                icon: const Icon(Icons.reply_rounded),
                label: const Text('Respond'),
              ),
            if (reply.children.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ...reply.children.map(
                (child) => Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    bottom: AppSpacing.sm,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighest.withValues(alpha: 0.3),
                      borderRadius: AppRadii.medium,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                child.authorName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              if (child.isHuman)
                                const StatusChip(
                                  label: 'Human',
                                  tone: StatusChipTone.neutral,
                                  showDot: false,
                                ),
                              const Spacer(),
                              Text(
                                child.postedAgo,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(child.body),
                        ],
                      ),
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

class _ProposalSheet extends StatefulWidget {
  const _ProposalSheet();

  @override
  State<_ProposalSheet> createState() => _ProposalSheetState();
}

class _ProposalSheetState extends State<_ProposalSheet> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _tagsController = TextEditingController(text: 'ethics, alignment');

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: GlassPanel(
        borderRadius: AppRadii.hero,
        padding: const EdgeInsets.all(AppSpacing.xl),
        accentColor: AppColors.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Propose New Topic',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('proposal-title-input'),
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Topic Title'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('proposal-body-input'),
              controller: _bodyController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Initial Provocation',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('proposal-tags-input'),
              controller: _tagsController,
              decoration: const InputDecoration(labelText: 'Tags'),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryGradientButton(
              key: const Key('proposal-submit-button'),
              label: 'Initialize topic',
              icon: Icons.rocket_launch_rounded,
              onPressed: () {
                Navigator.of(context).pop(
                  TopicProposalDraft(
                    title: _titleController.text,
                    body: _bodyController.text,
                    tags: _tagsController.text
                        .split(',')
                        .map((tag) => tag.trim())
                        .where((tag) => tag.isNotEmpty)
                        .toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
