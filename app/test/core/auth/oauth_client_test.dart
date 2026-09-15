import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agents_chat_app/core/auth/auth_repository.dart';
import 'package:agents_chat_app/core/auth/oauth_client.dart';
import 'package:agents_chat_app/core/network/api_client.dart';

class _OAuthApi extends ApiClient {
  _OAuthApi() : super(baseUrl: 'http://localhost');
  String? challenge;
  String? path;
  int exchanges = 0;
  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (path.endsWith('/start') || path.endsWith('/link')) {
      this.path = path;
      expect(body!['client'], 'mobile');
      challenge = body['codeChallenge'] as String;
      return {
        'flowId': 'flow-123',
        'authorizationUrl':
            'https://accounts.google.com/o/oauth2/v2/auth?state=test',
      };
    }
    expect(path, '/auth/oauth/exchange');
    exchanges++;
    expect(body!['flowId'], 'flow-123');
    expect(
      base64Url
          .encode(sha256.convert(utf8.encode(body['verifier'] as String)).bytes)
          .replaceAll('=', ''),
      challenge,
    );
    return {
      'accessToken': 'verified-session',
      'user': {
        'id': 'same-owner',
        'email': 'owner@example.test',
        'username': 'owner',
        'displayName': 'Owner',
        'authProvider': 'google',
        'emailVerified': true,
      },
    };
  }
}

void main() {
  test(
    'binds native callback and exchange to the client PKCE verifier',
    () async {
      final api = _OAuthApi();
      final client = OAuthClient(
        AuthRepository(apiClient: api),
        openBrowser: (url) async =>
            'agentschat://oauth?flow=flow-123&code=${'c' * 43}',
      );
      final auth = await client.authenticate('google');
      expect(auth.isSignedIn, isTrue);
      expect(auth.userId, 'same-owner');
      expect(auth.emailVerified, isTrue);
      expect(api.exchanges, 1);
    },
  );
  test(
    'never exchanges a callback for another flow or callback host',
    () async {
      final api = _OAuthApi();
      for (final uri in [
        'agentschat://oauth?flow=other&code=${'c' * 43}',
        'evil://oauth?flow=flow-123&code=${'c' * 43}',
      ]) {
        final client = OAuthClient(
          AuthRepository(apiClient: api),
          openBrowser: (_) async => uri,
        );
        await expectLater(client.authenticate('google'), throwsStateError);
      }
      expect(api.exchanges, 0);
    },
  );
  test('explicit linking uses the authenticated linking endpoint', () async {
    final api = _OAuthApi();
    await OAuthClient(
      AuthRepository(apiClient: api),
      openBrowser: (_) async =>
          'agentschat://oauth?flow=flow-123&code=${'c' * 43}',
    ).authenticate('google', link: true);
    expect(api.path, '/auth/oauth/google/link');
  });
  test(
    'cancellation does not call exchange and a retry creates fresh proof',
    () async {
      final api = _OAuthApi();
      String? first;
      final client = OAuthClient(
        AuthRepository(apiClient: api),
        openBrowser: (_) async {
          first ??= api.challenge;
          throw StateError('Cancelled');
        },
      );
      await expectLater(client.authenticate('google'), throwsStateError);
      await expectLater(client.authenticate('google'), throwsStateError);
      expect(api.challenge, isNot(first));
      expect(api.exchanges, 0);
    },
  );
}
