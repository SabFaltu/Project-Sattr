import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/ids.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../common/file_output.dart';
import '../common/widgets.dart';

/// The formulary and its stock ledger.
class MedicinesPage extends StatefulWidget {
  const MedicinesPage({super.key});

  @override
  State<MedicinesPage> createState() => _MedicinesPageState();
}

class _MedicinesPageState extends State<MedicinesPage> {
  final _search = TextEditingController();
  bool _lowOnly = false;
  String? _expandedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _exportStock() async {
    final state = context.read<AppState>();
    await guarded(context, () async {
      final bytes = await state.pdf.inventoryReport(state.medicines.all());
      if (!mounted) return;
      await FileOutput.savePdf(
        context,
        bytes: bytes,
        suggestedName: 'stock-report-${isoDate(DateTime.now())}.pdf',
        successMessage: 'Stock report saved',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    var medicines = state.medicines.all(query: _search.text);
    if (_lowOnly) medicines = medicines.where((m) => m.isLow).toList();

    final totalUnits =
        state.medicines.all().fold<int>(0, (sum, m) => sum + m.stockQty);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Pharmacy'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add_24_regular),
              label: const Text('Add medicine'),
              onPressed: state.isAdmin
                  ? () => MedicineFormDialog.show(context)
                  : null,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.document_pdf_24_regular),
              label: const Text('Stock report'),
              onPressed: _exportStock,
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 320,
                  child: TextBox(
                    controller: _search,
                    placeholder: 'Search the formulary',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(FluentIcons.search_20_regular, size: 14),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Checkbox(
                  checked: _lowOnly,
                  onChanged: (v) => setState(() => _lowOnly = v ?? false),
                  content: const Text('Only items needing reorder'),
                ),
                const Spacer(),
                Text(
                  '$totalUnits units across ${state.medicines.all().length} items',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                padding: const EdgeInsets.all(12),
                child: medicines.isEmpty
                    ? EmptyState(
                        icon: FluentIcons.pill_24_regular,
                        title: _lowOnly
                            ? 'Nothing needs reordering'
                            : 'No medicines match',
                        message: _lowOnly
                            ? 'Every item is above its reorder level.'
                            : null,
                      )
                    : ListView.separated(
                        itemCount: medicines.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final medicine = medicines[index];
                          return _MedicineTile(
                            medicine: medicine,
                            expanded: _expandedId == medicine.id,
                            onToggle: () => setState(
                              () => _expandedId = _expandedId == medicine.id
                                  ? null
                                  : medicine.id,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicineTile extends StatelessWidget {
  const _MedicineTile({
    required this.medicine,
    required this.expanded,
    required this.onToggle,
  });

  final Medicine medicine;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final tone = SattraTheme.stockColor(medicine.isOut, medicine.isLow);

    return Container(
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          HoverButton(
            onPressed: onToggle,
            builder: (context, states) => Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    expanded
                        ? FluentIcons.chevron_down_20_regular
                        : FluentIcons.chevron_right_20_regular,
                    size: 13,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: Text(medicine.displayName,
                        style: theme.typography.body),
                  ),
                  Expanded(
                    child: Text(
                      medicine.strength ?? '',
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Row(
                      children: [
                        StatusPill(
                          medicine.isOut
                              ? 'Out of stock'
                              : '${medicine.stockQty} ${medicine.unit}',
                          color: tone,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      'reorder at ${medicine.reorderLevel}',
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorTertiary,
                      ),
                    ),
                  ),
                  Button(
                    onPressed: () =>
                        StockAdjustDialog.show(context, medicine: medicine),
                    child: const Text('Adjust stock'),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(FluentIcons.edit_20_regular),
                    onPressed: state.isAdmin
                        ? () => MedicineFormDialog.show(
                              context,
                              existing: medicine,
                            )
                        : null,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(38, 0, 12, 12),
              child: _MovementHistory(medicine: medicine),
            ),
        ],
      ),
    );
  }
}

class _MovementHistory extends StatelessWidget {
  const _MovementHistory({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final movements = state.medicines.movementsFor(medicine.id, limit: 12);

    if (movements.isEmpty) {
      return Text(
        'No stock has moved yet. Use "Adjust stock" to record a delivery.',
        style: theme.typography.caption?.copyWith(
          color: theme.resources.textFillColorSecondary,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Recent movements', style: theme.typography.caption),
        const SizedBox(height: 6),
        for (final movement in movements)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    '${movement.delta > 0 ? '+' : ''}${movement.delta}',
                    style: theme.typography.bodyStrong?.copyWith(
                      color: movement.delta > 0
                          ? SattraTheme.ok
                          : SattraTheme.danger,
                    ),
                  ),
                ),
                Expanded(child: Text(movement.reason)),
                Text(
                  '${state.staff.byId(movement.byUser)?.fullName ?? 'System'} · '
                  '${fmtDateTime(movement.movedAt)}',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorTertiary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Records a delivery, a wastage, or a correction.
class StockAdjustDialog extends StatefulWidget {
  const StockAdjustDialog({super.key, required this.medicine});

  final Medicine medicine;

  static Future<void> show(BuildContext context,
          {required Medicine medicine}) =>
      showDialog<void>(
        context: context,
        builder: (context) => StockAdjustDialog(medicine: medicine),
      );

  @override
  State<StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends State<StockAdjustDialog> {
  int _quantity = 10;
  bool _incoming = true;
  String _reason = 'Delivery received';
  String? _error;

  static const _incomingReasons = [
    'Delivery received',
    'Returned to stock',
    'Stock count correction',
  ];
  static const _outgoingReasons = [
    'Dispensed at counter',
    'Expired',
    'Damaged',
    'Stock count correction',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final medicine =
        state.medicines.byId(widget.medicine.id) ?? widget.medicine;
    final theme = FluentTheme.of(context);
    final reasons = _incoming ? _incomingReasons : _outgoingReasons;
    final resulting =
        medicine.stockQty + (_incoming ? _quantity : -_quantity);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Text('Adjust stock — ${medicine.displayName}'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) InlineMessage(message: _error!),
          Text(
            'Currently ${medicine.stockQty} ${medicine.unit} on hand.',
            style: theme.typography.body,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ToggleButton(
                  checked: _incoming,
                  onChanged: (_) => setState(() {
                    _incoming = true;
                    _reason = _incomingReasons.first;
                  }),
                  child: const Text('Add to stock'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ToggleButton(
                  checked: !_incoming,
                  onChanged: (_) => setState(() {
                    _incoming = false;
                    _reason = _outgoingReasons.first;
                  }),
                  child: const Text('Take out of stock'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Quantity',
            child: NumberBox<int>(
              value: _quantity,
              min: 1,
              max: 100000,
              onChanged: (v) => setState(() => _quantity = v ?? _quantity),
            ),
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Reason',
            child: ComboBox<String>(
              value: _reason,
              isExpanded: true,
              items: [
                for (final r in reasons) ComboBoxItem(value: r, child: Text(r)),
              ],
              onChanged: (v) => setState(() => _reason = v ?? _reason),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'After this adjustment: ${resulting < 0 ? 0 : resulting} ${medicine.unit}',
            style: theme.typography.bodyStrong?.copyWith(
              color: resulting < 0 ? SattraTheme.danger : null,
            ),
          ),
          if (resulting < 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'That is more than is on hand. Stock will be recorded as zero.',
                style: theme.typography.caption
                    ?.copyWith(color: SattraTheme.danger),
              ),
            ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            state.medicines.adjustStock(
              medicine,
              _incoming ? _quantity : -_quantity,
              reason: _reason,
              by: state.currentUser,
            );
            state.touch();
            Navigator.pop(context);
            notify(context, 'Stock updated for ${medicine.displayName}.');
          },
          child: const Text('Record adjustment'),
        ),
      ],
    );
  }
}

/// Adds a formulation to the clinic's list, or edits one.
class MedicineFormDialog extends StatefulWidget {
  const MedicineFormDialog({super.key, this.existing});

  final Medicine? existing;

  static Future<void> show(BuildContext context, {Medicine? existing}) =>
      showDialog<void>(
        context: context,
        builder: (context) => MedicineFormDialog(existing: existing),
      );

  @override
  State<MedicineFormDialog> createState() => _MedicineFormDialogState();
}

class _MedicineFormDialogState extends State<MedicineFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _strength;
  late final TextEditingController _unit;
  late final TextEditingController _notes;
  late MedicineForm _form;
  late int _reorderLevel;
  String? _error;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _name = TextEditingController(text: m?.name ?? '');
    _strength = TextEditingController(text: m?.strength ?? '');
    _unit = TextEditingController(text: m?.unit ?? 'unit');
    _notes = TextEditingController(text: m?.notes ?? '');
    _form = m?.form ?? MedicineForm.tablet;
    _reorderLevel = m?.reorderLevel ?? 20;
  }

  @override
  void dispose() {
    for (final c in [_name, _strength, _unit, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 520),
      title: Text(widget.existing == null
          ? 'Add a medicine'
          : 'Edit ${widget.existing!.displayName}'),
      content: Column(
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
                  label: 'Form',
                  child: ComboBox<MedicineForm>(
                    value: _form,
                    isExpanded: true,
                    items: [
                      for (final f in MedicineForm.values)
                        ComboBoxItem(value: f, child: Text(f.label)),
                    ],
                    onChanged: (v) => setState(() => _form = v ?? _form),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  label: 'Strength',
                  child: TextBox(
                    controller: _strength,
                    placeholder: 'optional',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Unit',
                  hint: 'e.g. unit, ml',
                  child: TextBox(controller: _unit),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  label: 'Reorder level',
                  hint: 'Warn at or below this quantity.',
                  child: NumberBox<int>(
                    value: _reorderLevel,
                    min: 0,
                    onChanged: (v) =>
                        setState(() => _reorderLevel = v ?? _reorderLevel),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Notes',
            child: TextBox(controller: _notes, maxLines: 2),
          ),
        ],
      ),
      actions: [
        if (widget.existing != null)
          Button(
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Remove ${widget.existing!.displayName}?',
                message: 'It stops appearing in the formulary. Prescriptions '
                    'that already name it are unaffected.',
                confirmLabel: 'Remove',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              state.medicines.delete(widget.existing!, by: state.currentUser);
              state.touch();
              Navigator.pop(context);
            },
            child: const Text('Remove'),
          ),
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = 'Give the medicine a name.');
              return;
            }
            final base = widget.existing;
            final medicine = Medicine(
              id: base?.id ?? newId(),
              name: name,
              form: _form,
              strength:
                  _strength.text.trim().isEmpty ? null : _strength.text.trim(),
              unit: _unit.text.trim().isEmpty ? 'unit' : _unit.text.trim(),
              stockQty: base?.stockQty ?? 0,
              reorderLevel: _reorderLevel,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            );
            state.medicines.save(medicine, by: state.currentUser);
            state.touch();
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
