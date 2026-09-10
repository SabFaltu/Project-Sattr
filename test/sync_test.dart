import 'package:flutter_test/flutter_test.dart';
import 'package:sattra/data/db/app_database.dart';
import 'package:sattra/services/sync/merge.dart';

void main() {
  late AppDatabase local;

  setUp(() => local = AppDatabase.openInMemory());
  tearDown(() => local.close());

  Map<String, Object?> remoteRow({
    required String id,
    required String name,
    required int updatedAt,
    String node = 'zzz-remote',
    int deleted = 0,
  }) =>
      {
        'id': id,
        'code': 'P-0001',
        'name': name,
        'age': 30,
        'sex': 'female',
        'weight_kg': 55.0,
        'address': null,
        'phone': null,
        'chief_complaints': null,
        'notes': null,
        'assigned_to': null,
        'registered_at': 1000,
        'updated_at': updatedAt,
        'deleted': deleted,
        'node': node,
      };

  group('merge', () {
    test('applies a row that does not exist locally', () {
      final applied = SyncMerge.apply(local, 'patients', [
        remoteRow(id: 'a', name: 'Asha', updatedAt: 2000),
      ]);

      expect(applied, 1);
      final row = local.queryOne('SELECT * FROM patients WHERE id = ?', ['a']);
      expect(row!['name'], 'Asha');
      // Rows the hub sent are, by definition, already known to it.
      expect(row['dirty'], 0);
    });

    test('a newer incoming row wins', () {
      SyncMerge.apply(local, 'patients', [
        remoteRow(id: 'a', name: 'Asha', updatedAt: 2000),
      ]);
      SyncMerge.apply(local, 'patients', [
        remoteRow(id: 'a', name: 'Asha Devi', updatedAt: 3000),
      ]);

      final row = local.queryOne('SELECT name FROM patients WHERE id = ?', ['a']);
      expect(row!['name'], 'Asha Devi');
    });

    test('an older incoming row is discarded', () {
      SyncMerge.apply(local, 'patients', [
        remoteRow(id: 'a', name: 'Current', updatedAt: 5000),
      ]);
      final applied = SyncMerge.apply(local, 'patients', [
        remoteRow(id: 'a', name: 'Stale', updatedAt: 4000),
      ]);

      expect(applied, 0);
      final row = local.queryOne('SELECT name FROM patients WHERE id = ?', ['a']);
      expect(row!['name'], 'Current');
    });

    test('a same-millisecond tie is broken on node id, both ways round', () {
      // Two installs resolving the same conflict independently must reach the
      // same answer without consulting each other.
      final higher = remoteRow(
        id: 'a',
        name: 'From zzz',
        updatedAt: 7000,
        node: 'zzz',
      );
      final lower = remoteRow(
        id: 'a',
        name: 'From aaa',
        updatedAt: 7000,
        node: 'aaa',
      );

      expect(SyncMerge.wins(higher, lower), isTrue);
      expect(SyncMerge.wins(lower, higher), isFalse);
    });

    test('a deletion replicates instead of the row reappearing', () {
      SyncMerge.apply(local, 'patients', [
        remoteRow(id: 'a', name: 'Asha', updatedAt: 2000),
      ]);
      SyncMerge.apply(local, 'patients', [
        remoteRow(id: 'a', name: 'Asha', updatedAt: 3000, deleted: 1),
      ]);

      final row = local.queryOne('SELECT deleted FROM patients WHERE id = ?', ['a']);
      expect(row!['deleted'], 1);
    });

    test('refuses to write a table that is not replicated', () {
      // The credential tables are kept out of the replicated set, and a peer
      // must not be able to name one and have it written.
      expect(
        () => SyncMerge.apply(local, 'user_credentials', [
          {'user_id': 'x', 'hash': 'stolen'},
        ]),
        throwsArgumentError,
      );
    });
  });

  group('collect', () {
    test('offers only unacknowledged local work when pushing', () {
      local.upsert('patients', {
        'id': 'mine',
        'code': 'P-0002',
        'name': 'Local edit',
        'registered_at': 1000,
      });
      SyncMerge.apply(local, 'patients', [
        remoteRow(id: 'theirs', name: 'From hub', updatedAt: 2000),
      ]);

      final outgoing =
          SyncMerge.collect(local, 'patients', since: 0, onlyDirty: true);

      expect(outgoing.map((r) => r['id']), ['mine']);
    });

    test('strips the local-only dirty flag from the wire format', () {
      local.upsert('patients', {
        'id': 'mine',
        'code': 'P-0002',
        'name': 'Local edit',
        'registered_at': 1000,
      });

      final outgoing =
          SyncMerge.collect(local, 'patients', since: 0, onlyDirty: true);

      expect(outgoing.single.containsKey('dirty'), isFalse);
      expect(outgoing.single.containsKey('updated_at'), isTrue);
    });

    test('markSynced clears the debt after the hub accepts', () {
      local.upsert('patients', {
        'id': 'mine',
        'code': 'P-0002',
        'name': 'Local edit',
        'registered_at': 1000,
      });

      SyncMerge.markSynced(local, 'patients', ['mine']);

      expect(
        SyncMerge.collect(local, 'patients', since: 0, onlyDirty: true),
        isEmpty,
      );
    });
  });
}
