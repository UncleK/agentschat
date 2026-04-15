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
  String username = '',
  String? authProvider = 'email',
}) {
  return AuthState(
    token: token,
    user: AuthUser(
      id: userId,
      email: email ?? '$userId@example.com',
      username: username.isNotEmpty ? username : userId,
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

ConnectedAgentSummary connectedAgentSummary({
  required String id,
  String? handle,
  String? displayName,
  String ownerType = 'human',
  String status = 'online',
  String protocolVersion = '1.0',
  String transportMode = 'webhook',
  bool pollingEnabled = false,
  String? lastSeenAt = '2026-04-13T08:00:00.000Z',
  String? lastHeartbeatAt = '2026-04-13T08:01:00.000Z',
}) {
  return ConnectedAgentSummary(
    id: id,
    handle: handle ?? id,
    displayName: displayName ?? 'Agent $id',
    avatarUrl: null,
    bio: null,
    ownerType: ownerType,
    status: status,
    protocolVersion: protocolVersion,
    transportMode: transportMode,
    pollingEnabled: pollingEnabled,
    lastSeenAt: lastSeenAt,
    lastHeartbeatAt: lastHeartbeatAt,
  );
}

ConnectedAgentsResponse connectedAgentsResponse({
  List<ConnectedAgentSummary> connectedAgents = const <ConnectedAgentSummary>[],
}) {
  return ConnectedAgentsResponse(connectedAgents: connectedAgents);
}

class FakeApiClient extends ApiClient {
  FakeApiClient() : super(baseUrl: 'http://localhost');

  final Queue<
    Future<Map<String, dynamic>> Function(String, Map<String, String>?)
  >
  _getHandlers =
      Queue<
        Future<Map<String, dynamic>> Function(String, Map<String, String>?)
      >();
  final Queue<
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)
  >
  _postHandlers =
      Queue<
        Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)
      >();
  final Queue<
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)
  >
  _deleteHandlers =
      Queue<
        Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)
      >();

  void enqueueGet(
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, String>? queryParameters,
    )
    handler,
  ) {
    _getHandlers.add(handler);
  }

  void enqueuePost(
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic>? body,
    )
    handler,
  ) {
    _postHandlers.add(handler);
  }

  void enqueueDelete(
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic>? body,
    )
    handler,
  ) {
    _deleteHandlers.add(handler);
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    return _getHandlers.removeFirst()(path, queryParameters);
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) {
    return _postHandlers.removeFirst()(path, body);
  }

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _deleteHandlers.removeFirst()(path, body);
  }
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
      required String username,
      required String displayName,
      required String password,
    })
  >
  _registerHandlers =
      Queue<
        Future<AuthState> Function({
          required String email,
          required String username,
          required String displayName,
          required String password,
        })
      >();
  final Queue<Future<UsernameAvailabilityResult> Function(String username)>
  _usernameAvailabilityHandlers =
      Queue<Future<UsernameAvailabilityResult> Function(String)>();
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
      required String username,
      required String displayName,
      required String password,
    })
    handler,
  ) {
    _registerHandlers.add(handler);
  }

  void enqueueUsernameAvailability(
    Future<UsernameAvailabilityResult> Function(String username) handler,
  ) {
    _usernameAvailabilityHandlers.add(handler);
  }

  void enqueueFetchMe(Future<AuthState> Function(String token) handler) {
    _fetchMeHandlers.add(handler);
  }

  @override
  Future<AuthState> loginWithEmail({
    required String email,
    required String password,
  }) {
    return _loginHandlers.removeFirst()(email: email, password: password);
  }

  @override
  Future<AuthState> registerWithEmail({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) {
    return _registerHandlers.removeFirst()(
      email: email,
      username: username,
      displayName: displayName,
      password: password,
    );
  }

  @override
  Future<UsernameAvailabilityResult> readUsernameAvailability({
    required String username,
  }) {
    return _usernameAvailabilityHandlers.removeFirst()(username);
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
  final Queue<Future<ConnectedAgentsResponse> Function()>
  _readConnectedAgentsHandlers =
      Queue<Future<ConnectedAgentsResponse> Function()>();
  final Queue<Future<HumanOwnedAgentInvitation> Function()>
  _createInvitationHandlers =
      Queue<Future<HumanOwnedAgentInvitation> Function()>();
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
  final Queue<Future<Map<String, dynamic>> Function()>
  _disconnectConnectedAgentsHandlers =
      Queue<Future<Map<String, dynamic>> Function()>();

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

  void enqueueCreateHumanOwnedAgentInvitation(
    Future<HumanOwnedAgentInvitation> Function() handler,
  ) {
    _createInvitationHandlers.add(handler);
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

  void enqueueReadConnectedAgents(
    Future<ConnectedAgentsResponse> Function() handler,
  ) {
    _readConnectedAgentsHandlers.add(handler);
  }

  void enqueueDisconnectConnectedAgents(
    Future<Map<String, dynamic>> Function() handler,
  ) {
    _disconnectConnectedAgentsHandlers.add(handler);
  }

  @override
  Future<AgentsMineResponse> readMine() {
    return _readMineHandlers.removeFirst()();
  }

  @override
  Future<ConnectedAgentsResponse> readConnectedAgents() {
    return _readConnectedAgentsHandlers.removeFirst()();
  }

  @override
  Future<HumanOwnedAgentInvitation> createHumanOwnedAgentInvitation() {
    return _createInvitationHandlers.removeFirst()();
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

  @override
  Future<Map<String, dynamic>> disconnectAllConnectedAgents() {
    return _disconnectConnectedAgentsHandlers.removeFirst()();
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
