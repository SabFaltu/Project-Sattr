import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../common/widgets.dart';
import 'patient_detail.dart';
import 'patient_form.dart';

/// The patient register: a searchable list on the left, the selected record on
/// the right.
class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key});

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  final _search = TextEditingController();
  String? _selectedId;
  bool _mineOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final patients = state.patients.search(
      query: _search.text,
      assignedTo: _mineOnly ? state.currentUser?.id : null,
    );

    // Keep a valid selection as the list is filtered underneath it.
    final selected = patients.any((p) => p.id == _selectedId)
        ? state.patients.byId(_selectedId)
        : null;

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Patients'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.person_add_24_regular),
              label: const Text('Register patient'),
              onPressed: () async {
                final created = await PatientFormDialog.show(context);
                if (created != null) setState(() => _selectedId = created.id);
              },
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 340,
              child: Card(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextBox(
                      controller: _search,
                      placeholder: 'Search by name, record no. or phone',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(FluentIcons.search_20_regular, size: 14),
                      ),
                      suffix: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(FluentIcons.dismiss_16_regular,
                                  size: 12),
                              onPressed: () => setState(_search.clear),
                            ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          checked: _mineOnly,
                          onChanged: (v) =>
                              setState(() => _mineOnly = v ?? false),
                          content: const Text('Only my patients'),
                        ),
                        const Spacer(),
                        Text(
                          '${patients.length}',
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: patients.isEmpty
                          ? EmptyState(
                              icon: FluentIcons.people_24_regular,
                              title: _search.text.isEmpty
                                  ? 'No patients yet'
                                  : 'No matches',
                              message: _search.text.isEmpty
                                  ? 'Register the first patient to begin.'
                                  : 'Nothing matches "${_search.text}".',
                            )
                          : ListView.builder(
                              itemCount: patients.length,
                              itemBuilder: (context, index) => _PatientTile(
                                patient: patients[index],
                                selected: patients[index].id == _selectedId,
                                onTap: () => setState(
                                  () => _selectedId = patients[index].id,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: selected == null
                  ? Card(
                      child: EmptyState(
                        icon: FluentIcons.person_24_regular,
                        title: 'Select a patient',
                        message:
                            'Choose someone from the list to see their record, '
                            'consultations and prescriptions.',
                      ),
                    )
                  : PatientDetail(
                      key: ValueKey(selected.id),
                      patient: selected,
                      onDeleted: () => setState(() => _selectedId = null),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({
    required this.patient,
    required this.selected,
    required this.onTap,
  });

  final Patient patient;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final state = context.read<AppState>();
    final clinician = state.staff.byId(patient.assignedTo);

    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        final hovered = states.isHovered;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? theme.accentColor.normal.withValues(alpha: 0.12)
                : hovered
                    ? theme.resources.subtleFillColorSecondary
                    : null,
            borderRadius: BorderRadius.circular(5),
            border: Border(
              left: BorderSide(
                width: 3,
                color: selected ? theme.accentColor.normal : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: theme.typography.body?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        patient.code,
                        if (patient.age != null) '${patient.age}y',
                        patient.sex.short,
                        if (clinician != null) clinician.fullName,
                      ].join(' · '),
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
