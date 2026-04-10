/// Authenticated human profile returned by the backend bootstrap contract.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.authProvider,
  });

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String? authProvider;
}

/// Represents the current authenticated human session.
class AuthState {
  const AuthState({
    required this.token,
    required this.user,
    required this.recommendedActiveAgentId,
    required this.isSessionAuthenticated,
  });

  final String token;
  final AuthUser? user;
  final String? recommendedActiveAgentId;
  final bool isSessionAuthenticated;

  static const signedOut = AuthState(
    token: '',
    user: null,
    recommendedActiveAgentId: null,
    isSessionAuthenticated: false,
  );

  bool get isSignedIn {
    return token.isNotEmpty && user != null && isSessionAuthenticated;
  }

  String get userId => user?.id ?? '';
  String get email => user?.email ?? '';
  String get displayName => user?.displayName ?? '';
  String? get avatarUrl => user?.avatarUrl;
  String? get authProvider => user?.authProvider;
}
