/// Row-backed domain models.
///
/// Each model maps one-to-one onto a table and knows how to read itself from a
/// query row. Writes go through the repositories, which own the sync columns.
library;

import '../../core/constants.dart';

int _int(Object? v, [int fallback = 0]) =>
    v == null ? fallback : (v as num).toInt();
double? _dbl(Object? v) => v == null ? null : (v as num).toDouble();
String _str(Object? v, [String fallback = '']) => (v as String?) ?? fallback;
bool _bool(Object? v) => _int(v) != 0;
DateTime _time(Object? v) =>
    DateTime.fromMillisecondsSinceEpoch(_int(v));

/// A member of clinic staff and, equivalently, a login.
class Staff {
  Staff({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.speciality,
    this.phone,
    this.email,
    this.active = true,
    this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String username;
  final String fullName;
  final UserRole role;
  final String? speciality;
  final String? phone;
  final String? email;
  final bool active;
  final String? createdBy;
  final DateTime createdAt;

  bool get isAdmin => role == UserRole.admin;

  /// Initials for the avatar chip in the shell.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory Staff.fromRow(Map<String, Object?> r) => Staff(
        id: _str(r['id']),
        username: _str(r['username']),
        fullName: _str(r['full_name']),
        role: UserRole.fromName(_str(r['role'], 'provider')),
        speciality: r['speciality'] as String?,
        phone: r['phone'] as String?,
        email: r['email'] as String?,
        active: _bool(r['active']),
        createdBy: r['created_by'] as String?,
        createdAt: _time(r['created_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'role': role.name,
        'speciality': speciality,
        'phone': phone,
        'email': email,
        'active': active ? 1 : 0,
        'created_by': createdBy,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  Staff copyWith({
    String? username,
    String? fullName,
    UserRole? role,
    String? speciality,
    String? phone,
    String? email,
    bool? active,
  }) =>
      Staff(
        id: id,
        username: username ?? this.username,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
        speciality: speciality ?? this.speciality,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        active: active ?? this.active,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}

class Patient {
  Patient({
    required this.id,
    required this.code,
    required this.name,
    this.age,
    this.sex = Sex.other,
    this.weightKg,
    this.address,
    this.phone,
    this.chiefComplaints,
    this.notes,
    this.assignedTo,
    required this.registeredAt,
  });

  final String id;

  /// Human-facing record number, e.g. `P-0042`.
  final String code;
  final String name;
  final int? age;
  final Sex sex;
  final double? weightKg;
  final String? address;
  final String? phone;
  final String? chiefComplaints;
  final String? notes;

  /// Staff member responsible for this patient.
  final String? assignedTo;
  final DateTime registeredAt;

  factory Patient.fromRow(Map<String, Object?> r) => Patient(
        id: _str(r['id']),
        code: _str(r['code']),
        name: _str(r['name']),
        age: r['age'] == null ? null : _int(r['age']),
        sex: Sex.fromName(_str(r['sex'], 'other')),
        weightKg: _dbl(r['weight_kg']),
        address: r['address'] as String?,
        phone: r['phone'] as String?,
        chiefComplaints: r['chief_complaints'] as String?,
        notes: r['notes'] as String?,
        assignedTo: r['assigned_to'] as String?,
        registeredAt: _time(r['registered_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'code': code,
        'name': name,
        'age': age,
        'sex': sex.name,
        'weight_kg': weightKg,
        'address': address,
        'phone': phone,
        'chief_complaints': chiefComplaints,
        'notes': notes,
        'assigned_to': assignedTo,
        'registered_at': registeredAt.millisecondsSinceEpoch,
      };

  Patient copyWith({
    String? code,
    String? name,
    int? age,
    Sex? sex,
    double? weightKg,
    String? address,
    String? phone,
    String? chiefComplaints,
    String? notes,
    String? assignedTo,
    bool clearAssignedTo = false,
  }) =>
      Patient(
        id: id,
        code: code ?? this.code,
        name: name ?? this.name,
        age: age ?? this.age,
        sex: sex ?? this.sex,
        weightKg: weightKg ?? this.weightKg,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        chiefComplaints: chiefComplaints ?? this.chiefComplaints,
        notes: notes ?? this.notes,
        assignedTo: clearAssignedTo ? null : (assignedTo ?? this.assignedTo),
        registeredAt: registeredAt,
      );
}

/// One consultation, and the anchor for the symptom readings taken during it.
class Visit {
  Visit({
    required this.id,
    required this.patientId,
    this.appointmentId,
    required this.visitedAt,
    this.weightKg,
    this.chiefComplaints,
    this.findings,
    this.advice,
    this.recordedBy,
  });

  final String id;
  final String patientId;
  final String? appointmentId;
  final DateTime visitedAt;
  final double? weightKg;
  final String? chiefComplaints;
  final String? findings;
  final String? advice;
  final String? recordedBy;

  factory Visit.fromRow(Map<String, Object?> r) => Visit(
        id: _str(r['id']),
        patientId: _str(r['patient_id']),
        appointmentId: r['appointment_id'] as String?,
        visitedAt: _time(r['visited_at']),
        weightKg: _dbl(r['weight_kg']),
        chiefComplaints: r['chief_complaints'] as String?,
        findings: r['findings'] as String?,
        advice: r['advice'] as String?,
        recordedBy: r['recorded_by'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'patient_id': patientId,
        'appointment_id': appointmentId,
        'visited_at': visitedAt.millisecondsSinceEpoch,
        'weight_kg': weightKg,
        'chief_complaints': chiefComplaints,
        'findings': findings,
        'advice': advice,
        'recorded_by': recordedBy,
      };
}

/// A single graded symptom reading. For `lmp` the value is an ISO date.
class SymptomReading {
  SymptomReading({
    required this.id,
    required this.visitId,
    required this.patientId,
    required this.key,
    required this.value,
  });

  final String id;
  final String visitId;
  final String patientId;
  final String key;
  final String value;

  SymptomDefinition? get definition => symptomByKey(key);

  /// True when the reading is anything other than the baseline level.
  bool get isNotable {
    final def = definition;
    if (def == null || def.isDate || def.levels.isEmpty) return false;
    return value != def.levels.first;
  }

  factory SymptomReading.fromRow(Map<String, Object?> r) => SymptomReading(
        id: _str(r['id']),
        visitId: _str(r['visit_id']),
        patientId: _str(r['patient_id']),
        key: _str(r['key']),
        value: _str(r['value']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'visit_id': visitId,
        'patient_id': patientId,
        'key': key,
        'value': value,
      };
}

class Medicine {
  Medicine({
    required this.id,
    required this.name,
    required this.form,
    this.strength,
    this.unit = 'unit',
    this.stockQty = 0,
    this.reorderLevel = 0,
    this.notes,
  });

  final String id;
  final String name;
  final MedicineForm form;
  final String? strength;
  final String unit;
  final int stockQty;
  final int reorderLevel;
  final String? notes;

  /// Name as the clinic writes it on a slip, e.g. "Punarnava Capsule".
  String get displayName => '$name ${form.label}';

  bool get isLow => stockQty <= reorderLevel;
  bool get isOut => stockQty <= 0;

  factory Medicine.fromRow(Map<String, Object?> r) => Medicine(
        id: _str(r['id']),
        name: _str(r['name']),
        form: MedicineForm.fromName(_str(r['form'], 'tablet')),
        strength: r['strength'] as String?,
        unit: _str(r['unit'], 'unit'),
        stockQty: _int(r['stock_qty']),
        reorderLevel: _int(r['reorder_level']),
        notes: r['notes'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'form': form.name,
        'strength': strength,
        'unit': unit,
        'stock_qty': stockQty,
        'reorder_level': reorderLevel,
        'notes': notes,
      };

  Medicine copyWith({
    String? name,
    MedicineForm? form,
    String? strength,
    String? unit,
    int? stockQty,
    int? reorderLevel,
    String? notes,
  }) =>
      Medicine(
        id: id,
        name: name ?? this.name,
        form: form ?? this.form,
        strength: strength ?? this.strength,
        unit: unit ?? this.unit,
        stockQty: stockQty ?? this.stockQty,
        reorderLevel: reorderLevel ?? this.reorderLevel,
        notes: notes ?? this.notes,
      );
}

/// An entry in the append-only stock ledger.
class StockMovement {
  StockMovement({
    required this.id,
    required this.medicineId,
    required this.delta,
    required this.reason,
    this.reference,
    required this.movedAt,
    this.byUser,
  });

  final String id;
  final String medicineId;

  /// Positive for intake, negative for dispensing or wastage.
  final int delta;
  final String reason;
  final String? reference;
  final DateTime movedAt;
  final String? byUser;

  factory StockMovement.fromRow(Map<String, Object?> r) => StockMovement(
        id: _str(r['id']),
        medicineId: _str(r['medicine_id']),
        delta: _int(r['delta']),
        reason: _str(r['reason']),
        reference: r['reference'] as String?,
        movedAt: _time(r['moved_at']),
        byUser: r['by_user'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'medicine_id': medicineId,
        'delta': delta,
        'reason': reason,
        'reference': reference,
        'moved_at': movedAt.millisecondsSinceEpoch,
        'by_user': byUser,
      };
}

class Prescription {
  Prescription({
    required this.id,
    required this.patientId,
    this.visitId,
    this.prescribedBy,
    required this.prescribedAt,
    this.notes,
    this.dispensed = false,
  });

  final String id;
  final String patientId;
  final String? visitId;
  final String? prescribedBy;
  final DateTime prescribedAt;
  final String? notes;

  /// Once dispensed the items have been deducted from stock.
  final bool dispensed;

  factory Prescription.fromRow(Map<String, Object?> r) => Prescription(
        id: _str(r['id']),
        patientId: _str(r['patient_id']),
        visitId: r['visit_id'] as String?,
        prescribedBy: r['prescribed_by'] as String?,
        prescribedAt: _time(r['prescribed_at']),
        notes: r['notes'] as String?,
        dispensed: _bool(r['dispensed']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'patient_id': patientId,
        'visit_id': visitId,
        'prescribed_by': prescribedBy,
        'prescribed_at': prescribedAt.millisecondsSinceEpoch,
        'notes': notes,
        'dispensed': dispensed ? 1 : 0,
      };
}

class PrescriptionItem {
  PrescriptionItem({
    required this.id,
    required this.prescriptionId,
    required this.medicineId,
    required this.dose,
    this.durationDays = 1,
    this.quantity = 0,
    this.instructions,
  });

  final String id;
  final String prescriptionId;
  final String medicineId;
  final Dose dose;
  final int durationDays;

  /// Units to hand over. Defaults to [suggestedQuantity] but the prescriber
  /// may override it.
  final int quantity;
  final String? instructions;

  /// Units implied by the schedule over the course length, rounded up.
  static int suggestedQuantity(Dose dose, int durationDays) =>
      (dose.perDay * durationDays).ceil();

  factory PrescriptionItem.fromRow(Map<String, Object?> r) => PrescriptionItem(
        id: _str(r['id']),
        prescriptionId: _str(r['prescription_id']),
        medicineId: _str(r['medicine_id']),
        dose: Dose.fromCode(_str(r['dose'], 'OD')),
        durationDays: _int(r['duration_days'], 1),
        quantity: _int(r['quantity']),
        instructions: r['instructions'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'prescription_id': prescriptionId,
        'medicine_id': medicineId,
        'dose': dose.code,
        'duration_days': durationDays,
        'quantity': quantity,
        'instructions': instructions,
      };

  PrescriptionItem copyWith({
    Dose? dose,
    int? durationDays,
    int? quantity,
    String? instructions,
  }) =>
      PrescriptionItem(
        id: id,
        prescriptionId: prescriptionId,
        medicineId: medicineId,
        dose: dose ?? this.dose,
        durationDays: durationDays ?? this.durationDays,
        quantity: quantity ?? this.quantity,
        instructions: instructions ?? this.instructions,
      );
}

class Appointment {
  Appointment({
    required this.id,
    required this.patientId,
    this.staffId,
    required this.scheduledAt,
    this.durationMin = 15,
    this.status = AppointmentStatus.scheduled,
    this.reason,
    this.notes,
    this.createdBy,
  });

  final String id;
  final String patientId;
  final String? staffId;
  final DateTime scheduledAt;
  final int durationMin;
  final AppointmentStatus status;
  final String? reason;
  final String? notes;
  final String? createdBy;

  DateTime get endsAt => scheduledAt.add(Duration(minutes: durationMin));

  bool overlaps(Appointment other) =>
      scheduledAt.isBefore(other.endsAt) && other.scheduledAt.isBefore(endsAt);

  factory Appointment.fromRow(Map<String, Object?> r) => Appointment(
        id: _str(r['id']),
        patientId: _str(r['patient_id']),
        staffId: r['staff_id'] as String?,
        scheduledAt: _time(r['scheduled_at']),
        durationMin: _int(r['duration_min'], 15),
        status: AppointmentStatus.fromName(_str(r['status'], 'scheduled')),
        reason: r['reason'] as String?,
        notes: r['notes'] as String?,
        createdBy: r['created_by'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'patient_id': patientId,
        'staff_id': staffId,
        'scheduled_at': scheduledAt.millisecondsSinceEpoch,
        'duration_min': durationMin,
        'status': status.name,
        'reason': reason,
        'notes': notes,
        'created_by': createdBy,
      };

  Appointment copyWith({
    String? patientId,
    String? staffId,
    DateTime? scheduledAt,
    int? durationMin,
    AppointmentStatus? status,
    String? reason,
    String? notes,
    bool clearStaff = false,
  }) =>
      Appointment(
        id: id,
        patientId: patientId ?? this.patientId,
        staffId: clearStaff ? null : (staffId ?? this.staffId),
        scheduledAt: scheduledAt ?? this.scheduledAt,
        durationMin: durationMin ?? this.durationMin,
        status: status ?? this.status,
        reason: reason ?? this.reason,
        notes: notes ?? this.notes,
        createdBy: createdBy,
      );
}

class AuditEntry {
  AuditEntry({
    required this.id,
    required this.at,
    this.userId,
    this.userName,
    required this.action,
    this.entity,
    this.entityId,
    this.detail,
  });

  final String id;
  final DateTime at;
  final String? userId;
  final String? userName;
  final String action;
  final String? entity;
  final String? entityId;
  final String? detail;

  factory AuditEntry.fromRow(Map<String, Object?> r) => AuditEntry(
        id: _str(r['id']),
        at: _time(r['at']),
        userId: r['user_id'] as String?,
        userName: r['user_name'] as String?,
        action: _str(r['action']),
        entity: r['entity'] as String?,
        entityId: r['entity_id'] as String?,
        detail: r['detail'] as String?,
      );
}
