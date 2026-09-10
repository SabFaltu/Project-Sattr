import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/db/app_database.dart';
import '../data/db/schema.dart';
import '../data/models/models.dart';
import '../data/repos/repositories.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/app_config.dart';
import '../services/credential_store.dart';
import '../services/csv_service.dart';
import '../services/data_reset_service.dart';
import '../services/pdf_service.dart';
import '../services/settings_service.dart';
import '../services/sync/hub_client.dart';
import '../services/sync/hub_server.dart';
import '../services/sync/protocol.dart';

/// Single object the whole interface reads from.
///
/// Screens call into the repositories through here and then [touch] to
/// republish; with a local SQLite file the reads are cheap enough that a
/// coarse notification is simpler and less error-prone than per-list streams.
class AppState extends ChangeNotifier {
  AppState(this.db, {required this.config, required this.supportDir})
      : settings = SettingsService(db),
        _credentials = CredentialStore(db) {
    audit = AuditRepository(db);
    staff = StaffRepository(db, audit);
    patients = PatientRepository(db, audit);
    medicines = MedicineRepository(db, audit);
    prescriptions = PrescriptionRepository(db, audit, medicines);
    appointments = AppointmentRepository(db, audit);
    backups = BackupService(db: db, settings: settings);
    reset = DataResetService(
      db: db,
      settings: settings,
      audit: audit,
      medicines: medicines,
    );
    _client = HubClient(db: db, settings: settings);
    _hub = HubServer(db: db, settings: settings, credentials: _credentials);
    auth = AuthService(
      db: db,
      settings: settings,
      credentials: _credentials,
      staffRepo: staff,
      audit: audit,
      client: _client,
    );
  }

  final AppDatabase db;

  /// Settings that live outside the database, notably where the database is.
  final AppConfig config;

  /// Platform location used for the default database path.
  final String supportDir;

  final SettingsService settings;
  final CredentialStore _credentials;

  late final AuditRepository audit;
  late final StaffRepository staff;
  late final PatientRepository patients;
  late final MedicineRepository medicines;
  late final PrescriptionRepository prescriptions;
  late final AppointmentRepository appointments;
  late final BackupService backups;
  late final DataResetService reset;
  late final AuthService auth;
  late final HubClient _client;
  late final HubServer _hub;

  Timer? _autoSyncTimer;
  SyncOutcome? _lastSync;
  bool _syncing = false;
  String? _hubError;

  CredentialStore get credentials => _credentials;
  HubServer get hub => _hub;
  SyncOutcome? get lastSync => _lastSync;
  bool get isSyncing => _syncing;
  String? get hubError => _hubError;

  Staff? get currentUser => auth.currentUser;
  bool get isAdmin => auth.currentUser?.isAdmin ?? false;
  bool get isSignedIn => auth.isSignedIn;

  PdfService get pdf => PdfService(clinicName: settings.clinicName);

  /// Appearance preference, applied by the root widget.
  AppThemeMode get themeMode => settings.themeMode;

  void setThemeMode(AppThemeMode mode) {
    settings.themeMode = mode;
    notifyListeners();
  }

  /// Moves the clinic record to [directory] and remembers the new location.
  ///
  /// The move happens while the database is closed and is verified before the
  /// old copy is removed, because the failure mode here is losing the clinic's
  /// only set of records.
  Future<String> relocateDatabase(String directory) async {
    final destination = p.join(directory, 'sattra.db');
    if (p.equals(destination, db.path)) return destination;

    final target = File(destination);
    if (await target.exists()) {
      throw StateError(
        'There is already a sattra.db in that folder. Choose an empty folder, '
        'or move the existing file out of the way first.',
      );
    }

    // Fold the write-ahead log in so the single file we copy is complete.
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    final source = File(db.path);
    await target.parent.create(recursive: true);
    await source.copy(destination);

    if (await target.length() != await source.length()) {
      await target.delete();
      throw StateError('The copy did not complete; nothing was changed.');
    }

    await config.setDatabasePath(destination);
    notifyListeners();
    return destination;
  }

  /// Returns to the platform's default location on the next start.
  Future<void> useDefaultDatabaseLocation() async {
    await config.setDatabasePath(null);
    notifyListeners();
  }

  String get defaultDatabasePath => p.join(supportDir, 'sattra.db');

  CsvService get csv => CsvService(
        patients: patients,
        medicines: medicines,
        staff: staff,
      );

  /// What this machine is currently holding, for the storage panel.
  StorageSummary get storage => StorageSummary(
        bytes: db.onDiskBytes,
        counts: {
          'Patients': db.count('patients', where: 'deleted = 0'),
          'Consultations': db.count('visits', where: 'deleted = 0'),
          'Symptom readings': db.count('symptoms', where: 'deleted = 0'),
          'Prescriptions': db.count('prescriptions', where: 'deleted = 0'),
          'Medicines': db.count('medicines', where: 'deleted = 0'),
          'Stock movements': db.count('stock_movements', where: 'deleted = 0'),
          'Appointments': db.count('appointments', where: 'deleted = 0'),
          'Staff records': db.count('users', where: 'deleted = 0'),
          'Activity entries': db.count('audit_log', where: 'deleted = 0'),
        },
        pendingSync: kSyncedTables.fold<int>(
          0,
          (sum, table) => sum + db.count(table, where: 'dirty = 1'),
        ),
      );

  /// Prepares a fresh install: standing formulary, then whatever the
  /// deployment mode needs running.
  Future<void> bootstrap() async {
    if (!settings.isSeeded) {
      medicines.seedFormulary();
      settings.markSeeded();
    }
    await _applyDeployment();
  }

  Future<void> _applyDeployment() async {
    _hubError = null;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;

    switch (settings.mode) {
      case DeploymentMode.hub:
        try {
          await _hub.start();
        } on SyncProtocolException catch (e) {
          _hubError = e.message;
        } catch (e) {
          _hubError = 'Could not start the hub listener: $e';
        }
      case DeploymentMode.terminal:
        await _hub.stop();
        if (settings.autoSync) {
          _autoSyncTimer = Timer.periodic(
            const Duration(minutes: 2),
            (_) => syncNow(silent: true),
          );
        }
      case DeploymentMode.standalone:
        await _hub.stop();
    }
    notifyListeners();
  }

  /// Re-reads deployment settings and restarts the networking to match.
  Future<void> reconfigureNetworking() => _applyDeployment();

  /// Runs one exchange with the hub.
  ///
  /// [silent] is used by the background timer so a transient network blip does
  /// not repaint an error over whatever the user is doing.
  Future<SyncOutcome> syncNow({bool silent = false}) async {
    if (_syncing) {
      return const SyncOutcome.failed('A sync is already running.');
    }
    if (!settings.canSync) {
      return const SyncOutcome.failed(
        'This machine is not set up as a terminal, or has no hub address and '
        'clinic key yet.',
      );
    }
    final token = auth.sessionToken;
    if (token == null) {
      return const SyncOutcome.failed(
        'This session was signed in offline, so it has no hub credentials. '
        'Sign out and back in once the hub is reachable.',
      );
    }

    _syncing = true;
    notifyListeners();
    try {
      final outcome = await _client.sync(token: token);
      _lastSync = outcome;
      if (outcome.ok || !silent) notifyListeners();
      return outcome;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Checks a hub address and clinic key without committing to them.
  Future<({bool ok, String message})> testHub({
    required String host,
    required int port,
    required String clinicKey,
  }) async {
    try {
      final hello = await _client.hello(
        host: host,
        port: port,
        clinicKey: clinicKey,
      );
      return (ok: true, message: 'Reached "${hello.hubName}".');
    } on SyncProtocolException catch (e) {
      return (ok: false, message: e.message);
    } catch (e) {
      return (ok: false, message: '$e');
    }
  }

  Future<AuthResult> signIn(String username, String password) async {
    final result = await auth.signIn(username, password);
    if (result.ok) {
      notifyListeners();
      if (settings.canSync && result.channel == AuthChannel.hub) {
        // Pick up anything that changed while this terminal was away, without
        // making the user wait on the sign-in button.
        unawaited(syncNow(silent: true));
      }
    }
    return result;
  }

  void signOut() {
    auth.signOut();
    notifyListeners();
  }

  /// Republish after a write. Screens call this rather than each holding their
  /// own copy of the data.
  void touch() => notifyListeners();

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _client.dispose();
    _hub.stop();
    super.dispose();
  }
}


/// A snapshot of what this install is holding, shown in Settings.
class StorageSummary {
  const StorageSummary({
    required this.bytes,
    required this.counts,
    required this.pendingSync,
  });

  final int bytes;
  final Map<String, int> counts;

  /// Rows written here that a hub has not acknowledged yet.
  final int pendingSync;

  int get totalRows => counts.values.fold<int>(0, (sum, v) => sum + v);

  /// Human-readable size. Clinic databases stay small — text and dates — so
  /// this tops out at megabytes in practice.
  String get formattedSize {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
