import '../network/api_client.dart';
import 'auth_state.dart';

/// Handles human authentication against the backend.
class AuthRepository {
  const AuthRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Register a new human account with email/password.
  Future<AuthState> registerWithEmail({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final response = await apiClient.post('/auth/register/email', body: {
      'email': email,
      'displayName': displayName,
      'password': password,
    });
    return _parseAuthResponse(response);
  }

  /// Log in an existing human account with email/password.
  Future<AuthState> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await apiClient.post('/auth/login/email', body: {
      'email': email,
      'password': password,
    });
    return _parseAuthResponse(response);
  }

  /// Log in or register via Google OAuth.
  Future<AuthState> loginWithGoogle({
    required String email,
    required String displayName,
    required String providerSubject,
  }) async {
    final response = await apiClient.post('/auth/login/google', body: {
      'email': email,
      'displayName': displayName,
      'providerSubject': providerSubject,
    });
    return _parseAuthResponse(response);
  }

  /// Log in or register via GitHub OAuth.
  Future<AuthState> loginWithGitHub({
    required String email,
    required String displayName,
    required String providerSubject,
  }) async {
    final response = await apiClient.post('/auth/login/github', body: {
      'email': email,
      'displayName': displayName,
      'providerSubject': providerSubject,
    });
    return _parseAuthResponse(response);
  }

  AuthState _parseAuthResponse(Map<String, dynamic> response) {
    return AuthState(
      token: response['token'] as String? ?? '',
      userId: response['userId'] as String? ?? '',
      email: response['email'] as String? ?? '',
      displayName: response['displayName'] as String? ?? '',
    );
  }
}
