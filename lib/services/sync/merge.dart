import '../../data/db/app_database.dart';
import '../../data/db/schema.dart';

/// Last-write-wins merge, shared by both ends of a sync.
///
/// The hub runs it on rows a client pushed; the client runs it on rows the hub
/// returned. Using one implementation for both directions means the two ends
/// cannot disagree about who won a conflict.
class SyncMerge {
  /// Columns that never travel. `dirty` is each install's private record of
  /// what it still owes its hub.
  static const Set<String> localOnlyColumns = {'dirty'};

  /// Reads local rows changed since [since] for [table].
  ///
  /// [onlyDirty] is what a client uses: it should offer the hub its own
  /// unacknowledged work, not echo back rows the hub just sent it.
  static List<Map<String, Object?>> collect(
    AppDatabase db,
    String table, {
    required int since,
    bool onlyDirty = false,
    int limit = 500,
  }) {
    final where = onlyDirty ? 'dirty = 1' : 'updated_at > ?';
    final args = onlyDirty ? const <Object?>[] : <Object?>[since];
    final rows = db.query(
      'SELECT * FROM $table WHERE $where ORDER BY updated_at ASC LIMIT $limit',
      args,
    );
    return rows.map(strip).toList();
  }

  static Map<String, Object?> strip(Map<String, Object?> row) {
    final copy = Map<String, Object?>.from(row);
    for (final c in localOnlyColumns) {
      copy.remove(c);
    }
    return copy;
  }

  /// Applies [rows] to [table], keeping whichever version is newer.
  ///
  /// Ties are broken on `node` so that two installs resolving the same
  /// conflict independently reach the same answer without talking to each
  /// other.
  static int apply(
    AppDatabase db,
    String table,
    List<Map<String, Object?>> rows, {
    bool markClean = true,
  }) {
    if (!kSyncedTables.contains(table)) {
      // Defence in depth: a peer must not be able to name `user_credentials`
      // and have it written.
      throw ArgumentError('Table "$table" is not replicated');
    }
    if (rows.isEmpty) return 0;

    var applied = 0;
    db.transaction(() {
      final existing = <String, Map<String, Object?>>{};
      final ids = rows.map((r) => r['id']).whereType<String>().toList();
      for (var i = 0; i < ids.length; i += 200) {
        final chunk = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
        final marks = List.filled(chunk.length, '?').join(',');
        for (final row in db.query(
          'SELECT id, updated_at, node FROM $table WHERE id IN ($marks)',
          chunk,
        )) {
          existing[row['id'] as String] = row;
        }
      }

      for (final incoming in rows) {
        final id = incoming['id'] as String?;
        if (id == null) continue;
        final local = existing[id];
        if (local != null && !wins(incoming, local)) continue;

        final row = strip(incoming);
        row['dirty'] = markClean ? 0 : 1;
        db.applyRemote(table, row);
        applied++;
      }
    });
    return applied;
  }

  /// True when [incoming] should overwrite [local].
  static bool wins(Map<String, Object?> incoming, Map<String, Object?> local) {
    final a = (incoming['updated_at'] as num?)?.toInt() ?? 0;
    final b = (local['updated_at'] as num?)?.toInt() ?? 0;
    if (a != b) return a > b;
    final an = (incoming['node'] as String?) ?? '';
    final bn = (local['node'] as String?) ?? '';
    return an.compareTo(bn) > 0;
  }

  /// Clears the dirty flag for rows the hub has confirmed.
  static void markSynced(AppDatabase db, String table, List<String> ids) {
    if (ids.isEmpty) return;
    db.transaction(() {
      for (var i = 0; i < ids.length; i += 200) {
        final chunk = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
        final marks = List.filled(chunk.length, '?').join(',');
        db.execute('UPDATE $table SET dirty = 0 WHERE id IN ($marks)', chunk);
      }
    });
  }

  /// Highest `updated_at` present in [table], used as the next pull watermark.
  static int highWatermark(List<Map<String, Object?>> rows) {
    var max = 0;
    for (final r in rows) {
      final v = (r['updated_at'] as num?)?.toInt() ?? 0;
      if (v > max) max = v;
    }
    return max;
  }
}
