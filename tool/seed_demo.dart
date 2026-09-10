// Fills a database with a plausible day in a small clinic, for demos and for
// looking at the interface with something in it.
//
//   dart run tool/seed_demo.dart [directory]
//
// Writes `sattra.db` into the given directory (default: ./demo-data). Point the
// application at it with SATTRA_DATA_DIR to see the result.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sattra/core/constants.dart';
import 'package:sattra/core/ids.dart';
import 'package:sattra/data/db/app_database.dart';
import 'package:sattra/data/models/models.dart';
import 'package:sattra/data/repos/repositories.dart';
import 'package:sattra/services/credential_store.dart';
import 'package:sattra/services/settings_service.dart';

Future<void> main(List<String> args) async {
  final dir = args.isEmpty ? 'demo-data' : args.first;
  final path = p.join(dir, 'sattra.db');
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  for (final suffix in ['-wal', '-shm']) {
    final extra = File('$path$suffix');
    if (extra.existsSync()) extra.deleteSync();
  }

  final db = AppDatabase.open(path);
  SettingsService(db)
    ..clinicName = 'Sattra Ayurvedic Clinic'
    ..mode = DeploymentMode.standalone
    ..markSeeded();
  final credentials = CredentialStore(db);
  final audit = AuditRepository(db);
  final staffRepo = StaffRepository(db, audit);
  final patients = PatientRepository(db, audit);
  final medicines = MedicineRepository(db, audit);
  final prescriptions = PrescriptionRepository(db, audit, medicines);
  final appointments = AppointmentRepository(db, audit);

  // ---- Staff -------------------------------------------------------------
  final admin = staffRepo.create(
    username: 's.sharma',
    fullName: 'Saksham Sharma',
    role: UserRole.admin,
    speciality: 'Clinic administrator',
    phone: '+91 98110 22110',
  );
  await credentials.setPassword(admin.id, 'sattra123');

  final doctor = staffRepo.create(
    username: 'b.kihore',
    fullName: 'Brian Edwin Kihore',
    role: UserRole.provider,
    speciality: 'Consulting physician',
    by: admin,
  );
  await credentials.setPassword(doctor.id, 'sattra123');

  final nurse = staffRepo.create(
    username: 's.shandil',
    fullName: 'Sparsh Shandil',
    role: UserRole.provider,
    speciality: 'Panchakarma therapist',
    by: admin,
  );
  await credentials.setPassword(nurse.id, 'sattra123');

  // ---- Pharmacy ----------------------------------------------------------
  medicines.seedFormulary();
  final stockLevels = <String, int>{
    'Adhya': 240,
    'Awipatti': 180,
    'Madhuparni': 60,
    'Lekhniya': 15, // deliberately short, so the dashboard has something to say
    'Vrahkarni': 200,
    'Rakta Shodak': 8, // nearly out
    'Medhya Rasayan': 150,
    'Calvera': 95,
    'Punarnava': 120,
    'Maarkhav': 45,
    'Cystolve': 70,
  };
  for (final medicine in medicines.all()) {
    final qty = stockLevels[medicine.name] ?? 100;
    medicines.adjustStock(
      medicine,
      qty,
      reason: 'Opening stock count',
      by: admin,
    );
  }

  // ---- Patients ----------------------------------------------------------
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final roster = <({
    String name,
    int age,
    Sex sex,
    double weight,
    String address,
    String phone,
    String complaint,
    String staffId,
  })>[
    (
      name: 'Asha Devi',
      age: 42,
      sex: Sex.female,
      weight: 61.5,
      address: '14 Nehru Nagar, Sector 8, Chandigarh',
      phone: '+91 98765 43210',
      complaint: 'Disturbed sleep and acidity for three months',
      staffId: doctor.id,
    ),
    (
      name: 'Ramesh Kumar',
      age: 58,
      sex: Sex.male,
      weight: 78.0,
      address: '3/221 Model Town, Ludhiana',
      phone: '+91 99887 66554',
      complaint: 'Joint pain in both knees, worse in the mornings',
      staffId: doctor.id,
    ),
    (
      name: 'Priya Nair',
      age: 29,
      sex: Sex.female,
      weight: 54.2,
      address: '8 Rose Villa, Panchkula',
      phone: '+91 90123 45678',
      complaint: 'Irregular cycles and fatigue',
      staffId: nurse.id,
    ),
    (
      name: 'Gurpreet Singh',
      age: 35,
      sex: Sex.male,
      weight: 84.7,
      address: 'Village Kharar, Mohali',
      phone: '+91 97555 12345',
      complaint: 'Recurrent burning micturition',
      staffId: doctor.id,
    ),
    (
      name: 'Lakshmi Iyer',
      age: 66,
      sex: Sex.female,
      weight: 58.9,
      address: '22 Lake View, Sector 42, Chandigarh',
      phone: '+91 98000 11223',
      complaint: 'Poor appetite and weakness after a long illness',
      staffId: nurse.id,
    ),
    (
      name: 'Imran Sheikh',
      age: 24,
      sex: Sex.male,
      weight: 67.3,
      address: '5 Station Road, Zirakpur',
      phone: '+91 96444 55667',
      complaint: 'Skin eruptions on the forearms',
      staffId: doctor.id,
    ),
  ];

  final created = <Patient>[];
  for (var i = 0; i < roster.length; i++) {
    final entry = roster[i];
    final patient = patients.create(
      Patient(
        id: newId(),
        code: patients.nextCode(),
        name: entry.name,
        age: entry.age,
        sex: entry.sex,
        weightKg: entry.weight,
        address: entry.address,
        phone: entry.phone,
        chiefComplaints: entry.complaint,
        assignedTo: entry.staffId,
        registeredAt: today.subtract(Duration(days: 90 - i * 12)),
      ),
      by: admin,
    );
    created.add(patient);
  }

  // ---- Consultations, with a symptom picture that moves ------------------
  final grids = <String, List<Map<String, String>>>{
    'Asha Devi': [
      {
        'sleep': 'disrupted',
        'bowel': 'constipation',
        'appetite': 'disrupted',
        'digestion': 'poor',
        'stress': 'heavy',
        'micturition': 'normal',
        'tolerance': 'hot',
        'menstruation': 'scanty',
      },
      {
        'sleep': 'normal',
        'bowel': 'normal',
        'appetite': 'normal',
        'digestion': 'normal',
        'stress': 'heavy',
        'micturition': 'normal',
        'tolerance': 'hot',
        'menstruation': 'normal',
      },
    ],
    'Ramesh Kumar': [
      {
        'sleep': 'disrupted',
        'bowel': 'constipation',
        'appetite': 'normal',
        'digestion': 'poor',
        'stress': 'normal',
        'micturition': 'frequent',
        'tolerance': 'cold',
      },
    ],
    'Priya Nair': [
      {
        'sleep': 'disrupted',
        'bowel': 'normal',
        'appetite': 'disrupted',
        'digestion': 'normal',
        'stress': 'heavy',
        'micturition': 'normal',
        'tolerance': 'cold',
        'menstruation': 'scanty',
      },
    ],
    'Gurpreet Singh': [
      {
        'sleep': 'normal',
        'bowel': 'normal',
        'appetite': 'normal',
        'digestion': 'normal',
        'stress': 'normal',
        'micturition': 'frequent',
        'tolerance': 'hot',
      },
    ],
    'Lakshmi Iyer': [
      {
        'sleep': 'heavy',
        'bowel': 'frequent',
        'appetite': 'disrupted',
        'digestion': 'poor',
        'stress': 'poor',
        'micturition': 'low',
        'tolerance': 'cold',
      },
    ],
  };

  final findings = <String, String>{
    'Asha Devi': 'Pulse regular. Tenderness over the epigastrium. '
        'Tongue coated.',
    'Ramesh Kumar': 'Crepitus in both knees. No effusion. Gait antalgic.',
    'Priya Nair': 'Pallor present. Thyroid not enlarged.',
    'Gurpreet Singh': 'No suprapubic tenderness. Urine routine advised.',
    'Lakshmi Iyer': 'Generalised weakness. Weight down 3 kg since last visit.',
  };

  final advice = <String, String>{
    'Asha Devi': 'Early dinner, avoid tea after 6pm. Review in four weeks.',
    'Ramesh Kumar': 'Warm oil massage twice weekly. Avoid stairs where possible.',
    'Priya Nair': 'Iron-rich diet. Repeat haemogram before the next visit.',
    'Gurpreet Singh': 'Increase fluids to three litres daily.',
    'Lakshmi Iyer': 'Small frequent meals. Family to assist with intake.',
  };

  for (final patient in created) {
    final sequence = grids[patient.name];
    if (sequence == null) continue;
    for (var i = 0; i < sequence.length; i++) {
      // Oldest first, so the "latest reading" logic has something to resolve.
      final daysAgo = (sequence.length - i) * 28;
      final visitedAt = today.subtract(Duration(days: daysAgo, hours: -10));
      final grid = Map<String, String>.from(sequence[i]);
      if (patient.sex == Sex.female) {
        grid['lmp'] = isoDateOf(
          visitedAt.subtract(Duration(days: 12 + i * 3)),
        );
      }
      patients.recordVisit(
        Visit(
          id: newId(),
          patientId: patient.id,
          visitedAt: visitedAt,
          weightKg: patient.weightKg == null
              ? null
              : patient.weightKg! + (i == 0 ? 1.4 : 0),
          chiefComplaints: patient.chiefComplaints,
          findings: findings[patient.name],
          advice: advice[patient.name],
          recordedBy: patient.assignedTo,
        ),
        grid,
        by: staffRepo.byId(patient.assignedTo),
      );
    }
  }

  // ---- Prescriptions -----------------------------------------------------
  final formulary = {for (final m in medicines.all()) m.name: m};
  final scripts = <String, List<({String medicine, Dose dose, int days})>>{
    'Asha Devi': [
      (medicine: 'Awipatti', dose: Dose.bd, days: 21),
      (medicine: 'Medhya Rasayan', dose: Dose.hs, days: 30),
    ],
    'Ramesh Kumar': [
      (medicine: 'Vrahkarni', dose: Dose.tds, days: 14),
      (medicine: 'Calvera', dose: Dose.bd, days: 30),
    ],
    'Priya Nair': [
      (medicine: 'Punarnava', dose: Dose.bd, days: 21),
    ],
    'Gurpreet Singh': [
      (medicine: 'Cystolve', dose: Dose.tds, days: 10),
    ],
    'Imran Sheikh': [
      (medicine: 'Rakta Shodak', dose: Dose.bd, days: 30),
    ],
  };

  for (final patient in created) {
    final lines = scripts[patient.name];
    if (lines == null) continue;
    final prescription = Prescription(
      id: newId(),
      patientId: patient.id,
      prescribedBy: patient.assignedTo,
      prescribedAt: today.subtract(const Duration(days: 2, hours: -11)),
      notes: 'Take with warm water, half an hour after meals.',
    );
    prescriptions.save(
      prescription,
      [
        for (final line in lines)
          if (formulary[line.medicine] != null)
            PrescriptionItem(
              id: newId(),
              prescriptionId: prescription.id,
              medicineId: formulary[line.medicine]!.id,
              dose: line.dose,
              durationDays: line.days,
              quantity:
                  PrescriptionItem.suggestedQuantity(line.dose, line.days),
              instructions: line.dose == Dose.hs ? 'At bedtime' : null,
            ),
      ],
      by: staffRepo.byId(patient.assignedTo),
    );
    // Leave the most recent two waiting at the counter, so the dispensing
    // queue is not empty.
    if (patient.name != 'Imran Sheikh' && patient.name != 'Gurpreet Singh') {
      prescriptions.dispense(prescription, by: admin);
    }
  }

  // ---- The diary ---------------------------------------------------------
  final bookings = <({int patient, int hour, int minute, String reason, String staffId, AppointmentStatus status})>[
    (patient: 0, hour: 9, minute: 30, reason: 'Follow-up — sleep and acidity', staffId: doctor.id, status: AppointmentStatus.completed),
    (patient: 1, hour: 10, minute: 0, reason: 'Knee pain review', staffId: doctor.id, status: AppointmentStatus.completed),
    (patient: 2, hour: 11, minute: 15, reason: 'Report review', staffId: nurse.id, status: AppointmentStatus.scheduled),
    (patient: 3, hour: 12, minute: 0, reason: 'Urine report discussion', staffId: doctor.id, status: AppointmentStatus.scheduled),
    (patient: 4, hour: 16, minute: 30, reason: 'Panchakarma session 3 of 7', staffId: nurse.id, status: AppointmentStatus.scheduled),
    (patient: 5, hour: 17, minute: 15, reason: 'Skin review', staffId: doctor.id, status: AppointmentStatus.scheduled),
  ];

  for (final booking in bookings) {
    appointments.save(
      Appointment(
        id: newId(),
        patientId: created[booking.patient].id,
        staffId: booking.staffId,
        scheduledAt: today.add(
          Duration(hours: booking.hour, minutes: booking.minute),
        ),
        durationMin: 20,
        status: booking.status,
        reason: booking.reason,
        createdBy: admin.id,
      ),
      by: admin,
    );
  }

  // A few bookings later in the week, so the week strip is not flat.
  for (var day = 1; day <= 4; day++) {
    appointments.save(
      Appointment(
        id: newId(),
        patientId: created[day % created.length].id,
        staffId: day.isEven ? doctor.id : nurse.id,
        scheduledAt: today.add(Duration(days: day, hours: 10 + day)),
        durationMin: 20,
        reason: 'Review',
        createdBy: admin.id,
      ),
      by: admin,
    );
  }

  db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  db.close();

  stdout.writeln('Seeded demo clinic at ${File(path).absolute.path}');
  stdout.writeln('  ${created.length} patients, '
      '${bookings.length} appointments today, '
      '${stockLevels.length} stocked medicines');
  stdout.writeln('  Sign in as s.sharma / sattra123 (administrator)');
  stdout.writeln('           or b.kihore / sattra123 (provider)');
  stdout.writeln('');
  stdout.writeln('Run against it with:');
  stdout.writeln('  SATTRA_DATA_DIR=${Directory(dir).absolute.path} '
      'flutter run -d linux');
}

/// Local copy of the ISO date helper, to keep this tool free of UI imports.
String isoDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
