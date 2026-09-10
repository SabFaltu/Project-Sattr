import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../appointments/appointments_page.dart';
import '../auth/sign_in_page.dart';
import '../common/widgets.dart';
import '../dashboard/dashboard_page.dart';
import '../medicines/medicines_page.dart';
import '../patients/patients_page.dart';
import '../prescriptions/prescriptions_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import '../staff/staff_page.dart';

/// The application frame: navigation on the left, the current module on the
/// right, and a status strip that says whether this machine is in touch with
/// the rest of the clinic.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Staff management is administrator-only, so the item is absent rather
    // than present-and-refusing.
    final items = <_Module>[
      const _Module(
        label: 'Dashboard',
        icon: FluentIcons.home_24_regular,
        selectedIcon: FluentIcons.home_24_filled,
        body: DashboardPage(),
      ),
      const _Module(
        label: 'Patients',
        icon: FluentIcons.people_24_regular,
        selectedIcon: FluentIcons.people_24_filled,
        body: PatientsPage(),
      ),
      const _Module(
        label: 'Appointments',
        icon: FluentIcons.calendar_ltr_24_regular,
        selectedIcon: FluentIcons.calendar_ltr_24_filled,
        body: AppointmentsPage(),
      ),
      const _Module(
        label: 'Prescriptions',
        icon: FluentIcons.document_bullet_list_24_regular,
        selectedIcon: FluentIcons.document_bullet_list_24_filled,
        body: PrescriptionsPage(),
      ),
      const _Module(
        label: 'Pharmacy',
        icon: FluentIcons.pill_24_regular,
        selectedIcon: FluentIcons.pill_24_filled,
        body: MedicinesPage(),
      ),
      const _Module(
        label: 'Reports',
        icon: FluentIcons.document_pdf_24_regular,
        selectedIcon: FluentIcons.document_pdf_24_filled,
        body: ReportsPage(),
      ),
      if (state.isAdmin)
        const _Module(
          label: 'Staff',
          icon: FluentIcons.person_board_24_regular,
          selectedIcon: FluentIcons.person_board_24_filled,
          body: StaffPage(),
        ),
    ];

    // Settings sits in the pane footer, and NavigationPane numbers footer
    // items straight on from the main ones. Clamping to the main list alone
    // would silently bounce every click on Settings back to the last module.
    const footerCount = 1;
    final safeIndex = _index.clamp(0, items.length + footerCount - 1);
    final settingsIndex = items.length;

    return NavigationView(
      titleBar: TitleBar(
        icon: Icon(
          FluentIcons.heart_pulse_20_filled,
          size: 16,
          color: FluentTheme.of(context).accentColor.normal,
        ),
        title: const Text('Project सत्र'),
        subtitle: Text(state.settings.clinicName),
        endHeader: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _SyncIndicator(),
              const SizedBox(width: 12),
              _AccountButton(),
            ],
          ),
        ),
      ),
      pane: NavigationPane(
        selected: safeIndex,
        onChanged: (i) => setState(() => _index = i),
        displayMode: PaneDisplayMode.auto,
        items: [
          // The filled variant of each glyph marks the current module, which is
          // the Fluent convention; PaneItem has no selected-icon slot of its
          // own, so the swap happens here.
          for (var i = 0; i < items.length; i++)
            PaneItem(
              icon: Icon(
                i == safeIndex ? items[i].selectedIcon : items[i].icon,
              ),
              title: Text(items[i].label),
              body: items[i].body,
            ),
        ],
        footerItems: [
          PaneItem(
            icon: Icon(
              safeIndex == settingsIndex
                  ? FluentIcons.settings_24_filled
                  : FluentIcons.settings_24_regular,
            ),
            title: const Text('Settings'),
            body: const SettingsPage(),
          ),
        ],
      ),
    );
  }
}

class _Module {
  const _Module({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.body,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;
}

/// Sync state, in the corner where a user can glance at it.
class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final mode = state.settings.mode;

    if (mode == DeploymentMode.standalone) {
      return Tooltip(
        message: 'This machine keeps its own records and is not networked.',
        child: StatusPill(
          'Standalone',
          icon: FluentIcons.desktop_20_regular,
          color: theme.resources.textFillColorSecondary,
        ),
      );
    }

    if (mode == DeploymentMode.hub) {
      final running = state.hub.isRunning;
      return Tooltip(
        message: running
            ? 'Serving the clinic on port ${state.hub.port}. '
                '${state.hub.peers.length} terminal(s) seen.'
            : state.hubError ?? 'The hub listener is not running.',
        child: StatusPill(
          running ? 'Hub · port ${state.hub.port}' : 'Hub stopped',
          icon: running
              ? FluentIcons.server_20_regular
              : FluentIcons.warning_20_regular,
          color: running ? SattraTheme.ok : SattraTheme.danger,
        ),
      );
    }

    if (state.isSyncing) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 14, width: 14, child: ProgressRing(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Syncing…'),
        ],
      );
    }

    final offline = state.auth.isOffline;
    final last = state.settings.lastSyncAt;
    final failed = state.lastSync != null && !state.lastSync!.ok;

    return Tooltip(
      message: offline
          ? 'Signed in offline. Work is saved here and will sync once the hub '
              'is reachable and you sign in again.'
          : failed
              ? state.lastSync!.error!
              : last == null
                  ? 'Not synced yet.'
                  : 'Last synced ${relative(last)} — ${state.lastSync?.summary ?? ''}',
      child: GestureDetector(
        onTap: () => state.syncNow(),
        child: StatusPill(
          offline
              ? 'Offline'
              : failed
                  ? 'Sync failed'
                  : last == null
                      ? 'Not synced'
                      : 'Synced ${relative(last)}',
          icon: offline || failed
              ? FluentIcons.cloud_off_20_regular
              : FluentIcons.cloud_sync_20_regular,
          color: offline || failed ? SattraTheme.warn : SattraTheme.ok,
        ),
      ),
    );
  }
}

/// Who is signed in, and how to stop being signed in.
class _AccountButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final user = state.currentUser!;

    return DropDownButton(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accentColor.normal.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              user.initials,
              style: theme.typography.caption?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.accentColor.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(user.fullName),
        ],
      ),
      items: [
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.person_20_regular),
          text: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.role.label),
              Text(
                state.auth.channel == null
                    ? ''
                    : describeAuthChannel(state.auth.channel!),
                style: theme.typography.caption?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                ),
              ),
            ],
          ),
          onPressed: null,
        ),
        const MenuFlyoutSeparator(),
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.key_20_regular),
          text: const Text('Change my password'),
          onPressed: () => _changePassword(context, state),
        ),
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.sign_out_20_regular),
          text: const Text('Sign out'),
          onPressed: () => state.signOut(),
        ),
      ],
    );
  }

  Future<void> _changePassword(BuildContext context, AppState state) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _PasswordDialog(
        title: 'Change my password',
        current: current,
        next: next,
        confirm: confirm,
        onSubmit: (setError) async {
          if (next.text != confirm.text) {
            setError('The new passwords do not match.');
            return false;
          }
          final error = await state.auth.setPassword(
            state.currentUser!.id,
            next.text,
          );
          if (error != null) {
            setError(error);
            return false;
          }
          return true;
        },
      ),
    );
    if (result == true && context.mounted) {
      notify(context, 'Your password has been changed.');
    }
  }
}

/// Password dialog shared by the account menu and the staff module.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.current,
    required this.next,
    required this.confirm,
    required this.onSubmit,
  });

  final String title;
  final TextEditingController current;
  final TextEditingController next;
  final TextEditingController confirm;
  final Future<bool> Function(void Function(String) setError) onSubmit;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(widget.title),
      constraints: const BoxConstraints(maxWidth: 420),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) InlineMessage(message: _error!),
          LabeledField(
            label: 'New password',
            hint: 'At least 6 characters.',
            child: PasswordBox(controller: widget.next, autofocus: true),
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Confirm new password',
            child: PasswordBox(controller: widget.confirm),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  // Resolved before the await so the dialog can still be
                  // dismissed without reaching back through a stale context.
                  final navigator = Navigator.of(context);
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  final ok = await widget.onSubmit(
                    (message) => setState(() => _error = message),
                  );
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (ok) navigator.pop(true);
                },
          child: const Text('Change password'),
        ),
      ],
    );
  }
}
