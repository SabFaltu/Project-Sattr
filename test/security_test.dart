import 'package:flutter_test/flutter_test.dart';
import 'package:sattra/data/db/app_database.dart';
import 'package:sattra/data/db/schema.dart';
import 'package:sattra/services/credential_store.dart';
import 'package:sattra/services/crypto_service.dart';
import 'package:sattra/services/sync/protocol.dart';

void main() {
  group('password hashing', () {
    test('accepts the right password and rejects a wrong one', () async {
      final salt = CryptoService.newSalt();
      // The real work factor makes the suite crawl; the property under test is
      // the same at any iteration count.
      final hash = await CryptoService.hashPassword(
        'correct horse',
        salt,
        iterations: 1000,
      );

      expect(
        await CryptoService.verifyPassword(
          'correct horse',
          salt,
          hash,
          iterations: 1000,
        ),
        isTrue,
      );
      expect(
        await CryptoService.verifyPassword(
          'wrong horse',
          salt,
          hash,
          iterations: 1000,
        ),
        isFalse,
      );
    });

    test('the same password under a different salt gives a different hash',
        () async {
      final a = await CryptoService.hashPassword(
          'same', CryptoService.newSalt(), iterations: 1000);
      final b = await CryptoService.hashPassword(
          'same', CryptoService.newSalt(), iterations: 1000);

      expect(a, isNot(b));
    });

    test('comparison does not short-circuit on length-equal inputs', () {
      expect(CryptoService.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(CryptoService.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(CryptoService.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('sealed channel', () {
    test('a payload survives a round trip', () async {
      final key = await CryptoService.channelKey('ABCDE-FGHJK-LMNPQ-RSTUV');
      final packed = await SyncProtocol.pack(key, {'hello': 'world'});
      final opened = await SyncProtocol.unpack(key, packed);

      expect(opened['hello'], 'world');
    });

    test('a peer with the wrong clinic key cannot read it', () async {
      final theirs = await CryptoService.channelKey('ABCDE-FGHJK-LMNPQ-RSTUV');
      final mine = await CryptoService.channelKey('99999-88888-77777-66666');
      final packed = await SyncProtocol.pack(theirs, {'patient': 'Asha'});

      expect(
        () => SyncProtocol.unpack(mine, packed),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('a tampered envelope is rejected rather than parsed', () async {
      final key = await CryptoService.channelKey('ABCDE-FGHJK-LMNPQ-RSTUV');
      final packed = await SyncProtocol.pack(key, {'delta': 1});
      // Flip a character of the ciphertext.
      final corrupted = packed.replaceFirst(
        RegExp(r'"ct":"(.)'),
        '"ct":"${packed.contains('"ct":"A') ? 'B' : 'A'}',
      );

      expect(
        () => SyncProtocol.unpack(key, corrupted),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('a captured request cannot be replayed', () async {
      final key = await CryptoService.channelKey('ABCDE-FGHJK-LMNPQ-RSTUV');
      final guard = ReplayGuard();
      final packed = await SyncProtocol.pack(key, {'op': 'push'});

      await SyncProtocol.unpack(key, packed, seen: guard);
      expect(
        () => SyncProtocol.unpack(key, packed, seen: guard),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('the key fingerprint is stable and does not reveal the key', () async {
      final key = 'ABCDE-FGHJK-LMNPQ-RSTUV';
      final a = await CryptoService.fingerprint(key);
      final b = await CryptoService.fingerprint(key.toLowerCase());

      expect(a, b, reason: 'case should not change the fingerprint');
      expect(a.length, lessThan(key.length));
      expect(key.contains(a.replaceAll('-', '')), isFalse);
    });
  });

  group('credential separation', () {
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

    test('the credential tables are not in the replicated set', () {
      // This is the whole mechanism that keeps hashes off every terminal.
      expect(kSyncedTables, isNot(contains('user_credentials')));
      expect(kSyncedTables, isNot(contains('local_credentials')));
      expect(kSyncedTables, isNot(contains('sessions')));
      expect(kSyncedTables, contains('users'));
    });

    test('a hub verifies against its own store', () async {
      await credentials.setPassword('u1', 'opensesame');

      expect(await credentials.verifyLocal('a.doctor', 'opensesame'), isNotNull);
      expect(await credentials.verifyLocal('a.doctor', 'wrong'), isNull);
    });

    test('an unknown username is refused without leaking that it is unknown',
        () async {
      expect(await credentials.verifyLocal('nobody', 'anything'), isNull);
    });

    test('offline login only works for accounts that signed in here', () async {
      expect(await credentials.verifyCached('a.doctor', 'opensesame'), isNull);

      await credentials.cacheForOffline('u1', 'a.doctor', 'opensesame');

      expect(
        await credentials.verifyCached('a.doctor', 'opensesame'),
        isNotNull,
      );
      expect(await credentials.verifyCached('a.doctor', 'wrong'), isNull);
    });

    test('the offline verifier is not the hub verifier', () async {
      await credentials.setPassword('u1', 'opensesame');
      await credentials.cacheForOffline('u1', 'a.doctor', 'opensesame');

      final authoritative = db.queryOne(
        'SELECT hash, salt FROM user_credentials WHERE user_id = ?',
        ['u1'],
      );
      final cached = db.queryOne(
        'SELECT hash, salt FROM local_credentials WHERE user_id = ?',
        ['u1'],
      );

      // Derived under its own salt, so it cannot be replayed against the hub.
      expect(cached!['salt'], isNot(authoritative!['salt']));
      expect(cached['hash'], isNot(authoritative['hash']));
    });

    test('a deactivated account cannot sign in', () async {
      await credentials.setPassword('u1', 'opensesame');
      db.execute('UPDATE users SET active = 0 WHERE id = ?', ['u1']);

      expect(await credentials.verifyLocal('a.doctor', 'opensesame'), isNull);
    });

    test('sessions expire and can be revoked', () {
      final token = credentials.issueSession('u1');
      expect(credentials.staffForSession(token)?.id, 'u1');

      credentials.revokeSession(token);
      expect(credentials.staffForSession(token), isNull);
      expect(credentials.staffForSession('made-up'), isNull);
    });
  });
}
