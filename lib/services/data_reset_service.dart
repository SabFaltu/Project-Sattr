import '../data/db/app_database.dart';
import '../data/db/schema.dart';
import '../data/models/models.dart';
import '../data/repos/repositories.dart';
import 'settings_service.dart';

/// How much of the clinic record to clear.
enum ResetScope {
  /// Patients and everything hanging off them. The formulary, stock levels
  /// and staff accounts stay.
  patientRecords,

  /// Everything clinical, plus the formulary and its stock ledger. Staff
  /// accounts and their passwords are always kept, because removing them
  /// would lock the clinic out of its own installation.
  everythingButStaff;

  String get label => switch (this) {
        ResetScope.patientRecords => 'Patient records only',
        ResetScope.everythingButStaff => 'All clinic data',
      };

  String get description => switch (this) {
        ResetScope.patientRecords =>
          'Patients, consultations, symptom grids, prescriptions and '
              'appointments. The formulary, stock levels and staff accounts '
              'are kept.',
        ResetScope.everythingButStaff =>
          'Everything above, plus the formulary and its stock ledger. Staff '
              'accounts and passwords are kept so you can still sign in.',
      };

  /// Tables cleared, in an order that releases foreign keys first.
  List<String> get tables => switch (this) {
        ResetScope.patientRecords => const [
            'symptoms',
            'prescription_items',
            'prescriptions',
            'visits',
            'appointments',
            'patients',
          ],
        ResetScope.everythingButStaff => const [
            'symptoms',
            'prescription_items',
            'prescriptions',
            'visits',
            'appointments',
            'patients',
            'stock_movements',
            'medicines',
          ],
      };
}

/// Clearing out records — the demo data a clinic evaluated with, or a test
/// register typed in during training.
///
/// Deletions are tombstoned rather than dropped, so that on a networked clinic
/// the removal reaches the other terminals instead of them helpfully syncing
/// everything back. On a standalone install there is nobody to tell, so the
/// rows are removed outright and the file is compacted — which is what someone
/// clearing demo data before going live actually wants.
class DataResetService {
  DataResetService({
    required AppDatabase db,
    required SettingsService settings,
    required AuditRepository audit,
    required MedicineRepository medicines,
  })  : _db = db,
        _settings = settings,
        _audit = audit,
        _medicines = medicines;

  final AppDatabase _db;
  final SettingsService _settings;
  final AuditRepository _audit;
  final MedicineRepository _medicines;

  /// The phrase an administrator has to type to confirm. Deliberately not
  /// "yes": it should be impossible to do this by reflex.
  static const String confirmationPhrase = 'DELETE';

  /// Counts what each scope would remove, for the confirmation dialog.
  int countFor(ResetScope scope) => scope.tables.fold<int>(
        0,
        (sum, table) => sum + _db.count(table, where: 'deleted = 0'),
      );

  ResetOutcome reset(
    ResetScope scope, {
    Staff? by,
    bool restoreFormulary = true,
  }) {
    final removed = countFor(scope);
    final replicating = _settings.mode != DeploymentMode.standalone;

    _db.transaction(() {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final table in scope.tables) {
        if (replicating) {
          _db.execute(
            'UPDATE $table SET deleted = 1, updated_at = ?, node = ?, dirty = 1 '
            'WHERE deleted = 0',
            [now, _db.nodeId],
          );
        } else {
          _db.execute('DELETE FROM $table');
        }
      }
    });

    // The audit trail is the record of what was done, so it survives a
    // patient-records reset and is only cleared when wiping everything — and
    // even then the entry describing the wipe itself is written afterwards.
    if (scope == ResetScope.everythingButStaff && !replicating) {
      _db.execute('DELETE FROM audit_log');
    }

    if (scope == ResetScope.everythingButStaff && restoreFormulary) {
      _medicines.seedFormulary();
    }

    if (!replicating) {
      // Reclaim the space, so the storage figure reflects reality.
      _db.execute('VACUUM');
    }

    _audit.log(
      action: 'data.reset',
      detail: '${scope.label} — $removed record(s) removed',
      by: by,
    );

    return ResetOutcome(
      removed: removed,
      tombstoned: replicating,
      formularyRestored:
          scope == ResetScope.everythingButStaff && restoreFormulary,
    );
  }

  /// Sanity check used by the UI before enabling the button.
  bool get hasAnythingToDelete =>
      kSyncedTables.any((t) => _db.count(t, where: 'deleted = 0') > 0);
}

class ResetOutcome {
  const ResetOutcome({
    required this.removed,
    required this.tombstoned,
    required this.formularyRestored,
  });

  final int removed;

  /// True when the rows were marked deleted so the removal can reach the rest
  /// of the clinic, rather than being dropped outright.
  final bool tombstoned;
  final bool formularyRestored;

  String get summary {
    final base = '$removed record(s) removed';
    final how = tombstoned
        ? ', and the deletion will be sent to the other terminals on the next '
            'sync'
        : ' and the database file compacted';
    final extra = formularyRestored ? '. The standard formulary was restored' : '';
    return '$base$how$extra.';
  }
}
