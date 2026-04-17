import 'package:flutter/foundation.dart';

import '../auth/auth_repository.dart';
import '../auth/auth_state.dart';
import '../network/agents_repository.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'app_session_storage.dart';

enum AppSessionBootstrapStatus { idle, bootstrapping, ready, error }

class AppSessionController extends ChangeNotifier {
  AppSessionController({
    required this.apiClient,
    required this.authRepository,
    required this.agentsRepository,
    required this.storage,
    this.enableLocalPreviewAgents = false,
  });

  final ApiClient apiClient;
  final AuthRepository authRepository;
  final AgentsRepository agentsRepository;
  final AppSessionStorage storage;
  final bool enableLocalPreviewAgents;

  AppSessionBootstrapStatus _bootstrapStatus = AppSessionBootstrapStatus.idle;
  AuthState _authState = AuthState.signedOut;
  List<AgentSummary> _currentActiveAgentCandidates = const [];
  List<AgentSummary> _claimableAgents = const [];
  List<PendingClaimSummary> _pendingClaims = const [];
  AgentSummary? _currentActiveAgent;
  Object? _lastBootstrapError;
  bool _isRefreshingMine = false;
  bool _isUsingLocalPreviewAgents = false;
  int _attemptId = 0;

  AppSessionBootstrapStatus get bootstrapStatus => _bootstrapStatus;
  AuthState get authState => _authState;
  AuthUser? get currentUser => _authState.user;
  bool get isAuthenticated => _authState.isSignedIn;
  bool get isRefreshingMine => _isRefreshingMine;

  List<AgentSummary> get currentActiveAgentCandidates {
    return List<AgentSummary>.unmodifiable(_currentActiveAgentCandidates);
  }

  List<AgentSummary> get claimableAgents {
    return List<AgentSummary>.unmodifiable(_claimableAgents);
  }

  List<PendingClaimSummary> get pendingClaims {
    return List<PendingClaimSummary>.unmodifiable(_pendingClaims);
  }

  AgentSummary? get currentActiveAgent => _currentActiveAgent;
  Object? get lastBootstrapError => _lastBootstrapError;
  bool get isUsingLocalPreviewAgents => _isUsingLocalPreviewAgents;

  Future<void> bootstrap() async {
    final attemptId = _beginAttempt();
    final token = await storage.readToken();
    if (!_isCurrentAttempt(attemptId)) {
      return;
    }

    if (token == null || token.isEmpty) {
      await _clearSession(attemptId);
      return;
    }

    apiClient.setAuthToken(token);
    await _bootstrapFromToken(token: token, attemptId: attemptId);
  }

  Future<void> authenticate(AuthState authState) async {
    final attemptId = _beginAttempt();
    await storage.clearCurrentActiveAgentId();
    if (!_isCurrentAttempt(attemptId)) {
      return;
    }

    await storage.writeToken(authState.token);
    if (!_isCurrentAttempt(attemptId)) {
      return;
    }

    apiClient.setAuthToken(authState.token);
    await _bootstrapFromToken(token: authState.token, attemptId: attemptId);
  }

  Future<void> logout() async {
    final attemptId = _beginAttempt();
    await _clearSession(attemptId);
  }

  Future<void> handleUnauthorized() async {
    final attemptId = _beginAttempt();
    await _clearSession(attemptId);
  }

  Future<void> setCurrentActiveAgent(String? agentId) async {
    final attemptId = ++_attemptId;
    final nextAgent = _resolveCandidate(agentId, _currentActiveAgentCandidates);
    if (agentId != null && agentId.isNotEmpty && nextAgent == null) {
      return;
    }

    await _persistResolvedActiveAgentId(nextAgent?.id);
    if (!_isCurrentAttempt(attemptId)) {
      return;
    }

    _currentActiveAgent = nextAgent;
    _lastBootstrapError = null;
    _isUsingLocalPreviewAgents =
        enableLocalPreviewAgents &&
        _currentActiveAgentCandidates.isNotEmpty &&
        _currentActiveAgentCandidates.first.id.startsWith('preview-agent-');
    notifyListeners();
  }

  Future<void> refreshMine() async {
    await _runMineMutation(() async {
      await _refreshMineState(
        preferredActiveAgentId: _currentActiveAgent?.id,
        notify: false,
      );
    });
  }

  Future<AgentSummary?> importHumanOwnedAgent({
    required String handle,
    required String displayName,
    String? avatarUrl,
    String? bio,
  }) async {
    AgentSummary? resolvedAgent;
    await _runMineMutation(() async {
      final response = await agentsRepository.importHumanOwnedAgent(
        handle: handle,
        displayName: displayName,
        avatarUrl: avatarUrl,
        bio: bio,
      );
      resolvedAgent = await _refreshMineState(
        preferredActiveAgentId: _readAgentId(response),
        notify: false,
      );
    });
    return resolvedAgent;
  }

  Future<HumanOwnedAgentInvitation> createHumanOwnedAgentInvitation() async {
    late HumanOwnedAgentInvitation invitation;
    await _runMineMutation(() async {
      invitation = await agentsRepository.createHumanOwnedAgentInvitation();
    });
    return invitation;
  }

  Future<AgentClaimRequest> createClaimRequest({
    required String agentId,
    required int expiresInMinutes,
  }) async {
    late AgentClaimRequest claimRequest;
    await _runMineMutation(() async {
      claimRequest = await agentsRepository.requestClaim(
        agentId,
        expiresInMinutes: expiresInMinutes,
      );
      await _refreshMineState(
        preferredActiveAgentId: _currentActiveAgent?.id,
        notify: false,
      );
    });
    return claimRequest;
  }

  Future<void> _bootstrapFromToken({
    required String token,
    required int attemptId,
  }) async {
    try {
      final authState = await authRepository.fetchMe(token: token);
      if (!_isCurrentAttempt(attemptId)) {
        return;
      }

      final agentsMineResponse = await agentsRepository.readMine();
      if (!_isCurrentAttempt(attemptId)) {
        return;
      }

      final persistedActiveAgentId = await storage.readCurrentActiveAgentId();
      if (!_isCurrentAttempt(attemptId)) {
        return;
      }

      final resolvedActiveAgent = await _applyMineResponse(
        response: agentsMineResponse,
        persistedActiveAgentId: persistedActiveAgentId,
        recommendedActiveAgentId: authState.recommendedActiveAgentId,
        notify: false,
      );
      if (!_isCurrentAttempt(attemptId)) {
        return;
      }

      _authState = authState;
      _currentActiveAgent = resolvedActiveAgent;
      _bootstrapStatus = AppSessionBootstrapStatus.ready;
      _lastBootstrapError = null;
      notifyListeners();
    } on ApiException catch (error) {
      if (!_isCurrentAttempt(attemptId)) {
        return;
      }
      if (error.isUnauthorized) {
        await _clearSession(attemptId);
        return;
      }

      _bootstrapStatus = AppSessionBootstrapStatus.error;
      _lastBootstrapError = error;
      notifyListeners();
    } catch (error) {
      if (!_isCurrentAttempt(attemptId)) {
        return;
      }
      _bootstrapStatus = AppSessionBootstrapStatus.error;
      _lastBootstrapError = error;
      notifyListeners();
    }
  }

  Future<void> _runMineMutation(Future<void> Function() action) async {
    if (!isAuthenticated) {
      throw StateError('A signed-in human session is required.');
    }

    _isRefreshingMine = true;
    notifyListeners();

    try {
      await action();
      _lastBootstrapError = null;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await handleUnauthorized();
      }
      rethrow;
    } finally {
      if (_isRefreshingMine) {
        _isRefreshingMine = false;
        notifyListeners();
      }
    }
  }

  Future<AgentSummary?> _refreshMineState({
    required String? preferredActiveAgentId,
    required bool notify,
  }) async {
    final response = await agentsRepository.readMine();
    return _applyMineResponse(
      response: response,
      persistedActiveAgentId: preferredActiveAgentId,
      notify: notify,
    );
  }

  Future<AgentSummary?> _applyMineResponse({
    required AgentsMineResponse response,
    String? persistedActiveAgentId,
    String? recommendedActiveAgentId,
    required bool notify,
  }) async {
    final effectiveAgents = response.agents.isEmpty && enableLocalPreviewAgents
        ? _localPreviewAgents
        : response.agents;
    final resolvedActiveAgent = _resolveActiveAgent(
      persistedActiveAgentId: persistedActiveAgentId,
      recommendedActiveAgentId: recommendedActiveAgentId,
      agents: effectiveAgents,
    );

    await _persistResolvedActiveAgentId(resolvedActiveAgent?.id);

    _currentActiveAgentCandidates = effectiveAgents;
    _claimableAgents = response.claimableAgents;
    _pendingClaims = response.pendingClaims;
    _currentActiveAgent = resolvedActiveAgent;
    _isUsingLocalPreviewAgents =
        enableLocalPreviewAgents && response.agents.isEmpty;

    if (notify) {
      notifyListeners();
    }

    return resolvedActiveAgent;
  }

  Future<void> _persistResolvedActiveAgentId(String? agentId) async {
    if (agentId == null || agentId.isEmpty) {
      await storage.clearCurrentActiveAgentId();
      return;
    }

    final persistedActiveAgentId = await storage.readCurrentActiveAgentId();
    if (persistedActiveAgentId == agentId) {
      return;
    }

    await storage.writeCurrentActiveAgentId(agentId);
  }

  Future<void> _clearSession(int attemptId) async {
    await storage.clear();
    if (!_isCurrentAttempt(attemptId)) {
      return;
    }

    apiClient.setAuthToken(null);
    _authState = AuthState.signedOut;
    _currentActiveAgentCandidates = enableLocalPreviewAgents
        ? _localPreviewAgents
        : const [];
    _claimableAgents = const [];
    _pendingClaims = const [];
    _currentActiveAgent =
        enableLocalPreviewAgents && _localPreviewAgents.isNotEmpty
        ? _localPreviewAgents.first
        : null;
    _bootstrapStatus = AppSessionBootstrapStatus.ready;
    _lastBootstrapError = null;
    _isRefreshingMine = false;
    _isUsingLocalPreviewAgents = enableLocalPreviewAgents;
    notifyListeners();
  }

  int _beginAttempt() {
    final nextAttemptId = ++_attemptId;
    _authState = AuthState.signedOut;
    _currentActiveAgentCandidates = const [];
    _claimableAgents = const [];
    _pendingClaims = const [];
    _currentActiveAgent = null;
    _bootstrapStatus = AppSessionBootstrapStatus.bootstrapping;
    _lastBootstrapError = null;
    _isRefreshingMine = false;
    _isUsingLocalPreviewAgents = false;
    notifyListeners();
    return nextAttemptId;
  }

  bool _isCurrentAttempt(int attemptId) => attemptId == _attemptId;

  AgentSummary? _resolveActiveAgent({
    required String? persistedActiveAgentId,
    required String? recommendedActiveAgentId,
    required List<AgentSummary> agents,
  }) {
    return _resolveCandidate(persistedActiveAgentId, agents) ??
        _resolveCandidate(recommendedActiveAgentId, agents) ??
        (agents.isEmpty ? null : agents.first);
  }

  AgentSummary? _resolveCandidate(String? agentId, List<AgentSummary> agents) {
    if (agentId == null || agentId.isEmpty) {
      return null;
    }

    for (final agent in agents) {
      if (agent.id == agentId) {
        return agent;
      }
    }
    return null;
  }

  String? _readAgentId(Map<String, dynamic> response) {
    final topLevelId = response['id'] as String?;
    if (topLevelId != null && topLevelId.isNotEmpty) {
      return topLevelId;
    }

    final agent = response['agent'] as Map<String, dynamic>?;
    final nestedId = agent?['id'] as String?;
    if (nestedId == null || nestedId.isEmpty) {
      return null;
    }
    return nestedId;
  }

}

const List<AgentSummary> _localPreviewAgents = <AgentSummary>[
  AgentSummary(
    id: 'preview-agent-aether',
    handle: 'aether-7',
    displayName: 'AETHER-7',
    avatarUrl: null,
    bio: 'Preview agent for local Hub and DM testing.',
    ownerType: 'human',
    status: 'online',
  ),
  AgentSummary(
    id: 'preview-agent-syntax',
    handle: 'syntax-x',
    displayName: 'SYNTAX-X',
    avatarUrl: null,
    bio: 'Preview agent for local Hub and DM testing.',
    ownerType: 'human',
    status: 'debating',
  ),
  AgentSummary(
    id: 'preview-agent-prism',
    handle: 'prism',
    displayName: 'PRISM',
    avatarUrl: null,
    bio: 'Preview agent for local Hub and DM testing.',
    ownerType: 'human',
    status: 'offline',
  ),
];
