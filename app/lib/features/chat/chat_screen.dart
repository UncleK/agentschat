import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/chat_repository.dart';
import '../../core/network/follow_repository.dart';
import '../../core/session/app_session_controller.dart';
import '../../core/session/app_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../core/widgets/status_chip.dart';
import 'chat_models.dart';
import 'chat_view_model.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.initialViewModel,
    this.chatRepository,
    this.followRepository,
    this.liveConversationTransform,
    this.enableSessionSync = true,
  });

  final ChatViewModel? initialViewModel;
  final ChatRepository? chatRepository;
  final FollowRepository? followRepository;
  final List<ChatConversationModel> Function(
    List<ChatConversationModel> liveConversations,
  )?
  liveConversationTransform;
  final bool enableSessionSync;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late ChatViewModel _viewModel;
  late final TextEditingController _conversationSearchController;
  late final FocusNode _conversationSearchFocusNode;
  late final TextEditingController _threadSearchController;
  late final FocusNode _threadSearchFocusNode;
  bool _showCompactThread = false;
  bool _isLoadingMessages = false;
  String? _messageLoadError;
  String? _lastShareAnnouncement;
  String? _sessionSignature;
  int _threadsRequestId = 0;
  int _messagesRequestId = 0;
  int _readRequestId = 0;
  int _followRequestId = 0;
  ChatRepository? _chatRepository;
  FollowRepository? _followRepository;
  String? _followRequestConversationId;
  String? _followRequestErrorConversationId;
  String? _followRequestErrorMessage;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.initialViewModel ?? ChatViewModel.signedInSample();
    _conversationSearchController = TextEditingController(
      text: _viewModel.conversationSearchQuery,
    );
    _conversationSearchFocusNode = FocusNode();
    _threadSearchController = TextEditingController(
      text: _viewModel.threadSearchQuery,
    );
    _threadSearchFocusNode = FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AppSessionScope.maybeOf(context);
    if (session == null) {
      _chatRepository = widget.chatRepository;
      _followRepository = widget.followRepository;
      _sessionSignature = null;
      return;
    }

    _chatRepository =
        widget.chatRepository ?? ChatRepository(apiClient: session.apiClient);
    _followRepository =
        widget.followRepository ??
        FollowRepository(apiClient: session.apiClient);
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
      return;
    }
    _sessionSignature = nextSignature;
    unawaited(_syncToSession(session));
  }

  @override
  void dispose() {
    _conversationSearchController.dispose();
    _conversationSearchFocusNode.dispose();
    _threadSearchController.dispose();
    _threadSearchFocusNode.dispose();
    super.dispose();
  }

  void _syncConversationSearchController() {
    _conversationSearchController.value = TextEditingValue(
      text: _viewModel.conversationSearchQuery,
      selection: TextSelection.collapsed(
        offset: _viewModel.conversationSearchQuery.length,
      ),
    );
  }

  void _syncThreadSearchController() {
    _threadSearchController.value = TextEditingValue(
      text: _viewModel.threadSearchQuery,
      selection: TextSelection.collapsed(
        offset: _viewModel.threadSearchQuery.length,
      ),
    );
  }

  Future<void> _syncToSession(AppSessionController session) async {
    if (session.bootstrapStatus != AppSessionBootstrapStatus.ready) {
      _invalidateLiveRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = ChatViewModel.signedInSample();
        _showCompactThread = false;
        _isLoadingMessages = false;
        _messageLoadError = null;
        _lastShareAnnouncement = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _syncConversationSearchController();
        _syncThreadSearchController();
      });
      return;
    }

    final userId = session.currentUser?.id;
    final activeAgent = session.currentActiveAgent;
    if (session.isUsingLocalPreviewAgents) {
      final previewAgentName = _displayName(
        activeAgent?.displayName ?? '',
        fallback: 'AETHER-7',
      );
      setState(() {
        _viewModel = ChatViewModel.previewForActiveAgent(previewAgentName);
        _showCompactThread = false;
        _isLoadingMessages = false;
        _messageLoadError = null;
        _lastShareAnnouncement = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _syncConversationSearchController();
        _syncThreadSearchController();
      });
      return;
    }

    if (!session.isAuthenticated ||
        userId == null ||
        userId.isEmpty ||
        activeAgent == null) {
      _invalidateLiveRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = ChatViewModel.previewForActiveAgent('AETHER-7');
        _showCompactThread = false;
        _isLoadingMessages = false;
        _messageLoadError = null;
        _lastShareAnnouncement = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _syncConversationSearchController();
        _syncThreadSearchController();
      });
      return;
    }

    final activeAgentId = activeAgent.id;
    final activeAgentName = _displayName(
      activeAgent.displayName,
      fallback: activeAgent.handle,
    );
    final requestId = ++_threadsRequestId;
    _messagesRequestId += 1;
    _readRequestId += 1;
    if (mounted) {
      setState(() {
        _viewModel = ChatViewModel.loadingThreads(
          activeAgentName: activeAgentName,
        );
        _showCompactThread = false;
        _isLoadingMessages = false;
        _messageLoadError = null;
        _lastShareAnnouncement = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _syncConversationSearchController();
        _syncThreadSearchController();
      });
    }

    try {
      final response = await _chatRepository!.getThreads(
        activeAgentId: activeAgentId,
      );
      if (!_canApplyAgentScopedResult(
        requestId: requestId,
        currentRequestId: _threadsRequestId,
        userId: userId,
        activeAgentId: activeAgentId,
      )) {
        return;
      }

      var conversations = response.threads
          .map(_mapConversation)
          .toList(growable: false);
      final liveConversationTransform = widget.liveConversationTransform;
      if (liveConversationTransform != null) {
        conversations = liveConversationTransform(
          conversations,
        ).toList(growable: false);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = ChatViewModel.ready(
          conversations: conversations,
          activeAgentName: activeAgentName,
        );
        _isLoadingMessages = false;
        _messageLoadError = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session.handleUnauthorized();
        return;
      }
      if (!_canApplyAgentScopedResult(
        requestId: requestId,
        currentRequestId: _threadsRequestId,
        userId: userId,
        activeAgentId: activeAgentId,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = ChatViewModel.error(
          message: 'Unable to load direct messages right now.',
          activeAgentName: activeAgentName,
        );
        _isLoadingMessages = false;
        _messageLoadError = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
      });
    } catch (_) {
      if (!_canApplyAgentScopedResult(
        requestId: requestId,
        currentRequestId: _threadsRequestId,
        userId: userId,
        activeAgentId: activeAgentId,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = ChatViewModel.error(
          message: 'Unable to load direct messages right now.',
          activeAgentName: activeAgentName,
        );
        _isLoadingMessages = false;
        _messageLoadError = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
      });
    }
  }

  void _invalidateLiveRequests() {
    _threadsRequestId += 1;
    _messagesRequestId += 1;
    _readRequestId += 1;
    _followRequestId += 1;
  }

  bool _canApplyAgentScopedResult({
    required int requestId,
    required int currentRequestId,
    required String userId,
    required String activeAgentId,
  }) {
    final session = AppSessionScope.maybeOf(context);
    return mounted &&
        requestId == currentRequestId &&
        session != null &&
        session.bootstrapStatus == AppSessionBootstrapStatus.ready &&
        session.currentUser?.id == userId &&
        session.currentActiveAgent?.id == activeAgentId;
  }

  bool _canApplyMessageResult({
    required int requestId,
    required String userId,
    required String activeAgentId,
    required String conversationId,
  }) {
    return _canApplyAgentScopedResult(
          requestId: requestId,
          currentRequestId: _messagesRequestId,
          userId: userId,
          activeAgentId: activeAgentId,
        ) &&
        _viewModel.selectedConversationId == conversationId;
  }

  bool _canApplyReadResult({
    required int requestId,
    required String userId,
    required String activeAgentId,
    required String conversationId,
  }) {
    return _canApplyAgentScopedResult(
          requestId: requestId,
          currentRequestId: _readRequestId,
          userId: userId,
          activeAgentId: activeAgentId,
        ) &&
        _viewModel.selectedConversationId == conversationId;
  }

  bool _shouldLoadConversationThread(ChatConversationModel conversation) {
    return conversation.hasExistingThread;
  }

  void debugInjectAndSelectConversation(ChatConversationModel conversation) {
    final nextConversations = _viewModel.conversations
        .where((item) => item.id != conversation.id)
        .followedBy([conversation])
        .toList(growable: false);
    _viewModel = _viewModel.copyWith(
      conversations: nextConversations,
      surfaceState: ChatSurfaceState.ready,
      surfaceMessage: null,
    );
    _selectConversation(conversation);
  }

  void _selectConversation(ChatConversationModel conversation) {
    final shouldLoadConversationThread = _shouldLoadConversationThread(
      conversation,
    );
    setState(() {
      _viewModel = _viewModel
          .selectConversation(conversation.id)
          .replaceConversationMessages(conversation.id, const []);
      _syncThreadSearchController();
      _showCompactThread = true;
      _isLoadingMessages = shouldLoadConversationThread;
      _messageLoadError = null;
      _lastShareAnnouncement = null;
    });

    if (!shouldLoadConversationThread) {
      return;
    }

    final session = AppSessionScope.maybeOf(context);
    if (session == null ||
        !session.isAuthenticated ||
        session.currentActiveAgent == null) {
      setState(() {
        _isLoadingMessages = false;
      });
      return;
    }
    unawaited(_loadConversationMessages(conversationId: conversation.id));
  }

  Future<void> _loadConversationMessages({
    required String conversationId,
  }) async {
    final session = AppSessionScope.maybeOf(context);
    final currentUserId = session?.currentUser?.id;
    final activeAgentId = session?.currentActiveAgent?.id;
    if (session == null || currentUserId == null || activeAgentId == null) {
      return;
    }

    final requestId = ++_messagesRequestId;
    try {
      final response = await _chatRepository!.getMessages(
        threadId: conversationId,
        activeAgentId: activeAgentId,
      );
      if (!_canApplyMessageResult(
        requestId: requestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
        conversationId: conversationId,
      )) {
        return;
      }

      final messages = response.messages
          .map(
            (message) => _mapMessage(
              message,
              currentUserId: currentUserId,
              activeAgentId: activeAgentId,
            ),
          )
          .toList(growable: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = _viewModel.replaceConversationMessages(
          conversationId,
          messages,
        );
        _isLoadingMessages = false;
        _messageLoadError = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          _markConversationRead(
            conversationId: conversationId,
            currentUserId: currentUserId,
            activeAgentId: activeAgentId,
          ),
        );
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session.handleUnauthorized();
        return;
      }
      if (!_canApplyMessageResult(
        requestId: requestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
        conversationId: conversationId,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingMessages = false;
        _messageLoadError = 'Unable to load this thread right now.';
      });
    } catch (_) {
      if (!_canApplyMessageResult(
        requestId: requestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
        conversationId: conversationId,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingMessages = false;
        _messageLoadError = 'Unable to load this thread right now.';
      });
    }
  }

  Future<void> _markConversationRead({
    required String conversationId,
    required String currentUserId,
    required String activeAgentId,
  }) async {
    final requestId = ++_readRequestId;
    try {
      await _chatRepository!.markThreadRead(
        threadId: conversationId,
        activeAgentId: activeAgentId,
      );
      if (!_canApplyReadResult(
        requestId: requestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
        conversationId: conversationId,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = _viewModel.markConversationRead(conversationId);
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        final session = AppSessionScope.maybeOf(context);
        if (session != null) {
          await session.handleUnauthorized();
        }
      }
    } catch (_) {
      // Keep read failures non-blocking; the thread is already visible.
    }
  }

  void _handleThreadSearchChange(String value) {
    setState(() {
      _viewModel = _viewModel.updateThreadSearch(value);
    });
  }

  void _handleConversationSearchChange(String value) {
    setState(() {
      _viewModel = _viewModel.updateConversationSearch(value);
    });
  }

  void _clearConversationSearch() {
    setState(() {
      _viewModel = _viewModel.clearConversationSearch();
      _syncConversationSearchController();
    });
  }

  void _focusConversationSearch() {
    if (_showCompactThread) {
      setState(() {
        _showCompactThread = false;
        _viewModel = _viewModel.clearSelection();
        _syncThreadSearchController();
        _lastShareAnnouncement = null;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _conversationSearchFocusNode.requestFocus();
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
      _viewModel = _viewModel.clearSelection();
      _syncThreadSearchController();
      _lastShareAnnouncement = null;
    });
  }

  bool _isFollowRequestPending(ChatConversationModel conversation) {
    return _followRequestConversationId == conversation.id;
  }

  String? _followRequestBlockedReason(ChatConversationModel conversation) {
    if (conversation.requestQueued) {
      return null;
    }
    final session = AppSessionScope.maybeOf(context);
    if (session == null ||
        !session.isAuthenticated ||
        session.currentUser == null) {
      return 'Sign in to follow and request access.';
    }
    if (session.bootstrapStatus != AppSessionBootstrapStatus.ready) {
      return 'Wait for the current session to finish resolving before requesting access.';
    }
    if (session.currentActiveAgent == null) {
      return 'Activate an owned agent to follow and request access.';
    }
    return null;
  }

  String? _followRequestError(ChatConversationModel conversation) {
    if (_followRequestErrorConversationId != conversation.id) {
      return null;
    }
    return _followRequestErrorMessage;
  }

  Future<void> _queueFollowRequest(ChatConversationModel conversation) async {
    final session = AppSessionScope.maybeOf(context);
    final currentUserId = session?.currentUser?.id;
    final activeAgentId = session?.currentActiveAgent?.id;
    final blockedReason = _followRequestBlockedReason(conversation);
    if (session == null ||
        blockedReason != null ||
        currentUserId == null ||
        currentUserId.isEmpty ||
        activeAgentId == null ||
        activeAgentId.isEmpty ||
        _followRepository == null) {
      return;
    }

    final requestId = ++_followRequestId;
    if (mounted) {
      setState(() {
        _followRequestConversationId = conversation.id;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
      });
    }

    try {
      // Request-only conversations are modeled against the remote agent id.
      await _followRepository!.follow(
        targetType: 'agent',
        targetId: conversation.id,
        actorAgentId: activeAgentId,
      );
      if (!_canApplyAgentScopedResult(
        requestId: requestId,
        currentRequestId: _followRequestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = _viewModel.queueFollowRequest(conversation.id);
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Following ${conversation.remoteAgentName} and queued DM request',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        if (mounted) {
          setState(() {
            _followRequestConversationId = null;
          });
        }
        await session.handleUnauthorized();
        return;
      }
      if (!_canApplyAgentScopedResult(
        requestId: requestId,
        currentRequestId: _followRequestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      final message = error.message.trim().isEmpty
          ? 'Unable to follow and queue the DM request right now.'
          : error.message;
      setState(() {
        _followRequestConversationId = null;
        _followRequestErrorConversationId = conversation.id;
        _followRequestErrorMessage = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!_canApplyAgentScopedResult(
        requestId: requestId,
        currentRequestId: _followRequestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      const message = 'Unable to follow and queue the DM request right now.';
      setState(() {
        _followRequestConversationId = null;
        _followRequestErrorConversationId = conversation.id;
        _followRequestErrorMessage = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
    }
  }

  ChatConversationModel _mapConversation(ChatThreadSummary thread) {
    final counterpartName = _displayName(
      thread.counterpart.displayName,
      fallback: thread.counterpart.handle ?? thread.counterpart.id,
    );
    final counterpartHandle =
        thread.counterpart.handle == null ||
            thread.counterpart.handle!.trim().isEmpty
        ? '@${thread.counterpart.id}'
        : thread.counterpart.handle!.startsWith('@')
        ? thread.counterpart.handle!
        : '@${thread.counterpart.handle!}';
    return ChatConversationModel(
      id: thread.threadId,
      remoteAgentName: counterpartName,
      remoteAgentHeadline: counterpartHandle,
      channelTitle: counterpartName,
      participantsLabel: 'live direct thread',
      latestPreview: thread.lastMessage.preview.trim().isEmpty
          ? 'Direct thread ready.'
          : thread.lastMessage.preview,
      latestSpeakerLabel: counterpartName,
      latestSpeakerIsHuman: false,
      lastActivityLabel: _timestampLabel(thread.lastMessage.occurredAt),
      entryPoint: 'agentschat://dm/${thread.threadId}',
      remoteDmMode: ChatRemoteDmMode.open,
      messages: const [],
      hasUnread: thread.unreadCount > 0,
      unreadCount: thread.unreadCount,
      remoteAgentOnline: false,
      hasExistingThread: true,
      viewerFollowsRemoteAgent: true,
    );
  }

  ChatMessageModel _mapMessage(
    ChatMessageRecord message, {
    required String currentUserId,
    required String activeAgentId,
  }) {
    final isHuman = message.actor.type.toLowerCase() == 'human';
    final isLocal = isHuman
        ? message.actor.id == currentUserId
        : message.actor.id == activeAgentId;
    return ChatMessageModel(
      id: message.eventId,
      authorName: _displayName(
        message.actor.displayName,
        fallback: message.actor.id,
      ),
      body: _messageBody(message),
      timestampLabel: _timeLabel(message.occurredAt),
      side: isLocal ? ChatActorSide.local : ChatActorSide.remote,
      kind: isHuman ? ChatParticipantKind.human : ChatParticipantKind.agent,
    );
  }

  String _messageBody(ChatMessageRecord message) {
    final content = message.content?.trim();
    if (content != null && content.isNotEmpty) {
      return content;
    }
    if (message.contentType.toLowerCase() == 'image') {
      return 'Image';
    }
    return 'Unsupported message';
  }

  String _displayName(String value, {required String fallback}) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }

  String _timestampLabel(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return '${_twoDigits(parsed.toLocal().hour)}:${_twoDigits(parsed.toLocal().minute)}';
  }

  String _timeLabel(String value) => _timestampLabel(value);

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _surfaceStatusLabel(ChatConversationModel? selectedConversation) {
    if (selectedConversation != null) {
      return _viewModel.statusLabelFor(selectedConversation);
    }
    if (_viewModel.isResolvingActiveAgent) {
      return 'resolving agent';
    }
    if (_viewModel.isLoadingThreads) {
      return 'syncing inbox';
    }
    if (_viewModel.isBlocked) {
      return 'no active agent';
    }
    if (_viewModel.isError) {
      return 'sync error';
    }
    if (_viewModel.hasConversations) {
      return 'select a thread';
    }
    return 'inbox empty';
  }

  _ChatEmptyState _railEmptyState() {
    if (_viewModel.isResolvingActiveAgent) {
      return const _ChatEmptyState(
        title: 'Resolving active agent',
        message:
            'Direct threads stay blocked until the session picks a valid owned agent.',
        showProgress: true,
      );
    }
    if (_viewModel.isLoadingThreads) {
      return _ChatEmptyState(
        title: 'Loading direct channels',
        message:
            _viewModel.surfaceMessage ??
            'The inbox is syncing for the current active agent.',
        showProgress: true,
      );
    }
    if (_viewModel.isBlocked) {
      return _ChatEmptyState(
        title: 'No active agent',
        message:
            _viewModel.surfaceMessage ??
            'Select an owned agent in Hub to load direct messages.',
      );
    }
    if (_viewModel.isError) {
      return _ChatEmptyState(
        title: 'Unable to load chat',
        message:
            _viewModel.surfaceMessage ??
            'Try again after the current active agent is stable.',
      );
    }
    return _ChatEmptyState(
      title: 'No direct threads yet',
      message:
          'No private threads exist yet for ${_viewModel.activeAgentName ?? 'the current agent'}.',
    );
  }

  _ChatEmptyState _threadPlaceholderState() {
    if (_viewModel.hasConversations) {
      return _ChatEmptyState(
        title: 'Select a thread',
        message:
            'Choose a direct channel for ${_viewModel.activeAgentName ?? 'the current agent'} to inspect messages.',
      );
    }
    return _railEmptyState();
  }

  @override
  Widget build(BuildContext context) {
    final selectedConversation = _viewModel.selectedConversationOrNull;

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

          return Column(
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
                          'AGENTS CHAT',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.primary),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'AGENTS CHAT',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Synchronized neural channels with active agents.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  IconButton(
                    key: const Key('chat-conversation-search-button'),
                    onPressed: _focusConversationSearch,
                    icon: const Icon(Icons.search_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceHighest.withValues(
                        alpha: 0.4,
                      ),
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if ((_viewModel.activeAgentName ?? '').isNotEmpty)
                    StatusChip(
                      label: _viewModel.activeAgentName!,
                      tone: StatusChipTone.primary,
                      showDot: false,
                    ),
                  StatusChip(
                    label:
                        '${_viewModel.visibleConversations.length} active threads',
                  ),
                  StatusChip(
                    label: _surfaceStatusLabel(selectedConversation),
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
                              selectedConversationId:
                                  _viewModel.selectedConversationId,
                              conversationSearchController:
                                  _conversationSearchController,
                              conversationSearchFocusNode:
                                  _conversationSearchFocusNode,
                              emptyState: _railEmptyState(),
                              onConversationSearchChange:
                                  _handleConversationSearchChange,
                              onClearConversationSearch:
                                  _clearConversationSearch,
                              onFocusConversationSearch:
                                  _focusConversationSearch,
                              onSelectConversation: _selectConversation,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: selectedConversation == null
                                ? _ThreadPlaceholderPanel(
                                    state: _threadPlaceholderState(),
                                  )
                                : _ThreadPanel(
                                    viewModel: _viewModel,
                                    conversation: selectedConversation,
                                    compact: false,
                                    isLoadingMessages: _isLoadingMessages,
                                    messageLoadError: _messageLoadError,
                                    shareAnnouncement: _lastShareAnnouncement,
                                    threadSearchController:
                                        _threadSearchController,
                                    threadSearchFocusNode:
                                        _threadSearchFocusNode,
                                    onThreadSearchChange:
                                        _handleThreadSearchChange,
                                    onCloseThreadSearch: _closeThreadSearch,
                                    onMenuAction: _handleMenuAction,
                                    onQueueFollowRequest: _queueFollowRequest,
                                    isQueueFollowRequestPending:
                                        _isFollowRequestPending(
                                          selectedConversation,
                                        ),
                                    queueFollowRequestBlockedReason:
                                        _followRequestBlockedReason(
                                          selectedConversation,
                                        ),
                                    queueFollowRequestErrorMessage:
                                        _followRequestError(
                                          selectedConversation,
                                        ),
                                  ),
                          ),
                        ],
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child:
                            _showCompactThread && selectedConversation != null
                            ? _ThreadPanel(
                                key: ValueKey(
                                  'chat-thread-${selectedConversation.id}',
                                ),
                                viewModel: _viewModel,
                                conversation: selectedConversation,
                                compact: true,
                                isLoadingMessages: _isLoadingMessages,
                                messageLoadError: _messageLoadError,
                                shareAnnouncement: _lastShareAnnouncement,
                                threadSearchController: _threadSearchController,
                                threadSearchFocusNode: _threadSearchFocusNode,
                                onThreadSearchChange: _handleThreadSearchChange,
                                onCloseThreadSearch: _closeThreadSearch,
                                onMenuAction: _handleMenuAction,
                                onQueueFollowRequest: _queueFollowRequest,
                                isQueueFollowRequestPending:
                                    _isFollowRequestPending(
                                      selectedConversation,
                                    ),
                                queueFollowRequestBlockedReason:
                                    _followRequestBlockedReason(
                                      selectedConversation,
                                    ),
                                queueFollowRequestErrorMessage:
                                    _followRequestError(selectedConversation),
                                onBack: _showConversationList,
                              )
                            : _ConversationRail(
                                key: const ValueKey('chat-list'),
                                viewModel: _viewModel,
                                compact: true,
                                selectedConversationId:
                                    _viewModel.selectedConversationId,
                                conversationSearchController:
                                    _conversationSearchController,
                                conversationSearchFocusNode:
                                    _conversationSearchFocusNode,
                                emptyState: _railEmptyState(),
                                onConversationSearchChange:
                                    _handleConversationSearchChange,
                                onClearConversationSearch:
                                    _clearConversationSearch,
                                onFocusConversationSearch:
                                    _focusConversationSearch,
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

class _ChatEmptyState {
  const _ChatEmptyState({
    required this.title,
    required this.message,
    this.showProgress = false,
  });

  final String title;
  final String message;
  final bool showProgress;
}

class _ConversationRail extends StatelessWidget {
  const _ConversationRail({
    super.key,
    required this.viewModel,
    required this.compact,
    required this.selectedConversationId,
    required this.conversationSearchController,
    required this.conversationSearchFocusNode,
    required this.emptyState,
    required this.onConversationSearchChange,
    required this.onClearConversationSearch,
    required this.onFocusConversationSearch,
    required this.onSelectConversation,
  });

  final ChatViewModel viewModel;
  final bool compact;
  final String? selectedConversationId;
  final TextEditingController conversationSearchController;
  final FocusNode conversationSearchFocusNode;
  final _ChatEmptyState emptyState;
  final ValueChanged<String> onConversationSearchChange;
  final VoidCallback onClearConversationSearch;
  final VoidCallback onFocusConversationSearch;
  final ValueChanged<ChatConversationModel> onSelectConversation;

  @override
  Widget build(BuildContext context) {
    final activeSearchQuery = viewModel.conversationSearchQuery.trim();
    final railEmptyState =
        viewModel.conversations.isNotEmpty &&
            viewModel.visibleConversations.isEmpty &&
            activeSearchQuery.isNotEmpty
        ? const _ChatEmptyState(
            title: 'No matching channels',
            message:
                'Try a remote agent name, operator label, or preview keyword.',
          )
        : emptyState;

    return GlassPanel(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Synchronized channels',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const Key('chat-rail-search-button'),
                onPressed: onFocusConversationSearch,
                icon: const Icon(Icons.search_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceHighest.withValues(
                    alpha: 0.32,
                  ),
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            compact
                ? 'Remote agent identity stays primary.'
                : 'Cards stay grouped by remote agent, even when the latest visible speaker is a human admin.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          AnimatedBuilder(
            animation: conversationSearchFocusNode,
            builder: (context, child) {
              final isSearchVisible =
                  conversationSearchFocusNode.hasFocus ||
                  activeSearchQuery.isNotEmpty;
              if (!isSearchVisible) {
                return SizedBox(
                  height: compact ? AppSpacing.md : AppSpacing.lg,
                );
              }

              return Column(
                children: [
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('chat-conversation-search-input'),
                    controller: conversationSearchController,
                    focusNode: conversationSearchFocusNode,
                    onChanged: onConversationSearchChange,
                    decoration: InputDecoration(
                      hintText: 'Search remote agent or channel',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: activeSearchQuery.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('chat-conversation-search-clear'),
                              onPressed: onClearConversationSearch,
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                ],
              );
            },
          ),
          Expanded(
            child: viewModel.visibleConversations.isEmpty
                ? _EmptyConversationRailState(emptyState: railEmptyState)
                : ListView.separated(
                    key: const Key('chat-conversation-list'),
                    itemCount: viewModel.visibleConversations.length,
                    itemBuilder: (context, index) {
                      final conversation =
                          viewModel.visibleConversations[index];
                      return _ConversationCard(
                        conversation: conversation,
                        isSelected: conversation.id == selectedConversationId,
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

class _EmptyConversationRailState extends StatelessWidget {
  const _EmptyConversationRailState({required this.emptyState});

  final _ChatEmptyState emptyState;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (emptyState.showProgress) ...[
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ] else ...[
                    const Icon(
                      Icons.inbox_outlined,
                      color: AppColors.onSurfaceMuted,
                      size: 36,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text(
                    emptyState.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    emptyState.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    final hasUnread = conversation.hasUnread;

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
            child: Stack(
              children: [
                if (isSelected)
                  Positioned(
                    left: -AppSpacing.lg,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                    ),
                  ),
                Row(
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
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stackTimestamp = constraints.maxWidth < 140;

                              if (stackTimestamp) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      conversation.remoteAgentName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            color: foreground,
                                            fontWeight: FontWeight.w700,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      conversation.lastActivityLabel
                                          .toUpperCase(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: AppColors.onSurfaceMuted,
                                          ),
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      conversation.remoteAgentName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            color: foreground,
                                            fontWeight: FontWeight.w700,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    conversation.lastActivityLabel
                                        .toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: AppColors.onSurfaceMuted,
                                        ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            conversation.latestPreview,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: AppColors.onSurfaceMuted),
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
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (hasUnread)
                          Container(
                            width: AppSpacing.sm,
                            height: AppSpacing.sm,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        else
                          const SizedBox(
                            width: AppSpacing.sm,
                            height: AppSpacing.sm,
                          ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          actionLabel.toUpperCase(),
                          key: Key('conversation-cta-${conversation.id}'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.onSurfaceMuted),
                        ),
                      ],
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
          width: 60,
          height: 60,
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
            size: AppSpacing.xl,
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

class _ThreadPlaceholderPanel extends StatelessWidget {
  const _ThreadPlaceholderPanel({required this.state});

  final _ChatEmptyState state;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(AppSpacing.xl),
      accentColor: AppColors.tertiary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.showProgress) ...[
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.6),
                        ),
                      ] else ...[
                        const Icon(
                          Icons.forum_outlined,
                          size: 42,
                          color: AppColors.tertiary,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        state.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        state.message,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThreadPanel extends StatelessWidget {
  const _ThreadPanel({
    super.key,
    required this.viewModel,
    required this.conversation,
    required this.compact,
    required this.isLoadingMessages,
    required this.messageLoadError,
    required this.shareAnnouncement,
    required this.threadSearchController,
    required this.threadSearchFocusNode,
    required this.onThreadSearchChange,
    required this.onCloseThreadSearch,
    required this.onMenuAction,
    required this.onQueueFollowRequest,
    required this.isQueueFollowRequestPending,
    required this.queueFollowRequestBlockedReason,
    required this.queueFollowRequestErrorMessage,
    this.onBack,
  });

  final ChatViewModel viewModel;
  final ChatConversationModel conversation;
  final bool compact;
  final bool isLoadingMessages;
  final String? messageLoadError;
  final String? shareAnnouncement;
  final TextEditingController threadSearchController;
  final FocusNode threadSearchFocusNode;
  final ValueChanged<String> onThreadSearchChange;
  final VoidCallback onCloseThreadSearch;
  final ValueChanged<ChatThreadMenuAction> onMenuAction;
  final ValueChanged<ChatConversationModel> onQueueFollowRequest;
  final bool isQueueFollowRequestPending;
  final String? queueFollowRequestBlockedReason;
  final String? queueFollowRequestErrorMessage;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final entryMode = viewModel.entryModeFor(conversation);

    return GlassPanel(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      accentColor: entryMode == ChatConversationEntryMode.openThread
          ? AppColors.primary
          : AppColors.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceHighest.withValues(alpha: 0.24),
              borderRadius: AppRadii.large,
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
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
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${conversation.remoteAgentName} • ${conversation.participantsLabel}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.onSurfaceMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(
                          height: compact ? AppSpacing.xs : AppSpacing.sm,
                        ),
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
            ),
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
              ChatConversationEntryMode.openThread =>
                messageLoadError != null
                    ? _ThreadStatusView(
                        title: 'Unable to load thread',
                        message: messageLoadError!,
                      )
                    : isLoadingMessages
                    ? _ThreadStatusView(
                        title: 'Loading thread',
                        message:
                            'Messages are syncing for ${conversation.remoteAgentName}.',
                        showProgress: true,
                      )
                    : _OpenThreadView(
                        conversation: conversation,
                        messages: viewModel.visibleMessages,
                        emptyLabel:
                            viewModel.isThreadSearchOpen &&
                                viewModel.threadSearchQuery.trim().isNotEmpty
                            ? 'No messages matched this thread-only search.'
                            : 'No messages in this thread yet.',
                      ),
              ChatConversationEntryMode.followAndRequest => _RequestAccessView(
                conversation: conversation,
                onQueueFollowRequest: () => onQueueFollowRequest(conversation),
                isQueueFollowRequestPending: isQueueFollowRequestPending,
                blockedReason: queueFollowRequestBlockedReason,
                errorMessage: queueFollowRequestErrorMessage,
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

class _ThreadStatusView extends StatelessWidget {
  const _ThreadStatusView({
    required this.title,
    required this.message,
    this.showProgress = false,
  });

  final String title;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showProgress)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.6),
                      )
                    else
                      const Icon(
                        Icons.sync_problem_rounded,
                        color: AppColors.tertiary,
                        size: 42,
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OpenThreadView extends StatelessWidget {
  const _OpenThreadView({
    required this.conversation,
    required this.messages,
    required this.emptyLabel,
  });

  final ChatConversationModel conversation;
  final List<ChatMessageModel> messages;
  final String emptyLabel;

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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighest.withValues(alpha: 0.54),
                    borderRadius: AppRadii.pill,
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      'Private thread',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusChip(
                    label: conversation.latestSpeakerIsHuman
                        ? '4-role thread'
                        : 'agent-led thread',
                    tone: conversation.latestSpeakerIsHuman
                        ? StatusChipTone.tertiary
                        : StatusChipTone.primary,
                    showDot: false,
                  ),
                  StatusChip(
                    label: conversation.remoteAgentName,
                    tone: StatusChipTone.neutral,
                    showDot: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        emptyLabel,
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
    required this.isQueueFollowRequestPending,
    required this.blockedReason,
    required this.errorMessage,
  });

  final ChatConversationModel conversation;
  final VoidCallback onQueueFollowRequest;
  final bool isQueueFollowRequestPending;
  final String? blockedReason;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final canQueueFollowRequest =
        !conversation.requestQueued &&
        !isQueueFollowRequestPending &&
        blockedReason == null;

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
              Opacity(
                opacity: canQueueFollowRequest || conversation.requestQueued
                    ? 1
                    : 0.58,
                child: IgnorePointer(
                  ignoring: !canQueueFollowRequest,
                  child: PrimaryGradientButton(
                    key: const Key('chat-follow-request-button'),
                    label: conversation.requestQueued
                        ? 'Request queued'
                        : isQueueFollowRequestPending
                        ? 'Queueing request...'
                        : 'Follow + request',
                    icon: conversation.requestQueued
                        ? Icons.check_circle_outline_rounded
                        : isQueueFollowRequestPending
                        ? Icons.sync_rounded
                        : Icons.person_add_alt_1_rounded,
                    useTertiary: conversation.requestQueued,
                    onPressed: onQueueFollowRequest,
                  ),
                ),
              ),
              if (isQueueFollowRequestPending) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Following ${conversation.remoteAgentName} from the current active agent before the DM request is marked queued.',
                  key: const Key('chat-follow-request-progress'),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ] else if (errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  errorMessage!,
                  key: const Key('chat-follow-request-error'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ] else if (blockedReason != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  blockedReason!,
                  key: const Key('chat-follow-request-blocked-reason'),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
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
            Text(
              compact ? 'H' : 'HUMAN',
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
