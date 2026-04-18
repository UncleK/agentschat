import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/locale/app_localization_extensions.dart';
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
import '../../core/widgets/swipe_back_sheet.dart';
import 'agentmoji_catalog.dart';
import 'chat_models.dart';
import 'chat_view_model.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.initialViewModel,
    this.initialConversationId,
    this.conversationRequestId = 0,
    this.chatRepository,
    this.followRepository,
    this.liveConversationTransform,
    this.enableSessionSync = true,
    this.onSearchActionChanged,
  });

  final ChatViewModel? initialViewModel;
  final String? initialConversationId;
  final int conversationRequestId;
  final ChatRepository? chatRepository;
  final FollowRepository? followRepository;
  final List<ChatConversationModel> Function(
    List<ChatConversationModel> liveConversations,
  )?
  liveConversationTransform;
  final bool enableSessionSync;
  final ValueChanged<VoidCallback?>? onSearchActionChanged;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Duration _threadRefreshInterval = Duration(seconds: 3);
  static const double _threadBottomSnapThreshold = 120;

  late ChatViewModel _viewModel;
  late final TextEditingController _conversationSearchController;
  late final FocusNode _conversationSearchFocusNode;
  late final TextEditingController _threadSearchController;
  late final FocusNode _threadSearchFocusNode;
  late final TextEditingController _composerController;
  late final FocusNode _composerFocusNode;
  late final ScrollController _messageScrollController;
  final ImagePicker _imagePicker = ImagePicker();
  bool _composerHasDraft = false;
  bool _showCompactThread = false;
  bool _isLoadingMessages = false;
  bool _isSendingMessage = false;
  bool _isRefreshingSelectedThread = false;
  bool _forceScrollToBottomOnNextMessageLoad = false;
  String? _composerImagePath;
  String? _messageLoadError;
  String? _sendMessageError;
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
  Timer? _threadRefreshTimer;
  int _handledConversationRequestId = 0;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.initialViewModel ?? ChatViewModel.resolvingActiveAgent();
    _conversationSearchController = TextEditingController(
      text: _viewModel.conversationSearchQuery,
    );
    _conversationSearchFocusNode = FocusNode();
    _threadSearchController = TextEditingController(
      text: _viewModel.threadSearchQuery,
    );
    _threadSearchFocusNode = FocusNode();
    _composerController = TextEditingController();
    _composerHasDraft = _composerController.text.trim().isNotEmpty;
    _composerController.addListener(_handleComposerDraftChanged);
    _composerFocusNode = FocusNode();
    _messageScrollController = ScrollController();
    _threadRefreshTimer = Timer.periodic(_threadRefreshInterval, (_) {
      unawaited(_refreshSelectedConversationSilently());
    });
    _syncShellSearchAction();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeHandleInitialConversationRequest();
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final searchRegistrationChanged =
        (oldWidget.onSearchActionChanged == null) !=
        (widget.onSearchActionChanged == null);
    if (searchRegistrationChanged) {
      _syncShellSearchAction();
    }
    if (oldWidget.conversationRequestId != widget.conversationRequestId ||
        oldWidget.initialConversationId != widget.initialConversationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeHandleInitialConversationRequest();
      });
    }
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeHandleInitialConversationRequest();
      });
      return;
    }
    _sessionSignature = nextSignature;
    unawaited(_syncToSession(session));
  }

  @override
  void dispose() {
    final onSearchActionChanged = widget.onSearchActionChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSearchActionChanged?.call(null);
    });
    _threadRefreshTimer?.cancel();
    _conversationSearchController.dispose();
    _conversationSearchFocusNode.dispose();
    _threadSearchController.dispose();
    _threadSearchFocusNode.dispose();
    _composerController.removeListener(_handleComposerDraftChanged);
    _composerController.dispose();
    _composerFocusNode.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  void _syncShellSearchAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onSearchActionChanged?.call(_openConversationSearchSheet);
    });
  }

  void _maybeHandleInitialConversationRequest() {
    if (!mounted) {
      return;
    }

    final requestId = widget.conversationRequestId;
    final targetConversationId = widget.initialConversationId?.trim();
    if (requestId <= 0 ||
        requestId <= _handledConversationRequestId ||
        targetConversationId == null ||
        targetConversationId.isEmpty) {
      return;
    }

    final conversation = _conversationById(targetConversationId);
    if (conversation == null) {
      if (!_viewModel.isLoadingThreads) {
        _handledConversationRequestId = requestId;
      }
      return;
    }

    _handledConversationRequestId = requestId;
    _selectConversation(conversation);
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

  void _clearComposerDraft({bool unfocus = false}) {
    _composerController.clear();
    _composerImagePath = null;
    if (unfocus) {
      _composerFocusNode.unfocus();
    }
  }

  void _handleComposerDraftChanged() {
    final hasDraft = _composerController.text.trim().isNotEmpty;
    if (!mounted || hasDraft == _composerHasDraft) {
      return;
    }
    setState(() {
      _composerHasDraft = hasDraft;
    });
  }

  void _handleComposerChanged(String _) {
    if (_sendMessageError == null) {
      return;
    }
    setState(() {
      _sendMessageError = null;
    });
  }

  Future<void> _syncToSession(AppSessionController session) async {
    if (session.bootstrapStatus != AppSessionBootstrapStatus.ready) {
      _invalidateLiveRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = ChatViewModel.resolvingActiveAgent();
        _showCompactThread = false;
        _isLoadingMessages = false;
        _isSendingMessage = false;
        _messageLoadError = null;
        _sendMessageError = null;
        _lastShareAnnouncement = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _syncConversationSearchController();
        _syncThreadSearchController();
        _clearComposerDraft(unfocus: true);
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
        _isSendingMessage = false;
        _messageLoadError = null;
        _sendMessageError = null;
        _lastShareAnnouncement = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _syncConversationSearchController();
        _syncThreadSearchController();
        _clearComposerDraft(unfocus: true);
      });
      return;
    }

    if (!session.isAuthenticated || userId == null || userId.isEmpty) {
      _invalidateLiveRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = ChatViewModel.blocked(
          message: context.localizedText(
            en: 'Sign in and select an owned agent in Hub to load direct messages.',
            zhHans: '请先登录，并在 Hub 里选择一个自有智能体来加载私信。',
          ),
        );
        _showCompactThread = false;
        _isLoadingMessages = false;
        _isSendingMessage = false;
        _messageLoadError = null;
        _sendMessageError = null;
        _lastShareAnnouncement = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _syncConversationSearchController();
        _syncThreadSearchController();
        _clearComposerDraft(unfocus: true);
      });
      return;
    }

    if (activeAgent == null) {
      _invalidateLiveRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = ChatViewModel.blocked(
          message: context.localizedText(
            en: 'Select an owned agent in Hub to load direct messages.',
            zhHans: '请先在 Hub 里选择一个自有智能体来加载私信。',
          ),
        );
        _showCompactThread = false;
        _isLoadingMessages = false;
        _isSendingMessage = false;
        _messageLoadError = null;
        _sendMessageError = null;
        _lastShareAnnouncement = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _syncConversationSearchController();
        _syncThreadSearchController();
        _clearComposerDraft(unfocus: true);
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
          .where(
            (thread) =>
                !_isOwnedAgentCommandThread(thread, currentHumanId: userId),
          )
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
        _isSendingMessage = false;
        _messageLoadError = null;
        _sendMessageError = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
        _clearComposerDraft(unfocus: true);
      });
      _maybeHandleInitialConversationRequest();
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
          message: context.localizedText(
            en: 'Unable to load direct messages right now.',
            zhHans: '暂时无法加载私信。',
          ),
          activeAgentName: activeAgentName,
        );
        _isLoadingMessages = false;
        _messageLoadError = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
      });
      _maybeHandleInitialConversationRequest();
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
          message: context.localizedText(
            en: 'Unable to load direct messages right now.',
            zhHans: '暂时无法加载私信。',
          ),
          activeAgentName: activeAgentName,
        );
        _isLoadingMessages = false;
        _messageLoadError = null;
        _followRequestConversationId = null;
        _followRequestErrorConversationId = null;
        _followRequestErrorMessage = null;
      });
      _maybeHandleInitialConversationRequest();
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
    final shouldForceScroll =
        _viewModel.selectedConversationId != conversation.id;
    _forceScrollToBottomOnNextMessageLoad = shouldForceScroll;
    setState(() {
      _viewModel = _viewModel.selectConversation(conversation.id);
      _syncThreadSearchController();
      _showCompactThread = true;
      _isLoadingMessages = shouldLoadConversationThread;
      _isSendingMessage = false;
      _messageLoadError = null;
      _sendMessageError = null;
      _lastShareAnnouncement = null;
      _clearComposerDraft();
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
    final shouldAutoScroll =
        _forceScrollToBottomOnNextMessageLoad || _isNearMessageBottom();
    _forceScrollToBottomOnNextMessageLoad = false;
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
      if (shouldAutoScroll) {
        _scrollMessageListToBottom();
      }

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
        _messageLoadError = context.localizedText(
          en: 'Unable to load this thread right now.',
          zhHans: '暂时无法加载这个会话线程。',
        );
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
        _messageLoadError = context.localizedText(
          en: 'Unable to load this thread right now.',
          zhHans: '暂时无法加载这个会话线程。',
        );
      });
    }
  }

  Future<void> _refreshSelectedConversationSilently() async {
    final session = AppSessionScope.maybeOf(context);
    final selectedConversation = _viewModel.selectedConversationOrNull;
    final currentUserId = session?.currentUser?.id;
    final activeAgentId = session?.currentActiveAgent?.id;
    if (session == null ||
        !session.isAuthenticated ||
        session.bootstrapStatus != AppSessionBootstrapStatus.ready ||
        session.isUsingLocalPreviewAgents ||
        currentUserId == null ||
        currentUserId.isEmpty ||
        activeAgentId == null ||
        activeAgentId.isEmpty ||
        selectedConversation == null ||
        !selectedConversation.hasExistingThread ||
        _chatRepository == null ||
        _isLoadingMessages ||
        _isSendingMessage ||
        _isRefreshingSelectedThread) {
      return;
    }

    final requestId = ++_messagesRequestId;
    final conversationId = selectedConversation.id;
    final shouldAutoScroll = _isNearMessageBottom();
    _isRefreshingSelectedThread = true;
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
      if (!_chatMessagesChanged(selectedConversation.messages, messages) ||
          !mounted) {
        return;
      }

      setState(() {
        _viewModel = _viewModel.replaceConversationMessages(
          conversationId,
          messages,
        );
        _messageLoadError = null;
      });
      if (shouldAutoScroll) {
        _scrollMessageListToBottom(animate: true);
      }
      unawaited(
        _markConversationRead(
          conversationId: conversationId,
          currentUserId: currentUserId,
          activeAgentId: activeAgentId,
        ),
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session.handleUnauthorized();
      }
    } catch (_) {
      // Silent refresh should not disturb an already-open thread.
    } finally {
      _isRefreshingSelectedThread = false;
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
        if (!mounted) {
          return;
        }
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

  void _applyConversationSearch(String value) {
    final normalized = value.trim();
    setState(() {
      _viewModel = normalized.isEmpty
          ? _viewModel.clearConversationSearch()
          : _viewModel.updateConversationSearch(normalized);
      _syncConversationSearchController();
    });
  }

  void _clearConversationSearch() {
    setState(() {
      _viewModel = _viewModel.clearConversationSearch();
      _syncConversationSearchController();
    });
  }

  ChatConversationModel? _conversationById(String conversationId) {
    for (final conversation in _viewModel.conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  Future<void> _openConversationSearchSheet() async {
    final result = await showSwipeBackSheet<_ConversationSearchSheetResult>(
      context: context,
      builder: (context) => _ConversationSearchSheet(
        conversations: _viewModel.conversations,
        initialQuery: _viewModel.conversationSearchQuery,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    _applyConversationSearch(result.query);
    final selectedConversationId = result.selectedConversationId;
    if (selectedConversationId == null) {
      return;
    }

    final conversation = _conversationById(selectedConversationId);
    if (conversation != null) {
      _selectConversation(conversation);
    }
  }

  void _focusConversationSearch() {
    if (_showCompactThread) {
      setState(() {
        _showCompactThread = false;
        _viewModel = _viewModel.clearSelection();
        _syncThreadSearchController();
        _lastShareAnnouncement = null;
        _sendMessageError = null;
        _clearComposerDraft(unfocus: true);
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
          _lastShareAnnouncement = context.localizedText(
            en: 'Shared ${shareDraft.entryPoint}',
            zhHans: '已分享 ${shareDraft.entryPoint}',
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.localizedText(
                en: 'Shared ${shareDraft.entryPoint}',
                zhHans: '已分享 ${shareDraft.entryPoint}',
              ),
            ),
          ),
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
      _sendMessageError = null;
      _clearComposerDraft(unfocus: true);
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
      return context.localizedText(
        en: 'Sign in to follow and request access.',
        zhHans: '请先登录，再关注并申请访问。',
      );
    }
    if (session.bootstrapStatus != AppSessionBootstrapStatus.ready) {
      return context.localizedText(
        en: 'Wait for the current session to finish resolving before requesting access.',
        zhHans: '请先等待当前会话完成恢复，再申请访问。',
      );
    }
    if (session.currentActiveAgent == null) {
      return context.localizedText(
        en: 'Activate an owned agent to follow and request access.',
        zhHans: '请先激活一个自有智能体，再去关注并申请访问。',
      );
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
            context.localizedText(
              en: 'Following ${conversation.remoteAgentName} and queued the DM request.',
              zhHans: '已关注 ${conversation.remoteAgentName}，并把私信请求加入队列。',
            ),
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

  Future<void> _sendThreadMessage(ChatConversationModel conversation) async {
    final draft = _composerController.text.trim();
    if (draft.isEmpty || _isSendingMessage) {
      return;
    }
    if (_composerImagePath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.localizedText(
              en: 'Image upload is not wired yet. Remove the image to send text.',
              zhHans: '图片上传功能暂未接通，请先移除图片后再发送文字。',
            ),
          ),
        ),
      );
      return;
    }

    final session = AppSessionScope.maybeOf(context);
    final currentUserId = session?.currentUser?.id;
    final activeAgentId = session?.currentActiveAgent?.id;
    if (session == null ||
        !session.isAuthenticated ||
        currentUserId == null ||
        currentUserId.isEmpty ||
        activeAgentId == null ||
        activeAgentId.isEmpty ||
        _chatRepository == null) {
      return;
    }

    final requestId = ++_messagesRequestId;
    if (mounted) {
      setState(() {
        _isSendingMessage = true;
        _sendMessageError = null;
      });
    }

    try {
      final response = await _chatRepository!.sendThreadMessage(
        threadId: conversation.id,
        activeAgentId: activeAgentId,
        content: draft,
        contentType: 'text',
      );
      if (!_canApplyMessageResult(
        requestId: requestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
        conversationId: conversation.id,
      )) {
        return;
      }

      final message = _mapMessage(
        response.message,
        currentUserId: currentUserId,
        activeAgentId: activeAgentId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _viewModel = _viewModel.appendConversationMessage(
          conversation.id,
          message,
        );
        _isSendingMessage = false;
        _sendMessageError = null;
        _clearComposerDraft(unfocus: true);
      });
      _scrollMessageListToBottom(animate: true);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await session.handleUnauthorized();
        return;
      }
      if (!_canApplyMessageResult(
        requestId: requestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
        conversationId: conversation.id,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isSendingMessage = false;
        _sendMessageError = error.message.trim().isEmpty
            ? context.localizedText(
                en: 'Unable to send this message right now.',
                zhHans: '暂时无法发送这条消息。',
              )
            : error.message;
      });
    } catch (_) {
      if (!_canApplyMessageResult(
        requestId: requestId,
        userId: currentUserId,
        activeAgentId: activeAgentId,
        conversationId: conversation.id,
      )) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isSendingMessage = false;
        _sendMessageError = 'Unable to send this message right now.';
      });
    }
  }

  void _insertComposerTextAtCursor(String text) {
    final value = _composerController.value;
    final fallbackOffset = value.text.length;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: fallbackOffset);
    final start = selection.start < 0 ? fallbackOffset : selection.start;
    final end = selection.end < 0 ? fallbackOffset : selection.end;
    final nextText = value.text.replaceRange(start, end, text);
    final caretOffset = start + text.length;
    _composerController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caretOffset),
    );
    _composerFocusNode.requestFocus();
  }

  bool _chatMessagesChanged(
    List<ChatMessageModel> currentMessages,
    List<ChatMessageModel> nextMessages,
  ) {
    if (currentMessages.length != nextMessages.length) {
      return true;
    }
    if (currentMessages.isEmpty || nextMessages.isEmpty) {
      return false;
    }
    return currentMessages.last.id != nextMessages.last.id;
  }

  bool _isNearMessageBottom() {
    if (!_messageScrollController.hasClients) {
      return true;
    }
    final position = _messageScrollController.position;
    return position.maxScrollExtent - position.pixels <=
        _threadBottomSnapThreshold;
  }

  void _scrollMessageListToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messageScrollController.hasClients) {
        return;
      }
      final targetOffset = _messageScrollController.position.maxScrollExtent;
      if (animate) {
        _messageScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      _messageScrollController.jumpTo(targetOffset);
    });
  }

  Future<void> _showComposerKeyboard() async {
    _composerFocusNode.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  Future<void> _openComposerVoiceInput() async {
    await _showComposerKeyboard();
  }

  // ignore: unused_element
  void _insertComposerEmoji() {
    _insertComposerTextAtCursor('🙂');
  }

  Future<void> _pickComposerImage() async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) {
        return;
      }
      setState(() {
        _composerImagePath = image.path;
        _sendMessageError = null;
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.localizedText(
              en: 'Unable to open the image picker.',
              zhHans: '暂时无法打开图片选择器。',
            ),
          ),
        ),
      );
    }
  }

  void _removeComposerImage() {
    if (_composerImagePath == null) {
      return;
    }
    setState(() {
      _composerImagePath = null;
    });
  }

  void _handleComposerEmojiTap() {
    unawaited(_openComposerEmojiPicker());
  }

  Future<void> _openComposerEmojiPicker() async {
    final selected = await showModalBottomSheet<AgentmojiDefinition>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AgentmojiPickerSheet(),
    );
    if (!mounted || selected == null) {
      return;
    }
    _insertComposerTextAtCursor(':${selected.id}:');
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
      counterpartType: thread.counterpart.type,
      counterpartId: thread.counterpart.id,
      avatarUrl: thread.counterpart.avatarUrl,
      hasUnread: thread.unreadCount > 0,
      unreadCount: thread.unreadCount,
      remoteAgentOnline: thread.counterpart.isOnline,
      hasExistingThread: true,
      viewerFollowsRemoteAgent: thread.counterpart.viewerFollowsAgent,
      remoteAgentFollowsViewer: thread.counterpart.agentFollowsViewer,
    );
  }

  bool _isOwnedAgentCommandThread(
    ChatThreadSummary thread, {
    required String currentHumanId,
  }) {
    if (thread.isOwnedAgentCommandThread) {
      return true;
    }

    return thread.counterpart.type.toLowerCase() == 'human' &&
        thread.counterpart.id == currentHumanId;
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
      return context.localizedText(en: 'Image', zhHans: '图片');
    }
    return context.localizedText(
      en: 'Unsupported message',
      zhHans: '暂不支持的消息类型',
    );
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
    final session = AppSessionScope.maybeOf(context);
    if (selectedConversation != null) {
      return _viewModel.statusLabelFor(selectedConversation);
    }
    if (_viewModel.isResolvingActiveAgent) {
      return context.localizedText(en: 'resolving agent', zhHans: '正在确认智能体');
    }
    if (_viewModel.isLoadingThreads) {
      return context.localizedText(en: 'syncing inbox', zhHans: '正在同步收件箱');
    }
    if (_viewModel.isBlocked) {
      return session?.isAuthenticated == true
          ? context.localizedText(en: 'no active agent', zhHans: '没有激活智能体')
          : context.localizedText(en: 'sign in required', zhHans: '需要登录');
    }
    if (_viewModel.isError) {
      return context.localizedText(en: 'sync error', zhHans: '同步异常');
    }
    if (_viewModel.hasConversations) {
      return context.localizedText(en: 'select a thread', zhHans: '选择一个线程');
    }
    return context.localizedText(en: 'inbox empty', zhHans: '收件箱为空');
  }

  _ChatEmptyState _railEmptyState() {
    final session = AppSessionScope.maybeOf(context);
    final blockedTitle = session?.isAuthenticated == true
        ? context.localizedText(en: 'No active agent', zhHans: '没有激活智能体')
        : context.localizedText(en: 'Sign in required', zhHans: '需要登录');
    final blockedMessage =
        _viewModel.surfaceMessage ??
        (session?.isAuthenticated == true
            ? context.localizedText(
                en: 'Select an owned agent in Hub to load direct messages.',
                zhHans: '请先在 Hub 里选择一个自有智能体来加载私信。',
              )
            : context.localizedText(
                en: 'Sign in and select an owned agent in Hub to load direct messages.',
                zhHans: '请先登录，并在 Hub 里选择一个自有智能体来加载私信。',
              ));
    if (_viewModel.isResolvingActiveAgent) {
      return _ChatEmptyState(
        title: context.localizedText(
          en: 'Resolving active agent',
          zhHans: '正在确认激活智能体',
        ),
        message: context.localizedText(
          en: 'Direct threads stay blocked until the session picks a valid owned agent.',
          zhHans: '在当前会话选出有效的自有智能体之前，私信线程会继续保持阻塞。',
        ),
        showProgress: true,
      );
    }
    if (_viewModel.isLoadingThreads) {
      return _ChatEmptyState(
        title: context.localizedText(
          en: 'Loading direct channels',
          zhHans: '正在加载私信通道',
        ),
        message:
            _viewModel.surfaceMessage ??
            context.localizedText(
              en: 'The inbox is syncing for the current active agent.',
              zhHans: '当前激活智能体的收件箱正在同步。',
            ),
        showProgress: true,
      );
    }
    if (_viewModel.isBlocked) {
      return _ChatEmptyState(title: blockedTitle, message: blockedMessage);
    }
    if (_viewModel.isError) {
      return _ChatEmptyState(
        title: context.localizedText(
          en: 'Unable to load chat',
          zhHans: '暂时无法加载聊天',
        ),
        message:
            _viewModel.surfaceMessage ??
            context.localizedText(
              en: 'Try again after the current active agent is stable.',
              zhHans: '等当前激活智能体状态稳定后再试一次。',
            ),
      );
    }
    return _ChatEmptyState(
      title: context.localizedText(
        en: 'No direct threads yet',
        zhHans: '还没有私信线程',
      ),
      message: context.localizedText(
        en: 'No private threads exist yet for ${_viewModel.activeAgentName ?? 'the current agent'}.',
        zhHans: '${_viewModel.activeAgentName ?? '当前智能体'} 还没有任何私密会话线程。',
      ),
    );
  }

  _ChatEmptyState _threadPlaceholderState() {
    if (_viewModel.hasConversations) {
      return _ChatEmptyState(
        title: context.localizedText(en: 'Select a thread', zhHans: '选择一个线程'),
        message: context.localizedText(
          en: 'Choose a direct channel for ${_viewModel.activeAgentName ?? 'the current agent'} to inspect messages.',
          zhHans: '为 ${_viewModel.activeAgentName ?? '当前智能体'} 选择一个私信通道来查看消息。',
        ),
      );
    }
    return _railEmptyState();
  }

  @override
  Widget build(BuildContext context) {
    final selectedConversation = _viewModel.selectedConversationOrNull;

    return DecoratedBox(
      key: const Key('surface-chat'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background,
            Color(0xFF111722),
            AppColors.background,
          ],
          stops: [0, 0.38, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 920;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!(_showCompactThread && selectedConversation != null)) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AGENTS CHAT',
                              style: Theme.of(
                                context,
                              ).textTheme.displayMedium?.copyWith(fontSize: 34),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Text(
                                context.localizedText(
                                  en: 'Synchronized neural channels with active agents.',
                                  zhHans: '与当前激活智能体同步的私信通道。',
                                ),
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.onSurfaceMuted,
                                      height: 1.38,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (isWide &&
                    !(_showCompactThread && selectedConversation != null)) ...[
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
                        label: context.localizedText(
                          en: '${_viewModel.visibleConversations.length} active threads',
                          zhHans:
                              '${_viewModel.visibleConversations.length} 个活跃线程',
                        ),
                      ),
                      StatusChip(
                        label: _surfaceStatusLabel(selectedConversation),
                        tone: StatusChipTone.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                Expanded(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 332,
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
                                      isSendingMessage: _isSendingMessage,
                                      messageLoadError: _messageLoadError,
                                      sendMessageError: _sendMessageError,
                                      shareAnnouncement: _lastShareAnnouncement,
                                      composerController: _composerController,
                                      composerFocusNode: _composerFocusNode,
                                      composerImagePath: _composerImagePath,
                                      composerHasDraft: _composerHasDraft,
                                      messageScrollController:
                                          _messageScrollController,
                                      threadSearchController:
                                          _threadSearchController,
                                      threadSearchFocusNode:
                                          _threadSearchFocusNode,
                                      onThreadSearchChange:
                                          _handleThreadSearchChange,
                                      onCloseThreadSearch: _closeThreadSearch,
                                      onComposerChanged: _handleComposerChanged,
                                      onSubmitMessage: () => _sendThreadMessage(
                                        selectedConversation,
                                      ),
                                      onPickComposerImage: _pickComposerImage,
                                      onRemoveComposerImage:
                                          _removeComposerImage,
                                      onVoiceComposer: _openComposerVoiceInput,
                                      onOpenImeVoiceInput:
                                          _openComposerVoiceInput,
                                      onInsertComposerEmoji:
                                          _handleComposerEmojiTap,
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
                                  isSendingMessage: _isSendingMessage,
                                  messageLoadError: _messageLoadError,
                                  sendMessageError: _sendMessageError,
                                  shareAnnouncement: _lastShareAnnouncement,
                                  composerController: _composerController,
                                  composerFocusNode: _composerFocusNode,
                                  composerImagePath: _composerImagePath,
                                  composerHasDraft: _composerHasDraft,
                                  messageScrollController:
                                      _messageScrollController,
                                  threadSearchController:
                                      _threadSearchController,
                                  threadSearchFocusNode: _threadSearchFocusNode,
                                  onThreadSearchChange:
                                      _handleThreadSearchChange,
                                  onCloseThreadSearch: _closeThreadSearch,
                                  onComposerChanged: _handleComposerChanged,
                                  onSubmitMessage: () =>
                                      _sendThreadMessage(selectedConversation),
                                  onPickComposerImage: _pickComposerImage,
                                  onRemoveComposerImage: _removeComposerImage,
                                  onVoiceComposer: _openComposerVoiceInput,
                                  onOpenImeVoiceInput: _openComposerVoiceInput,
                                  onInsertComposerEmoji:
                                      _handleComposerEmojiTap,
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
        ? _ChatEmptyState(
            title: context.localizedText(
              en: 'No matching channels',
              zhHans: '没有匹配的通道',
            ),
            message: context.localizedText(
              en: 'Try a remote agent name, operator label, or preview keyword.',
              zhHans: '试试远端智能体名称、操作者标签或预览关键词。',
            ),
          )
        : emptyState;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: compact
            ? Colors.transparent
            : AppColors.surfaceLow.withValues(alpha: 0.28),
        borderRadius: AppRadii.hero,
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 0 : AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact) ...[
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  top: AppSpacing.sm,
                ),
                child: Text(
                  'Linked channels',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 17),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  context.localizedText(
                    en: 'Remote agent identity stays primary, even when the latest speaker is human.',
                    zhHans: '即使最后一条消息来自人类，远端智能体身份仍然是这个通道的主标识。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AnimatedBuilder(
              animation: conversationSearchFocusNode,
              builder: (context, child) {
                final isSearchVisible =
                    conversationSearchFocusNode.hasFocus ||
                    activeSearchQuery.isNotEmpty;
                if (!isSearchVisible) {
                  return SizedBox(
                    height: compact ? AppSpacing.sm : AppSpacing.md,
                  );
                }

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: compact ? AppSpacing.md : AppSpacing.lg,
                  ),
                  child: TextField(
                    key: const Key('chat-conversation-search-input'),
                    controller: conversationSearchController,
                    focusNode: conversationSearchFocusNode,
                    onChanged: onConversationSearchChange,
                    decoration: InputDecoration(
                      hintText: context.localizedText(
                        en: 'Search names, labels, or thread preview',
                        zhHans: '搜索名称、标签或线程预览',
                      ),
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
                );
              },
            ),
            Expanded(
              child: viewModel.visibleConversations.isEmpty
                  ? _EmptyConversationRailState(emptyState: railEmptyState)
                  : ListView.separated(
                      key: const Key('chat-conversation-list'),
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      itemCount: viewModel.visibleConversations.length,
                      itemBuilder: (context, index) {
                        final conversation =
                            viewModel.visibleConversations[index];
                        return _ConversationCard(
                          conversation: conversation,
                          isSelected: conversation.id == selectedConversationId,
                          statusLabel: viewModel.statusLabelFor(conversation),
                          compact: compact,
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

Color _conversationTitleColor(ChatConversationModel conversation) {
  if (!conversation.remoteAgentOnline) {
    return AppColors.onSurface;
  }
  if (conversation.hasMutualFollow) {
    return AppColors.tertiary;
  }
  return AppColors.primary;
}

Color _conversationPresenceColor(ChatConversationModel conversation) {
  if (!conversation.remoteAgentOnline) {
    return AppColors.outlineBright;
  }
  if (conversation.hasMutualFollow) {
    return AppColors.tertiary;
  }
  return AppColors.primary;
}

// ignore: unused_element
class _LegacyConversationCard extends StatelessWidget {
  const _LegacyConversationCard({
    required this.conversation,
    required this.isSelected,
    required this.statusLabel,
    required this.compact,
    required this.onTap,
  });

  final ChatConversationModel conversation;
  final bool isSelected;
  final String statusLabel;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = _conversationTitleColor(conversation);
    final presenceColor = _conversationPresenceColor(conversation);
    final background = isSelected
        ? AppColors.surfaceHigh.withValues(alpha: 0.96)
        : AppColors.surface.withValues(alpha: 0.88);
    final hasUnread = conversation.hasUnread;
    final cardRadius = BorderRadius.circular(compact ? 14 : 12);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('conversation-card-${conversation.id}'),
        onTap: onTap,
        borderRadius: cardRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: cardRadius,
            border: Border.all(
              color: (isSelected ? AppColors.primary : AppColors.outline)
                  .withValues(alpha: isSelected ? 0.22 : 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: (isSelected ? AppColors.primary : Colors.black)
                    .withValues(alpha: isSelected ? 0.06 : 0.025),
                blurRadius: isSelected ? 14 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 16,
              vertical: compact ? 12 : 14,
            ),
            child: Stack(
              children: [
                if (isSelected)
                  Positioned(
                    left: compact ? -15 : -17,
                    top: 2,
                    bottom: 2,
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
                      name: conversation.remoteAgentName,
                      avatarUrl: conversation.avatarUrl,
                      isOnline: conversation.remoteAgentOnline,
                      isSelected: isSelected,
                      presenceColor: presenceColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stackTimestamp = constraints.maxWidth < 150;

                              if (stackTimestamp) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      conversation.remoteAgentName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: titleColor,
                                            fontSize: compact ? 16 : 17,
                                            fontWeight: FontWeight.w700,
                                            height: 1.0,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      conversation.lastActivityLabel
                                          .toUpperCase(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: AppColors.onSurfaceMuted
                                                .withValues(alpha: 0.82),
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
                                          .titleLarge
                                          ?.copyWith(
                                            color: titleColor,
                                            fontSize: compact ? 16 : 17,
                                            fontWeight: FontWeight.w700,
                                            height: 1.0,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Text(
                                    conversation.lastActivityLabel
                                        .toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: AppColors.onSurfaceMuted
                                              .withValues(alpha: 0.82),
                                        ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          Text(
                            conversation.latestPreview,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontSize: compact ? 13.5 : 14,
                                  color: AppColors.onSurfaceMuted,
                                  height: 1.18,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  conversation.latestSpeakerIsHuman
                                      ? '${conversation.latestSpeakerLabel} • HUMAN'
                                      : conversation.remoteAgentHeadline,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.onSurfaceMuted
                                            .withValues(alpha: 0.72),
                                        height: 1.2,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!compact && !hasUnread)
                                Text(
                                  statusLabel.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (hasUnread)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (conversation.unreadCount > 1)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(
                                    '${conversation.unreadCount}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: presenceColor),
                                  ),
                                ),
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: presenceColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox(width: 10, height: 10),
                        if (!compact) ...[
                          const SizedBox(height: AppSpacing.md),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.onSurfaceMuted.withValues(
                              alpha: 0.68,
                            ),
                          ),
                        ],
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

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.isSelected,
    required this.statusLabel,
    required this.compact,
    required this.onTap,
  });

  final ChatConversationModel conversation;
  final bool isSelected;
  final String statusLabel;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = _conversationTitleColor(conversation);
    final presenceColor = _conversationPresenceColor(conversation);
    final background = isSelected
        ? AppColors.surfaceHigh.withValues(alpha: 0.96)
        : AppColors.surface.withValues(alpha: 0.88);
    final hasUnread = conversation.hasUnread;
    final cardRadius = BorderRadius.circular(compact ? 14 : 12);
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: titleColor,
      fontSize: compact ? 16 : 17,
      fontWeight: FontWeight.w700,
      height: 1.0,
    );
    final timestampStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.onSurfaceMuted.withValues(alpha: 0.82),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('conversation-card-${conversation.id}'),
        onTap: onTap,
        borderRadius: cardRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: cardRadius,
            border: Border.all(
              color: (isSelected ? AppColors.primary : AppColors.outline)
                  .withValues(alpha: isSelected ? 0.22 : 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: (isSelected ? AppColors.primary : Colors.black)
                    .withValues(alpha: isSelected ? 0.06 : 0.025),
                blurRadius: isSelected ? 14 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 16,
              vertical: compact ? 12 : 14,
            ),
            child: Stack(
              children: [
                if (isSelected)
                  Positioned(
                    left: compact ? -15 : -17,
                    top: 2,
                    bottom: 2,
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
                      name: conversation.remoteAgentName,
                      avatarUrl: conversation.avatarUrl,
                      isOnline: conversation.remoteAgentOnline,
                      isSelected: isSelected,
                      presenceColor: presenceColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stackTimestamp = constraints.maxWidth < 150;

                              if (stackTimestamp) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      conversation.remoteAgentName,
                                      style: titleStyle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      conversation.lastActivityLabel
                                          .toUpperCase(),
                                      style: timestampStyle,
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      conversation.remoteAgentName,
                                      style: titleStyle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Text(
                                    conversation.lastActivityLabel
                                        .toUpperCase(),
                                    style: timestampStyle,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          Text(
                            conversation.latestPreview,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontSize: compact ? 13.5 : 14,
                                  color: AppColors.onSurfaceMuted,
                                  height: 1.18,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!compact && !hasUnread) ...[
                            const SizedBox(height: 3),
                            Text(
                              statusLabel.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppColors.onSurfaceMuted.withValues(
                                      alpha: 0.66,
                                    ),
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (hasUnread)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (conversation.unreadCount > 1)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    '${conversation.unreadCount}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: presenceColor),
                                  ),
                                ),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: presenceColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: presenceColor.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox(width: 8, height: 8),
                        if (!compact) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.onSurfaceMuted.withValues(
                              alpha: 0.56,
                            ),
                          ),
                        ],
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
  const _ConversationAvatar({
    required this.name,
    required this.avatarUrl,
    required this.isOnline,
    required this.isSelected,
    required this.presenceColor,
  });

  final String name;
  final String? avatarUrl;
  final bool isOnline;
  final bool isSelected;
  final Color presenceColor;

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
                  .withValues(alpha: isSelected ? 0.24 : 0.18),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: avatarUrl != null && avatarUrl!.trim().isNotEmpty
              ? Image.network(
                  avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _ConversationAvatarFallback(
                        name: name,
                        isSelected: isSelected,
                      ),
                )
              : _ConversationAvatarFallback(name: name, isSelected: isSelected),
        ),
        Positioned(
          right: 1,
          bottom: 1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isOnline ? presenceColor : AppColors.outlineBright,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationAvatarFallback extends StatelessWidget {
  const _ConversationAvatarFallback({
    required this.name,
    required this.isSelected,
  });

  final String name;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final initials = name.isEmpty
        ? 'A'
        : name
              .split(RegExp(r'[\s\-_]+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.substring(0, 1).toUpperCase())
              .join();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isSelected
                ? AppColors.primary.withValues(alpha: 0.28)
                : AppColors.surfaceHighest,
            AppColors.backgroundFloor,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: isSelected ? AppColors.primary : AppColors.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ConversationSearchSheetResult {
  const _ConversationSearchSheetResult({
    required this.query,
    this.selectedConversationId,
  });

  final String query;
  final String? selectedConversationId;
}

class _ConversationSearchSheet extends StatefulWidget {
  const _ConversationSearchSheet({
    required this.conversations,
    required this.initialQuery,
  });

  final List<ChatConversationModel> conversations;
  final String initialQuery;

  @override
  State<_ConversationSearchSheet> createState() =>
      _ConversationSearchSheetState();
}

class _ConversationSearchSheetState extends State<_ConversationSearchSheet> {
  late final TextEditingController _controller;
  late String _query;

  static const List<String> _quickFilters = <String>[
    'online',
    'mutual',
    'unread',
  ];

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _controller = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ChatConversationModel> get _filteredConversations {
    return ChatViewModel.ready(
      conversations: widget.conversations,
      activeAgentName: null,
    ).copyWith(conversationSearchQuery: _query).visibleConversations;
  }

  void _updateQuery(String value) {
    setState(() {
      _query = value;
    });
  }

  void _selectQuery(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _updateQuery(value);
  }

  @override
  Widget build(BuildContext context) {
    final filteredConversations = _filteredConversations;
    final trimmedQuery = _query.trim();
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md + insetBottom,
      ),
      child: GlassPanel(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            key: const Key('chat-search-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.localizedText(en: 'Find agent', zhHans: '查找智能体'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.localizedText(
                  en: 'Search direct-message agents by name, handle, or channel state.',
                  zhHans: '按名称、handle 或通道状态搜索私信智能体。',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('chat-search-field'),
                controller: _controller,
                autofocus: true,
                onChanged: _updateQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.localizedText(
                    en: 'Search names, handles, or states',
                    zhHans: '搜索名称、handle 或状态',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: trimmedQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => _selectQuery(''),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final filter in _quickFilters)
                    ActionChip(
                      key: Key('chat-search-filter-$filter'),
                      label: Text(switch (filter) {
                        'online' => context.localizedText(
                          en: 'Online',
                          zhHans: '在线',
                        ),
                        'mutual' => context.localizedText(
                          en: 'Mutual',
                          zhHans: '互相关注',
                        ),
                        'unread' => context.localizedText(
                          en: 'Unread',
                          zhHans: '未读',
                        ),
                        _ => filter,
                      }),
                      onPressed: () => _selectQuery(filter),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                context.localizedText(
                  en: '${filteredConversations.length} matches',
                  zhHans: '${filteredConversations.length} 条匹配结果',
                ),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: filteredConversations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.hero,
                          ),
                          child: Text(
                            trimmedQuery.isEmpty
                                ? context.localizedText(
                                    en: 'Type a name, handle, or status to find a DM agent.',
                                    zhHans: '输入名称、handle 或状态来查找私信智能体。',
                                  )
                                : context.localizedText(
                                    en: 'No agents match "$trimmedQuery".',
                                    zhHans: '没有智能体匹配“$trimmedQuery”。',
                                  ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredConversations.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final conversation = filteredConversations[index];
                          final titleColor = _conversationTitleColor(
                            conversation,
                          );
                          final presenceColor = _conversationPresenceColor(
                            conversation,
                          );
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: Key('chat-search-result-${conversation.id}'),
                              borderRadius: AppRadii.large,
                              onTap: () => Navigator.of(context).pop(
                                _ConversationSearchSheetResult(
                                  query: trimmedQuery,
                                  selectedConversationId: conversation.id,
                                ),
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceHigh.withValues(
                                    alpha: 0.68,
                                  ),
                                  borderRadius: AppRadii.large,
                                  border: Border.all(
                                    color: AppColors.outline.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Row(
                                    children: [
                                      _ConversationAvatar(
                                        name: conversation.remoteAgentName,
                                        avatarUrl: conversation.avatarUrl,
                                        isOnline:
                                            conversation.remoteAgentOnline,
                                        isSelected: false,
                                        presenceColor: presenceColor,
                                      ),
                                      const SizedBox(width: AppSpacing.md),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              conversation.remoteAgentName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(color: titleColor),
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.xxs,
                                            ),
                                            Text(
                                              conversation.remoteAgentHeadline,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (conversation.hasUnread)
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: presenceColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const SwipeBackSheetBackButton(),
                  const Spacer(),
                  TextButton(
                    key: const Key('chat-search-clear'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(const _ConversationSearchSheetResult(query: '')),
                    child: Text(
                      context.localizedText(en: 'Show all', zhHans: '显示全部'),
                    ),
                  ),
                  FilledButton(
                    key: const Key('chat-search-apply'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_ConversationSearchSheetResult(query: trimmedQuery)),
                    child: Text(
                      trimmedQuery.isEmpty
                          ? context.localizedText(en: 'Close', zhHans: '关闭')
                          : context.localizedText(en: 'Apply', zhHans: '应用'),
                    ),
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
    required this.isSendingMessage,
    required this.messageLoadError,
    required this.sendMessageError,
    required this.shareAnnouncement,
    required this.composerController,
    required this.composerFocusNode,
    required this.composerImagePath,
    required this.composerHasDraft,
    required this.messageScrollController,
    required this.threadSearchController,
    required this.threadSearchFocusNode,
    required this.onThreadSearchChange,
    required this.onCloseThreadSearch,
    required this.onComposerChanged,
    required this.onSubmitMessage,
    required this.onPickComposerImage,
    required this.onRemoveComposerImage,
    required this.onVoiceComposer,
    required this.onOpenImeVoiceInput,
    required this.onInsertComposerEmoji,
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
  final bool isSendingMessage;
  final String? messageLoadError;
  final String? sendMessageError;
  final String? shareAnnouncement;
  final TextEditingController composerController;
  final FocusNode composerFocusNode;
  final String? composerImagePath;
  final bool composerHasDraft;
  final ScrollController messageScrollController;
  final TextEditingController threadSearchController;
  final FocusNode threadSearchFocusNode;
  final ValueChanged<String> onThreadSearchChange;
  final VoidCallback onCloseThreadSearch;
  final ValueChanged<String> onComposerChanged;
  final VoidCallback onSubmitMessage;
  final VoidCallback onPickComposerImage;
  final VoidCallback onRemoveComposerImage;
  final VoidCallback onVoiceComposer;
  final VoidCallback onOpenImeVoiceInput;
  final VoidCallback onInsertComposerEmoji;
  final ValueChanged<ChatThreadMenuAction> onMenuAction;
  final ValueChanged<ChatConversationModel> onQueueFollowRequest;
  final bool isQueueFollowRequestPending;
  final String? queueFollowRequestBlockedReason;
  final String? queueFollowRequestErrorMessage;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final entryMode = viewModel.entryModeFor(conversation);

    return GestureDetector(
      onHorizontalDragEnd: compact && onBack != null
          ? (details) {
              if ((details.primaryVelocity ?? 0) > 320) {
                onBack?.call();
              }
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ThreadTopBar(
            conversation: conversation,
            compact: compact,
            onBack: onBack,
            onMenuAction: onMenuAction,
          ),
          Visibility(
            visible: false,
            child: DecoratedBox(
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
                                StatusChip(
                                  label: context.localizedText(
                                    en: 'existing threads stay readable',
                                    zhHans: '既有线程仍可继续阅读',
                                  ),
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
                      itemBuilder: (context) => [
                        PopupMenuItem<ChatThreadMenuAction>(
                          key: Key('chat-thread-menu-search'),
                          value: ChatThreadMenuAction.searchThread,
                          child: Text(
                            context.localizedText(
                              en: 'Search thread',
                              zhHans: '搜索线程',
                            ),
                          ),
                        ),
                        PopupMenuItem<ChatThreadMenuAction>(
                          key: Key('chat-thread-menu-share'),
                          value: ChatThreadMenuAction.shareConversation,
                          child: Text(
                            context.localizedText(
                              en: 'Share conversation',
                              zhHans: '分享会话',
                            ),
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (viewModel.isThreadSearchOpen) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('chat-thread-search-input'),
                    controller: threadSearchController,
                    focusNode: threadSearchFocusNode,
                    onChanged: onThreadSearchChange,
                    decoration: InputDecoration(
                      hintText: context.localizedText(
                        en: 'Search only this thread',
                        zhHans: '仅搜索当前线程',
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppColors.surfaceHighest.withValues(
                        alpha: 0.44,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
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
                      alpha: 0.4,
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${viewModel.visibleMessages.length} matches in ${conversation.remoteAgentName}',
              key: const Key('chat-thread-search-summary'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.8),
              ),
            ),
          ],
          if (shareAnnouncement != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              key: const Key('chat-share-announcement'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
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
                ).textTheme.bodySmall?.copyWith(color: AppColors.primaryFixed),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (entryMode) {
              ChatConversationEntryMode.openThread =>
                messageLoadError != null
                    ? _ThreadStatusView(
                        title: context.localizedText(
                          en: 'Unable to load thread',
                          zhHans: '无法加载当前线程',
                        ),
                        message: messageLoadError!,
                      )
                    : isLoadingMessages
                    ? _ThreadStatusView(
                        title: context.localizedText(
                          en: 'Loading thread',
                          zhHans: '正在加载线程',
                        ),
                        message: context.localizedText(
                          en: 'Messages are syncing for ${conversation.remoteAgentName}.',
                          zhHans: '正在同步 ${conversation.remoteAgentName} 的消息。',
                        ),
                        showProgress: true,
                      )
                    : _OpenThreadView(
                        compact: compact,
                        conversation: conversation,
                        messages: viewModel.visibleMessages,
                        scrollController: messageScrollController,
                        emptyLabel:
                            viewModel.isThreadSearchOpen &&
                                viewModel.threadSearchQuery.trim().isNotEmpty
                            ? context.localizedText(
                                en: 'No messages matched this thread-only search.',
                                zhHans: '这次仅限本线程的搜索没有找到匹配消息。',
                              )
                            : context.localizedText(
                                en: 'No messages in this thread yet.',
                                zhHans: '这条线程里还没有消息。',
                              ),
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
          if (entryMode == ChatConversationEntryMode.openThread) ...[
            const SizedBox(height: AppSpacing.md),
            _ThreadComposer(
              controller: composerController,
              focusNode: composerFocusNode,
              selectedImagePath: composerImagePath,
              hasDraft: composerHasDraft,
              isSending: isSendingMessage,
              errorMessage: sendMessageError,
              onChanged: onComposerChanged,
              onSubmitted: onSubmitMessage,
              onPickImage: onPickComposerImage,
              onRemoveImage: onRemoveComposerImage,
              onVoiceTap: onVoiceComposer,
              onImeVoiceTap: onOpenImeVoiceInput,
              onEmojiTap: onInsertComposerEmoji,
            ),
          ],
        ],
      ),
    );
  }
}

class _ThreadTopBar extends StatelessWidget {
  const _ThreadTopBar({
    required this.conversation,
    required this.compact,
    required this.onMenuAction,
    this.onBack,
  });

  final ChatConversationModel conversation;
  final bool compact;
  final ValueChanged<ChatThreadMenuAction> onMenuAction;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final statusLabel = conversation.participantsLabel.trim().isEmpty
        ? context.localizedText(en: 'private thread', zhHans: '私密线程')
        : conversation.participantsLabel;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.07),
            Colors.transparent,
          ],
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.outline.withValues(alpha: 0.08)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: compact ? AppSpacing.xs : 0,
          bottom: AppSpacing.sm,
        ),
        child: Row(
          children: [
            if (compact && onBack != null) ...[
              IconButton(
                key: const Key('chat-back-to-list-button'),
                onPressed: onBack,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceHighest.withValues(
                    alpha: 0.24,
                  ),
                  minimumSize: const Size(46, 46),
                ),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            _ThreadHeroAvatar(
              label: conversation.remoteAgentName,
              avatarUrl: conversation.avatarUrl,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontSize: compact ? 22 : 24,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          context.localeAwareCaps(statusLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.primary.withValues(alpha: 0.9),
                                letterSpacing: context.localeAwareLetterSpacing(
                                  latin: 1.5,
                                  chinese: 0.2,
                                ),
                              ),
                        ),
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
              itemBuilder: (context) => [
                PopupMenuItem<ChatThreadMenuAction>(
                  key: Key('chat-thread-menu-search'),
                  value: ChatThreadMenuAction.searchThread,
                  child: Text(
                    context.localizedText(en: 'Search thread', zhHans: '搜索线程'),
                  ),
                ),
                PopupMenuItem<ChatThreadMenuAction>(
                  key: Key('chat-thread-menu-share'),
                  value: ChatThreadMenuAction.shareConversation,
                  child: Text(
                    context.localizedText(
                      en: 'Share conversation',
                      zhHans: '分享会话',
                    ),
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadHeroAvatar extends StatelessWidget {
  const _ThreadHeroAvatar({required this.label, this.avatarUrl});

  final String label;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
      ),
      child: avatarUrl != null && avatarUrl!.trim().isNotEmpty
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _ThreadHeroAvatarFallback(label: label);
              },
            )
          : _ThreadHeroAvatarFallback(label: label),
    );
  }
}

class _ThreadHeroAvatarFallback extends StatelessWidget {
  const _ThreadHeroAvatarFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final initials = label.isEmpty
        ? 'A'
        : label
              .split(RegExp(r'[\s\-_]+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.substring(0, 1).toUpperCase())
              .join();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.32),
            AppColors.surfaceHighest,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.primaryFixed),
        ),
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
    required this.compact,
    required this.conversation,
    required this.messages,
    required this.scrollController,
    required this.emptyLabel,
  });

  final bool compact;
  final ChatConversationModel conversation;
  final List<ChatMessageModel> messages;
  final ScrollController scrollController;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTight = constraints.maxHeight < 220;
        final bottomPadding = compact ? AppSpacing.xs : AppSpacing.sm;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isTight) ...[
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighest.withValues(alpha: 0.28),
                    borderRadius: AppRadii.pill,
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 8,
                    ),
                    child: Text(
                      context.localizedText(
                        en: 'CYCLE 892 // MULTI-LINK ESTABLISHED',
                        zhHans: '周期 892 // 多链路已建立',
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceMuted.withValues(alpha: 0.76),
                        letterSpacing: context.localeAwareLetterSpacing(
                          latin: 1.7,
                          chinese: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Expanded(
              child: messages.isEmpty
                  ? _ThreadEmptyState(
                      conversation: conversation,
                      label: emptyLabel,
                    )
                  : SingleChildScrollView(
                      key: const Key('chat-message-scroll'),
                      controller: scrollController,
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < messages.length;
                            index++
                          ) ...[
                            _MessageBubble(message: messages[index]),
                            if (index != messages.length - 1)
                              const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ThreadEmptyState extends StatelessWidget {
  const _ThreadEmptyState({required this.conversation, required this.label});

  final ChatConversationModel conversation;
  final String label;

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
                Icons.forum_outlined,
                color: AppColors.primary.withValues(alpha: 0.88),
                size: 30,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              label,
              key: const Key('chat-thread-empty-search'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 17,
                color: AppColors.onSurface.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              conversation.latestPreview,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                height: 1.42,
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.localizedText(
                en: 'Use the composer below to restart this private line with ${conversation.remoteAgentName}.',
                zhHans: '使用下方输入框，重新与 ${conversation.remoteAgentName} 建立这条私密对话。',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.72),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadComposer extends StatelessWidget {
  const _ThreadComposer({
    required this.controller,
    required this.focusNode,
    required this.selectedImagePath,
    required this.hasDraft,
    required this.isSending,
    required this.errorMessage,
    required this.onChanged,
    required this.onSubmitted,
    required this.onPickImage,
    required this.onRemoveImage,
    required this.onVoiceTap,
    required this.onImeVoiceTap,
    required this.onEmojiTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? selectedImagePath;
  final bool hasDraft;
  final bool isSending;
  final String? errorMessage;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;
  final VoidCallback onVoiceTap;
  final VoidCallback onImeVoiceTap;
  final VoidCallback onEmojiTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = selectedImagePath != null && selectedImagePath!.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          children: [
            if (hasImage) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighest.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(selectedImagePath!),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 44,
                            height: 44,
                            color: AppColors.surfaceHighest,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.image_outlined,
                              color: AppColors.primary,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.localizedText(
                              en: 'Selected image',
                              zhHans: '已选择图片',
                            ),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: AppColors.primaryFixed,
                                  letterSpacing: 1.0,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedImagePath!
                                .split(Platform.pathSeparator)
                                .last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('chat-composer-remove-image'),
                      onPressed: onRemoveImage,
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.onSurfaceMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ComposerActionButton(
                  buttonKey: const Key('chat-composer-voice-button'),
                  icon: Icons.volume_up_rounded,
                  accentColor: AppColors.tertiary,
                  onTap: onVoiceTap,
                ),
                const SizedBox(width: AppSpacing.sm),
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
                      key: const Key('chat-composer-input'),
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !isSending,
                      onChanged: onChanged,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSubmitted(),
                      decoration: InputDecoration(
                        hintText: null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 14,
                        ),
                        suffixIcon: IconButton(
                          key: const Key('chat-composer-ime-mic-button'),
                          onPressed: onImeVoiceTap,
                          icon: const Icon(Icons.keyboard_voice_rounded),
                          color: AppColors.onSurfaceMuted,
                          tooltip: context.localizedText(
                            en: 'Voice input',
                            zhHans: '语音输入',
                          ),
                        ),
                      ),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _ComposerActionButton(
                  buttonKey: const Key('chat-composer-emoji-button'),
                  icon: Icons.sentiment_satisfied_alt_rounded,
                  accentColor: AppColors.onSurfaceMuted,
                  onTap: onEmojiTap,
                ),
                const SizedBox(width: AppSpacing.xs),
                _ComposerActionButton(
                  key: ValueKey<String>(
                    hasDraft ? 'composer-send' : 'composer-plus',
                  ),
                  buttonKey: Key(
                    hasDraft
                        ? 'chat-composer-send-button'
                        : 'chat-composer-plus-button',
                  ),
                  icon: hasDraft ? Icons.send_rounded : Icons.add_rounded,
                  accentColor: AppColors.primary,
                  fillColor: AppColors.primary.withValues(
                    alpha: hasDraft ? 0.18 : 0.12,
                  ),
                  onTap: hasDraft ? onSubmitted : onPickImage,
                ),
              ],
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  errorMessage!,
                  key: const Key('chat-composer-error'),
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

class _ComposerActionButton extends StatelessWidget {
  const _ComposerActionButton({
    super.key,
    required this.buttonKey,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.fillColor,
  });

  final Key buttonKey;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor ?? AppColors.surfaceHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
      child: IconButton(
        key: buttonKey,
        onPressed: onTap,
        icon: Icon(icon),
        color: accentColor,
        iconSize: 22,
        constraints: const BoxConstraints.tightFor(width: 46, height: 46),
      ),
    );
  }
}

class _AgentmojiPickerSheet extends StatelessWidget {
  const _AgentmojiPickerSheet();

  @override
  Widget build(BuildContext context) {
    final grouped = <MapEntry<String, List<AgentmojiDefinition>>>[
      for (final category in kAgentmojiCategoryOrder)
        MapEntry(
          agentmojiCategoryLabel(category),
          kAgentmojiCatalog
              .where((item) => item.category == category)
              .toList(growable: false),
        ),
    ].where((entry) => entry.value.isNotEmpty).toList(growable: false);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          key: const Key('chat-agentmoji-sheet'),
          decoration: BoxDecoration(
            color: AppColors.surfaceLow.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalGap = constraints.maxWidth >= 340 ? 8.0 : 10.0;
                final crossAxisCount = constraints.maxWidth >= 320 ? 4 : 3;
                final tileWidth =
                    (constraints.maxWidth -
                        (horizontalGap * (crossAxisCount - 1))) /
                    crossAxisCount;

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.outline.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        context.localizedText(
                          en: 'Agentmoji',
                          zhHans: 'Agentmoji 表情',
                        ),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primaryFixed,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        context.localizedText(
                          en: 'Extracted PNG signal glyphs for agent chat. Tap to insert a shortcode.',
                          zhHans: '为智能体聊天提取的 PNG 信号表情。点击即可插入短代码。',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceMuted.withValues(
                            alpha: 0.86,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      for (final entry in grouped) ...[
                        Text(
                          entry.key,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppColors.onSurfaceMuted.withValues(
                                  alpha: 0.84,
                                ),
                                letterSpacing: 0.35,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: horizontalGap,
                          runSpacing: 8,
                          children: [
                            for (final emoji in entry.value)
                              _AgentmojiTile(
                                definition: emoji,
                                width: tileWidth,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentmojiTile extends StatelessWidget {
  const _AgentmojiTile({required this.definition, required this.width});

  final AgentmojiDefinition definition;
  final double width;

  @override
  Widget build(BuildContext context) {
    final imageBoxSize = width >= 86 ? 44.0 : 40.0;
    final imageSize = width >= 86 ? 34.0 : 30.0;
    final labelFontSize = width >= 86 ? 11.0 : 10.0;
    final codeFontSize = width >= 86 ? 9.5 : 8.6;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('chat-agentmoji-item-${definition.id}'),
        onTap: () => Navigator.of(context).pop(definition),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: width,
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighest.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: imageBoxSize,
                height: imageBoxSize,
                decoration: BoxDecoration(
                  color: AppColors.backgroundFloor.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  definition.assetPath,
                  width: imageSize,
                  height: imageSize,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                definition.displayLabel,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.94),
                  fontSize: labelFontSize,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ':${definition.id}:',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary.withValues(alpha: 0.92),
                  fontSize: codeFontSize,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
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
                        : 'dm closed',
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
              'No DM thread exists with ${conversation.remoteAgentName} yet.',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Open this agent from Agent Hall and ask your current active agent to start the DM there. The DM page only shows existing threads.',
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
    final isAgent = message.kind == ChatParticipantKind.agent;
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
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isRemote ? 0 : 16),
      bottomRight: Radius.circular(isRemote ? 16 : 0),
    );
    final bubbleBody = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 252),
      child: _MessageBubbleBody(
        message: message,
        accentColor: accentColor,
        bubbleColor: bubbleColor,
        bubbleRadius: bubbleRadius,
      ),
    );
    final bubble = isAgent
        ? Padding(
            padding: EdgeInsets.only(
              left: isRemote ? 8 : 0,
              right: isRemote ? 0 : 8,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                bubbleBody,
                Positioned(
                  left: isRemote ? -8 : null,
                  right: isRemote ? null : -8,
                  top: 0,
                  bottom: 0,
                  child: _AgentBracketAccent(
                    color: accentColor,
                    side: isRemote ? AxisDirection.left : AxisDirection.right,
                  ),
                ),
              ],
            ),
          )
        : bubbleBody;

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
                  _MessageAvatar(
                    name: message.authorName,
                    kind: message.kind,
                    accentColor: accentColor,
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: bubble),
                ]
              : [
                  Flexible(child: bubble),
                  const SizedBox(width: 10),
                  _MessageAvatar(
                    name: message.authorName,
                    kind: message.kind,
                    accentColor: accentColor,
                  ),
                ],
        ),
        Padding(
          padding: EdgeInsets.only(
            top: 5,
            left: isRemote ? 38 : 0,
            right: isRemote ? 0 : 38,
          ),
          child: Text(
            message.timestampLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceMuted.withValues(alpha: 0.5),
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({
    required this.name,
    required this.kind,
    required this.accentColor,
  });

  final String name;
  final ChatParticipantKind kind;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final initials = name.isEmpty
        ? 'A'
        : name
              .split(RegExp(r'[\s\-_]+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.substring(0, 1).toUpperCase())
              .join();
    return Container(
      width: 28,
      height: 28,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest,
        borderRadius: AppRadii.pill,
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentColor.withValues(alpha: 0.22),
              AppColors.surfaceHighest,
            ],
          ),
        ),
        child: Center(
          child: kind == ChatParticipantKind.human
              ? Text(
                  initials,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: accentColor,
                    fontSize: 10,
                  ),
                )
              : Icon(Icons.smart_toy_rounded, size: 16, color: accentColor),
        ),
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
    final showInlineAccent = message.kind == ChatParticipantKind.human;

    return ClipRRect(
      borderRadius: bubbleRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: bubbleRadius,
          border: Border.all(color: accentColor.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRemote && showInlineAccent)
              Container(width: 2.5, color: accentColor),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
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
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: accentColor,
                                fontSize: 10.5,
                                letterSpacing: 0.5,
                              ),
                        ),
                        if (message.isHuman) const _HumanIdentityBadge(),
                      ],
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      message.body,
                      textAlign: isRemote ? TextAlign.left : TextAlign.right,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 13.5,
                        height: 1.42,
                        color: AppColors.onSurface.withValues(alpha: 0.96),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isRemote && showInlineAccent)
              Container(width: 2.5, color: accentColor),
          ],
        ),
      ),
    );
  }
}

class _AgentBracketAccent extends StatelessWidget {
  const _AgentBracketAccent({required this.color, required this.side});

  final Color color;
  final AxisDirection side;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      child: CustomPaint(
        painter: _AgentBracketPainter(color: color, side: side),
      ),
    );
  }
}

class _AgentBracketPainter extends CustomPainter {
  const _AgentBracketPainter({required this.color, required this.side});

  final Color color;
  final AxisDirection side;

  @override
  void paint(Canvas canvas, Size size) {
    final isLeft = side == AxisDirection.left;
    final thickness = 3.2;
    final edgeX = isLeft ? size.width : 0.0;
    final innerX = isLeft ? edgeX - thickness : edgeX + thickness;
    final topInset = size.height < 40 ? size.height * 0.1 : 7.0;
    final curveDepth = size.height < 40 ? size.height * 0.18 : 13.0;
    final taperStartX = isLeft
        ? edgeX - (thickness * 0.08)
        : edgeX + (thickness * 0.08);
    final curveAnchorY = topInset + (curveDepth * 0.58);
    final fullFade = topInset + curveDepth;
    final path = Path();

    if (isLeft) {
      path
        ..moveTo(edgeX, topInset)
        ..quadraticBezierTo(
          edgeX,
          topInset + (curveDepth * 0.28),
          taperStartX,
          curveAnchorY,
        )
        ..quadraticBezierTo(
          innerX,
          topInset + (curveDepth * 0.82),
          innerX,
          fullFade,
        )
        ..lineTo(innerX, size.height)
        ..lineTo(edgeX, size.height)
        ..close();
    } else {
      path
        ..moveTo(edgeX, topInset)
        ..quadraticBezierTo(
          edgeX,
          topInset + (curveDepth * 0.28),
          taperStartX,
          curveAnchorY,
        )
        ..quadraticBezierTo(
          innerX,
          topInset + (curveDepth * 0.82),
          innerX,
          fullFade,
        )
        ..lineTo(innerX, size.height)
        ..lineTo(edgeX, size.height)
        ..close();
    }

    final paint = Paint()
      ..color = color.withValues(alpha: 0.98)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AgentBracketPainter oldDelegate) {
    return color != oldDelegate.color || side != oldDelegate.side;
  }
}

class _HumanIdentityBadge extends StatelessWidget {
  const _HumanIdentityBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: AppRadii.pill,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.localizedText(en: 'HUMAN', zhHans: '人类'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.warning,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
