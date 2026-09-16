import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../locale/app_localization_extensions.dart';
import '../network/api_exception.dart';
import '../session/app_session_controller.dart';
import 'oauth_client.dart';

class OAuthButtons extends StatefulWidget {
  const OAuthButtons({
    super.key,
    required this.session,
    this.link = false,
    this.onCompleted,
  });
  final AppSessionController session;
  final bool link;
  final Future<void> Function()? onCompleted;
  @override
  State<OAuthButtons> createState() => _OAuthButtonsState();
}

class _OAuthButtonsState extends State<OAuthButtons> {
  String? _busy;
  String? _message;
  final Set<String> _linked = {};
  Map<String, bool>? _available;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  Future<void> _loadMethods() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.session.apiClient.get('/auth/oauth/providers'),
        widget.link
            ? widget.session.apiClient.get('/auth/oauth/identities')
            : Future.value(<String, dynamic>{'identities': <dynamic>[]}),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _available = {
          for (final p in results[0]['providers'] as List)
            p['id'] as String: p['enabled'] == true,
        };
        _linked.addAll(
          (results[1]['identities'] as List).map(
            (p) => p['provider'] as String,
          ),
        );
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = text(
            'Unable to load sign-in methods. Please retry.',
            '无法加载登录方式，请重试。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String text(String en, String zh) =>
      context.localizedText(key: 'oauth$en', en: en, zhHans: zh);
  Future<void> _start(String provider) async {
    setState(() {
      _busy = provider;
      _message = null;
    });
    try {
      final auth = await OAuthClient(
        widget.session.authRepository,
      ).authenticate(provider, link: widget.link);
      await widget.session.authenticate(auth);
      if (!mounted) return;
      if (widget.link) {
        setState(() {
          _linked.add(provider);
          _message = text('Account linked.', '账号已绑定。');
        });
      }
      await widget.onCompleted?.call();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _message = error.code.toUpperCase().contains('CANCEL')
              ? text('Sign-in cancelled. You can try again.', '已取消登录，可以重新尝试。')
              : text(
                  'Unable to open the sign-in browser. Please try again.',
                  '无法打开登录浏览器，请重试。',
                ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _message = error.message.contains('not configured')
              ? text(
                  'This provider is not configured yet. Use email sign-in for now.',
                  '此登录方式尚未配置，请先使用邮箱登录。',
                )
              : error.message.contains('already uses this email')
              ? text(
                  'Sign in to your existing account first, then link this provider in account settings.',
                  '请先登录已有账号，再在“我的 → 登录方式”绑定此账号。',
                )
              : text(
                  error.message,
                  const {
                        'Sign-in was cancelled. Please try again.':
                            '登录已取消，请重新尝试。',
                        'Unable to verify the provider account. Check that it has a verified email and try again.':
                            '无法验证第三方账号，请确认该账号有已验证的邮箱后重试。',
                        'This provider is already linked to another account.':
                            '此第三方账号已绑定其他账号。',
                        'Your account already has a different identity linked to this provider.':
                            '你的账号已绑定此平台的另一个身份。',
                        'Sign in again before linking this provider.':
                            '请重新登录后再绑定此账号。',
                        'Invalid or expired sign-in completion.':
                            '登录已过期，请重新发起登录。',
                      }[error.message] ??
                      error.message,
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = text(
            'Unable to complete sign-in. Please try again.',
            '暂时无法完成登录，请重试。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: ['google', 'github']
            .map(
              (provider) => OutlinedButton.icon(
                key: Key('oauth-$provider-button'),
                onPressed:
                    _busy != null ||
                        _loading ||
                        _linked.contains(provider) ||
                        (_available != null && _available![provider] != true)
                    ? null
                    : () => _start(provider),
                icon: _busy == provider
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        provider == 'google' ? Icons.g_mobiledata : Icons.code,
                      ),
                label: Text(
                  '${provider == 'google' ? 'Google' : 'GitHub'}${_linked.contains(provider)
                      ? ' · ${text('Linked', '已绑定')}'
                      : _available != null && _available![provider] != true
                      ? ' · ${text('Not configured', '暂未配置')}'
                      : widget.link
                      ? ' · ${text('Link', '绑定')}'
                      : ''}',
                ),
              ),
            )
            .toList(),
      ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_message!, semanticsLabel: _message),
        ),
      if (_available == null && !_loading)
        TextButton(onPressed: _loadMethods, child: Text(text('Retry', '重试'))),
    ],
  );
}
