import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'auth_repository.dart';
import 'auth_state.dart';

typedef OAuthBrowser = Future<String> Function(String url);

class OAuthClient {
  OAuthClient(this.repository, {OAuthBrowser? openBrowser})
    : _openBrowser = openBrowser ?? _launch;
  final AuthRepository repository;
  final OAuthBrowser _openBrowser;
  static Future<String> _launch(String url) =>
      FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: 'agentschat');

  Future<AuthState> authenticate(String provider, {bool link = false}) async {
    final random = Random.secure();
    final verifier = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final flow = await repository.startOAuth(
      provider: provider,
      codeChallenge: challenge,
      link: link,
    );
    final url = Uri.parse(flow['authorizationUrl'] as String);
    final expectedHost = provider == 'google'
        ? 'accounts.google.com'
        : 'github.com';
    if (url.scheme != 'https' ||
        url.host != expectedHost ||
        url.userInfo.isNotEmpty) {
      throw StateError('Invalid provider destination.');
    }
    final result = Uri.parse(await _openBrowser(url.toString()));
    if (result.scheme != 'agentschat' ||
        result.host != 'oauth' ||
        result.queryParameters['flow'] != flow['flowId'] ||
        !RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(result.queryParameters['code'] ?? '')) {
      throw StateError('Sign-in callback did not match this session.');
    }
    return repository.completeOAuth(
      flowId: flow['flowId'] as String,
      code: result.queryParameters['code']!,
      verifier: verifier,
    );
  }
}
