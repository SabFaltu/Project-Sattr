import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../../core/ids.dart';
import 'schema.dart';

/// Thin wrapper around the on-disk SQLite database.
///
/// The whole application is deliberately single-file and embedded: a clinic
/// should be able to copy one `.db` to a USB stick and have its records.
/// Networked multi-terminal use is layered on top by the sync engine rather
/// than by requiring a database server.
class AppDatabase {
  AppDatabase._(this.db, this.file);

  final Database db;
  final File file;

  static const String _nodeKey = 'node_id';

  /// Opens (creating if needed) the database at [path].
  static AppDatabase open(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA busy_timeout = 5000');
    final instance = AppDatabase._(db, file);
    instance._migrate();
    return instance;
  }

  /// An in-memory database, used by the test suite.
  static AppDatabase openInMemory() {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON');
    final instance = AppDatabase._(db, File(':memory:'));
    instance._migrate();
    return instance;
  }

  void _migrate() {
    final current = db.select('PRAGMA user_version').first['user_version'] as int;
    if (current >= kSchemaVersion) {
      // Still run CREATE IF NOT EXISTS so a partially built file self-heals.
      for (final stmt in kCreateStatements) {
        db.execute(stmt);
      }
      return;
    }
    db.execute('BEGIN');
    try {
      for (final stmt in kCreateStatements) {
        db.execute(stmt);
      }
      db.execute('PRAGMA user_version = $kSchemaVersion');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ---- Settings ----------------------------------------------------------

  String? setting(String key) {
    final rows = db.select('SELECT value FROM app_settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) {
    db.execute(
      'INSERT INTO app_settings(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  void removeSetting(String key) =>
      db.execute('DELETE FROM app_settings WHERE key = ?', [key]);

  /// Stable identity of this install, minted on first run.
  ///
  /// Used as the `node` column on every row this machine writes and as the
  /// tie-breaker when two installs edit the same record in the same
  /// millisecond.
  String get nodeId {
    final existing = setting(_nodeKey);
    if (existing != null) return existing;
    final id = newId();
    setSetting(_nodeKey, id);
    return id;
  }

  // ---- Query helpers -----------------------------------------------------

  List<Map<String, Object?>> query(String sql, [List<Object?> args = const []]) =>
      db.select(sql, args).map((r) => Map<String, Object?>.from(r)).toList();

  Map<String, Object?>? queryOne(String sql, [List<Object?> args = const []]) {
    final rows = query(sql, args);
    return rows.isEmpty ? null : rows.first;
  }

  void execute(String sql, [List<Object?> args = const []]) =>
      db.execute(sql, args);

  int count(String table, {String where = '1=1', List<Object?> args = const []}) {
    final row = db.select('SELECT COUNT(*) AS c FROM $table WHERE $where', args);
    return (row.first['c'] as num).toInt();
  }

  /// Columns [table] actually has, read from the schema and cached.
  ///
  /// This is the allowlist that makes it safe to build an INSERT from the keys
  /// of a map. Anything not named here is dropped rather than reaching the
  /// statement text.
  Set<String> columnsOf(String table) =>
      _columns.putIfAbsent(table, () {
        if (!_safeIdentifier.hasMatch(table)) {
          throw ArgumentError('Unsafe table name: $table');
        }
        return db
            .select('PRAGMA table_info($table)')
            .map((r) => r['name'] as String)
            .toSet();
      });

  final Map<String, Set<String>> _columns = {};

  static final RegExp _safeIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Keeps only the entries of [values] that name a real column of [table].
  ///
  /// Column names cannot be bound as parameters, so they end up in the SQL
  /// text itself. Any map that came from outside this process — a sync payload
  /// from a peer, a restored backup file — must therefore be filtered against
  /// the schema before it gets anywhere near a statement, or a crafted key
  /// becomes arbitrary SQL.
  Map<String, Object?> _onlyRealColumns(
    String table,
    Map<String, Object?> values,
  ) {
    final allowed = columnsOf(table);
    return {
      for (final entry in values.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Runs [body] inside a transaction, rolling back on error.
  T transaction<T>(T Function() body) {
    db.execute('BEGIN');
    try {
      final result = body();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Inserts or replaces [values] into [table], stamping the sync columns.
  ///
  /// Callers pass business columns only; bookkeeping is applied here so no
  /// repository can forget it and quietly break replication.
  void upsert(String table, Map<String, Object?> values) {
    final row = <String, Object?>{
      ...values,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'node': nodeId,
      'dirty': 1,
      'deleted': values['deleted'] ?? 0,
    };
    _write(table, row, keyColumn: 'id');
  }

  /// Tombstones a row so the deletion replicates rather than resurrecting on
  /// the next pull.
  void softDelete(String table, String id) {
    db.execute(
      'UPDATE $table SET deleted = 1, updated_at = ?, node = ?, dirty = 1 '
      'WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, nodeId, id],
    );
  }

  /// Writes a row exactly as received from a peer, without re-stamping it.
  ///
  /// This is the only path that may set `dirty = 0`: the row is, by
  /// definition, already known to the hub.
  ///
  /// [keyColumn] names the primary key to resolve a conflict against. It is
  /// `id` for every replicated table, but the restore path also writes
  /// `user_credentials`, which is keyed on `user_id`.
  void applyRemote(
    String table,
    Map<String, Object?> row, {
    String keyColumn = 'id',
  }) =>
      _write(table, row, keyColumn: keyColumn);

  /// Builds and runs the upsert shared by [upsert] and [applyRemote].
  ///
  /// Values are bound; identifiers are filtered against the schema and then
  /// quoted. Both halves matter: the filter is what actually makes this safe,
  /// and the quoting is there so that a column which is also a SQL keyword
  /// cannot change the meaning of the statement.
  void _write(
    String table,
    Map<String, Object?> values, {
    required String keyColumn,
  }) {
    final row = _onlyRealColumns(table, values);
    if (!row.containsKey(keyColumn)) {
      throw ArgumentError(
        'Row for "$table" has no $keyColumn, or it was not a real column.',
      );
    }
    final cols = row.keys.toList();
    final placeholders = List.filled(cols.length, '?').join(', ');
    final updates = cols
        .where((c) => c != keyColumn)
        .map((c) => '"$c" = excluded."$c"')
        .join(', ');
    db.execute(
      'INSERT INTO $table (${cols.map((c) => '"$c"').join(', ')}) '
      'VALUES ($placeholders) '
      'ON CONFLICT("$keyColumn") DO UPDATE SET $updates',
      cols.map((c) => row[c]).toList(),
    );
  }

  String get path => file.path;

  /// Bytes the clinic record occupies on disk.
  ///
  /// SQLite in WAL mode spreads a database across three files, and the
  /// write-ahead log alone can be a large share of the total, so a size that
  /// only counted the main file would routinely understate what a backup has
  /// to carry.
  int get onDiskBytes {
    var total = 0;
    for (final suffix in const ['', '-wal', '-shm']) {
      final f = File('${file.path}$suffix');
      if (f.existsSync()) total += f.lengthSync();
    }
    return total;
  }

  void close() => db.close();
}
