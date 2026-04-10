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
            'displayName': 'Owner Human',
            'avatarUrl': null,
            'authProvider': 'email',
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
        expect(authState.displayName, 'Owner Human');
        expect(authState.authProvider, 'email');
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
            'displayName': 'New Owner',
            'avatarUrl': 'https://example.com/avatar.png',
            'authProvider': 'email',
          },
        });

        final authState = await repository.registerWithEmail(
          email: 'new-owner@example.com',
          displayName: 'New Owner',
          password: 'secret',
        );

        expect(apiClient.recordedPaths.single, '/auth/register/email');
        expect(authState.token, 'token-register');
        expect(authState.user?.id, 'usr-register');
        expect(authState.email, 'new-owner@example.com');
        expect(authState.displayName, 'New Owner');
        expect(authState.avatarUrl, 'https://example.com/avatar.png');
        expect(authState.authProvider, 'email');
        expect(authState.isSignedIn, isTrue);
      },
    );

    test('loginWithGoogle fails fast while external login is disabled', () async {
      await expectLater(
        repository.loginWithGoogle(
          email: 'google-user@example.com',
          displayName: 'Google User',
          providerSubject: 'google-subject-1',
        ),
        throwsA(isA<UnsupportedError>()),
      );

      expect(apiClient.recordedPaths, isEmpty);
    });

    test('loginWithGitHub fails fast while external login is disabled', () async {
      await expectLater(
        repository.loginWithGitHub(
          email: 'github-user@example.com',
          displayName: 'GitHub User',
          providerSubject: 'github-subject-1',
        ),
        throwsA(isA<UnsupportedError>()),
      );

      expect(apiClient.recordedPaths, isEmpty);
    });
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost');

  final Queue<Map<String, dynamic>> _postResponses =
      Queue<Map<String, dynamic>>();
  final List<String> recordedPaths = <String>[];

  void enqueuePostResponse(Map<String, dynamic> response) {
    _postResponses.add(response);
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
