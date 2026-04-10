import 'dart:collection';

import 'package:agents_chat_app/core/auth/auth_repository.dart';
import 'package:agents_chat_app/core/auth/auth_state.dart';
import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/session/app_session_storage.dart';

AuthState signedInState({
  required String token,
  required String userId,
  String? recommendedActiveAgentId,
  String displayName = 'Session User',
  String? email,
  String? authProvider = 'email',
}) {
  return AuthState(
    token: token,
    user: AuthUser(
      id: userId,
      email: email ?? '$userId@example.com',
      displayName: displayName,
      avatarUrl: null,
      authProvider: authProvider,
    ),
    recommendedActiveAgentId: recommendedActiveAgentId,
    isSessionAuthenticated: true,
  );
}

AgentSummary agentSummary({
  required String id,
  String? handle,
  String? displayName,
  String? bio,
  String ownerType = 'human',
  String status = 'offline',
}) {
  return AgentSummary(
    id: id,
    handle: handle ?? id,
    displayName: displayName ?? 'Agent $id',
    avatarUrl: null,
    bio: bio,
    ownerType: ownerType,
    status: status,
  );
}

PendingClaimSummary pendingClaimSummary({
  required String claimRequestId,
  required String agentId,
  String? handle,
  String? displayName,
  String status = 'pending',
  String requestedAt = '2026-04-03T12:00:00.000Z',
  String expiresAt = '2026-04-04T12:00:00.000Z',
}) {
  return PendingClaimSummary(
    claimRequestId: claimRequestId,
    agentId: agentId,
    handle: handle ?? agentId,
    displayName: displayName ?? 'Agent $agentId',
    status: status,
    requestedAt: requestedAt,
    expiresAt: expiresAt,
  );
}

AgentsMineResponse mineResponse({
  List<AgentSummary> agents = const <AgentSummary>[],
  List<AgentSummary> claimableAgents = const <AgentSummary>[],
  List<PendingClaimSummary> pendingClaims = const <PendingClaimSummary>[],
}) {
  return AgentsMineResponse(
    agents: agents,
    claimableAgents: claimableAgents,
    pendingClaims: pendingClaims,
  );
}

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final Queue<
    Future<AuthState> Function({
      required String email,
      required String password,
    })
  >
  _loginHandlers =
      Queue<
        Future<AuthState> Function({
          required String email,
          required String password,
        })
      >();
  final Queue<
    Future<AuthState> Function({
      required String email,
      required String displayName,
      required String password,
    })
  >
  _registerHandlers =
      Queue<
        Future<AuthState> Function({
          required String email,
          required String displayName,
          required String password,
        })
      >();
  final Queue<Future<AuthState> Function(String token)> _fetchMeHandlers =
      Queue<Future<AuthState> Function(String token)>();

  void enqueueLoginWithEmail(
    Future<AuthState> Function({
      required String email,
      required String password,
    })
    handler,
  ) {
    _loginHandlers.add(handler);
  }

  void enqueueRegisterWithEmail(
    Future<AuthState> Function({
      required String email,
      required String displayName,
      required String password,
    })
    handler,
  ) {
    _registerHandlers.add(handler);
  }

  void enqueueFetchMe(Future<AuthState> Function(String token) handler) {
    _fetchMeHandlers.add(handler);
  }

  @override
  Future<AuthState> loginWithEmail({
    required String email,
    required String password,
  }) {
    return _loginHandlers.removeFirst()(
      email: email,
      password: password,
    );
  }

  @override
  Future<AuthState> registerWithEmail({
    required String email,
    required String displayName,
    required String password,
  }) {
    return _registerHandlers.removeFirst()(
      email: email,
      displayName: displayName,
      password: password,
    );
  }

  @override
  Future<AuthState> fetchMe({required String token}) {
    return _fetchMeHandlers.removeFirst()(token);
  }
}

class FakeAgentsRepository extends AgentsRepository {
  FakeAgentsRepository()
    : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final Queue<Future<AgentsMineResponse> Function()> _readMineHandlers =
      Queue<Future<AgentsMineResponse> Function()>();
  final Queue<
    Future<Map<String, dynamic>> Function({
      required String handle,
      required String displayName,
      String? avatarUrl,
      String? bio,
    })
  >
  _importHandlers =
      Queue<
        Future<Map<String, dynamic>> Function({
          required String handle,
          required String displayName,
          String? avatarUrl,
          String? bio,
        })
      >();
  final Queue<Future<Map<String, dynamic>> Function(String agentId)>
  _requestClaimHandlers =
      Queue<Future<Map<String, dynamic>> Function(String)>();
  final Queue<
    Future<Map<String, dynamic>> Function({
      required String agentId,
      required String claimRequestId,
      required String challengeToken,
    })
  >
  _confirmClaimHandlers =
      Queue<
        Future<Map<String, dynamic>> Function({
          required String agentId,
          required String claimRequestId,
          required String challengeToken,
        })
      >();

  void enqueueReadMine(Future<AgentsMineResponse> Function() handler) {
    _readMineHandlers.add(handler);
  }

  void enqueueImportHumanOwnedAgent(
    Future<Map<String, dynamic>> Function({
      required String handle,
      required String displayName,
      String? avatarUrl,
      String? bio,
    })
    handler,
  ) {
    _importHandlers.add(handler);
  }

  void enqueueRequestClaim(
    Future<Map<String, dynamic>> Function(String agentId) handler,
  ) {
    _requestClaimHandlers.add(handler);
  }

  void enqueueConfirmClaim(
    Future<Map<String, dynamic>> Function({
      required String agentId,
      required String claimRequestId,
      required String challengeToken,
    })
    handler,
  ) {
    _confirmClaimHandlers.add(handler);
  }

  @override
  Future<AgentsMineResponse> readMine() {
    return _readMineHandlers.removeFirst()();
  }

  @override
  Future<Map<String, dynamic>> importHumanOwnedAgent({
    required String handle,
    required String displayName,
    String? avatarUrl,
    String? bio,
  }) {
    return _importHandlers.removeFirst()(
      handle: handle,
      displayName: displayName,
      avatarUrl: avatarUrl,
      bio: bio,
    );
  }

  @override
  Future<Map<String, dynamic>> requestClaim(String agentId) {
    return _requestClaimHandlers.removeFirst()(agentId);
  }

  @override
  Future<Map<String, dynamic>> confirmClaim({
    required String agentId,
    required String claimRequestId,
    required String challengeToken,
  }) {
    return _confirmClaimHandlers.removeFirst()(
      agentId: agentId,
      claimRequestId: claimRequestId,
      challengeToken: challengeToken,
    );
  }
}

class InMemoryAppSessionStorage implements AppSessionStorage {
  String? _token;
  String? _currentActiveAgentId;

  @override
  Future<void> clear() async {
    _token = null;
    _currentActiveAgentId = null;
  }

  @override
  Future<void> clearCurrentActiveAgentId() async {
    _currentActiveAgentId = null;
  }

  @override
  Future<void> clearToken() async {
    _token = null;
  }

  @override
  Future<String?> readCurrentActiveAgentId() async {
    return _currentActiveAgentId;
  }

  @override
  Future<String?> readToken() async {
    return _token;
  }

  @override
  Future<void> writeCurrentActiveAgentId(String agentId) async {
    _currentActiveAgentId = agentId;
  }

  @override
  Future<void> writeToken(String token) async {
    _token = token;
  }
}
