import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/locale/app_localization_extensions.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/chat_repository.dart';
import '../../core/session/app_session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/swipe_back_sheet.dart';

@immutable
class OwnedAgentCommandTarget {
  const OwnedAgentCommandTarget({
    required this.id,
    required this.name,
    required this.handle,
  });

  final String id;
  final String name;
  final String handle;
}

Future<void> showOwnedAgentCommandSheet({
  required BuildContext context,
  required AppSessionController session,
  required OwnedAgentCommandTarget agent,
}) {
  return showSwipeBackSheet<void>(
    context: context,
    builder: (context) =>
        OwnedAgentCommandSheet(session: session, agent: agent),
  );
}

class OwnedAgentCommandSheet extends StatefulWidget {
  const OwnedAgentCommandSheet({
    super.key,
    required this.session,
    required this.agent,
  });

  final AppSessionController session;
  final OwnedAgentCommandTarget agent;

  @override
  State<OwnedAgentCommandSheet> createState() => _OwnedAgentCommandSheetState();
}

class _OwnedAgentCommandSheetState extends State<OwnedAgentCommandSheet> {
  static const Duration _refreshInterval = Duration(seconds: 3);
  static const double _bottomSnapThreshold = 96;

  late final ChatRepository _chatRepository;
  late final TextEditingController _composerController;
  late final FocusNode _composerFocusNode;
  late final ScrollController _threadScrollController;
  bool _isLoadingThread = true;
  bool _isSendingMessage = false;
  bool _isRefreshingThread = false;
  String? _threadId;
  String? _loadError;
  String? _sendError;
  int _loadRequestId = 0;
  int _sendRequestId = 0;
  Timer? _refreshTimer;
  List<_OwnedAgentCommandMessage> _messages =
      const <_OwnedAgentCommandMessage>[];

  bool get _hasAuthenticatedHuman {
    return widget.session.isAuthenticated && widget.session.currentUser != null;
  }

  String? get _currentHumanId => widget.session.currentUser?.id;

  String get _currentHumanDisplayName {
    final displayName = widget.session.authState.displayName.trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final email = widget.session.authState.email.trim();
    if (email.isNotEmpty) {
      return email;
    }
    return context.localizedText(
      key: 'msgHumanAdminaabce010',
      en: 'Human admin',
      zhHans: '人类管理员',
    );
  }

  @override
  void initState() {
    super.initState();
    _chatRepository = ChatRepository(apiClient: widget.session.apiClient);
    _composerController = TextEditingController();
    _composerFocusNode = FocusNode();
    _threadScrollController = ScrollController();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(_refreshThreadSilently());
    });
    if (_hasAuthenticatedHuman) {
      unawaited(_loadCommandThread());
    } else {
      _isLoadingThread = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _composerController.dispose();
    _composerFocusNode.dispose();
    _threadScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCommandThread() async {
    final currentHumanId = _currentHumanId;
    if (!_hasAuthenticatedHuman || currentHumanId == null) {
      setState(() {
        _threadId = null;
        _messages = const <_OwnedAgentCommandMessage>[];
        _isLoadingThread = false;
        _loadError = context.localizedText(
          key: 'msgSignInAsTheOwnerBeforeOpeningThisPrivateThread4aa1888a',
          en: 'Sign in as the owner before opening this private thread.',
          zhHans: '请先以所有者身份登录，再打开这条私密线程。',
        );
      });
      return;
    }

    final requestId = ++_loadRequestId;
    setState(() {
      _isLoadingThread = true;
      _loadError = null;
      _sendError = null;
    });

    try {
      final threadsResponse = await _chatRepository.getThreads(
        activeAgentId: widget.agent.id,
        limit: 50,
      );
      if (!_canApplyLoadResult(requestId)) {
        return;
      }

      ChatThreadSummary? ownerThread;
      for (final thread in threadsResponse.threads) {
        final matchesLegacyOwnerFallback =
            thread.counterpart.type.toLowerCase() == 'human' &&
            thread.counterpart.id == currentHumanId;
        if (thread.isOwnedAgentCommandThread || matchesLegacyOwnerFallback) {
          ownerThread = thread;
          break;
        }
      }

      if (ownerThread == null) {
        setState(() {
          _threadId = null;
          _messages = const <_OwnedAgentCommandMessage>[];
          _isLoadingThread = false;
          _loadError = null;
        });
        return;
      }

      await _loadThreadMessages(
        threadId: ownerThread.threadId,
        requestId: requestId,
        shouldMarkRead: ownerThread.unreadCount > 0,
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await widget.session.handleUnauthorized();
      }
      if (!_canApplyLoadResult(requestId)) {
        return;
      }
      setState(() {
        _threadId = null;
        _messages = const <_OwnedAgentCommandMessage>[];
        _isLoadingThread = false;
        _loadError = error.message.trim().isEmpty
            ? context.localizedText(
                key: 'msgUnableToLoadThisPrivateThreadRightNow1422805d',
                en: 'Unable to load this private thread right now.',
                zhHans: '暂时无法加载这条私密线程。',
              )
            : error.message;
      });
    } catch (_) {
      if (!_canApplyLoadResult(requestId)) {
        return;
      }
      setState(() {
        _threadId = null;
        _messages = const <_OwnedAgentCommandMessage>[];
        _isLoadingThread = false;
        _loadError = context.localizedText(
          key: 'msgUnableToLoadThisPrivateThreadRightNow1422805d',
          en: 'Unable to load this private thread right now.',
          zhHans: '暂时无法加载这条私密线程。',
        );
      });
    }
  }

  Future<void> _loadThreadMessages({
    required String threadId,
    required int requestId,
    bool shouldMarkRead = false,
  }) async {
    final shouldAutoScroll =
        _threadId == null || _messages.isEmpty || _isNearThreadBottom();
    final response = await _chatRepository.getMessages(
      threadId: threadId,
      activeAgentId: widget.agent.id,
      limit: 50,
    );
    if (!_canApplyLoadResult(requestId)) {
      return;
    }

    if (shouldMarkRead) {
      _markThreadRead(threadId);
    }

    setState(() {
      _threadId = threadId;
      _messages = response.messages.map(_mapMessage).toList(growable: false);
      _isLoadingThread = false;
      _loadError = null;
    });
    if (shouldAutoScroll) {
      _scrollThreadToBottom();
    }
  }

  Future<void> _markThreadRead(String threadId) async {
    try {
      await _chatRepository.markThreadRead(
        threadId: threadId,
        activeAgentId: widget.agent.id,
      );
    } catch (_) {
      // Read receipt failure should not interrupt the thread itself.
    }
  }

  Future<void> _refreshThreadSilently() async {
    final threadId = _threadId;
    if (!_hasAuthenticatedHuman ||
        threadId == null ||
        threadId.isEmpty ||
        _isLoadingThread ||
        _isSendingMessage ||
        _isRefreshingThread) {
      return;
    }

    _isRefreshingThread = true;
    final shouldAutoScroll = _isNearThreadBottom();
    try {
      final response = await _chatRepository.getMessages(
        threadId: threadId,
        activeAgentId: widget.agent.id,
        limit: 50,
      );
      if (!mounted || _threadId != threadId) {
        return;
      }

      final nextMessages = response.messages
          .map(_mapMessage)
          .toList(growable: false);
      if (!_messagesChanged(nextMessages)) {
        return;
      }

      setState(() {
        _messages = nextMessages;
        _loadError = null;
      });
      unawaited(_markThreadRead(threadId));
      if (shouldAutoScroll) {
        _scrollThreadToBottom(animate: true);
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await widget.session.handleUnauthorized();
      }
    } catch (_) {
      // Silent refresh should never replace a readable thread with an error.
    } finally {
      _isRefreshingThread = false;
    }
  }

  Future<void> _sendMessage() async {
    final draft = _composerController.text.trim();
    final commandThreadIdMissingMessage = context.localizedText(
      key: 'msgCommandThreadIdWasNotReturnedca984c02',
      en: 'Command thread id was not returned.',
      zhHans: '未返回命令线程 ID。',
    );
    if (!_hasAuthenticatedHuman) {
      setState(() {
        _sendError = context.localizedText(
          key: 'msgSignInAsTheOwnerBeforeSendingMessagesd9acc950',
          en: 'Sign in as the owner before sending messages.',
          zhHans: '请先以所有者身份登录，再发送消息。',
        );
      });
      return;
    }
    if (draft.isEmpty || _isSendingMessage) {
      return;
    }

    final requestId = ++_sendRequestId;
    setState(() {
      _isSendingMessage = true;
      _sendError = null;
    });

    try {
      if (_threadId != null && _threadId!.isNotEmpty) {
        final response = await _chatRepository.sendThreadMessage(
          threadId: _threadId!,
          activeAgentId: widget.agent.id,
          content: draft,
          contentType: 'text',
        );
        if (!_canApplySendResult(requestId)) {
          return;
        }
        setState(() {
          _messages = [..._messages, _mapMessage(response.message)];
          _isSendingMessage = false;
          _sendError = null;
        });
        _scrollThreadToBottom(animate: true);
      } else {
        final response = await _chatRepository.sendDirectMessage(
          recipientType: 'agent',
          recipientAgentId: widget.agent.id,
          content: draft,
          contentType: 'text',
        );
        final createdThreadId = (response['threadId'] as String? ?? '').trim();
        if (createdThreadId.isEmpty) {
          throw StateError(commandThreadIdMissingMessage);
        }
        final messagesResponse = await _chatRepository.getMessages(
          threadId: createdThreadId,
          activeAgentId: widget.agent.id,
          limit: 50,
        );
        if (!_canApplySendResult(requestId)) {
          return;
        }
        setState(() {
          _threadId = createdThreadId;
          _messages = messagesResponse.messages
              .map(_mapMessage)
              .toList(growable: false);
          _isSendingMessage = false;
          _sendError = null;
          _loadError = null;
        });
        _scrollThreadToBottom();
      }

      _composerController.clear();
      _composerFocusNode.requestFocus();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await widget.session.handleUnauthorized();
      }
      if (!_canApplySendResult(requestId)) {
        return;
      }
      setState(() {
        _isSendingMessage = false;
        _sendError = error.message.trim().isEmpty
            ? context.localizedText(
                key: 'msgUnableToSendThisMessageRightNow010931ab',
                en: 'Unable to send this message right now.',
                zhHans: '暂时无法发送这条消息。',
              )
            : error.message;
      });
    } catch (_) {
      if (!_canApplySendResult(requestId)) {
        return;
      }
      setState(() {
        _isSendingMessage = false;
        _sendError = context.localizedText(
          key: 'msgUnableToSendThisMessageRightNow010931ab',
          en: 'Unable to send this message right now.',
          zhHans: '暂时无法发送这条消息。',
        );
      });
    }
  }

  bool _canApplyLoadResult(int requestId) {
    return mounted && requestId == _loadRequestId;
  }

  bool _canApplySendResult(int requestId) {
    return mounted && requestId == _sendRequestId;
  }

  bool _messagesChanged(List<_OwnedAgentCommandMessage> nextMessages) {
    if (nextMessages.length != _messages.length) {
      return true;
    }
    if (nextMessages.isEmpty) {
      return false;
    }
    return nextMessages.last.id != _messages.last.id;
  }

  bool _isNearThreadBottom() {
    if (!_threadScrollController.hasClients) {
      return true;
    }
    final position = _threadScrollController.position;
    return position.maxScrollExtent - position.pixels <= _bottomSnapThreshold;
  }

  void _scrollThreadToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_threadScrollController.hasClients) {
        return;
      }
      final targetOffset = _threadScrollController.position.maxScrollExtent;
      if (animate) {
        _threadScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      _threadScrollController.jumpTo(targetOffset);
    });
  }

  _OwnedAgentCommandMessage _mapMessage(ChatMessageRecord message) {
    final currentHumanId = _currentHumanId;
    final isHuman = message.actor.type.toLowerCase() == 'human';
    final isLocal = isHuman && message.actor.id == currentHumanId;
    final body = message.content?.trim();
    return _OwnedAgentCommandMessage(
      id: message.eventId,
      authorName: message.actor.displayName.trim().isEmpty
          ? isHuman
                ? _currentHumanDisplayName
                : widget.agent.name
          : message.actor.displayName.trim(),
      body: body != null && body.isNotEmpty
          ? body
          : message.contentType.toLowerCase() == 'image'
          ? context.localizedText(
              key: 'msgImage50e19fda',
              en: 'Image',
              zhHans: '图片',
            )
          : context.localizedText(
              key: 'msgOwnedAgentCommandUnsupportedMessage',
              en: 'Unsupported message',
              zhHans: '暂不支持的消息',
            ),
      timestampLabel: _timestampLabel(message.occurredAt),
      isHuman: isHuman,
      isLocal: isLocal,
    );
  }

  String _timestampLabel(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return '';
    }
    final local = parsed.toLocal();
    final now = DateTime.now();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final isSameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isSameDay) {
      return '$hour:$minute';
    }
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final handleLabel = widget.agent.handle.startsWith('@')
        ? widget.agent.handle
        : '@${widget.agent.handle}';
    final activeAgentName = widget.agent.name.trim().isEmpty
        ? handleLabel
        : widget.agent.name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: GlassPanel(
          key: const Key('owned-agent-command-sheet-shared'),
          borderRadius: AppRadii.hero,
          padding: EdgeInsets.zero,
          accentColor: AppColors.primary,
          child: Padding(
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
                            context.localizedText(
                              key: 'msgPrivateOwnerChat3a3d94c3',
                              en: 'Private Owner Chat',
                              zhHans: '私密所有者聊天',
                            ),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '$activeAgentName  $handleLabel',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    _OwnedAgentCommandIconButton(
                      buttonKey: const Key(
                        'owned-agent-command-refresh-button-shared',
                      ),
                      icon: Icons.refresh_rounded,
                      onTap: _isLoadingThread ? null : _loadCommandThread,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _OwnedAgentCommandIconButton(
                      buttonKey: const Key(
                        'close-owned-agent-command-button-shared',
                      ),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _OwnedAgentInfoPill(
                  icon: Icons.chat_bubble_rounded,
                  accentColor: AppColors.primaryFixed,
                  text: context.localizedText(
                    key:
                        'msgThisIsTheRealPrivateHumanToAgentCommandThread357cc1f3',
                    en: 'This is the real private human-to-agent command thread. First send creates it if it does not exist yet.',
                    zhHans: '这是人类与该智能体之间真实的私密命令线程。如果尚未创建，首次发送消息时会自动建立。',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(child: _buildThreadPanel(activeAgentName)),
                const SizedBox(height: AppSpacing.md),
                _buildComposer(activeAgentName),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThreadPanel(String activeAgentName) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.76),
        borderRadius: AppRadii.large,
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: _isLoadingThread
            ? const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            : _loadError != null
            ? Center(
                child: Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                ),
              )
            : _messages.isEmpty
            ? _OwnedAgentCommandEmptyState(agentName: activeAgentName)
            : SingleChildScrollView(
                key: const Key('owned-agent-command-scroll-shared'),
                controller: _threadScrollController,
                child: Column(
                  children: [
                    for (var index = 0; index < _messages.length; index++) ...[
                      _OwnedAgentCommandBubble(message: _messages[index]),
                      if (index != _messages.length - 1)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildComposer(String activeAgentName) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighest.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.outline.withValues(alpha: 0.14),
                      ),
                    ),
                    child: TextField(
                      key: const Key('owned-agent-command-input-shared'),
                      controller: _composerController,
                      focusNode: _composerFocusNode,
                      enabled: !_isSendingMessage,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: context.localizedText(
                          key: 'msgSendAMessageToActiveAgentNameef7c820d',
                          args: <String, Object?>{
                            'activeAgentName': activeAgentName,
                          },
                          en: 'Send a message to $activeAgentName...',
                          zhHans: '给 $activeAgentName 发送一条消息...',
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  key: const Key('owned-agent-command-send-button-shared'),
                  onPressed: _isSendingMessage ? null : _sendMessage,
                  child: _isSendingMessage
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
            if (_sendError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _sendError!,
                  key: const Key('owned-agent-command-error-shared'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OwnedAgentCommandMessage {
  const _OwnedAgentCommandMessage({
    required this.id,
    required this.authorName,
    required this.body,
    required this.timestampLabel,
    required this.isHuman,
    required this.isLocal,
  });

  final String id;
  final String authorName;
  final String body;
  final String timestampLabel;
  final bool isHuman;
  final bool isLocal;
}

class _OwnedAgentCommandEmptyState extends StatelessWidget {
  const _OwnedAgentCommandEmptyState({required this.agentName});

  final String agentName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.primary.withValues(alpha: 0.88),
                size: 30,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.localizedText(
                key: 'msgNoPrivateThreadYet2461de57',
                en: 'No private thread yet',
                zhHans: '还没有私密线程',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 17,
                color: AppColors.onSurface.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.localizedText(
                key: 'msgOwnedAgentCommandFirstMessageOpensPrivateLine',
                args: <String, Object?>{'agentName': agentName},
                en: 'Your first message opens a private human-to-agent line with $agentName.',
                zhHans: '你的第一条消息会为你和 $agentName 打开一条私密命令通道。',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                height: 1.42,
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnedAgentCommandBubble extends StatelessWidget {
  const _OwnedAgentCommandBubble({required this.message});

  final _OwnedAgentCommandMessage message;

  @override
  Widget build(BuildContext context) {
    final isRemote = !message.isLocal;
    final accentColor = message.isHuman ? AppColors.warning : AppColors.primary;
    final bubbleColor = isRemote
        ? AppColors.surface.withValues(alpha: 0.86)
        : AppColors.surfaceHighest.withValues(alpha: 0.84);
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isRemote ? 0 : 16),
      bottomRight: Radius.circular(isRemote ? 16 : 0),
    );

    return Column(
      key: Key('owned-agent-command-msg-shared-${message.id}'),
      crossAxisAlignment: isRemote
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: isRemote
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          children: [
            if (isRemote) ...[
              _OwnedAgentCommandAvatar(
                label: message.authorName,
                accentColor: accentColor,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: bubbleRadius,
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.authorName,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SelectableText(message.body),
                      if (message.timestampLabel.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          message.timestampLabel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.onSurfaceMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (!isRemote) ...[
              const SizedBox(width: AppSpacing.sm),
              _OwnedAgentCommandAvatar(
                label: message.authorName,
                accentColor: accentColor,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _OwnedAgentCommandAvatar extends StatelessWidget {
  const _OwnedAgentCommandAvatar({
    required this.label,
    required this.accentColor,
  });

  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: accentColor.withValues(alpha: 0.16),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: accentColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OwnedAgentCommandIconButton extends StatelessWidget {
  const _OwnedAgentCommandIconButton({
    required this.buttonKey,
    required this.icon,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surfaceHigh.withValues(alpha: 0.46),
        foregroundColor: AppColors.onSurfaceMuted,
      ),
      icon: Icon(icon),
    );
  }
}

class _OwnedAgentInfoPill extends StatelessWidget {
  const _OwnedAgentInfoPill({
    required this.icon,
    required this.accentColor,
    required this.text,
  });

  final IconData icon;
  final Color accentColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: AppRadii.large,
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accentColor, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  height: 1.42,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
