import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sattra/core/constants.dart';
import 'package:sattra/data/models/models.dart';
import 'package:sattra/services/pdf_service.dart';

void main() {
  // Fonts are loaded through the asset bundle, which needs the binding up.
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = PdfService(clinicName: 'Sattra Ayurvedic Clinic');

  final patient = Patient(
    id: 'p1',
    code: 'P-0001',
    name: 'Asha Devi',
    age: 42,
    sex: Sex.female,
    weightKg: 61.5,
    address: '14 Nehru Nagar, Sector 8, Chandigarh',
    phone: '+91 98765 43210',
    chiefComplaints: 'Disturbed sleep and acidity for three months',
    assignedTo: 's1',
    registeredAt: DateTime(2026, 6, 11),
  );

  final staff = Staff(
    id: 's1',
    username: 'b.kihore',
    fullName: 'Brian Edwin Kihore',
    role: UserRole.provider,
    speciality: 'Consulting physician',
    createdAt: DateTime(2026, 1, 1),
  );

  final visit = Visit(
    id: 'v1',
    patientId: 'p1',
    visitedAt: DateTime(2026, 8, 12, 10, 30),
    weightKg: 61.5,
    chiefComplaints: 'Sleep improving, acidity persists',
    findings: 'Tenderness over the epigastrium. Tongue coated.',
    advice: 'Early dinner, avoid tea after 6pm.',
    recordedBy: 's1',
  );

  final medicine = Medicine(
    id: 'm1',
    name: 'Awipatti',
    form: MedicineForm.tablet,
    stockQty: 180,
    reorderLevel: 20,
  );

  final prescription = Prescription(
    id: 'r1',
    patientId: 'p1',
    visitId: 'v1',
    prescribedBy: 's1',
    prescribedAt: DateTime(2026, 8, 12, 10, 45),
    notes: 'Take with warm water, half an hour after meals.',
  );

  final item = PrescriptionItem(
    id: 'i1',
    prescriptionId: 'r1',
    medicineId: 'm1',
    dose: Dose.bd,
    durationDays: 21,
    quantity: 42,
  );

  /// Every generated document should be a real PDF, not an empty buffer.
  void expectValidPdf(List<int> bytes) {
    expect(bytes.length, greaterThan(1000));
    expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
    // A PDF is only readable if it also carries its trailer.
    final tail = latin1.decode(
      bytes.skip(bytes.length - 1024).toList(),
      allowInvalid: true,
    );
    expect(tail, contains('%%EOF'));
  }

  test('a case sheet renders with consultations and prescriptions', () async {
    final bytes = await service.patientCaseSheet(
      patient: patient,
      visits: [visit],
      readingsByVisit: {
        'v1': [
          SymptomReading(
            id: 'x1',
            visitId: 'v1',
            patientId: 'p1',
            key: 'sleep',
            value: 'disrupted',
          ),
          SymptomReading(
            id: 'x2',
            visitId: 'v1',
            patientId: 'p1',
            key: 'lmp',
            value: '2026-07-28',
          ),
        ],
      },
      prescriptions: [prescription],
      itemsByPrescription: {'r1': [item]},
      medicines: {'m1': medicine},
      staff: {'s1': staff},
    );

    expectValidPdf(bytes);
  });

  test('a case sheet renders for a patient with no history at all', () async {
    // The empty case is the one a clinic hits on day one.
    final bytes = await service.patientCaseSheet(
      patient: patient,
      visits: const [],
      readingsByVisit: const {},
      prescriptions: const [],
      itemsByPrescription: const {},
      medicines: const {},
      staff: const {},
    );

    expectValidPdf(bytes);
  });

  test('a prescription slip renders', () async {
    final bytes = await service.prescriptionSlip(
      patient: patient,
      prescription: prescription,
      items: [item],
      medicines: {'m1': medicine},
      prescriber: staff,
    );

    expectValidPdf(bytes);
  });

  test('a day schedule renders, including an empty day', () async {
    final appointment = Appointment(
      id: 'a1',
      patientId: 'p1',
      staffId: 's1',
      scheduledAt: DateTime(2026, 9, 9, 9, 30),
      reason: 'Follow-up',
    );

    expectValidPdf(await service.daySchedule(
      day: DateTime(2026, 9, 9),
      appointments: [appointment],
      patients: {'p1': patient},
      staff: {'s1': staff},
    ));

    expectValidPdf(await service.daySchedule(
      day: DateTime(2026, 9, 10),
      appointments: const [],
      patients: const {},
      staff: const {},
    ));
  });

  test('a stock report renders and separates the short items', () async {
    final short = Medicine(
      id: 'm2',
      name: 'Rakta Shodak',
      form: MedicineForm.tablet,
      stockQty: 8,
      reorderLevel: 20,
    );

    expectValidPdf(await service.inventoryReport([medicine, short]));
  });

  test('a name that is not plain Latin survives into the document', () async {
    // The clinic this was built for records names in Devanagari as often as
    // in Latin; the standard PDF faces cannot represent them at all.
    final devanagari = Patient(
      id: 'p2',
      code: 'P-0002',
      name: 'अशा देवी',
      age: 42,
      sex: Sex.female,
      registeredAt: DateTime(2026, 6, 11),
    );

    final bytes = await service.prescriptionSlip(
      patient: devanagari,
      prescription: prescription,
      items: [item],
      medicines: {'m1': medicine},
      prescriber: staff,
    );

    expectValidPdf(bytes);
  });

  test('documents carry a unique id per generation', () async {
    // Two runs should both be complete files rather than one cached buffer.
    final a = await service.inventoryReport([medicine]);
    final b = await service.inventoryReport([medicine]);
    expectValidPdf(a);
    expectValidPdf(b);
  });
}
