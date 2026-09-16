import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ST-01 credentials are excluded from cloud and device transfer', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    const domains = [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ];
    final legacy = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final modern = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    for (final mode in ['cloud-backup', 'device-transfer']) {
      final section = RegExp(
        '<$mode[^>]*>([\\s\\S]*?)</$mode>',
      ).firstMatch(modern);
      expect(
        section,
        isNotNull,
        reason: 'Missing $mode policy permits default transfer',
      );
      for (final domain in domains) {
        expect(
          section!.group(1),
          contains('<exclude domain="$domain" path="."'),
        );
        expect(legacy, contains('<exclude domain="$domain" path="."'));
      }
    }
  });
}
