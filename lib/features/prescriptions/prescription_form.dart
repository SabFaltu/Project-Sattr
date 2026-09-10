import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/ids.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../common/widgets.dart';

/// Writes or edits a prescription.
///
/// Quantity follows from the dose and the course length, but stays editable —
/// a clinician handing out a part pack should not have to fight the form. The
/// stock a line would consume is shown next to it so a shortfall is visible
/// while prescribing, not at the counter.
class PrescriptionFormDialog extends StatefulWidget {
  const PrescriptionFormDialog({
    super.key,
    required this.patient,
    this.existing,
    this.visitId,
  });

  final Patient patient;
  final Prescription? existing;
  final String? visitId;

  static Future<bool?> show(
    BuildContext context, {
    required Patient patient,
    Prescription? existing,
    String? visitId,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => PrescriptionFormDialog(
          patient: patient,
          existing: existing,
          visitId: visitId,
        ),
      );

  @override
  State<PrescriptionFormDialog> createState() => _PrescriptionFormDialogState();
}

class _PrescriptionFormDialogState extends State<PrescriptionFormDialog> {
  late final TextEditingController _notes;
  late final String _prescriptionId;
  final List<PrescriptionItem> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
    _prescriptionId = widget.existing?.id ?? newId();
    if (widget.existing != null) {
      _items.addAll(state.prescriptions.itemsFor(widget.existing!.id));
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _addLine() {
    final state = context.read<AppState>();
    final formulary = state.medicines.all();
    if (formulary.isEmpty) {
      setState(() => _error =
          'The formulary is empty. Add medicines in the Pharmacy module first.');
      return;
    }
    setState(() {
      _error = null;
      _items.add(
        PrescriptionItem(
          id: newId(),
          prescriptionId: _prescriptionId,
          medicineId: formulary.first.id,
          dose: Dose.od,
          durationDays: 7,
          quantity: PrescriptionItem.suggestedQuantity(Dose.od, 7),
        ),
      );
    });
  }

  void _save() {
    if (_items.isEmpty) {
      setState(() => _error = 'Add at least one medicine.');
      return;
    }
    final state = context.read<AppState>();
    final prescription = Prescription(
      id: _prescriptionId,
      patientId: widget.patient.id,
      visitId: widget.existing?.visitId ?? widget.visitId,
      prescribedBy: widget.existing?.prescribedBy ?? state.currentUser?.id,
      prescribedAt: widget.existing?.prescribedAt ?? DateTime.now(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      dispensed: widget.existing?.dispensed ?? false,
    );
    state.prescriptions.save(prescription, _items, by: state.currentUser);
    state.touch();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final formulary = state.medicines.all();
    final byId = {for (final m in formulary) m.id: m};

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 820, maxHeight: 700),
      title: Text(
        widget.existing == null
            ? 'New prescription — ${widget.patient.name}'
            : 'Edit prescription — ${widget.patient.name}',
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) InlineMessage(message: _error!),
          if (widget.existing?.dispensed == true)
            const InlineMessage(
              message: 'This prescription has already been dispensed. Editing '
                  'it will not put the medicines back into stock.',
              severity: InfoBarSeverity.warning,
              title: 'Already dispensed',
            ),
          SizedBox(
            height: 300,
            child: _items.isEmpty
                ? EmptyState(
                    icon: FluentIcons.pill_24_regular,
                    title: 'Nothing prescribed yet',
                    message: 'Add the medicines this patient should take.',
                    action: FilledButton(
                      onPressed: _addLine,
                      child: const Text('Add a medicine'),
                    ),
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _ItemRow(
                      item: _items[index],
                      formulary: formulary,
                      medicine: byId[_items[index].medicineId],
                      onChanged: (updated) =>
                          setState(() => _items[index] = updated),
                      onRemove: () => setState(() => _items.removeAt(index)),
                    ),
                  ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Button(
                onPressed: _addLine,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.add_16_regular, size: 14),
                    SizedBox(width: 6),
                    Text('Add another medicine'),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LabeledField(
            label: 'Notes for the patient',
            child: TextBox(controller: _notes, maxLines: 2),
          ),
          const SizedBox(height: 6),
          Text(
            'Stock is only deducted when the prescription is dispensed.',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save prescription')),
      ],
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    required this.item,
    required this.formulary,
    required this.medicine,
    required this.onChanged,
    required this.onRemove,
  });

  final PrescriptionItem item;
  final List<Medicine> formulary;
  final Medicine? medicine;
  final ValueChanged<PrescriptionItem> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  /// Owned by the row rather than rebuilt each frame, so typing an
  /// instruction does not move the caret back to the start on every keystroke.
  late final TextEditingController _instructions =
      TextEditingController(text: widget.item.instructions);

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final item = widget.item;
    final medicine = widget.medicine;
    final formulary = widget.formulary;
    final onChanged = widget.onChanged;
    final onRemove = widget.onRemove;
    final short = medicine != null && medicine.stockQty < item.quantity;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 4,
                child: LabeledField(
                  label: 'Medicine',
                  child: ComboBox<String>(
                    value: item.medicineId,
                    isExpanded: true,
                    items: [
                      for (final m in formulary)
                        ComboBoxItem(
                          value: m.id,
                          child: Text(m.displayName),
                        ),
                    ],
                    onChanged: (v) =>
                        v == null ? null : onChanged(_withMedicine(v)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: LabeledField(
                  label: 'Dose',
                  child: ComboBox<Dose>(
                    value: item.dose,
                    isExpanded: true,
                    items: [
                      for (final dose in Dose.values)
                        ComboBoxItem(
                          value: dose,
                          child: Text('${dose.code} — ${dose.description}'),
                        ),
                    ],
                    onChanged: (v) => v == null
                        ? null
                        : onChanged(
                            item.copyWith(
                              dose: v,
                              quantity: PrescriptionItem.suggestedQuantity(
                                v,
                                item.durationDays,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 74,
                child: LabeledField(
                  label: 'Days',
                  child: NumberBox<int>(
                    value: item.durationDays,
                    min: 1,
                    max: 365,
                    mode: SpinButtonPlacementMode.compact,
                    onChanged: (v) {
                      final days = v ?? item.durationDays;
                      onChanged(
                        item.copyWith(
                          durationDays: days,
                          quantity: PrescriptionItem.suggestedQuantity(
                            item.dose,
                            days,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: LabeledField(
                  label: 'Quantity',
                  child: NumberBox<int>(
                    value: item.quantity,
                    min: 0,
                    mode: SpinButtonPlacementMode.compact,
                    onChanged: (v) =>
                        onChanged(item.copyWith(quantity: v ?? item.quantity)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(FluentIcons.delete_20_regular),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (medicine != null)
                StatusPill(
                  short
                      ? 'Only ${medicine.stockQty} in stock'
                      : '${medicine.stockQty} in stock',
                  color: short ? SattraTheme.danger : SattraTheme.ok,
                  icon: short
                      ? FluentIcons.warning_20_regular
                      : FluentIcons.checkmark_circle_20_regular,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: TextBox(
                  placeholder: 'Instructions (optional) — e.g. after meals',
                  controller: _instructions,
                  onChanged: (v) => onChanged(
                    item.copyWith(instructions: v.trim().isEmpty ? null : v),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PrescriptionItem _withMedicine(String medicineId) => PrescriptionItem(
        id: widget.item.id,
        prescriptionId: widget.item.prescriptionId,
        medicineId: medicineId,
        dose: widget.item.dose,
        durationDays: widget.item.durationDays,
        quantity: widget.item.quantity,
        instructions: widget.item.instructions,
      );
}
