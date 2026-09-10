import 'package:flutter_test/flutter_test.dart';
import 'package:sattra/core/constants.dart';
import 'package:sattra/core/ids.dart';
import 'package:sattra/data/db/app_database.dart';
import 'package:sattra/data/models/models.dart';
import 'package:sattra/data/repos/repositories.dart';
import 'package:sattra/services/data_reset_service.dart';
import 'package:sattra/services/settings_service.dart';

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late PatientRepository patients;
  late MedicineRepository medicines;
  late StaffRepository staff;
  late DataResetService reset;

  setUp(() {
    db = AppDatabase.openInMemory();
    settings = SettingsService(db);
    final audit = AuditRepository(db);
    patients = PatientRepository(db, audit);
    medicines = MedicineRepository(db, audit);
    staff = StaffRepository(db, audit);
    reset = DataResetService(
      db: db,
      settings: settings,
      audit: audit,
      medicines: medicines,
    );

    medicines.seedFormulary();
    staff.create(
      username: 'admin',
      fullName: 'The Administrator',
      role: UserRole.admin,
    );
    for (var i = 0; i < 3; i++) {
      final patient = patients.create(Patient(
        id: newId(),
        code: patients.nextCode(),
        name: 'Patient $i',
        sex: Sex.other,
        registeredAt: DateTime.now(),
      ));
      patients.recordVisit(
        Visit(
          id: newId(),
          patientId: patient.id,
          visitedAt: DateTime.now(),
        ),
        {'sleep': 'normal'},
      );
    }
  });
  tearDown(() => db.close());

  test('patient scope clears clinical data but keeps formulary and staff', () {
    settings.mode = DeploymentMode.standalone;

    reset.reset(ResetScope.patientRecords);

    expect(patients.total, 0);
    expect(db.count('visits', where: 'deleted = 0'), 0);
    expect(db.count('symptoms', where: 'deleted = 0'), 0);
    expect(medicines.all(), isNotEmpty);
    expect(staff.all(), isNotEmpty);
  });

  test('a standalone install removes rows outright', () {
    settings.mode = DeploymentMode.standalone;

    reset.reset(ResetScope.patientRecords);

    // Nothing to replicate to, so nothing is left behind.
    expect(db.count('patients'), 0);
  });

  test('a networked install tombstones so the deletion can replicate', () {
    settings.mode = DeploymentMode.terminal;

    reset.reset(ResetScope.patientRecords);

    expect(patients.total, 0);
    expect(db.count('patients'), 3);
    expect(db.count('patients', where: 'deleted = 1 AND dirty = 1'), 3);
  });

  test('the wider scope also clears the formulary and restores it', () {
    settings.mode = DeploymentMode.standalone;

    final outcome = reset.reset(ResetScope.everythingButStaff);

    expect(outcome.formularyRestored, isTrue);
    expect(medicines.all(), hasLength(kFormulary.length));
    // The restored formulary starts empty of stock.
    expect(medicines.all().every((m) => m.stockQty == 0), isTrue);
  });

  test('staff accounts survive every scope', () {
    settings.mode = DeploymentMode.standalone;

    reset.reset(ResetScope.everythingButStaff);

    expect(staff.all(), hasLength(1));
  });

  test('counts describe what each scope would remove', () {
    expect(reset.countFor(ResetScope.patientRecords), greaterThan(0));
    expect(
      reset.countFor(ResetScope.everythingButStaff),
      greaterThan(reset.countFor(ResetScope.patientRecords)),
    );
  });

  test('the reset itself is recorded in the activity log', () {
    settings.mode = DeploymentMode.standalone;
    final audit = AuditRepository(db);

    reset.reset(ResetScope.patientRecords);

    expect(
      audit.recent().map((e) => e.action),
      contains('data.reset'),
    );
  });
}
