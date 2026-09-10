import '../data/db/app_database.dart';
import '../data/models/models.dart';
import 'crypto_service.dart';

/// Password storage, split deliberately across two tables.
///
/// `user_credentials` is the authoritative set and exists only on a hub. It is
/// not in the replicated table list, so it physically cannot leave the machine
/// through a sync — which is the requirement that every terminal must be able
/// to log people in without every terminal holding every hash.
///
/// `local_credentials` is a per-machine cache holding a verifier for the
/// accounts that have actually signed in *here*. It is derived with its own
/// random salt, so it is not the hub's hash and cannot be replayed against the
/// hub; it only answers the question "has this person previously proved this
/// password on this machine?", which is what offline login needs.
class CredentialStore {
  CredentialStore(this._db);

  final AppDatabase _db;

  // ---- Authoritative store (hub) ----------------------------------------

  Future<void> setPassword(String userId, String password) async {
    final salt = CryptoService.newSalt();
    final hash = await CryptoService.hashPassword(password, salt);
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      'INSERT INTO user_credentials(user_id, algo, salt, iterations, hash, updated_at) '
      'VALUES(?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(user_id) DO UPDATE SET algo = excluded.algo, '
      'salt = excluded.salt, iterations = excluded.iterations, '
      'hash = excluded.hash, updated_at = excluded.updated_at',
      [
        userId,
        CryptoService.algo,
        salt,
        CryptoService.passwordIterations,
        hash,
        now,
      ],
    );
    // Touch the staff row. It is replicated, so bumping it is how a terminal
    // holding an offline verifier for this account finds out that the verifier
    // is now older than the account and must not be trusted.
    _db.execute(
      'UPDATE users SET updated_at = ?, node = ?, dirty = 1 WHERE id = ?',
      [now, _db.nodeId, userId],
    );
    // The old verifier on this machine is now wrong; a fresh one is written on
    // the next successful sign-in.
    forgetOffline(userId);
  }

  bool hasPassword(String userId) =>
      _db.queryOne(
        'SELECT 1 AS x FROM user_credentials WHERE user_id = ?',
        [userId],
      ) !=
      null;

  void removePassword(String userId) =>
      _db.execute('DELETE FROM user_credentials WHERE user_id = ?', [userId]);

  /// Verifies [password] for [username] against the authoritative store.
  Future<Staff?> verifyLocal(String username, String password) async {
    final row = _db.queryOne(
      'SELECT u.*, c.salt AS c_salt, c.hash AS c_hash, c.iterations AS c_iters '
      'FROM users u JOIN user_credentials c ON c.user_id = u.id '
      'WHERE u.username = ? AND u.deleted = 0 AND u.active = 1',
      [username.trim().toLowerCase()],
    );
    if (row == null) {
      // Spend comparable time on an unknown username so the response time does
      // not reveal which accounts exist.
      await CryptoService.hashPassword(password, CryptoService.newSalt());
      return null;
    }
    final ok = await CryptoService.verifyPassword(
      password,
      row['c_salt'] as String,
      row['c_hash'] as String,
      iterations: (row['c_iters'] as num).toInt(),
    );
    return ok ? Staff.fromRow(row) : null;
  }

  // ---- Offline cache (every machine) ------------------------------------

  /// Remembers that [password] was accepted for [userId] on this machine.
  Future<void> cacheForOffline(
    String userId,
    String username,
    String password,
  ) async {
    final salt = CryptoService.newSalt();
    final hash = await CryptoService.hashPassword(password, salt);
    _db.execute(
      'INSERT INTO local_credentials(user_id, username, algo, salt, iterations, hash, cached_at) '
      'VALUES(?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(user_id) DO UPDATE SET username = excluded.username, '
      'algo = excluded.algo, salt = excluded.salt, '
      'iterations = excluded.iterations, hash = excluded.hash, '
      'cached_at = excluded.cached_at',
      [
        userId,
        username.trim().toLowerCase(),
        CryptoService.algo,
        salt,
        CryptoService.passwordIterations,
        hash,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  /// How long a machine may keep answering for an account it has not been able
  /// to re-verify with the hub.
  ///
  /// Bounded because an offline verifier is a copy of a decision the hub made
  /// once, and a clinic that has been off the network for a month should be
  /// re-checking who still works there.
  static const Duration maxOfflineCacheAge = Duration(days: 30);

  /// Verifies against the offline cache, for use when the hub is unreachable.
  Future<Staff?> verifyCached(String username, String password) async {
    final row = _db.queryOne(
      'SELECT u.*, l.salt AS l_salt, l.hash AS l_hash, l.iterations AS l_iters, '
      'l.cached_at AS l_cached '
      'FROM users u JOIN local_credentials l ON l.user_id = u.id '
      'WHERE l.username = ? AND u.deleted = 0 AND u.active = 1',
      [username.trim().toLowerCase()],
    );
    if (row == null) return null;

    final cachedAt = (row['l_cached'] as num?)?.toInt() ?? 0;
    final staffUpdatedAt = (row['updated_at'] as num?)?.toInt() ?? 0;
    // The staff record has changed since this verifier was taken. That may
    // have been a password reset, and from here there is no way to tell, so
    // the safe reading is that this cached password is retired.
    if (cachedAt < staffUpdatedAt) return null;
    if (DateTime.now().millisecondsSinceEpoch - cachedAt >
        maxOfflineCacheAge.inMilliseconds) {
      return null;
    }
    final ok = await CryptoService.verifyPassword(
      password,
      row['l_salt'] as String,
      row['l_hash'] as String,
      iterations: (row['l_iters'] as num).toInt(),
    );
    return ok ? Staff.fromRow(row) : null;
  }

  /// Forgets the offline verifier for one account on this machine.
  void forgetOffline(String userId) =>
      _db.execute('DELETE FROM local_credentials WHERE user_id = ?', [userId]);

  /// Drops the offline cache. Used when a machine leaves the clinic network.
  void clearOfflineCache() => _db.execute('DELETE FROM local_credentials');

  int get cachedAccountCount =>
      _db.count('local_credentials');

  // ---- Sessions (hub) ----------------------------------------------------

  String issueSession(String userId, {Duration ttl = const Duration(hours: 12)}) {
    final token = CryptoService.newToken();
    final now = DateTime.now();
    _db.execute('DELETE FROM sessions WHERE expires_at < ?',
        [now.millisecondsSinceEpoch]);
    _db.execute(
      'INSERT INTO sessions(token, user_id, issued_at, expires_at) VALUES(?, ?, ?, ?)',
      [
        token,
        userId,
        now.millisecondsSinceEpoch,
        now.add(ttl).millisecondsSinceEpoch,
      ],
    );
    return token;
  }

  Staff? staffForSession(String? token) {
    if (token == null || token.isEmpty) return null;
    final row = _db.queryOne(
      'SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id '
      'WHERE s.token = ? AND s.expires_at > ? AND u.active = 1 AND u.deleted = 0',
      [token, DateTime.now().millisecondsSinceEpoch],
    );
    return row == null ? null : Staff.fromRow(row);
  }

  void revokeSession(String token) =>
      _db.execute('DELETE FROM sessions WHERE token = ?', [token]);

  void revokeAllFor(String userId) =>
      _db.execute('DELETE FROM sessions WHERE user_id = ?', [userId]);
}
