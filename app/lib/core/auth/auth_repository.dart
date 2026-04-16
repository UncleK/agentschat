import '../network/api_client.dart';
import 'auth_state.dart';

class UsernameAvailabilityResult {
  const UsernameAvailabilityResult({
    required this.normalizedUsername,
    required this.available,
    required this.message,
  });

  final String normalizedUsername;
  final bool available;
  final String message;

  factory UsernameAvailabilityResult.fromJson(Map<String, dynamic> json) {
    return UsernameAvailabilityResult(
      normalizedUsername: json['normalizedUsername'] as String? ?? '',
      available: json['available'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}

/// Handles human authentication against the backend.
class AuthRepository {
  const AuthRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Register a new human account with email/password.
  Future<AuthState> registerWithEmail({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async {
    final response = await apiClient.post(
      '/auth/register/email',
      body: {
        'email': email,
        'username': username,
        'displayName': displayName,
        'password': password,
      },
    );
    return _parseLoginResponse(response);
  }

  Future<UsernameAvailabilityResult> readUsernameAvailability({
    required String username,
  }) async {
    final response = await apiClient.get(
      '/auth/username-availability',
      queryParameters: {'username': username},
    );
    return UsernameAvailabilityResult.fromJson(response);
  }

  /// Log in an existing human account with email/password.
  Future<AuthState> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await apiClient.post(
      '/auth/login/email',
      body: {'email': email, 'password': password},
    );
    return _parseLoginResponse(response);
  }

  Future<String> requestPasswordResetCode({required String email}) async {
    final response = await apiClient.post(
      '/auth/password-reset/request',
      body: {'email': email},
    );
    return _readMessage(
      response,
      fallback:
          'If an email/password account exists for this address, a password reset code has been sent.',
    );
  }

  Future<String> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await apiClient.post(
      '/auth/password-reset/confirm',
      body: {'email': email, 'code': code, 'newPassword': newPassword},
    );
    return _readMessage(
      response,
      fallback: 'Password updated. Sign in with your new password.',
    );
  }

  Future<String> requestEmailVerificationCode() async {
    final response = await apiClient.post('/auth/email-verification/request');
    return _readMessage(response, fallback: 'Verification code sent.');
  }

  Future<String> confirmEmailVerification({required String code}) async {
    final response = await apiClient.post(
      '/auth/email-verification/confirm',
      body: {'code': code},
    );
    return _readMessage(response, fallback: 'Email verified.');
  }

  /// Temporarily disabled until backend provider-token verification exists.
  Future<AuthState> loginWithGoogle({
    required String email,
    required String displayName,
    required String providerSubject,
  }) async {
    throw UnsupportedError(
      'Google login is temporarily disabled until provider token verification is implemented.',
    );
  }

  /// Temporarily disabled until backend provider-token verification exists.
  Future<AuthState> loginWithGitHub({
    required String email,
    required String displayName,
    required String providerSubject,
  }) async {
    throw UnsupportedError(
      'GitHub login is temporarily disabled until provider token verification is implemented.',
    );
  }

  /// Fetch the canonical authenticated human session state.
  Future<AuthState> fetchMe({required String token}) async {
    final response = await apiClient.get('/auth/me');
    return _parseBootstrapResponse(response, token: token);
  }

  AuthState _parseLoginResponse(Map<String, dynamic> response) {
    final user = response['user'] as Map<String, dynamic>? ?? const {};
    return AuthState(
      token: response['accessToken'] as String? ?? '',
      user: AuthUser(
        id: user['id'] as String? ?? '',
        email: user['email'] as String? ?? '',
        username: user['username'] as String? ?? '',
        displayName: user['displayName'] as String? ?? '',
        avatarUrl: user['avatarUrl'] as String?,
        authProvider: user['authProvider'] as String?,
        emailVerified: user['emailVerified'] as bool? ?? false,
      ),
      recommendedActiveAgentId: null,
      isSessionAuthenticated: true,
    );
  }

  AuthState _parseBootstrapResponse(
    Map<String, dynamic> response, {
    required String token,
  }) {
    final user = response['user'] as Map<String, dynamic>? ?? const {};
    final session = response['session'] as Map<String, dynamic>? ?? const {};
    return AuthState(
      token: token,
      user: AuthUser(
        id: user['id'] as String? ?? '',
        email: user['email'] as String? ?? '',
        username: user['username'] as String? ?? '',
        displayName: user['displayName'] as String? ?? '',
        avatarUrl: user['avatarUrl'] as String?,
        authProvider: user['authProvider'] as String?,
        emailVerified: user['emailVerified'] as bool? ?? false,
      ),
      recommendedActiveAgentId: response['recommendedActiveAgentId'] as String?,
      isSessionAuthenticated: session['authenticated'] as bool? ?? false,
    );
  }

  String _readMessage(
    Map<String, dynamic> response, {
    required String fallback,
  }) {
    return response['message'] as String? ?? fallback;
  }
}
