import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../common/file_output.dart';
import '../common/widgets.dart';
import 'prescription_form.dart';

/// Everything prescribed across the clinic, newest first — the view the
/// dispensing counter works from.
class PrescriptionsPage extends StatefulWidget {
  const PrescriptionsPage({super.key});

  @override
  State<PrescriptionsPage> createState() => _PrescriptionsPageState();
}

class _PrescriptionsPageState extends State<PrescriptionsPage> {
  bool _pendingOnly = true;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    var prescriptions = state.prescriptions.recent(limit: 200);
    if (_pendingOnly) {
      prescriptions = prescriptions.where((p) => !p.dispensed).toList();
    }

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Prescriptions'),
        commandBar: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              checked: _pendingOnly,
              onChanged: (v) => setState(() => _pendingOnly = v ?? false),
              content: const Text('Awaiting dispensing only'),
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Card(
          padding: const EdgeInsets.all(12),
          child: prescriptions.isEmpty
              ? EmptyState(
                  icon: FluentIcons.document_bullet_list_24_regular,
                  title: _pendingOnly
                      ? 'Nothing waiting to be dispensed'
                      : 'No prescriptions yet',
                  message: _pendingOnly
                      ? 'Everything written so far has been handed over.'
                      : 'Prescriptions are written from a patient\'s record.',
                )
              : ListView.separated(
                  itemCount: prescriptions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final prescription = prescriptions[index];
                    final patient =
                        state.patients.byId(prescription.patientId);
                    final items =
                        state.prescriptions.itemsFor(prescription.id);
                    final prescriber =
                        state.staff.byId(prescription.prescribedBy);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.resources.subtleFillColorSecondary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patient?.name ?? 'Unknown patient',
                                      style: theme.typography.bodyStrong,
                                    ),
                                    Text(
                                      [
                                        if (patient != null) patient.code,
                                        fmtDateTime(prescription.prescribedAt),
                                        if (prescriber != null)
                                          prescriber.fullName,
                                      ].join(' · '),
                                      style:
                                          theme.typography.caption?.copyWith(
                                        color: theme
                                            .resources.textFillColorSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              StatusPill(
                                prescription.dispensed
                                    ? 'Dispensed'
                                    : 'Awaiting dispensing',
                                color: prescription.dispensed
                                    ? SattraTheme.ok
                                    : SattraTheme.warn,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final item in items)
                                StatusPill(
                                  '${state.medicines.byId(item.medicineId)?.displayName ?? 'Unknown'} '
                                  '· ${item.dose.code} · ${item.quantity}',
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (patient != null) ...[
                                Button(
                                  onPressed: () => _printSlip(
                                    context,
                                    state,
                                    patient,
                                    prescription,
                                    items,
                                  ),
                                  child: const Text('Print slip'),
                                ),
                                const SizedBox(width: 8),
                                Button(
                                  onPressed: () =>
                                      PrescriptionFormDialog.show(
                                    context,
                                    patient: patient,
                                    existing: prescription,
                                  ),
                                  child: const Text('Edit'),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (!prescription.dispensed)
                                FilledButton(
                                  onPressed: () {
                                    final result = state.prescriptions
                                        .dispense(prescription,
                                            by: state.currentUser);
                                    state.touch();
                                    if (!context.mounted) return;
                                    notify(
                                      context,
                                      result.ok
                                          ? 'Stock has been deducted.'
                                          : result.error!,
                                      title: result.ok
                                          ? 'Dispensed'
                                          : 'Cannot dispense',
                                      severity: result.ok
                                          ? InfoBarSeverity.success
                                          : InfoBarSeverity.error,
                                    );
                                  },
                                  child: const Text('Dispense'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _printSlip(
    BuildContext context,
    AppState state,
    Patient patient,
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
