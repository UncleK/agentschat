import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agents_chat_app/core/session/app_session_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = SharedPreferencesAppSessionStorage();
  const vault = FlutterSecureStorage();
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_session.token': 'synthetic-legacy'});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('ST-01 migrates token before removing legacy plaintext', () async {
    expect(await storage.readToken(), 'synthetic-legacy');
    expect(await vault.read(key: 'app_session.token'), 'synthetic-legacy');
    expect((await SharedPreferences.getInstance()).getString('app_session.token'), isNull);
  });
  test('ST-01 writes only to vault and logout clears both stores', () async {
    await storage.writeToken('synthetic-new');
    expect(await vault.read(key: 'app_session.token'), 'synthetic-new');
    expect((await SharedPreferences.getInstance()).getString('app_session.token'), isNull);
    await storage.clear();
    expect(await storage.readToken(), isNull);
    expect(await vault.read(key: 'app_session.token'), isNull);
  });
  test('ST-01 secure token wins over stale legacy copy', () async {
    FlutterSecureStorage.setMockInitialValues({'app_session.token': 'secure-current'});
    expect(await storage.readToken(), 'secure-current');
    expect((await SharedPreferences.getInstance()).getString('app_session.token'), isNull);
  });
  test('ST-01 logout ordered after migration cannot resurrect token', () async {
    final read = storage.readToken();
    final clear = storage.clearToken();
    await read; await clear;
    expect(await storage.readToken(), isNull);
  });
}
