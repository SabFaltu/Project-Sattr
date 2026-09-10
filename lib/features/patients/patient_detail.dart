import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../appointments/appointment_form.dart';
import '../common/file_output.dart';
import '../common/widgets.dart';
import '../prescriptions/prescription_form.dart';
import 'patient_form.dart';
import 'visit_form.dart';

/// Everything known about one patient, in four tabs.
class PatientDetail extends StatefulWidget {
  const PatientDetail({
    super.key,
    required this.patient,
    required this.onDeleted,
  });

  final Patient patient;
  final VoidCallback onDeleted;

  @override
  State<PatientDetail> createState() => _PatientDetailState();
}

class _PatientDetailState extends State<PatientDetail> {
  int _tab = 0;

  Patient get _patient =>
      context.read<AppState>().patients.byId(widget.patient.id) ??
      widget.patient;

  Future<void> _exportCaseSheet() async {
    final state = context.read<AppState>();
    final patient = _patient;
    await guarded(context, () async {
      final visits = state.patients.visitsFor(patient.id);
      final prescriptions = state.prescriptions.forPatient(patient.id);
      final bytes = await state.pdf.patientCaseSheet(
        patient: patient,
        visits: visits,
        readingsByVisit: {
          for (final v in visits) v.id: state.patients.symptomsFor(v.id),
        },
        prescriptions: prescriptions,
        itemsByPrescription: {
          for (final p in prescriptions)
            p.id: state.prescriptions.itemsFor(p.id),
        },
        medicines: {for (final m in state.medicines.all()) m.id: m},
        staff: {for (final s in state.staff.all()) s.id: s},
      );
      if (!mounted) return;
      await FileOutput.savePdf(
        context,
        bytes: bytes,
        suggestedName:
            'case-sheet-${patient.code.toLowerCase()}-${isoDate(DateTime.now())}.pdf',
        successMessage: 'Case sheet saved',
      );
    });
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    final patient = _patient;
    final ok = await confirm(
      context,
      title: 'Remove ${patient.name}?',
      message: 'The record is withdrawn from the register and stops appearing '
          'in lists and reports. Consultations already recorded are kept.',
      confirmLabel: 'Remove patient',
      destructive: true,
    );
    if (!ok) return;
    state.patients.delete(patient, by: state.currentUser);
    state.touch();
    widget.onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final patient = state.patients.byId(widget.patient.id);
    if (patient == null) return const SizedBox.shrink();
    final theme = FluentTheme.of(context);

    return Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  style: theme.typography.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // Wrap rather than Row: at narrow window widths these would
                // otherwise be squeezed until the text broke a letter per line.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusPill(patient.code, icon: FluentIcons.tag_20_regular),
                    StatusPill('${patient.age ?? '—'} · ${patient.sex.label}'),
                    StatusPill(fmtWeight(patient.weightKg)),
                  ],
                ),
                const SizedBox(height: 10),
                // The actions get the full width of the card and fold the ones
                // that do not fit into an overflow menu.
                CommandBar(
                  overflowBehavior: CommandBarOverflowBehavior.dynamicOverflow,
                  primaryItems: [
                    CommandBarButton(
                      icon: const Icon(FluentIcons.stethoscope_24_regular),
                      label: const Text('Consultation'),
                      onPressed: () => VisitFormDialog.show(
                        context,
                        patient: patient,
                      ),
                    ),
                    CommandBarButton(
                      icon: const Icon(
                          FluentIcons.document_bullet_list_24_regular),
                      label: const Text('Prescribe'),
                      onPressed: () => PrescriptionFormDialog.show(
                        context,
                        patient: patient,
                      ),
                    ),
                    CommandBarButton(
                      icon: const Icon(FluentIcons.calendar_add_24_regular),
                      label: const Text('Book'),
                      onPressed: () => AppointmentFormDialog.show(
                        context,
                        patient: patient,
                      ),
                    ),
                    CommandBarButton(
                      icon: const Icon(FluentIcons.document_pdf_24_regular),
                      label: const Text('Case sheet'),
                      onPressed: _exportCaseSheet,
                    ),
                    CommandBarButton(
                      icon: const Icon(FluentIcons.edit_24_regular),
                      label: const Text('Edit'),
                      onPressed: () =>
                          PatientFormDialog.show(context, existing: patient),
                    ),
                    CommandBarButton(
                      icon: const Icon(FluentIcons.delete_24_regular),
                      label: const Text('Remove'),
                      onPressed: _delete,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabView(
              currentIndex: _tab,
              onChanged: (i) => setState(() => _tab = i),
              closeButtonVisibility: CloseButtonVisibilityMode.never,
              tabWidthBehavior: TabWidthBehavior.sizeToContent,
              tabs: [
                Tab(
                  text: const Text('Overview'),
                  icon: const Icon(FluentIcons.person_24_regular),
                  body: _Overview(patient: patient),
                ),
                Tab(
                  text: Text(
                    'Consultations (${state.patients.visitsFor(patient.id).length})',
                  ),
                  icon: const Icon(FluentIcons.stethoscope_24_regular),
                  body: _Consultations(patient: patient),
                ),
                Tab(
                  text: Text(
                    'Prescriptions (${state.prescriptions.forPatient(patient.id).length})',
                  ),
                  icon: const Icon(
                      FluentIcons.document_bullet_list_24_regular),
                  body: _Prescriptions(patient: patient),
                ),
                Tab(
                  text: const Text('Appointments'),
                  icon: const Icon(FluentIcons.calendar_ltr_24_regular),
                  body: _Appointments(patient: patient),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final clinician = state.staff.byId(patient.assignedTo);
    final readings = state.patients.latestReadings(patient.id);
    final lastVisit = state.patients.latestVisit(patient.id);

    final details = SectionCard(
                  title: 'Details',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DetailRow('Record no.', patient.code),
                      DetailRow('Age', patient.age?.toString() ?? '—'),
                      DetailRow('Sex', patient.sex.label),
                      DetailRow('Weight', fmtWeight(patient.weightKg)),
                      DetailRow('Phone', patient.phone ?? ''),
                      DetailRow('Address', patient.address ?? ''),
                      DetailRow('Registered', fmtDate(patient.registeredAt)),
                      DetailRow(
                        'Under care of',
                        clinician?.fullName ?? 'Unassigned',
                      ),
                      DetailRow(
                        'Last seen',
                        lastVisit == null
                            ? 'Never'
                            : '${fmtDate(lastVisit.visitedAt)} (${relative(lastVisit.visitedAt)})',
                      ),
                    ],
                  ),
                );

    final narrative = Column(
      children: [
        SectionCard(
          title: 'Chief complaints',
          child: Text(
            (patient.chiefComplaints ?? '').isEmpty
                ? 'Nothing recorded.'
                : patient.chiefComplaints!,
            style: theme.typography.body,
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Notes',
          child: Text(
            (patient.notes ?? '').isEmpty
                ? 'Nothing recorded.'
                : patient.notes!,
            style: theme.typography.body,
          ),
        ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Side by side where there is room; stacked on a narrow window, so
          // neither column is squeezed to the point of breaking its text.
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 700) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    const SizedBox(height: 12),
                    narrative,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  Expanded(child: narrative),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Latest symptom picture',
            subtitle: readings.isEmpty
                ? 'No consultation has been recorded yet.'
                : 'Most recent grade for each symptom. Anything off baseline is '
                    'highlighted.',
            child: readings.isEmpty
                ? const SizedBox.shrink()
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final def in kSymptoms)
                        if (readings.containsKey(def.key))
                          _SymptomChip(
                            definition: def,
                            value: readings[def.key]!,
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SymptomChip extends StatelessWidget {
  const _SymptomChip({required this.definition, required this.value});

  final SymptomDefinition definition;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final notable =
        !definition.isDate && definition.levels.isNotEmpty && value != definition.levels.first;
    final tone = SattraTheme.symptomColor(notable, theme.brightness);
    final display =
        definition.isDate ? fmtDate(parseIsoDate(value)) : titleCase(value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: notable
            ? tone.withValues(alpha: 0.1)
            : theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: notable ? tone.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            definition.label.toUpperCase(),
            style: theme.typography.caption?.copyWith(
              fontSize: 9,
              letterSpacing: 0.6,
              color: theme.resources.textFillColorTertiary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            display,
            style: theme.typography.body?.copyWith(
              color: tone,
              fontWeight: notable ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _Consultations extends StatelessWidget {
  const _Consultations({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final visits = state.patients.visitsFor(patient.id);

    if (visits.isEmpty) {
      return EmptyState(
        icon: FluentIcons.stethoscope_24_regular,
        title: 'No consultations yet',
        message: 'Record one to start tracking how this patient is doing.',
        action: FilledButton(
          onPressed: () => VisitFormDialog.show(context, patient: patient),
          child: const Text('Record a consultation'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: visits.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final visit = visits[index];
        final readings = state.patients.symptomsFor(visit.id);
        final clinician = state.staff.byId(visit.recordedBy);
        return Expander(
          initiallyExpanded: index == 0,
          header: Row(
            children: [
              Expanded(
                child: Text(
                  fmtDateTime(visit.visitedAt),
                  style: theme.typography.bodyStrong,
                ),
              ),
              if (clinician != null)
                Text(
                  clinician.fullName,
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              const SizedBox(width: 10),
              StatusPill(fmtWeight(visit.weightKg)),
            ],
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((visit.chiefComplaints ?? '').isNotEmpty)
                DetailRow('Complaints', visit.chiefComplaints!),
              if ((visit.findings ?? '').isNotEmpty)
                DetailRow('Findings', visit.findings!),
              if ((visit.advice ?? '').isNotEmpty)
                DetailRow('Advice', visit.advice!),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final def in kSymptoms)
                    for (final r in readings)
                      if (r.key == def.key)
                        _SymptomChip(definition: def, value: r.value),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Button(
                  onPressed: () => VisitFormDialog.show(
                    context,
                    patient: patient,
                    existing: visit,
                  ),
                  child: const Text('Edit this consultation'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Prescriptions extends StatelessWidget {
  const _Prescriptions({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final prescriptions = state.prescriptions.forPatient(patient.id);

    if (prescriptions.isEmpty) {
      return EmptyState(
        icon: FluentIcons.document_bullet_list_24_regular,
        title: 'Nothing prescribed yet',
        action: FilledButton(
          onPressed: () =>
              PrescriptionFormDialog.show(context, patient: patient),
          child: const Text('Write a prescription'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: prescriptions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final prescription = prescriptions[index];
        final items = state.prescriptions.itemsFor(prescription.id);
        final prescriber = state.staff.byId(prescription.prescribedBy);

        return SectionCard(
          title: fmtDateTime(prescription.prescribedAt),
          subtitle: prescriber == null
              ? null
              : 'Prescribed by ${prescriber.fullName}',
          trailing: StatusPill(
            prescription.dispensed ? 'Dispensed' : 'Awaiting dispensing',
            color: prescription.dispensed ? SattraTheme.ok : SattraTheme.warn,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          state.medicines.byId(item.medicineId)?.displayName ??
                              'Unknown medicine',
                        ),
                      ),
                      Expanded(
                        child: Text(item.dose.code,
                            style: theme.typography.bodyStrong),
                      ),
                      Expanded(child: Text('${item.durationDays} days')),
                      Expanded(child: Text('${item.quantity} units')),
                    ],
                  ),
                ),
              if ((prescription.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  prescription.notes!,
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Button(
                    onPressed: () => PrescriptionFormDialog.show(
                      context,
                      patient: patient,
                      existing: prescription,
                    ),
                    child: const Text('Edit'),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () =>
                        _printSlip(context, state, prescription, items),
                    child: const Text('Print slip'),
                  ),
                  const SizedBox(width: 8),
                  if (!prescription.dispensed)
                    FilledButton(
                      onPressed: () => _dispense(context, state, prescription),
                      child: const Text('Dispense'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _dispense(
    BuildContext context,
    AppState state,
    Prescription prescription,
  ) async {
    final result =
        state.prescriptions.dispense(prescription, by: state.currentUser);
    state.touch();
    if (!context.mounted) return;
    if (result.ok) {
      notify(context, 'Stock has been deducted.', title: 'Dispensed');
    } else {
      notify(
        context,
        result.error!,
        title: 'Cannot dispense',
        severity: InfoBarSeverity.error,
      );
    }
  }

  Future<void> _printSlip(
    BuildContext context,
    AppState state,
    Prescription prescription,
    List<PrescriptionItem> items,
  ) async {
    await guarded(context, () async {
      final bytes = await state.pdf.prescriptionSlip(
        patient: patient,
        prescription: prescription,
        items: items,
        medicines: {for (final m in state.medicines.all()) m.id: m},
        prescriber: state.staff.byId(prescription.prescribedBy),
      );
      if (!context.mounted) return;
      await FileOutput.savePdf(
        context,
        bytes: bytes,
        suggestedName:
            'prescription-${patient.code.toLowerCase()}-${isoDate(prescription.prescribedAt)}.pdf',
        successMessage: 'Prescription slip saved',
      );
    });
  }
}

class _Appointments extends StatelessWidget {
  const _Appointments({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final appointments = state.appointments.forPatient(patient.id);

    if (appointments.isEmpty) {
      return EmptyState(
        icon: FluentIcons.calendar_ltr_24_regular,
        title: 'Nothing booked',
        action: FilledButton(
          onPressed: () => AppointmentFormDialog.show(context, patient: patient),
          child: const Text('Book an appointment'),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      itemBuilder: (context, index) {
        final appointment = appointments[index];
        final clinician = state.staff.byId(appointment.staffId);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.resources.subtleFillColorSecondary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtDateTime(appointment.scheduledAt)),
                      Text(
                        [
                          if (clinician != null) 'with ${clinician.fullName}',
                          if ((appointment.reason ?? '').isNotEmpty)
                            appointment.reason!,
                        ].join(' · '),
                        style: theme.typography.caption?.copyWith(
                          color: theme.resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusPill(appointment.status.label),
                const SizedBox(width: 8),
                Button(
                  onPressed: () => AppointmentFormDialog.show(
                    context,
                    patient: patient,
                    existing: appointment,
                  ),
                  child: const Text('Edit'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
