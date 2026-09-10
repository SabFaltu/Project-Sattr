import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/ids.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../common/widgets.dart';

/// Records a consultation and the symptom grid taken during it.
///
/// The grid is the clinic's own: nine rows, each graded against its own scale,
/// with the menstrual rows shown only where they apply. Grades default to the
/// last recorded value so a follow-up is a matter of changing what moved.
class VisitFormDialog extends StatefulWidget {
  const VisitFormDialog({
    super.key,
    required this.patient,
    this.existing,
    this.appointmentId,
  });

  final Patient patient;
  final Visit? existing;
  final String? appointmentId;

  static Future<bool?> show(
    BuildContext context, {
    required Patient patient,
    Visit? existing,
    String? appointmentId,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => VisitFormDialog(
          patient: patient,
          existing: existing,
          appointmentId: appointmentId,
        ),
      );

  @override
  State<VisitFormDialog> createState() => _VisitFormDialogState();
}

class _VisitFormDialogState extends State<VisitFormDialog> {
  late final TextEditingController _weight;
  late final TextEditingController _complaints;
  late final TextEditingController _findings;
  late final TextEditingController _advice;

  final Map<String, String> _readings = {};
  DateTime? _lmp;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final visit = widget.existing;

    _weight = TextEditingController(
      text: (visit?.weightKg ?? widget.patient.weightKg)?.toString() ?? '',
    );
    _complaints = TextEditingController(
      text: visit?.chiefComplaints ?? widget.patient.chiefComplaints ?? '',
    );
    _findings = TextEditingController(text: visit?.findings ?? '');
    _advice = TextEditingController(text: visit?.advice ?? '');

    // Seed from this visit if we are editing one, otherwise from whatever was
    // last recorded for the patient.
    final source = visit != null
        ? {
            for (final r in state.patients.symptomsFor(visit.id)) r.key: r.value,
          }
        : state.patients.latestReadings(widget.patient.id);

    for (final def in kSymptoms) {
      if (def.isDate) continue;
      _readings[def.key] = source[def.key] ?? def.levels.first;
    }
    _lmp = parseIsoDate(source['lmp']);
  }

  @override
  void dispose() {
    for (final c in [_weight, _complaints, _findings, _advice]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _showFemaleRows => widget.patient.sex == Sex.female;

  void _save() {
    final state = context.read<AppState>();
    final weightText = _weight.text.trim();
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);
    if (weightText.isNotEmpty && weight == null) {
      setState(() => _error = 'Weight must be a number, in kilograms.');
      return;
    }

    final visit = Visit(
      id: widget.existing?.id ?? newId(),
      patientId: widget.patient.id,
      appointmentId: widget.existing?.appointmentId ?? widget.appointmentId,
      visitedAt: widget.existing?.visitedAt ?? DateTime.now(),
      weightKg: weight,
      chiefComplaints:
          _complaints.text.trim().isEmpty ? null : _complaints.text.trim(),
      findings: _findings.text.trim().isEmpty ? null : _findings.text.trim(),
      advice: _advice.text.trim().isEmpty ? null : _advice.text.trim(),
      recordedBy: widget.existing?.recordedBy ?? state.currentUser?.id,
    );

    final readings = <String, String>{};
    for (final def in kSymptoms) {
      if (def.femaleOnly && !_showFemaleRows) continue;
      if (def.isDate) {
        if (_lmp != null) readings[def.key] = isoDate(_lmp!);
      } else {
        final value = _readings[def.key];
        if (value != null) readings[def.key] = value;
      }
    }

    state.patients.recordVisit(visit, readings, by: state.currentUser);
    state.touch();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
      title: Text(
        widget.existing == null
            ? 'New consultation — ${widget.patient.name}'
            : 'Edit consultation — ${fmtDateTime(widget.existing!.visitedAt)}',
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) InlineMessage(message: _error!),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Weight today',
                    child: TextBox(controller: _weight, placeholder: 'kg'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: LabeledField(
                    label: 'Chief complaints',
                    child: TextBox(controller: _complaints),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Symptom grid', style: theme.typography.bodyStrong),
            const SizedBox(height: 2),
            Text(
              'Each row starts at whatever was recorded last time.',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
            const SizedBox(height: 10),
            for (final def in kSymptoms)
              if (!def.femaleOnly || _showFemaleRows)
                _SymptomRow(
                  definition: def,
                  value: _readings[def.key],
                  date: _lmp,
                  onLevel: (v) => setState(() => _readings[def.key] = v),
                  onDate: (v) => setState(() => _lmp = v),
                ),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Findings',
              child: TextBox(controller: _findings, maxLines: 3),
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Advice',
              child: TextBox(controller: _advice, maxLines: 2),
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
          child: const Text('Save consultation'),
        ),
      ],
    );
  }
}

class _SymptomRow extends StatelessWidget {
  const _SymptomRow({
    required this.definition,
    required this.value,
    required this.date,
    required this.onLevel,
    required this.onDate,
  });

  final SymptomDefinition definition;
  final String? value;
  final DateTime? date;
  final ValueChanged<String> onLevel;
  final ValueChanged<DateTime> onDate;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(definition.label, style: theme.typography.body),
          ),
          Expanded(
            child: definition.isDate
                ? Row(
                    children: [
                      SizedBox(
                        width: 220,
                        child: DatePicker(
                          selected: date,
                          onChanged: onDate,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (date != null)
                        Text(
                          '${DateTime.now().difference(date!).inDays} days ago',
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      for (final level in definition.levels)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ToggleButton(
                            checked: value == level,
                            onChanged: (_) => onLevel(level),
                            child: Text(titleCase(level)),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
