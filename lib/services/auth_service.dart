import '../core/constants.dart';
import '../data/db/app_database.dart';
import '../data/models/models.dart';
import '../data/repos/repositories.dart';
import 'credential_store.dart';
import 'settings_service.dart';
import 'sync/hub_client.dart';
import 'sync/protocol.dart';

/// Why a sign-in succeeded, which the shell surfaces so staff know whether
/// their work is currently reaching the rest of the clinic.
enum AuthChannel {
  /// Verified against this machine's own authoritative store.
  local,

  /// Verified by the hub over the network.
  hub,

  /// Verified against the offline cache because the hub was unreachable.
  cached,
}

class AuthResult {
  const AuthResult.success(this.staff, this.channel, {this.token, this.notice})
      : error = null;
  const AuthResult.failure(this.error)
      : staff = null,
        channel = null,
        token = null,
        notice = null;

  final Staff? staff;
  final AuthChannel? channel;
  final String? token;

  /// Non-fatal message worth showing, e.g. that the hub was unreachable.
  final String? notice;
  final String? error;

  bool get ok => staff != null;
}

/// Sign-in, in whichever way this install is deployed.
///
/// A hub verifies locally. A terminal asks the hub, and only falls back to its
/// own cache if the hub cannot be reached — which keeps the authoritative
/// answer in one place while still letting a terminal work through a network
/// outage.
class AuthService {
  AuthService({
    required AppDatabase db,
    required SettingsService settings,
    required CredentialStore credentials,
    required StaffRepository staffRepo,
    required AuditRepository audit,
    HubClient? client,
  })  : _db = db,
        _settings = settings,
        _credentials = credentials,
        _staff = staffRepo,
        _audit = audit,
        _client = client ?? HubClient(db: db, settings: settings);

  final AppDatabase _db;
  final SettingsService _settings;
  final CredentialStore _credentials;
  final StaffRepository _staff;
  final AuditRepository _audit;
  final HubClient _client;

  Staff? _current;
  String? _token;
  AuthChannel? _channel;

  Staff? get currentUser => _current;
  String? get sessionToken => _token;
  AuthChannel? get channel => _channel;
  bool get isSignedIn => _current != null;

  /// True when this session is running on cached credentials and its work has
  /// not yet reached the hub.
  bool get isOffline => _channel == AuthChannel.cached;

  Future<AuthResult> signIn(String username, String password) async {
    final result = switch (_settings.mode) {
      DeploymentMode.terminal => await _signInViaHub(username, password),
      _ => await _signInLocally(username, password),
    };
    if (result.ok) {
      _current = result.staff;
      _token = result.token;
      _channel = result.channel;
      _audit.log(
        action: 'auth.signin',
        entity: 'users',
        entityId: result.staff!.id,
        detail: switch (result.channel!) {
          AuthChannel.local => 'on this machine',
          AuthChannel.hub => 'via the clinic hub',
          AuthChannel.cached => 'offline, from the local cache',
        },
        by: result.staff,
      );
    }
    return result;
  }

  Future<AuthResult> _signInLocally(String username, String password) async {
    final staff = await _credentials.verifyLocal(username, password);
    if (staff == null) {
      return const AuthResult.failure('Incorrect username or password.');
    }
    return AuthResult.success(staff, AuthChannel.local);
  }

  Future<AuthResult> _signInViaHub(String username, String password) async {
    try {
      final session = await _client.login(username, password);
      final staff = Staff.fromRow(session.user);
      // Keep the local users row in step so the rest of the app can resolve
      // this person's name even before the next full sync. The hub's own
      // updated_at and node are carried across unchanged; inventing newer ones
      // here would make this copy win every future merge for that row.
      _db.applyRemote('users', {...session.user, 'dirty': 0});
      // Now that the hub has vouched for this password, this machine may
      // remember it well enough to answer the same question offline.
      await _credentials.cacheForOffline(staff.id, staff.username, password);
      return AuthResult.success(staff, AuthChannel.hub, token: session.token);
    } on SyncProtocolException catch (e) {
      // Only an unreachable hub justifies falling back to the cache. A hub
      // that answered and refused has given an answer, and this machine must
      // not overrule it with a copy of an older decision.
      if (e is! SyncTransportException) {
        return AuthResult.failure(e.message);
      }
      final cached = await _credentials.verifyCached(username, password);
      if (cached == null) {
        return AuthResult.failure(
          '${e.message}\n\nThis account has not signed in on this machine '
          'before, so it cannot be verified offline.',
        );
      }
      return AuthResult.success(
        cached,
        AuthChannel.cached,
        notice: 'Signed in offline — the clinic hub could not be reached. '
            'Changes will sync when it comes back.',
      );
    }
  }

  void signOut() {
    if (_current != null) {
      _audit.log(action: 'auth.signout', by: _current);
    }
    if (_token != null && _settings.mode != DeploymentMode.terminal) {
      _credentials.revokeSession(_token!);
    }
    _current = null;
    _token = null;
    _channel = null;
  }

  /// Sets a password, on whichever machine is authoritative for it.
  Future<String?> setPassword(String userId, String newPassword) async {
    if (newPassword.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    final actor = _current;
    if (actor == null) return 'You are not signed in.';
    if (userId != actor.id && !actor.isAdmin) {
      return 'Only an administrator can change another account\'s password.';
    }
    if (_settings.mode == DeploymentMode.terminal) {
      final token = _token;
      if (token == null) {
        return 'This terminal is signed in offline, so it cannot change a '
            'password until it can reach the hub.';
      }
      try {
        await _client.setPassword(
          token: token,
          userId: userId,
          newPassword: newPassword,
        );
      } on SyncProtocolException catch (e) {
        return e.message;
      }
      // The hub has accepted the change, so any verifier this machine holds
      // for that account is now the old password. Re-cache it when the person
      // changed their own, so they can still work offline; otherwise forget it
      // rather than leave a retired password working here.
      if (userId == actor.id) {
        await _credentials.cacheForOffline(userId, actor.username, newPassword);
      } else {
        _credentials.forgetOffline(userId);
      }
    } else {
      await _credentials.setPassword(userId, newPassword);
    }
    _audit.log(
      action: 'auth.password_change',
      entity: 'users',
      entityId: userId,
      detail: _staff.byId(userId)?.fullName,
      by: actor,
    );
    return null;
  }

  /// Creates the first administrator on a brand-new install.
  Future<Staff> createFirstAdmin({
    required String username,
    required String fullName,
    required String password,
  }) async {
    final staff = _staff.create(
      username: username,
      fullName: fullName,
      role: UserRole.admin,
    );
    await _credentials.setPassword(staff.id, password);
    return staff;
  }

  /// True when this machine has not been set up yet.
  ///
  /// A terminal is deliberately not measured by whether it holds accounts: it
  /// creates none of its own, and will have none until its first sync pulls
  /// the staff list down. It is ready as soon as it knows which hub to ask,
  /// so asking "does it have users?" would send it back to the setup wizard
  /// forever and it could never reach the sign-in screen.
  bool get needsFirstRunSetup {
    if (_settings.mode == DeploymentMode.terminal) return !_settings.canSync;
    return _db.count('users', where: 'deleted = 0 AND active = 1') == 0;
  }
}
