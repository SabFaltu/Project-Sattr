import '../../core/constants.dart';
import '../../core/ids.dart';
import '../db/app_database.dart';
import '../models/models.dart';

/// Shared plumbing for the table repositories.
///
/// Reads always exclude tombstones, so callers never have to remember to.
abstract class _Repo {
  _Repo(this.db);
  final AppDatabase db;
}

/// Append-only activity trail.
///
/// Written by the other repositories rather than by the UI, so an action
/// cannot be recorded without the change it describes actually happening.
class AuditRepository extends _Repo {
  AuditRepository(super.db);

  void log({
    required String action,
    String? entity,
    String? entityId,
    String? detail,
    Staff? by,
  }) {
    db.upsert('audit_log', {
      'id': newId(),
      'at': DateTime.now().millisecondsSinceEpoch,
      'user_id': by?.id,
      'user_name': by?.fullName,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'detail': detail,
    });
  }

  List<AuditEntry> recent({int limit = 100}) => db
      .query(
        'SELECT * FROM audit_log WHERE deleted = 0 ORDER BY at DESC LIMIT ?',
        [limit],
      )
      .map(AuditEntry.fromRow)
      .toList();
}

class StaffRepository extends _Repo {
  StaffRepository(super.db, this._audit);
  final AuditRepository _audit;

  List<Staff> all({bool includeInactive = true}) => db
      .query(
        'SELECT * FROM users WHERE deleted = 0 '
        '${includeInactive ? '' : 'AND active = 1 '}'
        'ORDER BY active DESC, full_name COLLATE NOCASE',
      )
      .map(Staff.fromRow)
      .toList();

  Staff? byId(String? id) {
    if (id == null) return null;
    final row = db.queryOne('SELECT * FROM users WHERE id = ?', [id]);
    return row == null ? null : Staff.fromRow(row);
  }

  Staff? byUsername(String username) {
    final row = db.queryOne(
      'SELECT * FROM users WHERE username = ? AND deleted = 0',
      [username.trim().toLowerCase()],
    );
    return row == null ? null : Staff.fromRow(row);
  }

  bool usernameTaken(String username, {String? exceptId}) {
    final row = db.queryOne(
      'SELECT id FROM users WHERE username = ? AND deleted = 0',
      [username.trim().toLowerCase()],
    );
    return row != null && row['id'] != exceptId;
  }

  Staff create({
    required String username,
    required String fullName,
    required UserRole role,
    String? speciality,
    String? phone,
    String? email,
    Staff? by,
  }) {
    final staff = Staff(
      id: newId(),
      username: username.trim().toLowerCase(),
      fullName: fullName.trim(),
      role: role,
      speciality: speciality,
      phone: phone,
      email: email,
      createdBy: by?.id,
      createdAt: DateTime.now(),
    );
    db.upsert('users', staff.toRow());
    _audit.log(
      action: 'staff.create',
      entity: 'users',
      entityId: staff.id,
      detail: '${staff.fullName} (${staff.role.label})',
      by: by,
    );
    return staff;
  }

  void save(Staff staff, {Staff? by}) {
    db.upsert('users', staff.toRow());
    _audit.log(
      action: 'staff.update',
      entity: 'users',
      entityId: staff.id,
      detail: staff.fullName,
      by: by,
    );
  }

  /// Staff are deactivated rather than removed: their name still has to
  /// resolve on the records they signed.
  void deactivate(Staff staff, {Staff? by}) {
    db.upsert('users', staff.copyWith(active: false).toRow());
    _audit.log(
      action: 'staff.deactivate',
      entity: 'users',
      entityId: staff.id,
      detail: staff.fullName,
      by: by,
    );
  }

  int get adminCount => db.count(
        'users',
        where: "deleted = 0 AND active = 1 AND role = 'admin'",
      );
}

class PatientRepository extends _Repo {
  PatientRepository(super.db, this._audit);
  final AuditRepository _audit;

  List<Patient> search({String query = '', String? assignedTo}) {
    final where = StringBuffer('deleted = 0');
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.write(' AND (name LIKE ? OR code LIKE ? OR phone LIKE ?)');
      final like = '%${query.trim()}%';
      args.addAll([like, like, like]);
    }
    if (assignedTo != null) {
      where.write(' AND assigned_to = ?');
      args.add(assignedTo);
    }
    return db
        .query(
          'SELECT * FROM patients WHERE $where ORDER BY name COLLATE NOCASE',
          args,
        )
        .map(Patient.fromRow)
        .toList();
  }

  Patient? byId(String? id) {
    if (id == null) return null;
    final row = db.queryOne('SELECT * FROM patients WHERE id = ?', [id]);
    return row == null ? null : Patient.fromRow(row);
  }

  /// Next free record number.
  ///
  /// Derived from the highest existing code rather than a counter so that two
  /// terminals that both registered patients offline do not collide on the
  /// same number after they sync.
  String nextCode() {
    final row = db.queryOne(
      "SELECT code FROM patients WHERE code LIKE 'P-%' "
      'ORDER BY CAST(SUBSTR(code, 3) AS INTEGER) DESC LIMIT 1',
    );
    final last = row == null
        ? 0
        : int.tryParse((row['code'] as String).substring(2)) ?? 0;
    return 'P-${(last + 1).toString().padLeft(4, '0')}';
  }

  Patient create(Patient patient, {Staff? by}) {
    db.upsert('patients', patient.toRow());
    _audit.log(
      action: 'patient.register',
      entity: 'patients',
      entityId: patient.id,
      detail: '${patient.code} · ${patient.name}',
      by: by,
    );
    return patient;
  }

  void save(Patient patient, {Staff? by}) {
    db.upsert('patients', patient.toRow());
    _audit.log(
      action: 'patient.update',
      entity: 'patients',
      entityId: patient.id,
      detail: '${patient.code} · ${patient.name}',
      by: by,
    );
  }

  void delete(Patient patient, {Staff? by}) {
    db.softDelete('patients', patient.id);
    _audit.log(
      action: 'patient.delete',
      entity: 'patients',
      entityId: patient.id,
      detail: '${patient.code} · ${patient.name}',
      by: by,
    );
  }

  int get total => db.count('patients', where: 'deleted = 0');

  int registeredSince(DateTime since) => db.count(
        'patients',
        where: 'deleted = 0 AND registered_at >= ?',
        args: [since.millisecondsSinceEpoch],
      );

  // ---- Visits and symptoms ----------------------------------------------

  List<Visit> visitsFor(String patientId) => db
      .query(
        'SELECT * FROM visits WHERE patient_id = ? AND deleted = 0 '
        'ORDER BY visited_at DESC',
        [patientId],
      )
      .map(Visit.fromRow)
      .toList();

  Visit? latestVisit(String patientId) {
    final row = db.queryOne(
      'SELECT * FROM visits WHERE patient_id = ? AND deleted = 0 '
      'ORDER BY visited_at DESC LIMIT 1',
      [patientId],
    );
    return row == null ? null : Visit.fromRow(row);
  }

  List<SymptomReading> symptomsFor(String visitId) => db
      .query(
        'SELECT * FROM symptoms WHERE visit_id = ? AND deleted = 0',
        [visitId],
      )
      .map(SymptomReading.fromRow)
      .toList();

  /// Records a consultation and its symptom grid in one transaction.
  ///
  /// Readings are replaced wholesale for the visit so that editing a visit
  /// cannot leave a stale grade behind for a symptom that was cleared.
  Visit recordVisit(
    Visit visit,
    Map<String, String> readings, {
    Staff? by,
    bool updatePatientWeight = true,
  }) {
    db.transaction(() {
      db.upsert('visits', visit.toRow());
      for (final existing in symptomsFor(visit.id)) {
        db.softDelete('symptoms', existing.id);
      }
      readings.forEach((key, value) {
        if (value.isEmpty) return;
        db.upsert('symptoms', {
          'id': newId(),
          'visit_id': visit.id,
          'patient_id': visit.patientId,
          'key': key,
          'value': value,
        });
      });
      if (updatePatientWeight && visit.weightKg != null) {
        final patient = byId(visit.patientId);
        if (patient != null) {
          db.upsert(
            'patients',
            patient.copyWith(weightKg: visit.weightKg).toRow(),
          );
        }
      }
    });
    _audit.log(
      action: 'visit.record',
      entity: 'visits',
      entityId: visit.id,
      detail: byId(visit.patientId)?.name,
      by: by,
    );
    return visit;
  }

  /// Most recent value of each symptom for a patient, for the trend panel.
  Map<String, String> latestReadings(String patientId) {
    final rows = db.query(
      'SELECT s.key, s.value FROM symptoms s '
      'JOIN visits v ON v.id = s.visit_id '
      'WHERE s.patient_id = ? AND s.deleted = 0 AND v.deleted = 0 '
      'ORDER BY v.visited_at ASC',
      [patientId],
    );
    return {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
  }
}

class MedicineRepository extends _Repo {
  MedicineRepository(super.db, this._audit);
  final AuditRepository _audit;

  List<Medicine> all({String query = ''}) {
    final where = StringBuffer('deleted = 0');
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.write(' AND name LIKE ?');
      args.add('%${query.trim()}%');
    }
    return db
        .query(
          'SELECT * FROM medicines WHERE $where '
          'ORDER BY name COLLATE NOCASE, form',
          args,
        )
        .map(Medicine.fromRow)
        .toList();
  }

  Medicine? byId(String? id) {
    if (id == null) return null;
    final row = db.queryOne('SELECT * FROM medicines WHERE id = ?', [id]);
    return row == null ? null : Medicine.fromRow(row);
  }

  List<Medicine> lowStock() => all()
      .where((m) => m.isLow)
      .toList()
    ..sort((a, b) => a.stockQty.compareTo(b.stockQty));

  void save(Medicine medicine, {Staff? by}) {
    db.upsert('medicines', medicine.toRow());
    _audit.log(
      action: 'medicine.save',
      entity: 'medicines',
      entityId: medicine.id,
      detail: medicine.displayName,
      by: by,
    );
  }

  void delete(Medicine medicine, {Staff? by}) {
    db.softDelete('medicines', medicine.id);
    _audit.log(
      action: 'medicine.delete',
      entity: 'medicines',
      entityId: medicine.id,
      detail: medicine.displayName,
      by: by,
    );
  }

  /// Moves stock and records why, keeping the running total in step.
  ///
  /// The ledger and the total are written together so a crash cannot leave the
  /// displayed quantity disagreeing with the movement history.
  void adjustStock(
    Medicine medicine,
    int delta, {
    required String reason,
    String? reference,
    Staff? by,
  }) {
    if (delta == 0) return;
    db.transaction(() {
      db.upsert('stock_movements', {
        'id': newId(),
        'medicine_id': medicine.id,
        'delta': delta,
        'reason': reason,
        'reference': reference,
        'moved_at': DateTime.now().millisecondsSinceEpoch,
        'by_user': by?.id,
      });
      final current = byId(medicine.id) ?? medicine;
      final next = current.stockQty + delta;
      db.upsert(
        'medicines',
        current.copyWith(stockQty: next < 0 ? 0 : next).toRow(),
      );
    });
    _audit.log(
      action: delta > 0 ? 'stock.receive' : 'stock.issue',
      entity: 'medicines',
      entityId: medicine.id,
      detail: '${delta > 0 ? '+' : ''}$delta ${medicine.displayName} · $reason',
      by: by,
    );
  }

  List<StockMovement> movementsFor(String medicineId, {int limit = 50}) => db
      .query(
        'SELECT * FROM stock_movements WHERE medicine_id = ? AND deleted = 0 '
        'ORDER BY moved_at DESC LIMIT ?',
        [medicineId, limit],
      )
      .map(StockMovement.fromRow)
      .toList();

  /// Installs the clinic's standing formulary on a fresh database.
  void seedFormulary() {
    if (db.count('medicines') > 0) return;
    for (final entry in kFormulary) {
      db.upsert('medicines', {
        'id': newId(),
        'name': entry.name,
        'form': entry.form.name,
        'strength': null,
        'unit': entry.form == MedicineForm.syrup ? 'ml' : 'unit',
        'stock_qty': 0,
        'reorder_level': 20,
        'notes': null,
      });
    }
  }
}

class PrescriptionRepository extends _Repo {
  PrescriptionRepository(super.db, this._audit, this._medicines);
  final AuditRepository _audit;
  final MedicineRepository _medicines;

  List<Prescription> forPatient(String patientId) => db
      .query(
        'SELECT * FROM prescriptions WHERE patient_id = ? AND deleted = 0 '
        'ORDER BY prescribed_at DESC',
        [patientId],
      )
      .map(Prescription.fromRow)
      .toList();

  Prescription? byId(String? id) {
    if (id == null) return null;
    final row = db.queryOne('SELECT * FROM prescriptions WHERE id = ?', [id]);
    return row == null ? null : Prescription.fromRow(row);
  }

  List<PrescriptionItem> itemsFor(String prescriptionId) => db
      .query(
        'SELECT * FROM prescription_items WHERE prescription_id = ? '
        'AND deleted = 0',
        [prescriptionId],
      )
      .map(PrescriptionItem.fromRow)
      .toList();

  List<Prescription> recent({int limit = 20}) => db
      .query(
        'SELECT * FROM prescriptions WHERE deleted = 0 '
        'ORDER BY prescribed_at DESC LIMIT ?',
        [limit],
      )
      .map(Prescription.fromRow)
      .toList();

  void save(
    Prescription prescription,
    List<PrescriptionItem> items, {
    Staff? by,
  }) {
    db.transaction(() {
      db.upsert('prescriptions', prescription.toRow());
      final keep = items.map((i) => i.id).toSet();
      for (final existing in itemsFor(prescription.id)) {
        if (!keep.contains(existing.id)) {
          db.softDelete('prescription_items', existing.id);
        }
      }
      for (final item in items) {
        db.upsert('prescription_items', item.toRow());
      }
    });
    _audit.log(
      action: 'prescription.save',
      entity: 'prescriptions',
      entityId: prescription.id,
      detail: '${items.length} item(s)',
      by: by,
    );
  }

  /// Hands the medicines over and takes them out of stock.
  ///
  /// Refuses rather than going negative: a slip that cannot be filled should
  /// be visible at the counter, not discovered later in the ledger.
  ({bool ok, String? error}) dispense(Prescription prescription, {Staff? by}) {
    if (prescription.dispensed) {
      return (ok: false, error: 'This prescription has already been dispensed.');
    }
    final items = itemsFor(prescription.id);
    if (items.isEmpty) {
      return (ok: false, error: 'This prescription has no medicines on it.');
    }
    final shortfalls = <String>[];
    for (final item in items) {
      final medicine = _medicines.byId(item.medicineId);
      if (medicine == null) {
        shortfalls.add('a medicine that is no longer in the formulary');
        continue;
      }
      if (medicine.stockQty < item.quantity) {
        shortfalls.add(
          '${medicine.displayName} (need ${item.quantity}, '
          'have ${medicine.stockQty})',
        );
      }
    }
    if (shortfalls.isNotEmpty) {
      return (
        ok: false,
        error: 'Not enough stock for ${shortfalls.join('; ')}.',
      );
    }

    for (final item in items) {
      final medicine = _medicines.byId(item.medicineId)!;
      _medicines.adjustStock(
        medicine,
        -item.quantity,
        reason: 'Dispensed',
        reference: prescription.id,
        by: by,
      );
    }
    db.upsert('prescriptions', {
      ...prescription.toRow(),
      'dispensed': 1,
    });
    _audit.log(
      action: 'prescription.dispense',
      entity: 'prescriptions',
      entityId: prescription.id,
      detail: '${items.length} item(s)',
      by: by,
    );
    return (ok: true, error: null);
  }

  void delete(Prescription prescription, {Staff? by}) {
    db.transaction(() {
      for (final item in itemsFor(prescription.id)) {
        db.softDelete('prescription_items', item.id);
      }
      db.softDelete('prescriptions', prescription.id);
    });
    _audit.log(
      action: 'prescription.delete',
      entity: 'prescriptions',
      entityId: prescription.id,
      by: by,
    );
  }
}

class AppointmentRepository extends _Repo {
  AppointmentRepository(super.db, this._audit);
  final AuditRepository _audit;

  List<Appointment> between(DateTime from, DateTime to, {String? staffId}) {
    final where = StringBuffer(
      'deleted = 0 AND scheduled_at >= ? AND scheduled_at < ?',
    );
    final args = <Object?>[
      from.millisecondsSinceEpoch,
      to.millisecondsSinceEpoch,
    ];
    if (staffId != null) {
      where.write(' AND staff_id = ?');
      args.add(staffId);
    }
    return db
        .query(
          'SELECT * FROM appointments WHERE $where ORDER BY scheduled_at',
          args,
        )
        .map(Appointment.fromRow)
        .toList();
  }

  List<Appointment> onDay(DateTime day, {String? staffId}) {
    final start = DateTime(day.year, day.month, day.day);
    return between(start, start.add(const Duration(days: 1)), staffId: staffId);
  }

  List<Appointment> forPatient(String patientId) => db
      .query(
        'SELECT * FROM appointments WHERE patient_id = ? AND deleted = 0 '
        'ORDER BY scheduled_at DESC',
        [patientId],
      )
      .map(Appointment.fromRow)
      .toList();

  List<Appointment> upcoming({int limit = 10}) => db
      .query(
        'SELECT * FROM appointments WHERE deleted = 0 '
        "AND status = 'scheduled' AND scheduled_at >= ? "
        'ORDER BY scheduled_at LIMIT ?',
        [DateTime.now().millisecondsSinceEpoch, limit],
      )
      .map(Appointment.fromRow)
      .toList();

  Appointment? byId(String? id) {
    if (id == null) return null;
    final row = db.queryOne('SELECT * FROM appointments WHERE id = ?', [id]);
    return row == null ? null : Appointment.fromRow(row);
  }

  /// Other bookings for the same clinician that overlap [appointment].
  ///
  /// Reported rather than blocked: clinics double-book deliberately, so the
  /// scheduler warns and lets the user decide.
  List<Appointment> conflictsFor(Appointment appointment) {
    if (appointment.staffId == null) return const [];
    final sameDay = onDay(appointment.scheduledAt, staffId: appointment.staffId);
    return sameDay
        .where((a) =>
            a.id != appointment.id &&
            a.status == AppointmentStatus.scheduled &&
            a.overlaps(appointment))
        .toList();
  }

  void save(Appointment appointment, {Staff? by}) {
    db.upsert('appointments', appointment.toRow());
    _audit.log(
      action: 'appointment.save',
      entity: 'appointments',
      entityId: appointment.id,
      detail: appointment.status.label,
      by: by,
    );
  }

  void setStatus(Appointment appointment, AppointmentStatus status,
      {Staff? by}) {
    db.upsert('appointments', appointment.copyWith(status: status).toRow());
    _audit.log(
      action: 'appointment.${status.name}',
      entity: 'appointments',
      entityId: appointment.id,
      by: by,
    );
  }

  void delete(Appointment appointment, {Staff? by}) {
    db.softDelete('appointments', appointment.id);
    _audit.log(
      action: 'appointment.delete',
      entity: 'appointments',
      entityId: appointment.id,
      by: by,
    );
  }

  int countOn(DateTime day) => onDay(day)
      .where((a) => a.status != AppointmentStatus.cancelled)
      .length;
}
