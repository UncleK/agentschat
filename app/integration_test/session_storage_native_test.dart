import 'package:agents_chat_app/core/session/app_session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Run only in a fresh synthetic emulator/simulator. No mock method channels:
// this exercises the installed platform plugin and native Keystore/Keychain.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const storage = SharedPreferencesAppSessionStorage();
  const vault = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  const phase = String.fromEnvironment(
    'STORAGE_AUDIT_PHASE',
    defaultValue: 'migrate',
  );
  const token = 'agentschat-native-audit-synthetic-token-not-a-credential';

  testWidgets('ST-01 native vault $phase', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    if (phase == 'migrate') {
      await storage.clear();
      await prefs.setString('app_session.token', token);
      await storage.writeCurrentActiveAgentId('synthetic-agent-identity');
      expect(await storage.readToken(), token);
      await prefs.reload();
      expect(prefs.getString('app_session.token'), isNull);
      expect(await vault.read(key: 'app_session.token'), token);
      expect(
        await storage.readCurrentActiveAgentId(),
        'synthetic-agent-identity',
      );
      // Leave the synthetic token for the second process to check persistence.
    } else if (phase == 'restart') {
      expect(await storage.readToken(), token);
      expect(prefs.getString('app_session.token'), isNull);
      await storage.clear();
      expect(await vault.read(key: 'app_session.token'), isNull);
      expect(await storage.readToken(), isNull);
      expect(await storage.readCurrentActiveAgentId(), isNull);
    } else if (phase == 'logged-out') {
      expect(await storage.readToken(), isNull);
      expect(await vault.read(key: 'app_session.token'), isNull);
      expect(prefs.getString('app_session.token'), isNull);
    } else {
      fail('Unknown audit phase: $phase');
    }
  });
}
