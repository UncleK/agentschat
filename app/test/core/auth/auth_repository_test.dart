import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/auth/auth_repository.dart';
import 'package:agents_chat_app/core/network/api_client.dart';

void main() {
  group('AuthRepository', () {
    late _FakeApiClient apiClient;
    late AuthRepository repository;

    setUp(() {
      apiClient = _FakeApiClient();
      repository = AuthRepository(apiClient: apiClient);
    });

    test(
      'loginWithEmail parses backend accessToken plus nested user contract',
      () async {
        apiClient.enqueuePostResponse({
          'accessToken': 'token-login',
          'user': {
            'id': 'usr-login',
            'email': 'owner@example.com',
            'username': 'owner_human',
            'displayName': 'Owner Human',
            'avatarUrl': null,
            'authProvider': 'email',
            'emailVerified': true,
          },
        });

        final authState = await repository.loginWithEmail(
          email: 'owner@example.com',
          password: 'secret',
        );

        expect(apiClient.recordedPaths.single, '/auth/login/email');
        expect(authState.token, 'token-login');
        expect(authState.user?.id, 'usr-login');
        expect(authState.email, 'owner@example.com');
        expect(authState.username, 'owner_human');
        expect(authState.displayName, 'Owner Human');
        expect(authState.authProvider, 'email');
        expect(authState.emailVerified, isTrue);
        expect(authState.isSignedIn, isTrue);
      },
    );

    test(
      'registerWithEmail parses backend accessToken plus nested user contract',
      () async {
        apiClient.enqueuePostResponse({
          'accessToken': 'token-register',
          'user': {
            'id': 'usr-register',
            'email': 'new-owner@example.com',
            'username': 'new_owner',
            'displayName': 'New Owner',
            'avatarUrl': 'https://example.com/avatar.png',
            'authProvider': 'email',
            'emailVerified': false,
          },
        });

        final authState = await repository.registerWithEmail(
          email: 'new-owner@example.com',
          username: 'new_owner',
          displayName: 'New Owner',
          password: 'secret',
        );

        expect(apiClient.recordedPaths.single, '/auth/register/email');
        expect(authState.token, 'token-register');
        expect(authState.user?.id, 'usr-register');
        expect(authState.email, 'new-owner@example.com');
        expect(authState.username, 'new_owner');
        expect(authState.displayName, 'New Owner');
        expect(authState.avatarUrl, 'https://example.com/avatar.png');
        expect(authState.authProvider, 'email');
        expect(authState.emailVerified, isFalse);
        expect(authState.isSignedIn, isTrue);
      },
    );

    test('fetchMe parses emailVerified from the bootstrap contract', () async {
      apiClient.enqueueGetResponse({
        'user': {
          'id': 'usr-bootstrap',
          'email': 'owner@example.com',
          'username': 'owner_human',
          'displayName': 'Owner Human',
          'avatarUrl': null,
          'authProvider': 'email',
          'emailVerified': true,
        },
        'session': {'authenticated': true},
        'recommendedActiveAgentId': 'agt-owned-1',
      });

      final authState = await repository.fetchMe(token: 'token-bootstrap');

      expect(apiClient.recordedPaths.single, '/auth/me');
      expect(authState.user?.id, 'usr-bootstrap');
      expect(authState.emailVerified, isTrue);
      expect(authState.recommendedActiveAgentId, 'agt-owned-1');
    });

    test(
      'password reset and email verification endpoints return backend messages',
      () async {
        apiClient
          ..enqueuePostResponse({
            'message':
                'If an email/password account exists for this address, a password reset code has been sent.',
          })
          ..enqueuePostResponse({
            'message': 'Password updated. Sign in with your new password.',
          })
          ..enqueuePostResponse({
            'message': 'Verification code sent to owner@example.com.',
          })
          ..enqueuePostResponse({'message': 'Email verified.'});

        await expectLater(
          repository.requestPasswordResetCode(email: 'owner@example.com'),
          completion(
            'If an email/password account exists for this address, a password reset code has been sent.',
          ),
        );
        await expectLater(
          repository.confirmPasswordReset(
            email: 'owner@example.com',
            code: '123456',
            newPassword: 'newpassword123',
          ),
          completion('Password updated. Sign in with your new password.'),
        );
        await expectLater(
          repository.requestEmailVerificationCode(),
          completion('Verification code sent to owner@example.com.'),
        );
        await expectLater(
          repository.confirmEmailVerification(code: '654321'),
          completion('Email verified.'),
        );

        expect(
          apiClient.recordedPaths,
          equals([
            '/auth/password-reset/request',
            '/auth/password-reset/confirm',
            '/auth/email-verification/request',
            '/auth/email-verification/confirm',
          ]),
        );
      },
    );

    test(
      'loginWithGoogle fails fast while external login is disabled',
      () async {
        await expectLater(
          repository.loginWithGoogle(
            email: 'google-user@example.com',
            displayName: 'Google User',
            providerSubject: 'google-subject-1',
          ),
          throwsA(isA<UnsupportedError>()),
        );

        expect(apiClient.recordedPaths, isEmpty);
      },
    );

    test(
      'loginWithGitHub fails fast while external login is disabled',
      () async {
        await expectLater(
          repository.loginWithGitHub(
            email: 'github-user@example.com',
            displayName: 'GitHub User',
            providerSubject: 'github-subject-1',
          ),
          throwsA(isA<UnsupportedError>()),
        );

        expect(apiClient.recordedPaths, isEmpty);
      },
    );
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost');

  final Queue<Map<String, dynamic>> _postResponses =
      Queue<Map<String, dynamic>>();
  final Queue<Map<String, dynamic>> _getResponses =
      Queue<Map<String, dynamic>>();
  final List<String> recordedPaths = <String>[];

  void enqueuePostResponse(Map<String, dynamic> response) {
    _postResponses.add(response);
  }

  void enqueueGetResponse(Map<String, dynamic> response) {
    _getResponses.add(response);
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    recordedPaths.add(path);
    return _getResponses.removeFirst();
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    recordedPaths.add(path);
    return _postResponses.removeFirst();
  }
}
