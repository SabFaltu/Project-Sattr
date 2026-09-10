import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../data/db/app_database.dart';
import '../../data/db/schema.dart';
import '../../data/models/models.dart';
import '../credential_store.dart';
import '../crypto_service.dart';
import '../settings_service.dart';
import 'merge.dart';
import 'protocol.dart';

/// The listener a hub install runs for the rest of the clinic.
///
/// It answers four things and nothing else: who it is, a login, a pull, and a
/// push. There is no general query surface, so a terminal cannot ask the hub
/// for anything the sync protocol does not already replicate — notably, there
/// is no route that returns a password hash.
class HubServer {
  HubServer({
    required AppDatabase db,
    required SettingsService settings,
    required CredentialStore credentials,
  })  : _db = db,
        _settings = settings,
        _credentials = credentials;

  final AppDatabase _db;
  final SettingsService _settings;
  final CredentialStore _credentials;
  final ReplayGuard _replay = ReplayGuard();

  HttpServer? _server;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Peers that have successfully talked to this hub, for the status panel.
  final Map<String, DateTime> _peers = {};
  Map<String, DateTime> get peers => Map.unmodifiable(_peers);

  Future<void> start() async {
    if (_server != null) return;
    final key = _settings.clinicKey;
    if (key == null) {
      throw const SyncProtocolException(
        'Generate a clinic key before starting the hub.',
      );
    }
    final router = Router()
      ..post('/api/hello', _guard(_hello))
      ..post('/api/login', _guard(_login))
      ..post('/api/pull', _guard(_pull))
      ..post('/api/push', _guard(_push))
      ..post('/api/set-password', _guard(_setPassword));

    final handler =
        const Pipeline().addMiddleware(_logRequests()).addHandler(router.call);

    // Bound to anyIPv4 so other terminals on the clinic LAN can reach it. The
    // clinic key, not the network boundary, is what authorises a peer.
    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      _settings.listenPort,
      shared: true,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Middleware _logRequests() => (inner) => (request) async {
        try {
          return await inner(request);
        } on SyncProtocolException catch (e) {
          return Response(401, body: jsonEncode({'error': e.message}));
        } catch (e) {
          return Response.internalServerError(
            body: jsonEncode({'error': '$e'}),
          );
        }
      };

  /// Wraps a handler so it only ever sees a decrypted, fresh payload, and its
  /// reply is always sealed on the way out.
  ///
  /// Handlers below therefore never touch ciphertext, and no route can
  /// accidentally be published in the clear.
  Handler _guard(
    Future<Map<String, Object?>> Function(Map<String, Object?> payload) inner,
  ) {
    return (Request request) async {
      final key = await _key();
      final payload = await SyncProtocol.unpack(
        key,
        await request.readAsString(),
        seen: _replay,
      );
      final result = await inner(payload);
      return Response.ok(
        await SyncProtocol.pack(key, result),
        headers: {'content-type': 'application/json'},
      );
    };
  }

  Future<Map<String, Object?>> _hello(Map<String, Object?> payload) async {
    _notePeer(payload);
    return {
      'hub': _settings.clinicName,
      'node': _db.nodeId,
      'schema': kSchemaVersion,
      'serverTime': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<Map<String, Object?>> _login(Map<String, Object?> payload) async {
    final username = (payload['username'] as String? ?? '').trim();
    final password = payload['password'] as String? ?? '';
    final staff = await _credentials.verifyLocal(username, password);
    if (staff == null) {
      return {'ok': false, 'error': 'Incorrect username or password'};
    }
    // Return the stored row rather than a rebuilt one, so the terminal can
    // record this account with the hub's own updated_at and node. Fabricating
    // those locally would make the terminal's copy look newer than the hub's,
    // and a later deactivation or role change would then lose the merge and
    // never arrive.
    final stored = _db.queryOne('SELECT * FROM users WHERE id = ?', [staff.id]);
    return {
      'ok': true,
      'token': _credentials.issueSession(staff.id),
      'user': stored ?? staff.toRow(),
    };
  }

  Future<Map<String, Object?>> _pull(Map<String, Object?> payload) async {
    _requireSession(payload);
    final since = (payload['since'] as Map?)?.cast<String, Object?>() ?? {};
    final changes = <String, List<Map<String, Object?>>>{};
    for (final table in kSyncedTables) {
      final watermark = (since[table] as num?)?.toInt() ?? 0;
      final rows = SyncMerge.collect(_db, table, since: watermark);
      if (rows.isNotEmpty) changes[table] = rows;
    }
    _notePeer(payload);
    return {
      'ok': true,
      'changes': changes,
      'serverTime': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<Map<String, Object?>> _push(Map<String, Object?> payload) async {
    final actor = _requireSession(payload);
    final changes = (payload['changes'] as Map?)?.cast<String, Object?>() ?? {};
    var applied = 0;
    final rejected = <String>[];
    for (final entry in changes.entries) {
      if (!kSyncedTables.contains(entry.key)) {
        rejected.add(entry.key);
        continue;
      }
      final rows = (entry.value as List)
          .map((r) => (r as Map).cast<String, Object?>())
          .toList();
      final permitted = _permittedRows(actor, entry.key, rows, rejected);
      if (permitted.isEmpty) continue;
      applied += SyncMerge.apply(_db, entry.key, permitted);
    }
    _notePeer(payload);
    return {'ok': true, 'applied': applied, 'rejected': rejected};
  }

  /// Narrows a pushed batch to the rows [actor] is actually allowed to write.
  ///
  /// The clinic key decides which *machines* may talk to the hub; it says
  /// nothing about who is sitting at one. Per-user authorisation has to happen
  /// here, on the hub, because the merge engine is shared with the client and
  /// a client cannot be trusted to police itself.
  List<Map<String, Object?>> _permittedRows(
    Staff actor,
    String table,
    List<Map<String, Object?>> rows,
    List<String> rejected,
  ) {
    switch (table) {
      case 'users':
        // A staff row carries the role that authorisation itself reads back a
        // moment later, so accepting one from a provider would let them
        // promote themselves and then act as an administrator.
        if (!actor.isAdmin) {
          rejected.add('users (administrators only)');
          return const [];
        }
        return rows;

      case 'audit_log':
        // Append-only for everyone, administrators included. Adding an entry
        // is ordinary; editing or tombstoning one that already exists is how
        // a trail gets covered.
        final kept = <Map<String, Object?>>[];
        for (final row in rows) {
          final id = row['id'];
          final tombstone = ((row['deleted'] as num?)?.toInt() ?? 0) != 0;
          final exists = id is String &&
              _db.queryOne(
                    'SELECT 1 AS x FROM audit_log WHERE id = ?',
                    [id],
                  ) !=
                  null;
          if (tombstone || exists) {
            rejected.add('audit_log ${id ?? 'entry'} (append-only)');
            continue;
          }
          kept.add(row);
        }
        return kept;

      default:
        return rows;
    }
  }

  /// Password changes are a dedicated call rather than a replicated row.
  ///
  /// This is the only way a terminal can affect the hub's credential table,
  /// and it never carries a hash: the plaintext is stretched here, on the
  /// machine that owns the authoritative verifier.
  Future<Map<String, Object?>> _setPassword(Map<String, Object?> payload) async {
    // Re-read the session rather than reusing an earlier Staff object, so the
    // role checked here is the one in the database right now.
    final actor = _requireSession(payload);
    final userId = payload['userId'] as String? ?? actor.id;
    final newPassword = payload['newPassword'] as String? ?? '';
    if (newPassword.length < 6) {
      return {'ok': false, 'error': 'Password must be at least 6 characters'};
    }
    if (userId != actor.id && !actor.isAdmin) {
      return {
        'ok': false,
        'error': 'Only an administrator can change another account\'s password',
      };
    }
    await _credentials.setPassword(userId, newPassword);
    _credentials.revokeAllFor(userId);
    return {'ok': true};
  }

  Staff _requireSession(Map<String, Object?> payload) {
    final staff = _credentials.staffForSession(payload['token'] as String?);
    if (staff == null) {
      throw const SyncProtocolException('Session expired. Sign in again.');
    }
    return staff;
  }

  void _notePeer(Map<String, Object?> payload) {
    final node = payload['node'] as String?;
    if (node != null) _peers[node] = DateTime.now();
  }

  Future<SecretKey> _key() =>
      CryptoService.channelKey(_settings.clinicKey ?? '');
}
