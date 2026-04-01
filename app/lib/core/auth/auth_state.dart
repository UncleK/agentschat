/// Represents the current authentication state of the human user.
class AuthState {
  const AuthState({
    required this.token,
    required this.userId,
    required this.email,
    required this.displayName,
  });

  final String token;
  final String userId;
  final String email;
  final String displayName;

  static const signedOut = _SignedOutAuthState();

  bool get isSignedIn => token.isNotEmpty;
}

/// Sentinel subclass representing the signed-out state.
class _SignedOutAuthState extends AuthState {
  const _SignedOutAuthState()
      : super(token: '', userId: '', email: '', displayName: '');

  @override
  bool get isSignedIn => false;
}
