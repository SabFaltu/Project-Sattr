/// Domain constants for Project सत्र (Sattra).
///
/// The clinical vocabulary here is taken verbatim from `DataCalls.org` so the
/// application stays faithful to the data model the clinic asked for.
library;

/// Roles as defined in the project report (section 3.1).
enum UserRole {
  /// Full system oversight: user management, sync, backups, inventory writes.
  admin,

  /// Doctors and nurses: patient care, prescriptions, appointments, reports.
  provider;

  static UserRole fromName(String value) =>
      UserRole.values.firstWhere((r) => r.name == value, orElse: () => provider);

  String get label => switch (this) {
        UserRole.admin => 'Administrator',
        UserRole.provider => 'Healthcare Provider',
      };
}

/// Biological sex recorded at intake (`Sex | toggle`).
enum Sex {
  female,
  male,
  other;

  static Sex fromName(String value) =>
      Sex.values.firstWhere((s) => s.name == value, orElse: () => other);

  String get label => switch (this) {
        Sex.female => 'Female',
        Sex.male => 'Male',
        Sex.other => 'Other',
      };

  String get short => switch (this) {
        Sex.female => 'F',
        Sex.male => 'M',
        Sex.other => 'O',
      };
}

/// One row of the symptom table in `DataCalls.org`.
class SymptomDefinition {
  const SymptomDefinition({
    required this.key,
    required this.label,
    required this.levels,
    this.isDate = false,
    this.femaleOnly = false,
  });

  final String key;
  final String label;

  /// Allowed levels, first entry being the unremarkable/baseline one.
  final List<String> levels;

  /// `LMP` is a date rather than a graded level.
  final bool isDate;

  /// Menstruation and LMP are only prompted for female patients.
  final bool femaleOnly;
}

/// The nine tracked symptoms, in the order the clinic lists them.
const List<SymptomDefinition> kSymptoms = [
  SymptomDefinition(
    key: 'sleep',
    label: 'Sleep',
    levels: ['normal', 'disrupted', 'heavy'],
  ),
  SymptomDefinition(
    key: 'bowel',
    label: 'Bowel',
    levels: ['normal', 'constipation', 'frequent'],
  ),
  SymptomDefinition(
    key: 'appetite',
    label: 'Appetite',
    levels: ['normal', 'disrupted', 'heavy'],
  ),
  SymptomDefinition(
    key: 'digestion',
    label: 'Digestion',
    levels: ['normal', 'poor', 'heavy'],
  ),
  SymptomDefinition(
    key: 'stress',
    label: 'Stress',
    levels: ['normal', 'heavy', 'poor'],
  ),
  SymptomDefinition(
    key: 'micturition',
    label: 'Micturition',
    levels: ['normal', 'frequent', 'low'],
  ),
  SymptomDefinition(
    key: 'tolerance',
    label: 'Tolerance',
    levels: ['normal', 'hot', 'cold'],
  ),
  SymptomDefinition(
    key: 'menstruation',
    label: 'Menstruation',
    levels: ['normal', 'scanty', 'heavy'],
    femaleOnly: true,
  ),
  SymptomDefinition(
    key: 'lmp',
    label: 'LMP',
    levels: [],
    isDate: true,
    femaleOnly: true,
  ),
];

SymptomDefinition? symptomByKey(String key) {
  for (final s in kSymptoms) {
    if (s.key == key) return s;
  }
  return null;
}

/// Dosing schedules offered for every formulation.
///
/// These are the standard prescribing abbreviations used in the source data.
enum Dose {
  od('OD', 'Once daily'),
  bd('BD', 'Twice daily'),
  hs('Hs', 'At bedtime'),
  tds('TDS', 'Three times daily'),
  eod('EOD', 'Every other day');

  const Dose(this.code, this.description);

  final String code;
  final String description;

  static Dose fromCode(String code) => Dose.values
      .firstWhere((d) => d.code == code, orElse: () => Dose.od);

  /// Units consumed per day, used to size a dispensed quantity.
  double get perDay => switch (this) {
        Dose.od => 1,
        Dose.bd => 2,
        Dose.hs => 1,
        Dose.tds => 3,
        Dose.eod => 0.5,
      };
}

/// Dispensable forms of a medicine.
enum MedicineForm {
  tablet,
  capsule,
  syrup,
  powder,
  oil;

  static MedicineForm fromName(String value) => MedicineForm.values
      .firstWhere((f) => f.name == value, orElse: () => MedicineForm.tablet);

  String get label => switch (this) {
        MedicineForm.tablet => 'Tablet',
        MedicineForm.capsule => 'Capsule',
        MedicineForm.syrup => 'Syrup',
        MedicineForm.powder => 'Powder',
        MedicineForm.oil => 'Oil',
      };
}

/// Formulary shipped with a fresh install, from `DataCalls.org`.
const List<({String name, MedicineForm form})> kFormulary = [
  (name: 'Adhya', form: MedicineForm.tablet),
  (name: 'Awipatti', form: MedicineForm.tablet),
  (name: 'Madhuparni', form: MedicineForm.tablet),
  (name: 'Lekhniya', form: MedicineForm.tablet),
  (name: 'Vrahkarni', form: MedicineForm.tablet),
  (name: 'Rakta Shodak', form: MedicineForm.tablet),
  (name: 'Medhya Rasayan', form: MedicineForm.tablet),
  (name: 'Calvera', form: MedicineForm.tablet),
  (name: 'Punarnava', form: MedicineForm.capsule),
  (name: 'Maarkhav', form: MedicineForm.capsule),
  (name: 'Cystolve', form: MedicineForm.tablet),
  (name: 'Cystolve', form: MedicineForm.capsule),
];

/// Lifecycle of a booked appointment.
enum AppointmentStatus {
  scheduled,
  completed,
  cancelled,
  noShow;

  static AppointmentStatus fromName(String value) =>
      AppointmentStatus.values.firstWhere((s) => s.name == value,
          orElse: () => AppointmentStatus.scheduled);

  String get label => switch (this) {
        AppointmentStatus.scheduled => 'Scheduled',
        AppointmentStatus.completed => 'Completed',
        AppointmentStatus.cancelled => 'Cancelled',
        AppointmentStatus.noShow => 'No show',
      };
}
