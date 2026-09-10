import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sattra/core/constants.dart';
import 'package:sattra/core/ids.dart';
import 'package:sattra/data/db/app_database.dart';
import 'package:sattra/data/models/models.dart';
import 'package:sattra/data/repos/repositories.dart';
import 'package:sattra/services/backup_service.dart';
import 'package:sattra/services/credential_store.dart';
import 'package:sattra/services/settings_service.dart';

void main() {
  late Directory workspace;

  setUp(() => workspace = Directory.systemTemp.createTempSync('sattra-test'));
  tearDown(() => workspace.deleteSync(recursive: true));

  ({
    AppDatabase db,
    BackupService backups,
    SettingsService settings,
    PatientRepository patients,
    CredentialStore credentials,
  }) makeInstall(String name) {
    final db = AppDatabase.open(p.join(workspace.path, name, 'sattra.db'));
    final settings = SettingsService(db)..clinicName = 'Test Clinic';
    final audit = AuditRepository(db);
    return (
      db: db,
      backups: BackupService(db: db, settings: settings),
      settings: settings,
      patients: PatientRepository(db, audit),
      credentials: CredentialStore(db),
    );
  }

  Patient patientNamed(String name, String code) => Patient(
        id: newId(),
        code: code,
        name: name,
        age: 40,
        sex: Sex.male,
        registeredAt: DateTime.now(),
      );

  test('a backup round-trips into a fresh install', () async {
    final origin = makeInstall('origin');
    origin.patients.create(patientNamed('Asha Devi', 'P-0001'));
    origin.patients.create(patientNamed('Brian Kihore', 'P-0002'));

    final path = p.join(workspace.path, 'clinic.sattrabak');
    await origin.backups.export(path, 'a good passphrase');
    origin.db.close();

    final restoredInto = makeInstall('restored');
    expect(restoredInto.patients.total, 0);

    final info = await restoredInto.backups.restore(path, 'a good passphrase');

    expect(info.clinic, 'Test Clinic');
    expect(restoredInto.patients.total, 2);
    expect(
      restoredInto.patients.search().map((p) => p.name),
      containsAll(['Asha Devi', 'Brian Kihore']),
    );
    restoredInto.db.close();
  });

  test('the wrong passphrase does not open the file', () async {
    final origin = makeInstall('origin');
    origin.patients.create(patientNamed('Asha Devi', 'P-0001'));
    final path = p.join(workspace.path, 'clinic.sattrabak');
    await origin.backups.export(path, 'the right passphrase');
    origin.db.close();

    final target = makeInstall('target');
    await expectLater(
      target.backups.restore(path, 'the wrong passphrase'),
      throwsA(isA<BackupException>()),
    );
    target.db.close();
  });

  test('the file on disk does not contain patient names in the clear',
      () async {
    final origin = makeInstall('origin');
    origin.patients.create(patientNamed('Asha Devi', 'P-0001'));
    final path = p.join(workspace.path, 'clinic.sattrabak');
    await origin.backups.export(path, 'a good passphrase');
    origin.db.close();

    final raw = await File(path).readAsString();
    expect(raw.contains('Asha Devi'), isFalse);
    // The header stays readable so a restore screen can describe the file.
    expect(raw.contains('Test Clinic'), isTrue);
  });

  test('a backup carries credentials so a restored hub can sign people in',
      () async {
    final origin = makeInstall('origin');
    origin.db.upsert('users', {
      'id': 'u1',
      'username': 'admin',
      'full_name': 'The Administrator',
      'role': 'admin',
      'active': 1,
      'created_at': 1000,
    });
    await origin.credentials.setPassword('u1', 'opensesame');
    final path = p.join(workspace.path, 'clinic.sattrabak');
    await origin.backups.export(path, 'a good passphrase');
    origin.db.close();

    final restoredInto = makeInstall('restored');
    await restoredInto.backups.restore(path, 'a good passphrase');

    expect(
      await restoredInto.credentials.verifyLocal('admin', 'opensesame'),
      isNotNull,
    );
    restoredInto.db.close();
  });

  test('a restored install owes all of its rows to the hub again', () async {
    final origin = makeInstall('origin');
    origin.patients.create(patientNamed('Asha Devi', 'P-0001'));
    final path = p.join(workspace.path, 'clinic.sattrabak');
    await origin.backups.export(path, 'a good passphrase');
    origin.db.close();

    final restoredInto = makeInstall('restored');
    restoredInto.settings.setWatermark('patients', 999999);
    await restoredInto.backups.restore(path, 'a good passphrase');

    final row = restoredInto.db.queryOne('SELECT dirty FROM patients LIMIT 1');
    expect(row!['dirty'], 1);
    // Old watermarks describe a database that no longer exists.
    expect(restoredInto.settings.watermark('patients'), 0);
    restoredInto.db.close();
  });

  test('inspect refuses a file that is not a backup', () async {
    final path = p.join(workspace.path, 'notes.sattrabak');
    await File(path).writeAsString('just some text');
    final target = makeInstall('target');

    await expectLater(
      target.backups.inspect(path),
      throwsA(isA<BackupException>()),
    );
    target.db.close();
  });

  test('a short passphrase is refused up front', () async {
    final origin = makeInstall('origin');

    await expectLater(
      origin.backups.export(p.join(workspace.path, 'x.sattrabak'), 'short'),
      throwsA(isA<BackupException>()),
    );
    origin.db.close();
  });
}
