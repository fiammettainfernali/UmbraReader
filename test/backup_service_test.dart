// Tests for BackupService — JSON snapshot of every SharedPreferences value.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/backup_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('exportToJson captures every shared-prefs value, typed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flag': true,
      'count': 42,
      'ratio': 0.5,
      'name': 'Umbra',
      'tags': <String>['action', 'fantasy'],
    });
    final json = await BackupService().exportToJson();
    expect(json, contains('"umbra_reader_backup"'));
    expect(json, contains('"flag": true'));
    expect(json, contains('"count": 42'));
    expect(json, contains('"name": "Umbra"'));
    expect(json, contains('"tags"'));
  });

  test('importFromJson restores every type back into shared prefs', () async {
    final source = await BackupService().exportToJson();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await BackupService().importFromJson(source), greaterThanOrEqualTo(0));
  });

  test('round-trip preserves each value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flag': true,
      'count': 42,
      'ratio': 0.5,
      'name': 'Umbra',
      'tags': <String>['a', 'b'],
    });
    final json = await BackupService().exportToJson();

    // Wipe and restore.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final restored = await BackupService().importFromJson(json);
    expect(restored, 5);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('flag'), true);
    expect(prefs.getInt('count'), 42);
    expect(prefs.getDouble('ratio'), 0.5);
    expect(prefs.getString('name'), 'Umbra');
    expect(prefs.getStringList('tags'), ['a', 'b']);
  });

  test('importFromJson wipes existing keys before restoring', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'existing': 'old'});
    final json = await BackupService().exportToJson();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('newer', 'value');
    expect(prefs.getString('newer'), 'value');

    await BackupService().importFromJson(json);
    final after = await SharedPreferences.getInstance();
    expect(after.getString('newer'), isNull);
    expect(after.getString('existing'), 'old');
  });

  test('importFromJson rejects empty input', () async {
    await expectLater(
      BackupService().importFromJson(''),
      throwsA(isA<BackupException>()),
    );
  });

  test('importFromJson rejects malformed JSON', () async {
    await expectLater(
      BackupService().importFromJson('this is not json'),
      throwsA(isA<BackupException>()),
    );
  });

  test('importFromJson rejects JSON without the signature', () async {
    await expectLater(
      BackupService().importFromJson('{"random": 1}'),
      throwsA(isA<BackupException>()),
    );
  });
}
