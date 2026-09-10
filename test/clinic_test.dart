import 'package:flutter_test/flutter_test.dart';
import 'package:sattra/core/constants.dart';
import 'package:sattra/core/ids.dart';
import 'package:sattra/data/db/app_database.dart';
import 'package:sattra/data/models/models.dart';
import 'package:sattra/data/repos/repositories.dart';

void main() {
  late AppDatabase db;
  late AuditRepository audit;
  late PatientRepository patients;
  late MedicineRepository medicines;
  late PrescriptionRepository prescriptions;
  late AppointmentRepository appointments;
  late StaffRepository staff;

  setUp(() {
    db = AppDatabase.openInMemory();
    audit = AuditRepository(db);
    staff = StaffRepository(db, audit);
    patients = PatientRepository(db, audit);
    medicines = MedicineRepository(db, audit);
    prescriptions = PrescriptionRepository(db, audit, medicines);
    appointments = AppointmentRepository(db, audit);
  });
  tearDown(() => db.close());

  Patient newPatient({String name = 'Asha', Sex sex = Sex.female}) => Patient(
        id: newId(),
        code: patients.nextCode(),
        name: name,
        age: 34,
        sex: sex,
        registeredAt: DateTime.now(),
      );

  group('patient register', () {
    test('record numbers run in sequence and pad', () {
      expect(patients.nextCode(), 'P-0001');
      patients.create(newPatient());
      expect(patients.nextCode(), 'P-0002');
    });

    test('numbering follows the highest existing code, not the row count', () {
      // Two terminals registering offline must not both mint the same number
      // once their rows merge.
      patients.create(newPatient(name: 'First'));
      db.upsert('patients', {
        'id': newId(),
        'code': 'P-0042',
        'name': 'Merged in from another terminal',
        'sex': 'male',
        'registered_at': DateTime.now().millisecondsSinceEpoch,
      });

      expect(patients.nextCode(), 'P-0043');
    });

    test('a removed patient drops out of the register but is not erased', () {
      final patient = patients.create(newPatient());
      patients.delete(patient);

      expect(patients.search(), isEmpty);
      expect(patients.total, 0);
      // The row survives so the deletion can replicate.
      expect(db.count('patients'), 1);
    });

    test('search matches name, code and phone', () {
      final patient = patients.create(
        newPatient(name: 'Bhavna Rao').copyWith(phone: '9876543210'),
      );
      patients.create(newPatient(name: 'Chandra'));

      expect(patients.search(query: 'bhav').single.id, patient.id);
      expect(patients.search(query: patient.code).single.id, patient.id);
      expect(patients.search(query: '98765').single.id, patient.id);
      expect(patients.search(query: 'nobody'), isEmpty);
    });
  });

  group('consultations', () {
    test('a visit stores its symptom grid', () {
      final patient = patients.create(newPatient());
      final visit = Visit(
        id: newId(),
        patientId: patient.id,
        visitedAt: DateTime.now(),
        weightKg: 58,
      );

      patients.recordVisit(visit, {
        'sleep': 'disrupted',
        'bowel': 'normal',
        'lmp': '2026-08-14',
      });

      final readings = patients.symptomsFor(visit.id);
      expect(readings.length, 3);
      expect(
        readings.firstWhere((r) => r.key == 'sleep').value,
        'disrupted',
      );
    });

    test('re-recording a visit replaces its grid rather than layering it', () {
      final patient = patients.create(newPatient());
      final visit = Visit(
        id: newId(),
        patientId: patient.id,
        visitedAt: DateTime.now(),
      );

      patients.recordVisit(visit, {'sleep': 'disrupted', 'stress': 'heavy'});
      patients.recordVisit(visit, {'sleep': 'normal'});

      final readings = patients.symptomsFor(visit.id);
      expect(readings.map((r) => r.key), ['sleep']);
      expect(readings.single.value, 'normal');
    });

    test('a visit weight updates the patient record', () {
      final patient = patients.create(newPatient());

      patients.recordVisit(
        Visit(
          id: newId(),
          patientId: patient.id,
          visitedAt: DateTime.now(),
          weightKg: 61.5,
        ),
        const {},
      );

      expect(patients.byId(patient.id)!.weightKg, 61.5);
    });

    test('the latest reading of each symptom wins across visits', () {
      final patient = patients.create(newPatient());
      final earlier = DateTime.now().subtract(const Duration(days: 30));

      patients.recordVisit(
        Visit(id: newId(), patientId: patient.id, visitedAt: earlier),
        {'sleep': 'heavy', 'bowel': 'constipation'},
      );
      patients.recordVisit(
        Visit(id: newId(), patientId: patient.id, visitedAt: DateTime.now()),
        {'sleep': 'normal'},
      );

      final latest = patients.latestReadings(patient.id);
      expect(latest['sleep'], 'normal');
      // Untouched at the later visit, so the earlier grade still stands.
      expect(latest['bowel'], 'constipation');
    });

    test('a grade off baseline is flagged as notable', () {
      final baseline = SymptomReading(
        id: 'a',
        visitId: 'v',
        patientId: 'p',
        key: 'sleep',
        value: 'normal',
      );
      final off = SymptomReading(
        id: 'b',
        visitId: 'v',
        patientId: 'p',
        key: 'sleep',
        value: 'disrupted',
      );

      expect(baseline.isNotable, isFalse);
      expect(off.isNotable, isTrue);
    });
  });

  group('pharmacy', () {
    test('the standing formulary is installed once', () {
      medicines.seedFormulary();
      final first = medicines.all().length;
      medicines.seedFormulary();

      expect(first, kFormulary.length);
      expect(medicines.all().length, first);
    });

    test('stock movements keep the running total in step', () {
      medicines.seedFormulary();
      final medicine = medicines.all().first;

      medicines.adjustStock(medicine, 100, reason: 'Delivery received');
      medicines.adjustStock(
        medicines.byId(medicine.id)!,
        -30,
        reason: 'Dispensed',
      );

      expect(medicines.byId(medicine.id)!.stockQty, 70);
      expect(medicines.movementsFor(medicine.id).length, 2);
    });

    test('stock never goes negative', () {
      medicines.seedFormulary();
      final medicine = medicines.all().first;
      medicines.adjustStock(medicine, 5, reason: 'Delivery received');

      medicines.adjustStock(
        medicines.byId(medicine.id)!,
        -50,
        reason: 'Damaged',
      );

      expect(medicines.byId(medicine.id)!.stockQty, 0);
    });

    test('low stock is reported at or below the reorder level', () {
      medicines.seedFormulary();
      final medicine = medicines.all().first;
      medicines.save(medicine.copyWith(reorderLevel: 20, stockQty: 20));

      expect(medicines.lowStock().map((m) => m.id), contains(medicine.id));

      medicines.save(medicines.byId(medicine.id)!.copyWith(stockQty: 21));
      expect(medicines.lowStock().map((m) => m.id), isNot(contains(medicine.id)));
    });
  });

  group('prescribing and dispensing', () {
    late Patient patient;
    late Medicine medicine;

    setUp(() {
      medicines.seedFormulary();
      patient = patients.create(newPatient());
      medicine = medicines.all().first;
    });

    Prescription writeFor(int quantity) {
      final prescription = Prescription(
        id: newId(),
        patientId: patient.id,
        prescribedAt: DateTime.now(),
      );
      prescriptions.save(prescription, [
        PrescriptionItem(
          id: newId(),
          prescriptionId: prescription.id,
          medicineId: medicine.id,
          dose: Dose.bd,
          durationDays: 7,
          quantity: quantity,
        ),
      ]);
      return prescription;
    }

    test('quantity follows the dose and the course length', () {
      expect(PrescriptionItem.suggestedQuantity(Dose.bd, 7), 14);
      expect(PrescriptionItem.suggestedQuantity(Dose.tds, 5), 15);
      expect(PrescriptionItem.suggestedQuantity(Dose.od, 10), 10);
      // Alternate days over an odd course rounds up to a whole unit.
      expect(PrescriptionItem.suggestedQuantity(Dose.eod, 7), 4);
    });

    test('dispensing deducts stock and marks the slip', () {
      medicines.adjustStock(medicine, 50, reason: 'Delivery received');
      final prescription = writeFor(14);

      final result = prescriptions.dispense(prescription);

      expect(result.ok, isTrue);
      expect(medicines.byId(medicine.id)!.stockQty, 36);
      expect(prescriptions.byId(prescription.id)!.dispensed, isTrue);
    });

    test('a shortfall is refused and nothing moves', () {
      medicines.adjustStock(medicine, 5, reason: 'Delivery received');
      final prescription = writeFor(14);

      final result = prescriptions.dispense(prescription);

      expect(result.ok, isFalse);
      expect(result.error, contains('Not enough stock'));
      expect(medicines.byId(medicine.id)!.stockQty, 5);
      expect(prescriptions.byId(prescription.id)!.dispensed, isFalse);
    });

    test('the same prescription cannot be dispensed twice', () {
      medicines.adjustStock(medicine, 50, reason: 'Delivery received');
      final prescription = writeFor(14);
      prescriptions.dispense(prescription);

      final again = prescriptions.dispense(
        prescriptions.byId(prescription.id)!,
      );

      expect(again.ok, isFalse);
      expect(medicines.byId(medicine.id)!.stockQty, 36);
    });

    test('editing a prescription drops the lines that were removed', () {
      final prescription = writeFor(14);
      prescriptions.save(prescription, const []);

      expect(prescriptions.itemsFor(prescription.id), isEmpty);
    });
  });

  group('scheduling', () {
    late Patient patient;
    late Staff clinician;

    setUp(() {
      patient = patients.create(newPatient());
      clinician = staff.create(
        username: 'n.bala',
        fullName: 'Neeru Bala',
        role: UserRole.provider,
      );
    });

    Appointment at(DateTime when, {int minutes = 15}) => Appointment(
          id: newId(),
          patientId: patient.id,
          staffId: clinician.id,
          scheduledAt: when,
          durationMin: minutes,
        );

    test('overlap is judged on the whole slot, not just the start', () {
      final nine = DateTime(2026, 5, 4, 9);
      final a = at(nine, minutes: 30);
      final overlapping = at(nine.add(const Duration(minutes: 15)));
      final after = at(nine.add(const Duration(minutes: 30)));

      expect(a.overlaps(overlapping), isTrue);
      expect(a.overlaps(after), isFalse);
    });

    test('a clash with the same clinician is reported', () {
      final nine = DateTime(2026, 5, 4, 9);
      appointments.save(at(nine, minutes: 30));

      final clashes = appointments.conflictsFor(
        at(nine.add(const Duration(minutes: 10))),
      );

      expect(clashes, hasLength(1));
    });

    test('a cancelled booking no longer clashes', () {
      final nine = DateTime(2026, 5, 4, 9);
      final existing = at(nine, minutes: 30);
      appointments.save(existing);
      appointments.setStatus(existing, AppointmentStatus.cancelled);

      expect(appointments.conflictsFor(at(nine)), isEmpty);
    });

    test('a different clinician at the same time does not clash', () {
      final nine = DateTime(2026, 5, 4, 9);
      appointments.save(at(nine, minutes: 30));
      final other = staff.create(
        username: 'a.kaushik',
        fullName: 'Aman Kaushik',
        role: UserRole.provider,
      );

      final clashes = appointments.conflictsFor(
        Appointment(
          id: newId(),
          patientId: patient.id,
          staffId: other.id,
          scheduledAt: nine,
        ),
      );

      expect(clashes, isEmpty);
    });

    test('the day list is bounded to that day', () {
      appointments.save(at(DateTime(2026, 5, 4, 23, 45)));
      appointments.save(at(DateTime(2026, 5, 5, 0, 15)));

      expect(appointments.onDay(DateTime(2026, 5, 4)), hasLength(1));
      expect(appointments.onDay(DateTime(2026, 5, 5)), hasLength(1));
    });
  });

  group('staff', () {
    test('the last administrator is detectable before being demoted', () {
      staff.create(
        username: 'admin',
        fullName: 'The Administrator',
        role: UserRole.admin,
      );
      expect(staff.adminCount, 1);

      staff.create(
        username: 'admin2',
        fullName: 'Another Administrator',
        role: UserRole.admin,
      );
      expect(staff.adminCount, 2);
    });

    test('a deactivated administrator stops counting', () {
      final admin = staff.create(
        username: 'admin',
        fullName: 'The Administrator',
        role: UserRole.admin,
      );

      staff.deactivate(admin);

      expect(staff.adminCount, 0);
    });

    test('usernames are unique across active records', () {
      staff.create(
        username: 'a.doctor',
        fullName: 'A Doctor',
        role: UserRole.provider,
      );

      expect(staff.usernameTaken('a.doctor'), isTrue);
      expect(staff.usernameTaken('b.doctor'), isFalse);
    });

    test('every write leaves an attributable trail', () {
      final actor = staff.create(
        username: 'admin',
        fullName: 'The Administrator',
        role: UserRole.admin,
      );
      patients.create(newPatient(), by: actor);

      final entry = audit.recent().firstWhere(
            (e) => e.action == 'patient.register',
          );
      expect(entry.userName, 'The Administrator');
    });
  });
}
