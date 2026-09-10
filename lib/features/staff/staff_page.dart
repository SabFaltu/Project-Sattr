import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../common/widgets.dart';

/// Staff records and the accounts that go with them. Administrators only.
class StaffPage extends StatelessWidget {
  const StaffPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final everyone = state.staff.all();
    final isHub = state.settings.mode != DeploymentMode.terminal;

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Staff'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.person_add_24_regular),
              label: const Text('Add staff member'),
              onPressed: () => StaffFormDialog.show(context),
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isHub)
              const InlineMessage(
                severity: InfoBarSeverity.info,
                title: 'Passwords are set on the hub',
                message: 'This is a terminal, so it does not hold the clinic\'s '
                    'password file. Adding a person here creates their record '
                    'and syncs it, but their first password has to be set from '
                    'the hub — or from here once you are signed in against it.',
              ),
            Expanded(
              child: Card(
                padding: const EdgeInsets.all(12),
                child: everyone.isEmpty
                    ? const EmptyState(
                        icon: FluentIcons.person_board_24_regular,
                        title: 'No staff records',
                      )
                    : ListView.separated(
                        itemCount: everyone.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) => _StaffTile(
                          staff: everyone[index],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Every record in the clinic is signed with the account that made '
              'it, so accounts are deactivated rather than deleted.',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.staff});

  final Staff staff;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final isSelf = state.currentUser?.id == staff.id;
    final hasPassword = state.credentials.hasPassword(staff.id);
    final isHub = state.settings.mode != DeploymentMode.terminal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accentColor.normal
                  .withValues(alpha: staff.active ? 0.15 : 0.06),
              shape: BoxShape.circle,
            ),
            child: Text(
              staff.initials,
              style: theme.typography.caption?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.accentColor.normal
                    .withValues(alpha: staff.active ? 1 : 0.5),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.fullName, style: theme.typography.body),
                Text(
                  [
                    staff.username,
                    if ((staff.speciality ?? '').isNotEmpty) staff.speciality!,
                    'joined ${fmtDate(staff.createdAt)}',
                  ].join(' · '),
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          StatusPill(
            staff.role.label,
            color: staff.isAdmin ? SattraTheme.info : null,
            icon: staff.isAdmin
                ? FluentIcons.shield_20_regular
                : FluentIcons.stethoscope_20_regular,
          ),
          const SizedBox(width: 8),
          if (!staff.active)
            const StatusPill('Deactivated', color: SattraTheme.danger)
          else if (isHub && !hasPassword)
            const StatusPill(
              'No password set',
              color: SattraTheme.warn,
              icon: FluentIcons.key_20_regular,
            ),
          const SizedBox(width: 8),
          DropDownButton(
            title: const Icon(FluentIcons.more_horizontal_20_regular, size: 14),
            items: [
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.edit_20_regular),
                text: const Text('Edit details'),
                onPressed: () => StaffFormDialog.show(context, existing: staff),
              ),
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.key_20_regular),
                text: Text(hasPassword ? 'Reset password' : 'Set password'),
                onPressed: () => _setPassword(context, state, staff),
              ),
              if (staff.active && !isSelf)
                MenuFlyoutItem(
                  leading: const Icon(FluentIcons.person_delete_20_regular),
                  text: const Text('Deactivate'),
                  onPressed: () => _deactivate(context, state, staff),
                ),
              if (!staff.active)
                MenuFlyoutItem(
                  leading:
                      const Icon(FluentIcons.person_available_20_regular),
                  text: const Text('Reactivate'),
                  onPressed: () {
                    state.staff.save(
                      staff.copyWith(active: true),
                      by: state.currentUser,
                    );
                    state.touch();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deactivate(
    BuildContext context,
    AppState state,
    Staff staff,
  ) async {
    // Locking the last administrator out is unrecoverable without a backup, so
    // the check is here rather than in the confirmation copy.
    if (staff.isAdmin && state.staff.adminCount <= 1) {
      notify(
        context,
        'This is the only active administrator. Promote someone else first.',
        title: 'Cannot deactivate',
        severity: InfoBarSeverity.error,
      );
      return;
    }
    final ok = await confirm(
      context,
      title: 'Deactivate ${staff.fullName}?',
      message: 'They will no longer be able to sign in. Their name stays on '
          'everything they recorded.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (!ok) return;
    state.staff.deactivate(staff, by: state.currentUser);
    state.touch();
  }

  Future<void> _setPassword(
    BuildContext context,
    AppState state,
    Staff staff,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _SetPasswordDialog(staff: staff),
    );
    if (result == null) return;
    final error = await state.auth.setPassword(staff.id, result);
    if (!context.mounted) return;
    if (error != null) {
      notify(context, error,
          title: 'Password not changed', severity: InfoBarSeverity.error);
    } else {
      state.touch();
      notify(context, 'Password set for ${staff.fullName}.');
    }
  }
}

class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog({required this.staff});

  final Staff staff;

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      title: Text('Set a password for ${widget.staff.fullName}'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) InlineMessage(message: _error!),
          LabeledField(
            label: 'New password',
            hint: 'At least 6 characters. Ask them to change it after signing '
                'in.',
            child: PasswordBox(controller: _password, autofocus: true),
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Confirm',
            child: PasswordBox(controller: _confirm),
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
            if (_password.text.length < 6) {
              setState(() => _error = 'Use at least 6 characters.');
              return;
            }
            if (_password.text != _confirm.text) {
              setState(() => _error = 'The passwords do not match.');
              return;
            }
            Navigator.pop(context, _password.text);
          },
          child: const Text('Set password'),
        ),
      ],
    );
  }
}

/// Adds or edits a staff record.
class StaffFormDialog extends StatefulWidget {
  const StaffFormDialog({super.key, this.existing});

  final Staff? existing;

  static Future<void> show(BuildContext context, {Staff? existing}) =>
      showDialog<void>(
        context: context,
        builder: (context) => StaffFormDialog(existing: existing),
      );

  @override
  State<StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<StaffFormDialog> {
  late final TextEditingController _fullName;
  late final TextEditingController _username;
  late final TextEditingController _speciality;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late UserRole _role;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _fullName = TextEditingController(text: s?.fullName ?? '');
    _username = TextEditingController(text: s?.username ?? '');
    _speciality = TextEditingController(text: s?.speciality ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _email = TextEditingController(text: s?.email ?? '');
    _password = TextEditingController();
    _role = s?.role ?? UserRole.provider;
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _username,
      _speciality,
      _phone,
      _email,
      _password,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final fullName = _fullName.text.trim();
    final username = _username.text.trim().toLowerCase();

    if (fullName.isEmpty) {
      setState(() => _error = 'Enter their name.');
      return;
    }
    if (username.length < 3) {
      setState(() => _error = 'Choose a username of at least 3 characters.');
      return;
    }
    if (state.staff.usernameTaken(username, exceptId: widget.existing?.id)) {
      setState(() => _error = 'That username is already in use.');
      return;
    }
    // Demoting the last administrator would leave nobody able to manage the
    // clinic, so it is refused rather than warned about.
    if (!_isNew &&
        widget.existing!.isAdmin &&
        _role != UserRole.admin &&
        state.staff.adminCount <= 1) {
      setState(() => _error =
          'This is the only administrator. Promote someone else first.');
      return;
    }
    if (_isNew &&
        state.settings.mode != DeploymentMode.terminal &&
        _password.text.isNotEmpty &&
        _password.text.length < 6) {
      setState(() => _error = 'The password must be at least 6 characters.');
      return;
    }

    if (_isNew) {
      final created = state.staff.create(
        username: username,
        fullName: fullName,
        role: _role,
        speciality:
            _speciality.text.trim().isEmpty ? null : _speciality.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        by: state.currentUser,
      );
      if (_password.text.isNotEmpty) {
        final error = await state.auth.setPassword(created.id, _password.text);
        if (error != null && mounted) {
          setState(() => _error = error);
          state.touch();
          return;
        }
      }
    } else {
      state.staff.save(
        widget.existing!.copyWith(
          username: username,
          fullName: fullName,
          role: _role,
          speciality:
              _speciality.text.trim().isEmpty ? null : _speciality.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        ),
        by: state.currentUser,
      );
    }
    state.touch();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final canSetPassword =
        _isNew && state.settings.mode != DeploymentMode.terminal;

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560),
      title: Text(_isNew ? 'Add a staff member' : 'Edit ${widget.existing!.fullName}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) InlineMessage(message: _error!),
            LabeledField(
              label: 'Full name',
              child: TextBox(controller: _fullName, autofocus: true),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Username',
                    child: TextBox(
                      controller: _username,
                      placeholder: 'e.g. b.kihore',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: 'Role',
                    child: ComboBox<UserRole>(
                      value: _role,
                      isExpanded: true,
                      items: [
                        for (final role in UserRole.values)
                          ComboBoxItem(value: role, child: Text(role.label)),
                      ],
                      onChanged: (v) => setState(() => _role = v ?? _role),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Speciality',
              child: TextBox(
                controller: _speciality,
                placeholder: 'optional — appears on printed slips',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Phone',
                    child: TextBox(controller: _phone),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: 'Email',
                    child: TextBox(controller: _email),
                  ),
                ),
              ],
            ),
            if (canSetPassword) ...[
              const SizedBox(height: 12),
              LabeledField(
                label: 'Initial password',
                hint: 'Optional — you can set one later from the staff list.',
                child: PasswordBox(controller: _password),
              ),
            ],
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
          child: Text(_isNew ? 'Add staff member' : 'Save changes'),
        ),
      ],
    );
  }
}
