import '../core/constants.dart';
import '../core/format.dart';
import '../core/ids.dart';
import '../data/models/models.dart';
import '../data/repos/repositories.dart';

/// Bringing a clinic's existing records in from a spreadsheet.
///
/// Clinics arriving at Sattra almost always have a register in Excel or Google
/// Sheets already, and retyping it is the single biggest reason a migration
/// stalls. The import is deliberately forgiving about column order, casing and
/// spacing, and deliberately strict about telling the administrator exactly
/// which rows it could not take and why.
class CsvService {
  CsvService({
    required PatientRepository patients,
    required MedicineRepository medicines,
    required StaffRepository staff,
  })  : _patients = patients,
        _medicines = medicines,
        _staff = staff;

  final PatientRepository _patients;
  final MedicineRepository _medicines;
  final StaffRepository _staff;

  // ---- Parsing -----------------------------------------------------------

  /// Splits CSV text into rows of fields.
  ///
  /// Handles quoted fields, embedded commas and newlines, and doubled quotes,
  /// because a real address column contains all three. Accepts LF and CRLF.
  static List<List<String>> parse(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var i = 0;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      // A trailing newline should not produce a phantom empty row.
      if (row.length > 1 || row.first.trim().isNotEmpty) rows.add(row);
      row = <String>[];
    }

    while (i < input.length) {
      final char = input[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.write(char);
        i++;
        continue;
      }
      switch (char) {
        case '"':
          inQuotes = true;
          i++;
        case ',':
          endField();
          i++;
        case '\r':
          // Swallow it; the \n that follows ends the row.
          i++;
        case '\n':
          endRow();
          i++;
        default:
          field.write(char);
          i++;
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  /// Renders rows back to CSV, quoting only what needs it.
  static String write(List<List<String>> rows) => rows
      .map((row) => row.map(_escape).join(','))
      .join('\n');

  static String _escape(String value) {
    if (!value.contains(RegExp(r'[",\n\r]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  /// Normalises a header cell so `Chief Complaints`, `chief_complaints` and
  /// `chief-complaints` all mean the same column.
  static String normaliseHeader(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');

  // ---- What the importer expects ----------------------------------------

  static const List<String> patientColumns = [
    'name',
    'age',
    'sex',
    'weight_kg',
    'phone',
    'address',
    'chief_complaints',
    'notes',
    'assigned_to',
  ];

  static const List<String> medicineColumns = [
    'name',
    'form',
    'strength',
    'unit',
    'stock_qty',
    'reorder_level',
    'notes',
  ];

  /// A filled-in example, so an administrator can see the shape rather than
  /// read a specification.
  static String samplePatientsCsv() => write([
        patientColumns,
        [
          'Asha Devi',
          '42',
          'female',
          '61.5',
          '+91 98765 43210',
          '14 Nehru Nagar, Sector 8, Chandigarh',
          'Disturbed sleep and acidity for three months',
          'Prefers morning appointments',
          'b.kihore',
        ],
        [
          'Ramesh Kumar',
          '58',
          'male',
          '78',
          '+91 99887 66554',
          '3/221 Model Town, Ludhiana',
          'Joint pain in both knees',
          '',
          '',
        ],
      ]);

  static String sampleMedicinesCsv() => write([
        medicineColumns,
        ['Adhya', 'tablet', '', 'unit', '240', '20', ''],
        ['Punarnava', 'capsule', '500 mg', 'unit', '120', '20', 'Keep dry'],
        ['Cystolve', 'syrup', '', 'ml', '3000', '500', ''],
      ]);

  /// Human description of each column, shown next to the download button.
  static const Map<String, String> patientColumnHelp = {
    'name': 'Required. The patient\'s full name.',
    'age': 'Optional. Whole years.',
    'sex': 'Optional. female, male or other.',
    'weight_kg': 'Optional. Kilograms, decimals allowed.',
    'phone': 'Optional.',
    'address': 'Optional. Quote it if it contains commas.',
    'chief_complaints': 'Optional. What brought them in.',
    'notes': 'Optional.',
    'assigned_to': 'Optional. The username of the staff member responsible.',
  };

  // ---- Importing ---------------------------------------------------------

  /// Reads patients from [csv].
  ///
  /// Rows are taken one at a time and a bad row is skipped with a reason
  /// rather than aborting the run: a spreadsheet with three broken rows out of
  /// four hundred should still import three hundred and ninety-seven.
  CsvImportResult importPatients(String csv, {Staff? by, bool dryRun = false}) {
    final rows = parse(csv);
    if (rows.isEmpty) {
      return const CsvImportResult(
        imported: 0,
        problems: [CsvProblem(row: 0, message: 'The file is empty.')],
      );
    }

    final header = rows.first.map(normaliseHeader).toList();
    final nameAt = header.indexOf('name');
    if (nameAt < 0) {
      return const CsvImportResult(
        imported: 0,
        problems: [
          CsvProblem(
            row: 1,
            message: 'No "name" column was found. Download the sample file to '
                'see the expected header row.',
          ),
        ],
      );
    }

    final staffByUsername = {
      for (final s in _staff.all()) s.username.toLowerCase(): s,
    };
    final problems = <CsvProblem>[];
    var imported = 0;

    String cell(List<String> row, String column) {
      final index = header.indexOf(column);
      if (index < 0 || index >= row.length) return '';
      return row[index].trim();
    }

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final lineNumber = i + 1;
      final name = cell(row, 'name');
      if (name.isEmpty) {
        problems.add(CsvProblem(row: lineNumber, message: 'No name; skipped.'));
        continue;
      }

      final ageText = cell(row, 'age');
      int? age;
      if (ageText.isNotEmpty) {
        age = int.tryParse(ageText);
        if (age == null || age < 0 || age > 130) {
          problems.add(CsvProblem(
            row: lineNumber,
            message: '"$ageText" is not a usable age; imported without one.',
          ));
          age = null;
        }
      }

      final weightText = cell(row, 'weight_kg');
      double? weight;
      if (weightText.isNotEmpty) {
        weight = double.tryParse(weightText);
        if (weight == null) {
          problems.add(CsvProblem(
            row: lineNumber,
            message: '"$weightText" is not a usable weight; imported without '
                'one.',
          ));
        }
      }

      final sexText = cell(row, 'sex').toLowerCase();
      var sex = Sex.other;
      if (sexText.isNotEmpty) {
        sex = switch (sexText) {
          'f' || 'female' || 'w' || 'woman' => Sex.female,
          'm' || 'male' || 'man' => Sex.male,
          'o' || 'other' => Sex.other,
          _ => Sex.other,
        };
        if (sex == Sex.other && sexText != 'other' && sexText != 'o') {
          problems.add(CsvProblem(
            row: lineNumber,
            message: '"$sexText" was not recognised; recorded as Other.',
          ));
        }
      }

      final assignedText = cell(row, 'assigned_to').toLowerCase();
      String? assignedTo;
      if (assignedText.isNotEmpty) {
        final match = staffByUsername[assignedText];
        if (match == null) {
          problems.add(CsvProblem(
            row: lineNumber,
            message: 'No staff member with username "$assignedText"; imported '
                'unassigned.',
          ));
        } else {
          assignedTo = match.id;
        }
      }

      if (dryRun) {
        imported++;
        continue;
      }

      _patients.create(
        Patient(
          id: newId(),
          code: _patients.nextCode(),
          name: name,
          age: age,
          sex: sex,
          weightKg: weight,
          address: _orNull(cell(row, 'address')),
          phone: _orNull(cell(row, 'phone')),
          chiefComplaints: _orNull(cell(row, 'chief_complaints')),
          notes: _orNull(cell(row, 'notes')),
          assignedTo: assignedTo,
          registeredAt: DateTime.now(),
        ),
        by: by,
      );
      imported++;
    }

    return CsvImportResult(imported: imported, problems: problems);
  }

  /// Reads the formulary from [csv].
  ///
  /// A medicine that already exists by name and form has its stock and reorder
  /// level updated rather than being duplicated, so re-importing a corrected
  /// sheet does not leave the clinic with two of everything.
  CsvImportResult importMedicines(String csv, {Staff? by, bool dryRun = false}) {
    final rows = parse(csv);
    if (rows.isEmpty) {
      return const CsvImportResult(
        imported: 0,
        problems: [CsvProblem(row: 0, message: 'The file is empty.')],
      );
    }

    final header = rows.first.map(normaliseHeader).toList();
    if (!header.contains('name')) {
      return const CsvImportResult(
        imported: 0,
        problems: [
          CsvProblem(
            row: 1,
            message: 'No "name" column was found. Download the sample file to '
                'see the expected header row.',
          ),
        ],
      );
    }

    final problems = <CsvProblem>[];
    var imported = 0;
    var updated = 0;

    String cell(List<String> row, String column) {
      final index = header.indexOf(column);
      if (index < 0 || index >= row.length) return '';
      return row[index].trim();
    }

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final lineNumber = i + 1;
      final name = cell(row, 'name');
      if (name.isEmpty) {
        problems.add(CsvProblem(row: lineNumber, message: 'No name; skipped.'));
        continue;
      }

      final formText = cell(row, 'form').toLowerCase();
      final form = formText.isEmpty
          ? MedicineForm.tablet
          : MedicineForm.fromName(formText);
      if (formText.isNotEmpty && form.name != formText) {
        problems.add(CsvProblem(
          row: lineNumber,
          message: '"$formText" is not a known form; recorded as Tablet.',
        ));
      }

      final stock = int.tryParse(cell(row, 'stock_qty')) ?? 0;
      final reorder = int.tryParse(cell(row, 'reorder_level')) ?? 20;

      if (dryRun) {
        imported++;
        continue;
      }

      final existing = _medicines.all().where(
            (m) =>
                m.name.toLowerCase() == name.toLowerCase() && m.form == form,
          );

      if (existing.isNotEmpty) {
        final medicine = existing.first;
        _medicines.save(
          medicine.copyWith(
            strength: _orNull(cell(row, 'strength')),
            unit: _orNull(cell(row, 'unit')) ?? medicine.unit,
            reorderLevel: reorder,
            notes: _orNull(cell(row, 'notes')),
          ),
          by: by,
        );
        // Stock moves through the ledger so the change is explained, rather
        // than the running total being silently overwritten.
        final delta = stock - medicine.stockQty;
        if (delta != 0) {
          _medicines.adjustStock(
            _medicines.byId(medicine.id)!,
            delta,
            reason: 'Imported from spreadsheet',
            by: by,
          );
        }
        updated++;
        continue;
      }

      final medicine = Medicine(
        id: newId(),
        name: name,
        form: form,
        strength: _orNull(cell(row, 'strength')),
        unit: _orNull(cell(row, 'unit')) ?? 'unit',
        reorderLevel: reorder,
        notes: _orNull(cell(row, 'notes')),
      );
      _medicines.save(medicine, by: by);
      if (stock > 0) {
        _medicines.adjustStock(
          _medicines.byId(medicine.id)!,
          stock,
          reason: 'Imported from spreadsheet',
          by: by,
        );
      }
      imported++;
    }

    return CsvImportResult(
      imported: imported,
      updated: updated,
      problems: problems,
    );
  }

  static String? _orNull(String value) => value.isEmpty ? null : value;

  /// Suggested filename for a sample download.
  static String sampleFileName(CsvImportKind kind) =>
      'sattra-${kind.name}-template-${isoDate(DateTime.now())}.csv';
}

enum CsvImportKind {
  patients,
  medicines;

  String get label => switch (this) {
        CsvImportKind.patients => 'Patients',
        CsvImportKind.medicines => 'Medicines and stock',
      };

  String get description => switch (this) {
        CsvImportKind.patients =>
          'Names, ages and contact details from an existing register.',
        CsvImportKind.medicines =>
          'The formulary with opening stock levels. Re-importing updates what '
              'is already there instead of duplicating it.',
      };

  List<String> get columns => switch (this) {
        CsvImportKind.patients => CsvService.patientColumns,
        CsvImportKind.medicines => CsvService.medicineColumns,
      };

  String get sample => switch (this) {
        CsvImportKind.patients => CsvService.samplePatientsCsv(),
        CsvImportKind.medicines => CsvService.sampleMedicinesCsv(),
      };
}

class CsvProblem {
  const CsvProblem({required this.row, required this.message});

  /// 1-based line number in the file, so it matches what the spreadsheet shows.
  final int row;
  final String message;

  @override
  String toString() => 'Line $row: $message';
}

class CsvImportResult {
  const CsvImportResult({
    required this.imported,
    this.updated = 0,
    this.problems = const [],
  });

  final int imported;
  final int updated;
  final List<CsvProblem> problems;

  bool get hasProblems => problems.isNotEmpty;

  String get summary {
    final parts = <String>[
      if (imported > 0) '$imported added',
      if (updated > 0) '$updated updated',
    ];
    if (parts.isEmpty) return 'Nothing was imported.';
    return '${parts.join(', ')}'
        '${problems.isEmpty ? '.' : ', ${problems.length} row(s) needed attention.'}';
  }
}
