import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/ids.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../common/widgets.dart';

/// Registration and editing of a patient's standing details.
///
/// The intake fields follow the clinic's own form, in the same order, so a
/// receptionist copying from paper does not have to hunt.
class PatientFormDialog extends StatefulWidget {
  const PatientFormDialog({super.key, this.existing});

  final Patient? existing;

  static Future<Patient?> show(BuildContext context, {Patient? existing}) =>
      showDialog<Patient>(
        context: context,
        builder: (context) => PatientFormDialog(existing: existing),
      );

  @override
  State<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<PatientFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _weight;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _complaints;
  late final TextEditingController _notes;

  late Sex _sex;
  String? _assignedTo;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _age = TextEditingController(text: p?.age?.toString() ?? '');
    _weight = TextEditingController(text: p?.weightKg?.toString() ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _complaints = TextEditingController(text: p?.chiefComplaints ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    _sex = p?.sex ?? Sex.female;
    _assignedTo = p?.assignedTo;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _age,
      _weight,
      _address,
      _phone,
      _complaints,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final state = context.read<AppState>();
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A patient needs a name.');
      return;
    }
    final age = _age.text.trim().isEmpty ? null : int.tryParse(_age.text.trim());
    if (_age.text.trim().isNotEmpty && (age == null || age < 0 || age > 130)) {
      setState(() => _error = 'Enter an age between 0 and 130, or leave it blank.');
      return;
    }
    final weight = _weight.text.trim().isEmpty
        ? null
        : double.tryParse(_weight.text.trim());
    if (_weight.text.trim().isNotEmpty && weight == null) {
      setState(() => _error = 'Weight must be a number, in kilograms.');
      return;
    }

    final base = widget.existing;
    final patient = Patient(
      id: base?.id ?? newId(),
      code: base?.code ?? state.patients.nextCode(),
      name: name,
      age: age,
      sex: _sex,
      weightKg: weight,
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      chiefComplaints:
          _complaints.text.trim().isEmpty ? null : _complaints.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      assignedTo: _assignedTo,
      registeredAt: base?.registeredAt ?? DateTime.now(),
    );

    if (_isNew) {
      state.patients.create(patient, by: state.currentUser);
    } else {
      state.patients.save(patient, by: state.currentUser);
    }
    state.touch();
    Navigator.pop(context, patient);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final providers = state.staff.all(includeInactive: false);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 640),
      title: Text(_isNew ? 'Register a patient' : 'Edit ${widget.existing!.name}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) InlineMessage(message: _error!),
            LabeledField(
              label: 'Name',
              child: TextBox(controller: _name, autofocus: true),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Age',
                    child: TextBox(controller: _age, placeholder: 'years'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: LabeledField(
                    label: 'Sex',
                    child: _SexToggle(
                      value: _sex,
                      onChanged: (v) => setState(() => _sex = v),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: 'Weight',
                    child: TextBox(controller: _weight, placeholder: 'kg'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: LabeledField(
                    label: 'Phone',
                    child: TextBox(controller: _phone),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: LabeledField(
                    label: 'Under the care of',
                    child: ComboBox<String?>(
                      value: _assignedTo,
                      isExpanded: true,
                      placeholder: const Text('Unassigned'),
                      items: [
                        const ComboBoxItem<String?>(
                          value: null,
                          child: Text('Unassigned'),
                        ),
                        for (final s in providers)
                          ComboBoxItem<String?>(
                            value: s.id,
                            child: Text(s.fullName),
                          ),
                      ],
                      onChanged: (v) => setState(() => _assignedTo = v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Address',
              child: TextBox(controller: _address, maxLines: 2),
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Chief complaints',
              hint: 'What brought the patient in.',
              child: TextBox(controller: _complaints, maxLines: 3),
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Notes',
              child: TextBox(controller: _notes, maxLines: 2),
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isNew ? 'Register patient' : 'Save changes'),
        ),
      ],
    );
  }
}

/// The `Sex | toggle` field from the clinic's intake sheet.
class _SexToggle extends StatelessWidget {
  const _SexToggle({required this.value, required this.onChanged});

  final Sex value;
  final ValueChanged<Sex> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final sex in Sex.values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ToggleButton(
              checked: value == sex,
              onChanged: (_) => onChanged(sex),
              child: Text(sex.label),
            ),
          ),
      ],
    );
  }
}
