import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../core/ids.dart';
import '../data/db/app_database.dart';
import '../data/db/schema.dart';
import 'crypto_service.dart';
import 'settings_service.dart';

/// Encrypted, self-contained clinic backups.
///
/// A backup is a single file an administrator can put on a USB stick or a
/// network share. It is encrypted with a passphrase the administrator chooses,
/// because the thing being carried out of the building is the entire patient
/// record.
///
/// Unlike the sync protocol, a backup *does* include the credential tables:
/// its purpose is to be able to rebuild the hub, and a hub that cannot log
/// anyone in has not been restored.
class BackupService {
  BackupService({required AppDatabase db, required SettingsService settings})
      : _db = db,
        _settings = settings;

  final AppDatabase _db;
  final SettingsService _settings;

  static const String format = 'sattra-backup';
  static const int version = 1;
  static const String fileExtension = 'sattrabak';

  /// Tables written to a backup: everything replicated, plus the credentials
  /// that make a restored hub usable.
  static const List<String> backedUpTables = [
    ...kSyncedTables,
    'user_credentials',
  ];

  /// Primary key of each backed-up table. Everything replicated is keyed on
  /// `id`; the credential table is keyed on the account it belongs to.
  static String keyColumnFor(String table) =>
      table == 'user_credentials' ? 'user_id' : 'id';

  String suggestedFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}';
    final clinic = _settings.clinicName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$clinic-$stamp.$fileExtension';
  }

  /// Serialises and encrypts the whole clinic record.
  Future<File> export(String path, String passphrase) async {
    if (passphrase.length < 8) {
      throw const BackupException(
        'Choose a backup passphrase of at least 8 characters. '
        'It is the only thing protecting this file.',
      );
    }
    final tables = <String, List<Map<String, Object?>>>{
      for (final table in backedUpTables)
        table: _db.query('SELECT * FROM $table'),
    };
    final payload = jsonEncode({
      'tables': tables,
      'clinic': _settings.clinicName,
      'schema': kSchemaVersion,
      'node': _db.nodeId,
    });

    final salt = CryptoService.newSalt(24);
    final key = await _keyFromPassphrase(passphrase, salt);
    final sealed = await CryptoService.seal(key, payload);

    final envelope = jsonEncode({
      'format': format,
      'v': version,
      'created': DateTime.now().millisecondsSinceEpoch,
      'clinic': _settings.clinicName,
      'schema': kSchemaVersion,
      'counts': {
        for (final e in tables.entries) e.key: e.value.length,
      },
      'salt': salt,
      'nonce': sealed.nonce,
      'ct': sealed.ciphertext,
      'mac': sealed.mac,
    });

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(envelope);
    return file;
  }

  /// Reads a backup's unencrypted header, so the restore screen can show what
  /// the file is before asking for the passphrase.
  Future<BackupInfo> inspect(String path) async {
    final raw = await File(path).readAsString();
    final Map<String, Object?> envelope;
    try {
      envelope = (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      throw const BackupException('That file is not a Sattra backup.');
    }
    if (envelope['format'] != format) {
      throw const BackupException('That file is not a Sattra backup.');
    }
    if (envelope['v'] != version) {
      throw BackupException(
        'This backup was written by a different version of Sattra '
        '(format ${envelope['v']}, expected $version).',
      );
    }
    final counts = (envelope['counts'] as Map?)?.cast<String, Object?>() ?? {};
    return BackupInfo(
      clinic: envelope['clinic'] as String? ?? 'Unknown clinic',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (envelope['created'] as num?)?.toInt() ?? 0,
      ),
      rowCounts: {
        for (final e in counts.entries) e.key: (e.value as num).toInt(),
      },
    );
  }

  /// Replaces the contents of this install with the backup's.
  ///
  /// Destructive by design and done in one transaction: a half-restored
  /// clinic record would be worse than either the old one or the new one.
  Future<BackupInfo> restore(String path, String passphrase) async {
    final info = await inspect(path);
    final envelope =
        (jsonDecode(await File(path).readAsString()) as Map)
            .cast<String, Object?>();

    final key = await _keyFromPassphrase(
      passphrase,
      envelope['salt'] as String,
    );
    final String clear;
    try {
      clear = await CryptoService.open(
        key,
        nonce: envelope['nonce'] as String,
        ciphertext: envelope['ct'] as String,
        mac: envelope['mac'] as String,
      );
    } catch (_) {
      throw const BackupException(
        'That passphrase does not open this backup.',
      );
    }

    final decoded = (jsonDecode(clear) as Map).cast<String, Object?>();
    final tables = (decoded['tables'] as Map).cast<String, Object?>();

    _db.transaction(() {
      // Reverse order on the way out so foreign keys are released before the
      // rows they point at.
      for (final table in backedUpTables.reversed) {
        _db.execute('DELETE FROM $table');
      }
      for (final table in backedUpTables) {
        final rows = tables[table];
        if (rows is! List) continue;
        for (final row in rows) {
          _db.applyRemote(
            table,
            (row as Map).cast<String, Object?>(),
            keyColumn: keyColumnFor(table),
          );
        }
      }
      // The restored copy has not been offered to any hub, so everything is
      // owed again, and our old watermarks describe a database that no longer
      // exists.
      for (final table in kSyncedTables) {
        _db.execute('UPDATE $table SET dirty = 1');
      }
    });
    _settings.resetWatermarks(kSyncedTables);
    if (info.clinic.isNotEmpty) _settings.clinicName = info.clinic;
    return info;
  }

  /// Straight file copy of the live database, for administrators who would
  /// rather keep a plain snapshot alongside the encrypted export.
  Future<File> copyDatabaseFile(String destinationPath) async {
    final source = File(_db.path);
    if (!await source.exists()) {
      throw const BackupException('The database file could not be found.');
    }
    // Fold the write-ahead log back in first, so the copy is complete rather
    // than missing the most recent transactions.
    _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    return source.copy(destinationPath);
  }

  Future<SecretKey> _keyFromPassphrase(String passphrase, String salt) async {
    final derived = await CryptoService.hashPassword(
      passphrase,
      salt,
      iterations: CryptoService.passwordIterations,
    );
    return SecretKey(base64Decode(derived));
  }

  /// Identifier used when naming an ad-hoc export path.
  static String scratchName() => 'sattra-${newId().substring(0, 8)}';
}

class BackupInfo {
  const BackupInfo({
    required this.clinic,
    required this.createdAt,
    required this.rowCounts,
  });

  final String clinic;
  final DateTime createdAt;
  final Map<String, int> rowCounts;

  int get patients => rowCounts['patients'] ?? 0;
  int get totalRows =>
      rowCounts.values.fold<int>(0, (sum, v) => sum + v);
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
