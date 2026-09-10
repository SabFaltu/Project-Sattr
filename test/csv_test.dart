import 'package:flutter_test/flutter_test.dart';
import 'package:sattra/core/constants.dart';
import 'package:sattra/data/db/app_database.dart';
import 'package:sattra/data/repos/repositories.dart';
import 'package:sattra/services/csv_service.dart';

void main() {
  group('parsing', () {
    test('splits plain rows', () {
      final rows = CsvService.parse('a,b,c\n1,2,3');
      expect(rows, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('keeps commas inside quoted fields', () {
      // A real address column is exactly this shape.
      final rows = CsvService.parse('name,address\nAsha,"14 Nehru Nagar, Sector 8"');
      expect(rows[1], ['Asha', '14 Nehru Nagar, Sector 8']);
    });

    test('unescapes doubled quotes', () {
      final rows = CsvService.parse('note\n"She said ""fine"""');
      expect(rows[1].single, 'She said "fine"');
    });

    test('keeps newlines inside quoted fields', () {
      final rows = CsvService.parse('a,b\n"line one\nline two",x');
      expect(rows, hasLength(2));
      expect(rows[1][0], 'line one\nline two');
      expect(rows[1][1], 'x');
    });

    test('handles CRLF and a trailing newline without phantom rows', () {
      final rows = CsvService.parse('a,b\r\n1,2\r\n');
      expect(rows, hasLength(2));
      expect(rows[1], ['1', '2']);
    });

    test('round-trips through write', () {
      final original = [
        ['name', 'address'],
        ['Asha, D', 'He said "hi"\nsecond line'],
      ];
      expect(CsvService.parse(CsvService.write(original)), original);
    });

    test('header normalisation accepts spaces, dashes and casing', () {
      expect(CsvService.normaliseHeader('Chief Complaints'), 'chief_complaints');
      expect(CsvService.normaliseHeader('chief-complaints'), 'chief_complaints');
      expect(CsvService.normaliseHeader('  WEIGHT KG '), 'weight_kg');
    });
  });

  group('importing', () {
    late AppDatabase db;
    late CsvService csv;
    late PatientRepository patients;
    late MedicineRepository medicines;
    late StaffRepository staff;

    setUp(() {
      db = AppDatabase.openInMemory();
      final audit = AuditRepository(db);
      patients = PatientRepository(db, audit);
      medicines = MedicineRepository(db, audit);
      staff = StaffRepository(db, audit);
      csv = CsvService(
        patients: patients,
        medicines: medicines,
        staff: staff,
      );
    });
    tearDown(() => db.close());

    test('the shipped sample imports cleanly', () {
      staff.create(
        username: 'b.kihore',
        fullName: 'Brian Edwin Kihore',
        role: UserRole.provider,
      );

      final result = csv.importPatients(CsvService.samplePatientsCsv());

      expect(result.imported, 2);
      expect(result.problems, isEmpty);
      expect(patients.total, 2);
      final asha = patients.search(query: 'Asha').single;
      expect(asha.age, 42);
      expect(asha.sex, Sex.female);
      expect(asha.weightKg, 61.5);
      expect(asha.address, contains('Nehru Nagar'));
    });

    test('column order does not matter', () {
      final result = csv.importPatients('age,name\n30,Priya');

      expect(result.imported, 1);
      expect(patients.search().single.name, 'Priya');
      expect(patients.search().single.age, 30);
    });

    test('a dry run reports without writing anything', () {
      final result = csv.importPatients('name\nAsha\nRamesh', dryRun: true);

      expect(result.imported, 2);
      expect(patients.total, 0);
    });

    test('one bad row does not abort the rest of the file', () {
      final result = csv.importPatients('name,age\nAsha,42\n,99\nRamesh,58');

      expect(result.imported, 2);
      expect(result.problems, hasLength(1));
      expect(result.problems.single.row, 3);
    });

    test('an unusable age is reported and the row still imports', () {
      final result = csv.importPatients('name,age\nAsha,fortyish');

      expect(result.imported, 1);
      expect(patients.search().single.age, isNull);
      expect(result.problems.single.message, contains('age'));
    });

    test('an unknown clinician is reported and the patient is unassigned', () {
      final result = csv.importPatients('name,assigned_to\nAsha,nobody');

      expect(result.imported, 1);
      expect(patients.search().single.assignedTo, isNull);
      expect(result.problems.single.message, contains('nobody'));
    });

    test('imported patients get sequential record numbers', () {
      csv.importPatients('name\nAsha\nRamesh\nPriya');

      expect(
        patients.search().map((p) => p.code).toList()..sort(),
        ['P-0001', 'P-0002', 'P-0003'],
      );
    });

    test('a file with no name column is refused with an explanation', () {
      final result = csv.importPatients('age,phone\n42,12345');

      expect(result.imported, 0);
      expect(result.problems.single.message, contains('name'));
    });

    test('an empty file is refused', () {
      expect(csv.importPatients('').imported, 0);
    });

    test('medicines import with their opening stock', () {
      final result = csv.importMedicines(CsvService.sampleMedicinesCsv());

      expect(result.imported, 3);
      final adhya = medicines.all().firstWhere((m) => m.name == 'Adhya');
      expect(adhya.stockQty, 240);
      expect(adhya.reorderLevel, 20);
      expect(adhya.form, MedicineForm.tablet);
    });

    test('re-importing updates stock instead of duplicating the medicine', () {
      csv.importMedicines('name,form,stock_qty\nAdhya,tablet,100');
      final result =
          csv.importMedicines('name,form,stock_qty\nAdhya,tablet,175');

      expect(medicines.all().where((m) => m.name == 'Adhya'), hasLength(1));
      expect(result.updated, 1);
      expect(result.imported, 0);
      final adhya = medicines.all().firstWhere((m) => m.name == 'Adhya');
      expect(adhya.stockQty, 175);
      // The correction is explained in the ledger rather than silently applied.
      expect(
        medicines.movementsFor(adhya.id).first.reason,
        'Imported from spreadsheet',
      );
    });

    test('an unknown medicine form is reported and defaults to tablet', () {
      final result = csv.importMedicines('name,form\nAdhya,lozenge');

      expect(result.imported, 1);
      expect(medicines.all().single.form, MedicineForm.tablet);
      expect(result.problems.single.message, contains('lozenge'));
    });
  });
}
