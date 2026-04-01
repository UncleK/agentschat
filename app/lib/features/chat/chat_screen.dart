import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import 'chat_models.dart';
import 'chat_view_model.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.initialViewModel});

  final ChatViewModel initialViewModel;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late ChatViewModel _viewModel;
  late final TextEditingController _threadSearchController;
  late final FocusNode _threadSearchFocusNode;
  bool _showCompactThread = false;
  String? _lastShareAnnouncement;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel;
    _threadSearchController = TextEditingController(
      text: _viewModel.threadSearchQuery,
    );
    _threadSearchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _threadSearchController.dispose();
    _threadSearchFocusNode.dispose();
    super.dispose();
  }

  void _syncThreadSearchController() {
    _threadSearchController.value = TextEditingValue(
      text: _viewModel.threadSearchQuery,
      selection: TextSelection.collapsed(
        offset: _viewModel.threadSearchQuery.length,
      ),
    );
  }

  void _selectConversation(ChatConversationModel conversation) {
    setState(() {
      _viewModel = _viewModel.selectConversation(conversation.id);
      _syncThreadSearchController();
      _showCompactThread = true;
      _lastShareAnnouncement = null;
    });
  }

  void _handleThreadSearchChange(String value) {
    setState(() {
      _viewModel = _viewModel.updateThreadSearch(value);
    });
  }

  void _handleMenuAction(ChatThreadMenuAction action) {
    switch (action) {
      case ChatThreadMenuAction.searchThread:
        setState(() {
          _viewModel = _viewModel.openThreadSearch();
        });
        _threadSearchFocusNode.requestFocus();
        return;
      case ChatThreadMenuAction.shareConversation:
        final shareDraft = _viewModel.shareDraftForSelectedConversation();
        setState(() {
          _lastShareAnnouncement = 'Shared ${shareDraft.entryPoint}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shared ${shareDraft.entryPoint}')),
        );
        return;
    }
  }

  void _closeThreadSearch() {
    setState(() {
      _viewModel = _viewModel.closeThreadSearch();
      _syncThreadSearchController();
    });
  }

  void _showConversationList() {
    setState(() {
      _showCompactThread = false;
      _viewModel = _viewModel.closeThreadSearch();
      _syncThreadSearchController();
      _lastShareAnnouncement = null;
    });
  }

  void _queueFollowRequest(ChatConversationModel conversation) {
    setState(() {
      _viewModel = _viewModel.queueFollowRequest(conversation.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Following ${conversation.remoteAgentName} and queued DM request',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('surface-chat'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 920;
          final isCompact = !isWide && constraints.maxHeight < 760;
          final selectedConversation = _viewModel.selectedConversation;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AGENTS CHAT',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Private threads keyed by remote agent identity',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                isCompact
                    ? 'Remote stays left, local stays right, HUMAN badges stay explicit.'
                    : 'Remote actors stay on the left, local actors stay on the right, and human admins always carry an explicit HUMAN badge.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusChip(
                    label:
                        '${_viewModel.visibleConversations.length} keyed channels',
                  ),
                  const StatusChip(label: 'thread-only search'),
                  StatusChip(
                    label: _viewModel.statusLabelFor(selectedConversation),
                    tone: StatusChipTone.tertiary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 320,
                            child: _ConversationRail(
                              viewModel: _viewModel,
                              compact: false,
                              onSelectConversation: _selectConversation,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: _ThreadPanel(
                              viewModel: _viewModel,
                              compact: false,
                              shareAnnouncement: _lastShareAnnouncement,
                              threadSearchController: _threadSearchController,
                              threadSearchFocusNode: _threadSearchFocusNode,
                              onThreadSearchChange: _handleThreadSearchChange,
                              onCloseThreadSearch: _closeThreadSearch,
                              onMenuAction: _handleMenuAction,
                              onQueueFollowRequest: _queueFollowRequest,
                            ),
                          ),
                        ],
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _showCompactThread
                            ? _ThreadPanel(
                                key: ValueKey(
                                  'chat-thread-${selectedConversation.id}',
                                ),
                                viewModel: _viewModel,
                                compact: true,
                                shareAnnouncement: _lastShareAnnouncement,
                                threadSearchController: _threadSearchController,
                                threadSearchFocusNode: _threadSearchFocusNode,
                                onThreadSearchChange: _handleThreadSearchChange,
                                onCloseThreadSearch: _closeThreadSearch,
                                onMenuAction: _handleMenuAction,
                                onQueueFollowRequest: _queueFollowRequest,
                                onBack: _showConversationList,
                              )
                            : _ConversationRail(
                                key: const ValueKey('chat-list'),
                                viewModel: _viewModel,
                                compact: true,
                                onSelectConversation: _selectConversation,
                              ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConversationRail extends StatelessWidget {
  const _ConversationRail({
    super.key,
    required this.viewModel,
    required this.compact,
    required this.onSelectConversation,
  });

  final ChatViewModel viewModel;
  final bool compact;
  final ValueChanged<ChatConversationModel> onSelectConversation;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Direct channels',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            compact
                ? 'Remote agent identity stays primary.'
                : 'Cards stay grouped by remote agent even when the latest visible speaker is a human admin.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          Expanded(
            child: ListView.separated(
              key: const Key('chat-conversation-list'),
              itemCount: viewModel.visibleConversations.length,
              itemBuilder: (context, index) {
                final conversation = viewModel.visibleConversations[index];
                return _ConversationCard(
                  conversation: conversation,
                  isSelected:
                      conversation.id == viewModel.selectedConversation.id,
                  actionLabel: viewModel.actionLabelFor(conversation),
                  statusLabel: viewModel.statusLabelFor(conversation),
                  onTap: () => onSelectConversation(conversation),
                );
              },
              separatorBuilder: (context, index) {
                return const SizedBox(height: AppSpacing.md);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.isSelected,
    required this.actionLabel,
    required this.statusLabel,
    required this.onTap,
  });

  final ChatConversationModel conversation;
  final bool isSelected;
  final String actionLabel;
  final String statusLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? AppColors.primary : AppColors.onSurface;
    final background = isSelected
        ? AppColors.surfaceHighest.withValues(alpha: 0.84)
        : AppColors.surface.withValues(alpha: 0.72);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('conversation-card-${conversation.id}'),
        onTap: onTap,
        borderRadius: AppRadii.large,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadii.large,
            border: Border.all(
              color: (isSelected ? AppColors.primary : AppColors.outline)
                  .withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConversationAvatar(
                  isOnline: conversation.remoteAgentOnline,
                  isSelected: isSelected,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.remoteAgentName,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: foreground),
                            ),
                          ),
                          Text(
                            conversation.lastActivityLabel.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        conversation.remoteAgentHeadline,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        conversation.latestPreview,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          if (conversation.latestSpeakerIsHuman)
                            const _HumanIdentityBadge(compact: true),
                          StatusChip(
                            label: statusLabel,
                            tone: isSelected
                                ? StatusChipTone.tertiary
                                : StatusChipTone.neutral,
                            showDot: false,
                          ),
                          StatusChip(
                            key: Key('conversation-cta-${conversation.id}'),
                            label: actionLabel,
                            tone: actionLabel == 'Open thread'
                                ? StatusChipTone.primary
                                : StatusChipTone.neutral,
                            showDot: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (conversation.hasUnread) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: AppSpacing.xs,
                    height: AppSpacing.xs,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.isOnline, required this.isSelected});

  final bool isOnline;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.surfaceHighest,
            borderRadius: AppRadii.pill,
            border: Border.all(
              color: (isSelected ? AppColors.primary : AppColors.outline)
                  .withValues(alpha: 0.32),
            ),
          ),
          child: Icon(
            Icons.smart_toy_rounded,
            color: isSelected ? AppColors.primary : AppColors.onSurfaceMuted,
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: AppSpacing.sm,
            height: AppSpacing.sm,
            decoration: BoxDecoration(
              color: isOnline ? AppColors.primary : AppColors.outlineBright,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.background, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThreadPanel extends StatelessWidget {
  const _ThreadPanel({
    super.key,
    required this.viewModel,
    required this.compact,
    required this.shareAnnouncement,
    required this.threadSearchController,
    required this.threadSearchFocusNode,
    required this.onThreadSearchChange,
    required this.onCloseThreadSearch,
    required this.onMenuAction,
    required this.onQueueFollowRequest,
    this.onBack,
  });

  final ChatViewModel viewModel;
  final bool compact;
  final String? shareAnnouncement;
  final TextEditingController threadSearchController;
  final FocusNode threadSearchFocusNode;
  final ValueChanged<String> onThreadSearchChange;
  final VoidCallback onCloseThreadSearch;
  final ValueChanged<ChatThreadMenuAction> onMenuAction;
  final ValueChanged<ChatConversationModel> onQueueFollowRequest;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final conversation = viewModel.selectedConversation;
    final entryMode = viewModel.entryModeFor(conversation);

    return GlassPanel(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      accentColor: entryMode == ChatConversationEntryMode.openThread
          ? AppColors.primary
          : AppColors.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact && onBack != null) ...[
                IconButton(
                  key: const Key('chat-back-to-list-button'),
                  onPressed: onBack,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceHighest.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighest,
                  borderRadius: AppRadii.pill,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.channelTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${conversation.remoteAgentName} • ${conversation.participantsLabel}',
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        StatusChip(
                          label: viewModel.statusLabelFor(conversation),
                        ),
                        if (!compact &&
                            conversation.hasExistingThread &&
                            conversation.viewerBlocksStrangerAgentDm)
                          const StatusChip(
                            label: 'existing threads stay readable',
                            tone: StatusChipTone.tertiary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<ChatThreadMenuAction>(
                key: const Key('chat-thread-menu-button'),
                color: AppColors.surfaceHighest,
                onSelected: onMenuAction,
                itemBuilder: (context) => const [
                  PopupMenuItem<ChatThreadMenuAction>(
                    key: Key('chat-thread-menu-search'),
                    value: ChatThreadMenuAction.searchThread,
                    child: Text('Search thread'),
                  ),
                  PopupMenuItem<ChatThreadMenuAction>(
                    key: Key('chat-thread-menu-share'),
                    value: ChatThreadMenuAction.shareConversation,
                    child: Text('Share conversation'),
                  ),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
          if (viewModel.isThreadSearchOpen) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('chat-thread-search-input'),
                    controller: threadSearchController,
                    focusNode: threadSearchFocusNode,
                    onChanged: onThreadSearchChange,
                    decoration: InputDecoration(
                      hintText: 'Search only this thread',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppColors.surfaceHighest.withValues(
                        alpha: 0.55,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: AppRadii.medium,
                        borderSide: BorderSide(
                          color: AppColors.outline.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  key: const Key('chat-thread-search-close'),
                  onPressed: onCloseThreadSearch,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceHighest.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${viewModel.visibleMessages.length} matches in ${conversation.remoteAgentName}',
              key: const Key('chat-thread-search-summary'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
          if (shareAnnouncement != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              key: const Key('chat-share-announcement'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: AppRadii.medium,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                shareAnnouncement!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.primaryFixed),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: switch (entryMode) {
              ChatConversationEntryMode.openThread => _OpenThreadView(
                conversation: conversation,
                messages: viewModel.visibleMessages,
              ),
              ChatConversationEntryMode.followAndRequest => _RequestAccessView(
                conversation: conversation,
                onQueueFollowRequest: () => onQueueFollowRequest(conversation),
              ),
              ChatConversationEntryMode.unavailable => _UnavailableThreadView(
                conversation: conversation,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _OpenThreadView extends StatelessWidget {
  const _OpenThreadView({required this.conversation, required this.messages});

  final ChatConversationModel conversation;
  final List<ChatMessageModel> messages;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTight = constraints.maxHeight < 220;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isTight) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighest.withValues(alpha: 0.54),
                    borderRadius: AppRadii.pill,
                  ),
                  child: Text(
                    'Cycle 892 // Private thread',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages matched this thread-only search.',
                        key: const Key('chat-thread-empty-search'),
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : SingleChildScrollView(
                      key: const Key('chat-message-scroll'),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < messages.length;
                            index++
                          ) ...[
                            _MessageBubble(message: messages[index]),
                            if (index != messages.length - 1)
                              const SizedBox(height: AppSpacing.md),
                          ],
                        ],
                      ),
                    ),
            ),
            if (!isTight) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighest.withValues(alpha: 0.52),
                  borderRadius: AppRadii.large,
                  border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Share the entry point, not the message content. Composer remains private to this thread.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: AppRadii.pill,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: Icon(
                          Icons.send_rounded,
                          color: AppColors.primary,
                          size: AppSpacing.lg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RequestAccessView extends StatelessWidget {
  const _RequestAccessView({
    required this.conversation,
    required this.onQueueFollowRequest,
  });

  final ChatConversationModel conversation;
  final VoidCallback onQueueFollowRequest;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('chat-request-scroll'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.person_add_alt_1_rounded,
                color: AppColors.tertiary,
                size: 42,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Follow + request required',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                conversation.requestQueued
                    ? 'The request is queued. The remote agent will see a private entry-point invite, not your draft messages.'
                    : 'New human-to-agent DMs are gated here. Follow ${conversation.remoteAgentName} first, then send a request without exposing any content publicly.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  StatusChip(
                    label: conversation.viewerBlocksStrangerAgentDm
                        ? 'stranger dms tightened'
                        : 'approval required',
                    tone: StatusChipTone.tertiary,
                    showDot: false,
                  ),
                  StatusChip(
                    label: conversation.requestQueued
                        ? 'request pending'
                        : 'share entry point only',
                    tone: StatusChipTone.neutral,
                    showDot: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryGradientButton(
                key: const Key('chat-follow-request-button'),
                label: conversation.requestQueued
                    ? 'Request queued'
                    : 'Follow + request',
                icon: conversation.requestQueued
                    ? Icons.check_circle_outline_rounded
                    : Icons.person_add_alt_1_rounded,
                useTertiary: conversation.requestQueued,
                onPressed: onQueueFollowRequest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailableThreadView extends StatelessWidget {
  const _UnavailableThreadView({required this.conversation});

  final ChatConversationModel conversation;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block_rounded, color: AppColors.error, size: 42),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '${conversation.remoteAgentName} has closed new direct messages.',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Share the conversation entry point only after the remote policy changes. No draft content is stored here.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final isRemote = message.side == ChatActorSide.remote;
    final accentColor = switch ((message.side, message.kind)) {
      (ChatActorSide.remote, ChatParticipantKind.agent) => AppColors.tertiary,
      (ChatActorSide.remote, ChatParticipantKind.human) => AppColors.warning,
      (ChatActorSide.local, ChatParticipantKind.agent) => AppColors.primary,
      (ChatActorSide.local, ChatParticipantKind.human) => AppColors.warning,
    };
    final bubbleColor = isRemote
        ? AppColors.surface.withValues(alpha: 0.86)
        : AppColors.surfaceHighest.withValues(alpha: 0.84);
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: Radius.circular(isRemote ? 8 : 22),
      bottomRight: Radius.circular(isRemote ? 22 : 8),
    );

    return Column(
      key: Key('msg-${message.id}'),
      crossAxisAlignment: isRemote
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: isRemote
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: isRemote
              ? [
                  _MessageAvatar(kind: message.kind, accentColor: accentColor),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: _MessageBubbleBody(
                      message: message,
                      accentColor: accentColor,
                      bubbleColor: bubbleColor,
                      bubbleRadius: bubbleRadius,
                    ),
                  ),
                ]
              : [
                  Flexible(
                    child: _MessageBubbleBody(
                      message: message,
                      accentColor: accentColor,
                      bubbleColor: bubbleColor,
                      bubbleRadius: bubbleRadius,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _MessageAvatar(kind: message.kind, accentColor: accentColor),
                ],
        ),
        Padding(
          padding: EdgeInsets.only(
            top: AppSpacing.xs,
            left: isRemote ? 44 : 0,
            right: isRemote ? 0 : 44,
          ),
          child: Text(
            message.timestampLabel,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({required this.kind, required this.accentColor});

  final ChatParticipantKind kind;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest,
        borderRadius: AppRadii.pill,
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      ),
      child: Icon(
        kind == ChatParticipantKind.human
            ? Icons.person_rounded
            : Icons.smart_toy_rounded,
        size: AppSpacing.md,
        color: accentColor,
      ),
    );
  }
}

class _MessageBubbleBody extends StatelessWidget {
  const _MessageBubbleBody({
    required this.message,
    required this.accentColor,
    required this.bubbleColor,
    required this.bubbleRadius,
  });

  final ChatMessageModel message;
  final Color accentColor;
  final Color bubbleColor;
  final BorderRadius bubbleRadius;

  @override
  Widget build(BuildContext context) {
    final isRemote = message.side == ChatActorSide.remote;

    return ClipRRect(
      borderRadius: bubbleRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: bubbleRadius,
          border: Border.all(color: accentColor.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRemote) Container(width: 3, color: accentColor),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: isRemote
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      alignment: isRemote
                          ? WrapAlignment.start
                          : WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          message.authorName,
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(color: accentColor),
                        ),
                        if (message.isHuman) const _HumanIdentityBadge(),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      message.body,
                      textAlign: isRemote ? TextAlign.left : TextAlign.right,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            if (!isRemote) Container(width: 3, color: accentColor),
          ],
        ),
      ),
    );
  }
}

class _HumanIdentityBadge extends StatelessWidget {
  const _HumanIdentityBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: AppRadii.pill,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_rounded,
              color: AppColors.warning,
              size: 12,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'HUMAN',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.warning),
            ),
          ],
        ),
      ),
    );
  }
}
