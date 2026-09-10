import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/ids.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../common/widgets.dart';

/// Books or amends an appointment.
///
/// A clash with the same clinician is surfaced as a warning rather than a
/// block: clinics do double-book on purpose, and the person at the desk is
/// better placed to judge than the form is.
class AppointmentFormDialog extends StatefulWidget {
  const AppointmentFormDialog({
    super.key,
    this.patient,
    this.existing,
    this.initialDate,
  });

  final Patient? patient;
  final Appointment? existing;
  final DateTime? initialDate;

  static Future<bool?> show(
    BuildContext context, {
    Patient? patient,
    Appointment? existing,
    DateTime? initialDate,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AppointmentFormDialog(
          patient: patient,
          existing: existing,
          initialDate: initialDate,
        ),
      );

  @override
  State<AppointmentFormDialog> createState() => _AppointmentFormDialogState();
}

class _AppointmentFormDialogState extends State<AppointmentFormDialog> {
  late final TextEditingController _reason;
  late final TextEditingController _notes;

  String? _patientId;
  String? _staffId;
  late DateTime _date;
  late DateTime _time;
  int _duration = 15;
  AppointmentStatus _status = AppointmentStatus.scheduled;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _reason = TextEditingController(text: existing?.reason ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _patientId = existing?.patientId ?? widget.patient?.id;
    _staffId = existing?.staffId ?? widget.patient?.assignedTo;
    _duration = existing?.durationMin ?? 15;
    _status = existing?.status ?? AppointmentStatus.scheduled;

    final when = existing?.scheduledAt ??
        _nextSensibleSlot(widget.initialDate ?? DateTime.now());
    _date = DateTime(when.year, when.month, when.day);
    _time = when;
  }

  /// Defaults to the next quarter hour, or 9am if the chosen day is not today.
  static DateTime _nextSensibleSlot(DateTime day) {
    final now = DateTime.now();
    final isToday = startOfDay(day) == startOfDay(now);
    if (!isToday) return DateTime(day.year, day.month, day.day, 9);
    final minutes = ((now.minute ~/ 15) + 1) * 15;
    return DateTime(now.year, now.month, now.day, now.hour)
        .add(Duration(minutes: minutes));
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _scheduledAt =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  void _save() {
    final state = context.read<AppState>();
    if (_patientId == null) {
      setState(() => _error = 'Choose which patient this is for.');
      return;
    }
    final appointment = Appointment(
      id: widget.existing?.id ?? newId(),
      patientId: _patientId!,
      staffId: _staffId,
      scheduledAt: _scheduledAt,
      durationMin: _duration,
      status: _status,
      reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdBy: widget.existing?.createdBy ?? state.currentUser?.id,
    );
    state.appointments.save(appointment, by: state.currentUser);
    state.touch();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final patients = state.patients.search();
    final clinicians = state.staff.all(includeInactive: false);

    // Recomputed live so moving the time shows the clash disappearing.
    final clashes = _patientId == null
        ? const <Appointment>[]
        : state.appointments.conflictsFor(
            Appointment(
              id: widget.existing?.id ?? '',
              patientId: _patientId!,
              staffId: _staffId,
              scheduledAt: _scheduledAt,
              durationMin: _duration,
            ),
          );

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 620),
      title: Text(widget.existing == null
          ? 'Book an appointment'
          : 'Edit appointment'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) InlineMessage(message: _error!),
            if (clashes.isNotEmpty)
              InlineMessage(
                severity: InfoBarSeverity.warning,
                title: 'Overlaps another booking',
                message: clashes
                    .map((a) =>
                        '${fmtTime(a.scheduledAt)} — ${state.patients.byId(a.patientId)?.name ?? 'a patient'}')
                    .join('; '),
              ),
            LabeledField(
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
            const SizedBox(height: 12),
            LabeledField(
              label: 'With',
              child: ComboBox<String?>(
                value: _staffId,
                isExpanded: true,
                placeholder: const Text('Unassigned'),
                items: [
                  const ComboBoxItem<String?>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  for (final s in clinicians)
                    ComboBoxItem<String?>(
                      value: s.id,
                      child: Text(s.fullName),
                    ),
                ],
                onChanged: (v) => setState(() => _staffId = v),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: LabeledField(
                    label: 'Date',
                    child: DatePicker(
                      selected: _date,
                      onChanged: (v) => setState(() => _date = v),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: LabeledField(
                    label: 'Time',
                    child: TimePicker(
                      selected: _time,
                      onChanged: (v) => setState(() => _time = v),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: LabeledField(
                    label: 'Minutes',
                    child: NumberBox<int>(
                      value: _duration,
                      min: 5,
                      max: 240,
                      mode: SpinButtonPlacementMode.compact,
                      onChanged: (v) =>
                          setState(() => _duration = v ?? _duration),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Reason',
              child: TextBox(
                controller: _reason,
                placeholder: 'e.g. follow-up, review of reports',
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Notes',
              child: TextBox(controller: _notes, maxLines: 2),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 12),
              LabeledField(
                label: 'Status',
                child: ComboBox<AppointmentStatus>(
                  value: _status,
                  isExpanded: true,
                  items: [
                    for (final s in AppointmentStatus.values)
                      ComboBoxItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Ends at ${fmtTime(_scheduledAt.add(Duration(minutes: _duration)))}',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.existing == null ? 'Book' : 'Save changes'),
        ),
      ],
    );
  }
}
