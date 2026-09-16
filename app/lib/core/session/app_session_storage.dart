import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class AppSessionStorage {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<void> clearToken();

  Future<String?> readCurrentActiveAgentId();

  Future<void> writeCurrentActiveAgentId(String agentId);

  Future<void> clearCurrentActiveAgentId();

  Future<List<String>> readDismissedChatThreadIds({
    required String userId,
    required String activeAgentId,
  });

  Future<void> writeDismissedChatThreadIds({
    required String userId,
    required String activeAgentId,
    required List<String> threadIds,
  });

  Future<void> clear();
}

class SharedPreferencesAppSessionStorage implements AppSessionStorage {
  const SharedPreferencesAppSessionStorage();

  static const _vault = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static Future<void> _pending = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }

  static const _tokenKey = 'app_session.token';
  static const _currentActiveAgentKey = 'app_session.current_active_agent';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await clearToken();
    await prefs.remove(_currentActiveAgentKey);
  }

  @override
  Future<void> clearCurrentActiveAgentId() async {
    final prefs = await _prefs;
    await prefs.remove(_currentActiveAgentKey);
  }

  @override
  Future<void> clearToken() => _serial(() async {
    // Remove fallback first so a failed vault deletion cannot restore it.
    final prefs = await _prefs;
    await prefs.remove(_tokenKey);
    await _vault.delete(key: _tokenKey);
  });

  @override
  Future<List<String>> readDismissedChatThreadIds({
    required String userId,
    required String activeAgentId,
  }) async {
    final prefs = await _prefs;
    final values = prefs.getStringList(
      _dismissedChatThreadsKey(userId: userId, activeAgentId: activeAgentId),
    );
    if (values == null || values.isEmpty) {
      return const <String>[];
    }
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  @override
  Future<String?> readCurrentActiveAgentId() async {
    final prefs = await _prefs;
    final value = prefs.getString(_currentActiveAgentKey);
    return _normalize(value);
  }

  @override
  Future<String?> readToken() => _serial(() async {
    final prefs = await _prefs;
    final secure = await _vault.read(key: _tokenKey);
    if (secure != null) {
      await prefs.remove(_tokenKey);
      return _normalize(secure);
    }
    final legacy = _normalize(prefs.getString(_tokenKey));
    if (legacy != null) {
      // A failed secure write leaves the original available for a later retry.
      await _vault.write(key: _tokenKey, value: legacy);
      await prefs.remove(_tokenKey);
    }
    return legacy;
  });

  @override
  Future<void> writeCurrentActiveAgentId(String agentId) async {
    final prefs = await _prefs;
    await prefs.setString(_currentActiveAgentKey, agentId);
  }

  @override
  Future<void> writeDismissedChatThreadIds({
    required String userId,
    required String activeAgentId,
    required List<String> threadIds,
  }) async {
    final prefs = await _prefs;
    final normalized = threadIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    await prefs.setStringList(
      _dismissedChatThreadsKey(userId: userId, activeAgentId: activeAgentId),
      normalized,
    );
  }

  @override
  Future<void> writeToken(String token) => _serial(() async {
    await _vault.write(key: _tokenKey, value: token);
    final prefs = await _prefs;
    await prefs.remove(_tokenKey);
  });

  String? _normalize(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String _dismissedChatThreadsKey({
    required String userId,
    required String activeAgentId,
  }) {
    return 'chat.dismissed_threads.$userId.$activeAgentId';
  }
}
