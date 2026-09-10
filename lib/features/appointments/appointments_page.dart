import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../common/file_output.dart';
import '../common/widgets.dart';
import '../patients/visit_form.dart';
import 'appointment_form.dart';

/// The diary. A week strip to move between days, and the chosen day's list.
class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  DateTime _day = startOfDay(DateTime.now());
  String? _staffFilter;

  DateTime get _weekStart =>
      _day.subtract(Duration(days: _day.weekday - DateTime.monday));

  Future<void> _printDay() async {
    final state = context.read<AppState>();
    await guarded(context, () async {
      final appointments =
          state.appointments.onDay(_day, staffId: _staffFilter);
      final bytes = await state.pdf.daySchedule(
        day: _day,
        appointments: appointments,
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
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final clinicians = state.staff.all(includeInactive: false);
    final appointments = state.appointments.onDay(_day, staffId: _staffFilter);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Appointments'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.calendar_add_24_regular),
              label: const Text('Book'),
              onPressed: () => AppointmentFormDialog.show(
                context,
                initialDate: _day,
              ),
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.document_pdf_24_regular),
              label: const Text('Print day'),
              onPressed: _printDay,
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(FluentIcons.chevron_left_20_regular),
                        onPressed: () => setState(
                          () => _day = _day.subtract(const Duration(days: 7)),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          fmtDay(_day),
                          textAlign: TextAlign.center,
                          style: theme.typography.bodyStrong,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(FluentIcons.chevron_right_20_regular),
                        onPressed: () => setState(
                          () => _day = _day.add(const Duration(days: 7)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: () => setState(
                          () => _day = startOfDay(DateTime.now()),
                        ),
                        child: const Text('Today'),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 200,
                        child: ComboBox<String?>(
                          value: _staffFilter,
                          isExpanded: true,
                          placeholder: const Text('All clinicians'),
                          items: [
                            const ComboBoxItem<String?>(
                              value: null,
                              child: Text('All clinicians'),
                            ),
                            for (final s in clinicians)
                              ComboBoxItem<String?>(
                                value: s.id,
                                child: Text(s.fullName),
                              ),
                          ],
                          onChanged: (v) => setState(() => _staffFilter = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: _DayCell(
                            day: _weekStart.add(Duration(days: i)),
                            selected: startOfDay(
                                  _weekStart.add(Duration(days: i)),
                                ) ==
                                _day,
                            count: state.appointments.countOn(
                              _weekStart.add(Duration(days: i)),
                            ),
                            onTap: () => setState(
                              () => _day = startOfDay(
                                _weekStart.add(Duration(days: i)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                padding: const EdgeInsets.all(12),
                child: appointments.isEmpty
                    ? EmptyState(
                        icon: FluentIcons.calendar_empty_24_regular,
                        title: 'Nothing booked',
                        message: 'No appointments on ${fmtDate(_day)}.',
                        action: FilledButton(
                          onPressed: () => AppointmentFormDialog.show(
                            context,
                            initialDate: _day,
                          ),
                          child: const Text('Book an appointment'),
                        ),
                      )
                    : ListView.separated(
                        itemCount: appointments.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _AppointmentRow(
                          appointment: appointments[index],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isToday = startOfDay(day) == startOfDay(DateTime.now());

    return HoverButton(
      onPressed: onTap,
      builder: (context, states) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.accentColor.normal.withValues(alpha: 0.14)
              : states.isHovered
                  ? theme.resources.subtleFillColorSecondary
                  : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? theme.accentColor.normal.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Text(
              const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][
                  day.weekday - 1],
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.day}',
              style: theme.typography.bodyStrong?.copyWith(
                color: isToday ? theme.accentColor.normal : null,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 4,
              width: count == 0 ? 0 : (count * 6).clamp(6, 42).toDouble(),
              decoration: BoxDecoration(
                color: theme.accentColor.normal.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({required this.appointment});

  final Appointment appointment;

  Color get _tone => switch (appointment.status) {
        AppointmentStatus.scheduled => SattraTheme.info,
        AppointmentStatus.completed => SattraTheme.ok,
        AppointmentStatus.cancelled => SattraTheme.danger,
        AppointmentStatus.noShow => SattraTheme.warn,
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final patient = state.patients.byId(appointment.patientId);
    final clinician = state.staff.byId(appointment.staffId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: _tone, width: 3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtTime(appointment.scheduledAt),
                    style: theme.typography.bodyStrong),
                Text(
                  '${appointment.durationMin} min',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient?.name ?? 'Unknown patient',
                    style: theme.typography.body),
                Text(
                  [
                    if (patient != null) patient.code,
                    if (clinician != null) 'with ${clinician.fullName}',
                    if ((appointment.reason ?? '').isNotEmpty)
                      appointment.reason!,
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(appointment.status.label, color: _tone),
          const SizedBox(width: 10),
          if (appointment.status == AppointmentStatus.scheduled &&
              patient != null)
            FilledButton(
              onPressed: () async {
                // Seeing the patient is the point of the booking, so start the
                // consultation and close the appointment in one step.
                final recorded = await VisitFormDialog.show(
                  context,
                  patient: patient,
                  appointmentId: appointment.id,
                );
                if (recorded == true && context.mounted) {
                  state.appointments.setStatus(
                    appointment,
                    AppointmentStatus.completed,
                    by: state.currentUser,
                  );
                  state.touch();
                }
              },
              child: const Text('Start consultation'),
            ),
          const SizedBox(width: 6),
          DropDownButton(
            title: const Icon(FluentIcons.more_horizontal_20_regular, size: 14),
            items: [
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.edit_20_regular),
                text: const Text('Edit'),
                onPressed: () => AppointmentFormDialog.show(
                  context,
                  existing: appointment,
                ),
              ),
              if (appointment.status != AppointmentStatus.completed)
                MenuFlyoutItem(
                  leading:
                      const Icon(FluentIcons.checkmark_circle_20_regular),
                  text: const Text('Mark completed'),
                  onPressed: () {
                    state.appointments.setStatus(
                      appointment,
                      AppointmentStatus.completed,
                      by: state.currentUser,
                    );
                    state.touch();
                  },
                ),
              if (appointment.status == AppointmentStatus.scheduled)
                MenuFlyoutItem(
                  leading: const Icon(FluentIcons.person_delete_20_regular),
                  text: const Text('Mark no show'),
                  onPressed: () {
                    state.appointments.setStatus(
                      appointment,
                      AppointmentStatus.noShow,
                      by: state.currentUser,
                    );
                    state.touch();
                  },
                ),
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.dismiss_circle_20_regular),
                text: const Text('Cancel booking'),
                onPressed: () {
                  state.appointments.setStatus(
                    appointment,
                    AppointmentStatus.cancelled,
                    by: state.currentUser,
                  );
                  state.touch();
                },
              ),
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.delete_20_regular),
                text: const Text('Delete'),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Delete this booking?',
                    message: 'It will be removed from the diary entirely. '
                        'To keep a record of a missed visit, mark it cancelled '
                        'or no show instead.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (!ok) return;
                  state.appointments.delete(appointment, by: state.currentUser);
                  state.touch();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
