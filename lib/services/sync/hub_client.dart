import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/db/app_database.dart';
import '../../data/db/schema.dart';
import '../crypto_service.dart';
import '../settings_service.dart';
import 'merge.dart';
import 'protocol.dart';

/// The terminal side of the sync conversation.
///
/// Every call seals its request with the clinic key and refuses to parse a
/// reply that does not authenticate, so a machine impersonating the hub cannot
/// feed a terminal fabricated patient records.
class HubClient {
  HubClient({
    required AppDatabase db,
    required SettingsService settings,
    http.Client? httpClient,
  })  : _db = db,
        _settings = settings,
        _http = httpClient ?? http.Client();

  final AppDatabase _db;
  final SettingsService _settings;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 20);

  Future<Map<String, Object?>> _call(
    String path,
    Map<String, Object?> payload, {
    String? host,
    int? port,
    String? clinicKey,
  }) async {
    final useKey = clinicKey ?? _settings.clinicKey;
    if (useKey == null) {
      throw const SyncProtocolException('No clinic key is configured.');
    }
    final uri = Uri.parse(
      'http://${host ?? _settings.hubHost}:${port ?? _settings.hubPort}$path',
    );
    final key = await CryptoService.channelKey(useKey);
    final body = await SyncProtocol.pack(key, {
      ...payload,
      'node': _db.nodeId,
    });

    final http.Response response;
    try {
      response = await _http
          .post(uri,
              body: body, headers: {'content-type': 'application/json'})
          .timeout(_timeout);
    } on TimeoutException {
      throw const SyncTransportException(
        'The hub did not answer in time. Check that it is switched on and on '
        'the same network.',
      );
    } on SocketException catch (e) {
      throw SyncTransportException(
        'Could not reach the hub at ${uri.host}:${uri.port} (${e.osError?.message ?? 'no route'}).',
      );
    }

    if (response.statusCode != 200) {
      String message = 'Hub returned ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is String) {
          message = decoded['error'] as String;
        }
      } catch (_) {
        // Body was not the JSON error shape; the status line is all we have.
      }
      // A 5xx is the hub failing rather than refusing, so it is transport.
      throw response.statusCode >= 500
          ? SyncTransportException(message)
          : SyncProtocolException(message);
    }
    return SyncProtocol.unpack(key, response.body);
  }

  /// Checks reachability and key agreement without changing anything.
  Future<({String hubName, String node})> hello({
    String? host,
    int? port,
    String? clinicKey,
  }) async {
    final r = await _call('/api/hello', const {},
        host: host, port: port, clinicKey: clinicKey);
    return (
      hubName: r['hub'] as String? ?? 'Sattra hub',
      node: r['node'] as String? ?? '',
    );
  }

  /// Authenticates against the hub. The password leaves this machine only
  /// inside the sealed envelope, and only ever to the hub.
  Future<({String token, Map<String, Object?> user})> login(
    String username,
    String password,
  ) async {
    final r = await _call('/api/login', {
      'username': username,
      'password': password,
    });
    if (r['ok'] != true) {
      throw SyncProtocolException(
        r['error'] as String? ?? 'Sign-in was refused',
      );
    }
    return (
      token: r['token'] as String,
      user: (r['user'] as Map).cast<String, Object?>(),
    );
  }

  Future<void> setPassword({
    required String token,
    required String userId,
    required String newPassword,
  }) async {
    final r = await _call('/api/set-password', {
      'token': token,
      'userId': userId,
      'newPassword': newPassword,
    });
    if (r['ok'] != true) {
      throw SyncProtocolException(
        r['error'] as String? ?? 'The hub refused the password change',
      );
    }
  }

  /// One full exchange: offer local work, then take everything new.
  ///
  /// Push happens first so that a record created here is on the hub before we
  /// ask for the hub's view; otherwise a slow terminal could pull a stale
  /// version of a row it had just edited and lose the edit to the merge.
  Future<SyncOutcome> sync({required String token}) async {
    try {
      final pushed = await _pushLocalChanges(token);
      final pulled = await _pullRemoteChanges(token);
      final now = DateTime.now();
      _settings.lastSyncAt = now;
      return SyncOutcome(pushed: pushed, pulled: pulled, at: now);
    } on SyncProtocolException catch (e) {
      return SyncOutcome.failed(e.message);
    } catch (e) {
      return SyncOutcome.failed('$e');
    }
  }

  Future<int> _pushLocalChanges(String token) async {
    final changes = <String, List<Map<String, Object?>>>{};
    final idsByTable = <String, List<String>>{};
    for (final table in kSyncedTables) {
      final rows = SyncMerge.collect(_db, table, since: 0, onlyDirty: true);
      if (rows.isEmpty) continue;
      changes[table] = rows;
      idsByTable[table] =
          rows.map((r) => r['id']).whereType<String>().toList();
    }
    if (changes.isEmpty) return 0;

    final r = await _call('/api/push', {'token': token, 'changes': changes});
    if (r['ok'] != true) {
      throw SyncProtocolException(r['error'] as String? ?? 'Push refused');
    }
    // The hub has the rows now, even where its copy won the merge, so nothing
    // here is still owed.
    idsByTable.forEach((table, ids) => SyncMerge.markSynced(_db, table, ids));
    return changes.values.fold<int>(0, (sum, rows) => sum + rows.length);
  }

  Future<int> _pullRemoteChanges(String token) async {
    final since = {
      for (final table in kSyncedTables) table: _settings.watermark(table),
    };
    final r = await _call('/api/pull', {'token': token, 'since': since});
    if (r['ok'] != true) {
      throw SyncProtocolException(r['error'] as String? ?? 'Pull refused');
    }
    final changes = (r['changes'] as Map?)?.cast<String, Object?>() ?? {};
    var total = 0;
    for (final table in kSyncedTables) {
      final raw = changes[table];
      if (raw is! List || raw.isEmpty) continue;
      final rows =
          raw.map((e) => (e as Map).cast<String, Object?>()).toList();
      total += SyncMerge.apply(_db, table, rows);
      // Advance on what was received rather than on what was applied: rows we
      // rejected as older are still accounted for, so they are not re-sent
      // forever.
      final mark = SyncMerge.highWatermark(rows);
      if (mark > _settings.watermark(table)) {
        _settings.setWatermark(table, mark);
      }
    }
    return total;
  }

  void dispose() => _http.close();
}
