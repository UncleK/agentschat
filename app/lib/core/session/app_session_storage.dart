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

  static const _tokenKey = 'app_session.token';
  static const _currentActiveAgentKey = 'app_session.current_active_agent';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_tokenKey);
    await prefs.remove(_currentActiveAgentKey);
  }

  @override
  Future<void> clearCurrentActiveAgentId() async {
    final prefs = await _prefs;
    await prefs.remove(_currentActiveAgentKey);
  }

  @override
  Future<void> clearToken() async {
    final prefs = await _prefs;
    await prefs.remove(_tokenKey);
  }

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
  Future<String?> readToken() async {
    final prefs = await _prefs;
    final value = prefs.getString(_tokenKey);
    return _normalize(value);
  }

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
  Future<void> writeToken(String token) async {
    final prefs = await _prefs;
    await prefs.setString(_tokenKey, token);
  }

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
