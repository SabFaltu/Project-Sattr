import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../common/widgets.dart';

/// What the clinic looks like this morning.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final today = startOfDay(DateTime.now());

    final todaysAppointments = state.appointments.onDay(today);
    final lowStock = state.medicines.lowStock();
    final upcoming = state.appointments.upcoming(limit: 6);
    final recentActivity = state.audit.recent(limit: 8);
    final weekAgo = today.subtract(const Duration(days: 7));

    return ScaffoldPage.scrollable(
      header: PageHeader(
        title: Text('Good ${_partOfDay()}, ${_firstName(state.currentUser)}'),
        commandBar: Text(
          fmtDay(DateTime.now()),
          style: theme.typography.body?.copyWith(
            color: theme.resources.textFillColorSecondary,
          ),
        ),
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 1100 ? 4 : 2;
            final width =
                (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: StatTile(
                    label: 'Patients on file',
                    value: '${state.patients.total}',
                    icon: FluentIcons.people_24_regular,
                    hint:
                        '${state.patients.registeredSince(weekAgo)} registered this week',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatTile(
                    label: 'Booked today',
                    value: '${todaysAppointments.where((a) => a.status != AppointmentStatus.cancelled).length}',
                    icon: FluentIcons.calendar_ltr_24_regular,
                    hint:
                        '${todaysAppointments.where((a) => a.status == AppointmentStatus.completed).length} seen so far',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatTile(
                    label: 'Formulary items',
                    value: '${state.medicines.all().length}',
                    icon: FluentIcons.pill_24_regular,
                    hint: 'Across tablets and capsules',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StatTile(
                    label: 'Need reordering',
                    value: '${lowStock.length}',
                    icon: FluentIcons.arrow_trending_down_24_regular,
                    tone: lowStock.isEmpty ? SattraTheme.ok : SattraTheme.warn,
                    hint: lowStock.isEmpty
                        ? 'Stock is comfortable'
                        : lowStock.take(2).map((m) => m.name).join(', '),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 980;
            final schedule = _TodaySchedule(
              appointments: todaysAppointments,
              upcoming: upcoming,
            );
            final side = Column(
              children: [
                _LowStockPanel(medicines: lowStock),
                const SizedBox(height: 12),
                _ActivityPanel(entries: recentActivity),
              ],
            );
            if (!wide) {
              return Column(children: [schedule, const SizedBox(height: 12), side]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: schedule),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: side),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _partOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  static String _firstName(Staff? staff) =>
      (staff?.fullName ?? '').split(' ').first;
}

class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule({required this.appointments, required this.upcoming});

  final List<Appointment> appointments;
  final List<Appointment> upcoming;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final active = appointments
        .where((a) => a.status != AppointmentStatus.cancelled)
        .toList();

    return SectionCard(
      title: "Today's clinic",
      subtitle: active.isEmpty
          ? 'Nothing booked for today.'
          : '${active.length} appointment${active.length == 1 ? '' : 's'}',
      child: SizedBox(
        height: 320,
        child: active.isEmpty
            ? _UpcomingFallback(upcoming: upcoming)
            : ListView.separated(
                itemCount: active.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final appointment = active[index];
                  final patient =
                      state.patients.byId(appointment.patientId);
                  final clinician = state.staff.byId(appointment.staffId);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.resources.subtleFillColorSecondary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 54,
                          child: Text(
                            fmtTime(appointment.scheduledAt),
                            style: theme.typography.bodyStrong,
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
                                  if (clinician != null)
                                    'with ${clinician.fullName}',
                                  if ((appointment.reason ?? '').isNotEmpty)
                                    appointment.reason!,
                                ].join(' · '),
                                overflow: TextOverflow.ellipsis,
                                style: theme.typography.caption?.copyWith(
                                  color:
                                      theme.resources.textFillColorSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StatusPill(
                          appointment.status.label,
                          color: switch (appointment.status) {
                            AppointmentStatus.completed => SattraTheme.ok,
                            AppointmentStatus.noShow => SattraTheme.danger,
                            AppointmentStatus.cancelled => SattraTheme.danger,
                            AppointmentStatus.scheduled => SattraTheme.info,
                          },
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

class _UpcomingFallback extends StatelessWidget {
  const _UpcomingFallback({required this.upcoming});

  final List<Appointment> upcoming;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    if (upcoming.isEmpty) {
      return const EmptyState(
        icon: FluentIcons.calendar_empty_24_regular,
        title: 'The diary is empty',
        message: 'Nothing is booked today or later. '
            'Add an appointment from the Appointments module.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Coming up', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: upcoming.length,
            itemBuilder: (context, index) {
              final appointment = upcoming[index];
              final patient = state.patients.byId(appointment.patientId);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(patient?.name ?? 'Unknown patient',
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      fmtDateTime(appointment.scheduledAt),
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LowStockPanel extends StatelessWidget {
  const _LowStockPanel({required this.medicines});

  final List<Medicine> medicines;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SectionCard(
      title: 'Stock to watch',
      subtitle: medicines.isEmpty
          ? 'Everything is above its reorder level.'
          : '${medicines.length} item(s) at or below the reorder level',
      child: SizedBox(
        height: 148,
        child: medicines.isEmpty
            ? Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(FluentIcons.checkmark_circle_24_regular,
                        size: 18, color: SattraTheme.ok),
                    const SizedBox(width: 8),
                    Text('Nothing to reorder',
                        style: theme.typography.body?.copyWith(
                          color: theme.resources.textFillColorSecondary,
                        )),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: medicines.length,
                itemBuilder: (context, index) {
                  final medicine = medicines[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(medicine.displayName,
                              overflow: TextOverflow.ellipsis),
                        ),
                        StatusPill(
                          medicine.isOut
                              ? 'Out of stock'
                              : '${medicine.stockQty} left',
                          color: SattraTheme.stockColor(
                              medicine.isOut, medicine.isLow),
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

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.entries});

  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SectionCard(
      title: 'Recent activity',
      subtitle: 'What has been recorded across the clinic',
      child: SizedBox(
        height: 200,
        child: entries.isEmpty
            ? Center(
                child: Text('Nothing recorded yet.',
                    style: theme.typography.body?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    )),
              )
            : ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_iconFor(entry.action),
                            size: 14,
                            color: theme.resources.textFillColorTertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _describe(entry),
                                style: theme.typography.caption,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${entry.userName ?? 'System'} · ${relative(entry.at)}',
                                style: theme.typography.caption?.copyWith(
                                  color:
                                      theme.resources.textFillColorTertiary,
                                ),
                              ),
                            ],
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

  static IconData _iconFor(String action) {
    if (action.startsWith('patient')) return FluentIcons.person_24_regular;
    if (action.startsWith('visit')) return FluentIcons.stethoscope_24_regular;
    if (action.startsWith('appointment')) {
      return FluentIcons.calendar_ltr_24_regular;
    }
    if (action.startsWith('prescription')) {
      return FluentIcons.document_bullet_list_24_regular;
    }
    if (action.startsWith('stock') || action.startsWith('medicine')) {
      return FluentIcons.pill_24_regular;
    }
    if (action.startsWith('auth') || action.startsWith('staff')) {
      return FluentIcons.person_board_24_regular;
    }
    return FluentIcons.history_24_regular;
  }

  static String _describe(AuditEntry entry) {
    final label = switch (entry.action) {
      'patient.register' => 'Registered patient',
      'patient.update' => 'Updated patient',
      'patient.delete' => 'Removed patient',
      'visit.record' => 'Recorded a consultation',
      'prescription.save' => 'Wrote a prescription',
      'prescription.dispense' => 'Dispensed a prescription',
      'stock.receive' => 'Received stock',
      'stock.issue' => 'Issued stock',
      'medicine.save' => 'Updated the formulary',
      'staff.create' => 'Added a staff member',
      'auth.signin' => 'Signed in',
      'auth.signout' => 'Signed out',
      _ => entry.action,
    };
    return entry.detail == null ? label : '$label — ${entry.detail}';
  }
}
