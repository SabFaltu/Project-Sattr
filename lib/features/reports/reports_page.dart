import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../common/file_output.dart';
import '../common/widgets.dart';

/// One place to produce every printable document the clinic needs.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String? _patientId;
  DateTime _day = startOfDay(DateTime.now());
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    await guarded(context, job);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _caseSheet() => _run(() async {
        final state = context.read<AppState>();
        final patient = state.patients.byId(_patientId);
        if (patient == null) {
          notify(context, 'Choose a patient first.',
              title: 'No patient selected', severity: InfoBarSeverity.warning);
          return;
        }
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
          suggestedName: 'case-sheet-${patient.code.toLowerCase()}.pdf',
          successMessage: 'Case sheet saved',
        );
      });

  Future<void> _schedule() => _run(() async {
        final state = context.read<AppState>();
        final bytes = await state.pdf.daySchedule(
          day: _day,
          appointments: state.appointments.onDay(_day),
          patients: {for (final p in state.patients.search()) p.id: p},
          staff: {for (final s in state.staff.all()) s.id: s},
        );
        if (!mounted) return;
        await FileOutput.savePdf(
          context,
          bytes: bytes,
          suggestedName: 'schedule-${isoDate(_day)}.pdf',
          successMessage: 'Day schedule saved',
        );
      });

  Future<void> _stock() => _run(() async {
        final state = context.read<AppState>();
        final bytes = await state.pdf.inventoryReport(state.medicines.all());
        if (!mounted) return;
        await FileOutput.savePdf(
          context,
          bytes: bytes,
          suggestedName: 'stock-report-${isoDate(DateTime.now())}.pdf',
          successMessage: 'Stock report saved',
        );
      });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final patients = state.patients.search();

    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('Reports')),
      children: [
        SectionCard(
          title: 'Patient case sheet',
          subtitle: 'Demographics, every consultation with its symptom grid, '
              'and all prescriptions.',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Patient',
                  child: ComboBox<String>(
                    value: _patientId,
                    isExpanded: true,
                    placeholder: const Text('Choose a patient'),
                    items: [
                      for (final p in patients)
                        ComboBoxItem(
                          value: p.id,
                          child: Text('${p.name} · ${p.code}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _patientId = v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy || _patientId == null ? null : _caseSheet,
                child: const Text('Generate PDF'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Day schedule',
          subtitle: 'The appointment list for a single day, for the front desk.',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Day',
                  child: DatePicker(
                    selected: _day,
                    onChanged: (v) => setState(() => _day = startOfDay(v)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${state.appointments.countOn(_day)} booked',
                style: FluentTheme.of(context).typography.caption,
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy ? null : _schedule,
                child: const Text('Generate PDF'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Stock report',
          subtitle: 'Everything on hand, with items below their reorder level '
              'listed first.',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${state.medicines.lowStock().length} of '
                  '${state.medicines.all().length} items need reordering.',
                  style: FluentTheme.of(context).typography.body,
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : _stock,
                child: const Text('Generate PDF'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ActivityLog(entries: state.audit.recent(limit: 60)),
      ],
    );
  }
}

class _ActivityLog extends StatelessWidget {
  const _ActivityLog({required this.entries});

  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SectionCard(
      title: 'Activity log',
      subtitle: 'Every change is attributed to the account that made it.',
      child: SizedBox(
        height: 300,
        child: entries.isEmpty
            ? const EmptyState(
                icon: FluentIcons.history_24_regular,
                title: 'Nothing recorded yet',
              )
            : ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(
                            fmtDateTime(entry.at),
                            style: theme.typography.caption?.copyWith(
                              color: theme.resources.textFillColorSecondary,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: Text(
                            entry.userName ?? 'System',
                            style: theme.typography.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: Text(
                            entry.action,
                            style: theme.typography.caption?.copyWith(
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.detail ?? '',
                            style: theme.typography.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
