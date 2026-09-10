import 'package:flutter_test/flutter_test.dart';
import 'package:sattra/core/constants.dart';
import 'package:sattra/core/ids.dart';
import 'package:sattra/data/db/app_database.dart';
import 'package:sattra/data/models/models.dart';
import 'package:sattra/data/repos/repositories.dart';
import 'package:sattra/services/credential_store.dart';
import 'package:sattra/services/settings_service.dart';
import 'package:sattra/services/sync/hub_client.dart';
import 'package:sattra/services/sync/hub_server.dart';
import 'package:sattra/services/sync/protocol.dart';
import 'package:sattra/services/sync/merge.dart';

/// Regression tests for the findings of the security review.
///
/// Each group names the flaw it pins down, so that if one of these ever fails
/// it is obvious what has been reopened.
void main() {
  group('column names from a peer cannot become SQL', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.openInMemory();
      // user_credentials references users(id), so the account has to exist
      // before a verifier can be planted for it.
      db.upsert('users', {
        'id': 'u1',
        'username': 'the.admin',
        'full_name': 'The Administrator',
        'role': 'admin',
        'active': 1,
        'created_at': 1000,
      });
      db.execute(
        'INSERT INTO user_credentials(user_id, algo, salt, iterations, hash, updated_at) '
        'VALUES(?, ?, ?, ?, ?, ?)',
        ['u1', 'pbkdf2-hmac-sha256', 'SALT', 1000, 'SUPER_SECRET_HASH', 1],
      );
    });
    tearDown(() => db.close());

    Map<String, Object?> patientRow(Map<String, Object?> extra) => {
          'id': 'evil-1',
          'code': 'P-9001',
          'name': 'Mallory',
          'registered_at': 1,
          'updated_at': 9999999999999,
          'deleted': 0,
          'node': 'attacker',
          ...extra,
        };

    test('a crafted column name is dropped, not executed', () {
      // The payload closes the column list and appends a subquery that reads
      // the credential table, which sync is designed never to expose.
      // Balanced so that it is a valid single statement when unfixed: the row
      // binds nine values (seven real columns, the crafted key, and the dirty
      // flag the merge appends), so the payload supplies seven placeholders in
      // VALUES, takes the eighth column from a subquery against the credential
      // table, and spends the last two in the UPDATE clause.
      const injected =
          'address) VALUES (?,?,?,?,?,?,?,'
          '(SELECT hash FROM user_credentials LIMIT 1)) '
          'ON CONFLICT(id) DO UPDATE SET address=excluded.address, notes=?, '
          'chief_complaints=? --';

      SyncMerge.apply(db, 'patients', [
        patientRow({injected: 0}),
      ]);

      final row = db.queryOne('SELECT * FROM patients WHERE id = ?', ['evil-1']);
      expect(row, isNotNull);
      for (final value in row!.values) {
        expect(
          value.toString(),
          isNot(contains('SUPER_SECRET_HASH')),
          reason: 'a credential hash reached a replicated column',
        );
      }
    });

    test('unknown columns are ignored rather than rejected wholesale', () {
      // A peer on a newer schema will legitimately send columns this build has
      // never heard of; the row it belongs to should still land.
      SyncMerge.apply(db, 'patients', [
        patientRow({'some_future_column': 'ignored'}),
      ]);

      expect(
        db.queryOne('SELECT name FROM patients WHERE id = ?', ['evil-1'])!['name'],
        'Mallory',
      );
    });

    test('a row whose primary key is not a real column is refused', () {
      expect(
        () => db.applyRemote('patients', {'not_a_column': 1}),
        throwsArgumentError,
      );
    });

    test('the credential tables stay out of the replicated set', () {
      expect(
        () => SyncMerge.apply(db, 'user_credentials', [
          {'user_id': 'u1', 'hash': 'planted'},
        ]),
        throwsArgumentError,
      );
    });
  });

  group('the offline verifier does not outlive the password', () {
    late AppDatabase db;
    late CredentialStore credentials;

    setUp(() {
      db = AppDatabase.openInMemory();
      credentials = CredentialStore(db);
      db.upsert('users', {
        'id': 'u1',
        'username': 'a.doctor',
        'full_name': 'A Doctor',
        'role': 'provider',
        'active': 1,
        'created_at': 1000,
      });
    });
    tearDown(() => db.close());

    test('changing the password forgets this machine\'s cached verifier',
        () async {
      await credentials.cacheForOffline('u1', 'a.doctor', 'old-password');
      expect(
        await credentials.verifyCached('a.doctor', 'old-password'),
        isNotNull,
      );

      await credentials.setPassword('u1', 'new-password');

      expect(
        await credentials.verifyCached('a.doctor', 'old-password'),
        isNull,
        reason: 'a retired password still opened the offline path',
      );
    });

    test('a verifier older than the staff record is not trusted', () async {
      // Simulates a reset that happened on the hub: the users row arrives by
      // sync stamped later than the cache entry this machine holds.
      await credentials.cacheForOffline('u1', 'a.doctor', 'old-password');
      db.execute(
        'UPDATE users SET updated_at = ? WHERE id = ?',
        [DateTime.now().millisecondsSinceEpoch + 60000, 'u1'],
      );

      expect(await credentials.verifyCached('a.doctor', 'old-password'), isNull);
    });

    test('a verifier past its maximum age is not trusted', () async {
      await credentials.cacheForOffline('u1', 'a.doctor', 'password');
      final stale = DateTime.now()
              .subtract(CredentialStore.maxOfflineCacheAge)
              .millisecondsSinceEpoch -
          1000;
      db.execute(
        'UPDATE local_credentials SET cached_at = ? WHERE user_id = ?',
        [stale, 'u1'],
      );
      // Keep the staff row older still, so age is the only thing under test.
      db.execute('UPDATE users SET updated_at = ? WHERE id = ?', [1, 'u1']);

      expect(await credentials.verifyCached('a.doctor', 'password'), isNull);
    });

    test('a current verifier still works, so offline login is not broken',
        () async {
      db.execute('UPDATE users SET updated_at = ? WHERE id = ?', [1, 'u1']);
      await credentials.cacheForOffline('u1', 'a.doctor', 'password');

      expect(await credentials.verifyCached('a.doctor', 'password'), isNotNull);
      expect(await credentials.verifyCached('a.doctor', 'wrong'), isNull);
    });
  });

  group('the hub authorises writes, not just connections', () {
    late AppDatabase hubDb;
    late AppDatabase terminalDb;
    late HubServer server;
    late HubClient client;
    late SettingsService hubSettings;
    late SettingsService terminalSettings;
    late CredentialStore hubCredentials;
    late StaffRepository hubStaff;
    late Staff admin;
    late Staff provider;

    const clinicKey = 'ABCDE-FGHJK-LMNPQ-RSTUV';
    // A high port, kept out of the way of a real install's default.
    const port = 7399;

    setUp(() async {
      hubDb = AppDatabase.openInMemory();
      hubSettings = SettingsService(hubDb)
        ..clinicName = 'Test Clinic'
        ..mode = DeploymentMode.hub
        ..clinicKey = clinicKey
        ..listenPort = port;
      hubCredentials = CredentialStore(hubDb);
      final hubAudit = AuditRepository(hubDb);
      hubStaff = StaffRepository(hubDb, hubAudit);

      admin = hubStaff.create(
        username: 'the.admin',
        fullName: 'The Administrator',
        role: UserRole.admin,
      );
      provider = hubStaff.create(
        username: 'a.provider',
        fullName: 'A Provider',
        role: UserRole.provider,
      );
      await hubCredentials.setPassword(admin.id, 'admin-password');
      await hubCredentials.setPassword(provider.id, 'provider-password');

      server = HubServer(
        db: hubDb,
        settings: hubSettings,
        credentials: hubCredentials,
      );
      await server.start();

      terminalDb = AppDatabase.openInMemory();
      terminalSettings = SettingsService(terminalDb)
        ..mode = DeploymentMode.terminal
        ..hubHost = '127.0.0.1'
        ..hubPort = port
        ..clinicKey = clinicKey;
      client = HubClient(db: terminalDb, settings: terminalSettings);
    });

    tearDown(() async {
      client.dispose();
      await server.stop();
      hubDb.close();
      terminalDb.close();
    });

    test('a terminal can reach the hub and sign in', () async {
      // Nothing previously proved these two halves talk to each other at all.
      final hello = await client.hello();
      expect(hello.hubName, 'Test Clinic');

      final session = await client.login('a.provider', 'provider-password');
      expect(session.token, isNotEmpty);
      expect(Staff.fromRow(session.user).role, UserRole.provider);
    });

    test('the wrong password is refused', () async {
      expect(
        () => client.login('a.provider', 'not-the-password'),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('a provider cannot promote themselves by pushing a staff row',
        () async {
      final session = await client.login('a.provider', 'provider-password');

      terminalDb.upsert('users', {
        ...provider.toRow(),
        'role': 'admin',
      });
      final outcome = await client.sync(token: session.token);

      expect(outcome.ok, isTrue);
      expect(
        hubStaff.byId(provider.id)!.role,
        UserRole.provider,
        reason: 'a provider escalated to administrator over the sync API',
      );
    });

    test('an administrator may still manage staff over sync', () async {
      final session = await client.login('the.admin', 'admin-password');

      terminalDb.upsert('users', {
        ...provider.toRow(),
        'full_name': 'A Renamed Provider',
      });
      await client.sync(token: session.token);

      expect(hubStaff.byId(provider.id)!.fullName, 'A Renamed Provider');
    });

    test('an existing audit entry cannot be tombstoned', () async {
      final session = await client.login('the.admin', 'admin-password');
      final entry = hubDb.query(
        'SELECT * FROM audit_log ORDER BY at LIMIT 1',
      ).single;
      final before = hubDb.count('audit_log', where: 'deleted = 0');

      terminalDb.applyRemote('audit_log', {...entry, 'dirty': 1});
      terminalDb.execute(
        'UPDATE audit_log SET deleted = 1, dirty = 1, updated_at = ? WHERE id = ?',
        [DateTime.now().millisecondsSinceEpoch + 60000, entry['id']],
      );
      await client.sync(token: session.token);

      expect(hubDb.count('audit_log', where: 'deleted = 0'), before);
    });

    test('ordinary clinical data still syncs', () async {
      final session = await client.login('a.provider', 'provider-password');

      terminalDb.upsert('patients', {
        'id': newId(),
        'code': 'P-0001',
        'name': 'Asha Devi',
        'sex': 'female',
        'registered_at': DateTime.now().millisecondsSinceEpoch,
      });
      final outcome = await client.sync(token: session.token);

      expect(outcome.ok, isTrue, reason: outcome.error ?? '');
      expect(hubDb.count('patients', where: 'deleted = 0'), 1);
    });

    test('a peer with the wrong clinic key is refused', () async {
      final stranger = HubClient(
        db: terminalDb,
        settings: SettingsService(terminalDb)
          ..mode = DeploymentMode.terminal
          ..hubHost = '127.0.0.1'
          ..hubPort = port
          ..clinicKey = '99999-88888-77777-66666',
      );
      addTearDown(stranger.dispose);

      expect(
        () => stranger.hello(),
        throwsA(isA<SyncProtocolException>()),
      );
    });
  });
}
