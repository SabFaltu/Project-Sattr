import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../services/backup_service.dart';
import '../../services/crypto_service.dart';
import '../../services/csv_service.dart';
import '../../services/data_reset_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../common/file_output.dart';
import '../common/widgets.dart';

/// Clinic identity, networking, and backups.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('Settings')),
      children: [
        const _ClinicCard(),
        const SizedBox(height: 12),
        const _AppearanceCard(),
        const SizedBox(height: 12),
        const _StorageCard(),
        const SizedBox(height: 12),
        const _NetworkCard(),
        const SizedBox(height: 12),
        const _BackupCard(),
        const SizedBox(height: 12),
        const _ImportCard(),
        const SizedBox(height: 12),
        const _DangerCard(),
        const SizedBox(height: 12),
        const _AboutCard(),
      ],
    );
  }
}



/// Light, dark, or whatever the desktop is doing.
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);

    return SectionCard(
      title: 'Appearance',
      subtitle: 'Applies to this machine only.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final mode in AppThemeMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ToggleButton(
                    checked: state.themeMode == mode,
                    onChanged: (_) => state.setThemeMode(mode),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          switch (mode) {
                            AppThemeMode.system =>
                              FluentIcons.desktop_20_regular,
                            AppThemeMode.light =>
                              FluentIcons.weather_sunny_20_regular,
                            AppThemeMode.dark =>
                              FluentIcons.weather_moon_20_regular,
                          },
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(mode.label),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.themeMode == AppThemeMode.system
                ? 'Currently showing the ${theme.brightness == Brightness.dark ? 'dark' : 'light'} theme, following the desktop.'
                : 'Fixed to the ${state.themeMode.label.toLowerCase()} theme.',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// What this machine is holding, how much room it takes, and where it lives.
class _StorageCard extends StatefulWidget {
  const _StorageCard();

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  bool _busy = false;
  String? _pendingLocation;

  Future<void> _chooseLocation() async {
    final directory = await getDirectoryPath(
      confirmButtonText: 'Use this folder',
    );
    if (directory == null || !mounted) return;

    final state = context.read<AppState>();
    final ok = await confirm(
      context,
      title: 'Move the clinic record?',
      message: 'The database will be copied to:\n\n$directory\n\n'
          'Sattra will use it from the next time the application starts. The '
          'copy at the old location is left in place until you are satisfied '
          'the move worked — delete it yourself once you are.',
      confirmLabel: 'Move database',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    await guarded(context, () async {
      final destination = await state.relocateDatabase(directory);
      if (!mounted) return;
      setState(() => _pendingLocation = destination);
      notify(
        context,
        'Copied to $destination. Restart Sattra to start using it.',
        title: 'Database moved',
      );
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _useDefault() async {
    final state = context.read<AppState>();
    setState(() => _busy = true);
    await guarded(context, () async {
      await state.useDefaultDatabaseLocation();
      if (!mounted) return;
      setState(() => _pendingLocation = state.defaultDatabasePath);
      notify(
        context,
        'Sattra will use the default location on the next start.',
        title: 'Location reset',
      );
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final storage = state.storage;
    final canManage = state.isAdmin;

    return SectionCard(
      title: 'Storage',
      subtitle: 'Everything is kept in a single database file on this machine.',
      trailing: StatusPill(
        storage.formattedSize,
        icon: FluentIcons.database_20_regular,
        color: theme.accentColor.normal,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in storage.counts.entries)
                _CountChip(label: entry.key, value: entry.value),
            ],
          ),
          const SizedBox(height: 14),
          DetailRow('On disk', '${storage.formattedSize} across '
              '${storage.totalRows} records'),
          DetailRow('Database file', state.db.path),
          if (state.settings.mode == DeploymentMode.terminal)
            DetailRow(
              'Waiting to sync',
              storage.pendingSync == 0
                  ? 'Nothing — the hub has everything from this machine'
                  : '${storage.pendingSync} record(s) not yet sent to the hub',
            ),
          if (_pendingLocation != null) ...[
            const SizedBox(height: 10),
            InlineMessage(
              severity: InfoBarSeverity.info,
              title: 'Takes effect on restart',
              message: 'From the next start, Sattra will use '
                  '$_pendingLocation.',
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Button(
                onPressed: _busy || !canManage ? null : _chooseLocation,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.folder_20_regular, size: 14),
                    SizedBox(width: 6),
                    Text('Move to another folder'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (state.config.databasePath != null)
                Button(
                  onPressed: _busy || !canManage ? null : _useDefault,
                  child: const Text('Use the default location'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Clinic records are text and dates, so the file stays small. It '
            'grows slowly with each consultation and never phones home. '
            'Putting it on a network share or an encrypted volume is a '
            'reasonable thing to do; putting it on removable media that may be '
            'unplugged mid-consultation is not.',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.typography.caption?.copyWith(
              fontSize: 9,
              letterSpacing: 0.6,
              color: theme.resources.textFillColorTertiary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$value',
            style: theme.typography.bodyStrong,
          ),
        ],
      ),
    );
  }
}

class _ClinicCard extends StatefulWidget {
  const _ClinicCard();

  @override
  State<_ClinicCard> createState() => _ClinicCardState();
}

class _ClinicCardState extends State<_ClinicCard> {
  late final TextEditingController _name =
      TextEditingController(text: context.read<AppState>().settings.clinicName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return SectionCard(
      title: 'Clinic',
      subtitle: 'The name printed at the top of every report.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: LabeledField(
              label: 'Clinic name',
              child: TextBox(
                controller: _name,
                enabled: state.isAdmin,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: state.isAdmin
                ? () {
                    state.settings.clinicName = _name.text.trim();
                    state.touch();
                    notify(context, 'Clinic name updated.');
                  }
                : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Deployment mode, hub address, clinic key, and the sync controls.
class _NetworkCard extends StatefulWidget {
  const _NetworkCard();

  @override
  State<_NetworkCard> createState() => _NetworkCardState();
}

class _NetworkCardState extends State<_NetworkCard> {
  late final AppState _state = context.read<AppState>();
  late DeploymentMode _mode = _state.settings.mode;
  late final TextEditingController _host =
      TextEditingController(text: _state.settings.hubHost);
  late final TextEditingController _port =
      TextEditingController(text: '${_state.settings.hubPort}');
  late final TextEditingController _listenPort =
      TextEditingController(text: '${_state.settings.listenPort}');
  late final TextEditingController _key =
      TextEditingController(text: _state.settings.clinicKey ?? '');

  String? _fingerprint;
  String? _testMessage;
  bool _testOk = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshFingerprint();
  }

  Future<void> _refreshFingerprint() async {
    final key = _key.text.trim();
    final value =
        key.isEmpty ? null : await CryptoService.fingerprint(key);
    if (mounted) setState(() => _fingerprint = value);
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _listenPort, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final settings = _state.settings;
    settings.mode = _mode;
    settings.clinicKey = _key.text.trim().isEmpty ? null : _key.text.trim();
    settings.hubHost = _host.text.trim();
    settings.hubPort =
        int.tryParse(_port.text.trim()) ?? SettingsService.defaultPort;
    settings.listenPort =
        int.tryParse(_listenPort.text.trim()) ?? SettingsService.defaultPort;
    await _state.reconfigureNetworking();
    if (!mounted) return;
    setState(() => _busy = false);
    notify(context, 'Network settings applied.');
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _testMessage = null;
    });
    final result = await _state.testHub(
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? SettingsService.defaultPort,
      clinicKey: _key.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _testOk = result.ok;
      _testMessage = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final canEdit = state.isAdmin;

    return SectionCard(
      title: 'Clinic network',
      subtitle: 'How this machine shares records with the rest of the clinic.',
      trailing: state.settings.mode == DeploymentMode.terminal
          ? FilledButton(
              onPressed: state.isSyncing ? null : () => state.syncNow(),
              child: state.isSyncing
                  ? const SizedBox(
                      height: 14, width: 14, child: ProgressRing(strokeWidth: 2))
                  : const Text('Sync now'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.hubError != null)
            InlineMessage(
              message: state.hubError!,
              title: 'The hub listener could not start',
            ),
          if (state.lastSync != null && !state.lastSync!.ok)
            InlineMessage(
              message: state.lastSync!.error!,
              severity: InfoBarSeverity.warning,
              title: 'Last sync did not complete',
            ),
          RadioGroup<DeploymentMode>(
            groupValue: _mode,
            // RadioGroup always wants a handler; the buttons themselves are
            // disabled for non-administrators, so this simply never fires.
            onChanged: (value) {
              if (!canEdit) return;
              setState(() => _mode = value ?? _mode);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final mode in DeploymentMode.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RadioButton<DeploymentMode>(
                      value: mode,
                      enabled: canEdit,
                      content: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mode.label),
                            Text(
                              mode.description,
                              style: theme.typography.caption?.copyWith(
                                color: theme.resources.textFillColorSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_mode != DeploymentMode.standalone) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Clinic key',
              hint: 'Shared by every machine in this clinic. It encrypts all '
                  'traffic between them, and a machine without it is refused.',
              child: Row(
                children: [
                  Expanded(
                    child: TextBox(
                      controller: _key,
                      enabled: canEdit,
                      onChanged: (_) => _refreshFingerprint(),
                    ),
                  ),
                  if (_mode == DeploymentMode.hub && canEdit) ...[
                    const SizedBox(width: 8),
                    Button(
                      onPressed: () {
                        _key.text = CryptoService.newClinicKey();
                        _refreshFingerprint();
                      },
                      child: const Text('Generate'),
                    ),
                  ],
                ],
              ),
            ),
            if (_fingerprint != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(FluentIcons.fingerprint_20_regular, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'Key fingerprint $_fingerprint — this should match on every '
                    'machine in the clinic.',
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (_mode == DeploymentMode.hub) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 160,
                  child: LabeledField(
                    label: 'Listen on port',
                    child: TextBox(controller: _listenPort, enabled: canEdit),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: _HubStatus()),
              ],
            ),
          ],
          if (_mode == DeploymentMode.terminal) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: LabeledField(
                    label: 'Hub address',
                    child: TextBox(
                      controller: _host,
                      enabled: canEdit,
                      placeholder: 'e.g. 192.168.1.10',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: LabeledField(
                    label: 'Port',
                    child: TextBox(controller: _port, enabled: canEdit),
                  ),
                ),
                const SizedBox(width: 10),
                Button(
                  onPressed: _busy ? null : _test,
                  child: const Text('Test connection'),
                ),
              ],
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: 10),
              InlineMessage(
                message: _testMessage!,
                severity: _testOk
                    ? InfoBarSeverity.success
                    : InfoBarSeverity.error,
                title: _testOk ? 'Hub reachable' : 'Could not reach the hub',
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  checked: state.settings.autoSync,
                  onChanged: canEdit
                      ? (v) {
                          state.settings.autoSync = v ?? true;
                          state.reconfigureNetworking();
                        }
                      : null,
                  content: const Text('Sync automatically every two minutes'),
                ),
                const Spacer(),
                Text(
                  state.settings.lastSyncAt == null
                      ? 'Never synced'
                      : 'Last synced ${relative(state.settings.lastSyncAt!)}'
                          '${state.lastSync?.ok == true ? ' — ${state.lastSync!.summary}' : ''}',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (canEdit) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : _apply,
                child: const Text('Apply network settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HubStatus extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final hub = state.hub;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusPill(
              hub.isRunning ? 'Listening on port ${hub.port}' : 'Not listening',
              color: hub.isRunning ? SattraTheme.ok : SattraTheme.danger,
              icon: FluentIcons.server_20_regular,
            ),
            const SizedBox(width: 10),
            Text(
              hub.peers.isEmpty
                  ? 'No terminals have connected yet.'
                  : '${hub.peers.length} terminal(s) seen, most recently '
                      '${relative(hub.peers.values.reduce((a, b) => a.isAfter(b) ? a : b))}.',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Terminals connect to this machine\'s address on the clinic network.',
          style: theme.typography.caption?.copyWith(
            color: theme.resources.textFillColorTertiary,
          ),
        ),
      ],
    );
  }
}

/// Encrypted export and restore, plus the plain database copy.
class _BackupCard extends StatefulWidget {
  const _BackupCard();

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _busy = false;

  Future<String?> _askPassphrase({
    required String title,
    required String label,
    required String hint,
    bool confirmTwice = false,
  }) =>
      showDialog<String>(
        context: context,
        builder: (context) => _PassphraseDialog(
          title: title,
          label: label,
          hint: hint,
          confirmTwice: confirmTwice,
        ),
      );

  Future<void> _export() async {
    final passphrase = await _askPassphrase(
      title: 'Encrypt this backup',
      label: 'Backup passphrase',
      hint: 'At least 8 characters. Without it the backup cannot be restored, '
          'and there is no way to recover it.',
      confirmTwice: true,
    );
    if (passphrase == null || !mounted) return;

    final state = context.read<AppState>();
    setState(() => _busy = true);
    await guarded(context, () async {
      await FileOutput.saveFile(
        context,
        suggestedName: state.backups.suggestedFileName(),
        typeLabel: 'Sattra backup',
        extension: BackupService.fileExtension,
        successMessage: 'Backup written',
        write: (path) => state.backups.export(path, passphrase),
      );
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    final file = await FileOutput.pickFile(
      typeLabel: 'Sattra backup',
      extension: BackupService.fileExtension,
    );
    if (file == null || !mounted) return;

    final state = context.read<AppState>();
    setState(() => _busy = true);
    await guarded(context, () async {
      final info = await state.backups.inspect(file.path);
      if (!mounted) return;

      final ok = await confirm(
        context,
        title: 'Restore over this clinic\'s records?',
        message: 'The backup is from ${info.clinic}, taken '
            '${fmtDateTime(info.createdAt)} and holding ${info.patients} '
            'patient record(s).\n\nEverything currently on this machine is '
            'replaced. This cannot be undone.',
        confirmLabel: 'Replace everything',
        destructive: true,
      );
      if (!ok || !mounted) return;

      final passphrase = await _askPassphrase(
        title: 'Unlock the backup',
        label: 'Backup passphrase',
        hint: 'The passphrase this file was encrypted with.',
      );
      if (passphrase == null || !mounted) return;

      final restored = await state.backups.restore(file.path, passphrase);
      state.auth.signOut();
      state.touch();
      if (!mounted) return;
      notify(
        context,
        'Restored ${restored.totalRows} records from ${restored.clinic}. '
        'Sign in again to continue.',
        title: 'Backup restored',
      );
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copyDatabase() async {
    final state = context.read<AppState>();
    setState(() => _busy = true);
    await guarded(context, () async {
      await FileOutput.saveFile(
        context,
        suggestedName: 'sattra-${isoDate(DateTime.now())}.db',
        typeLabel: 'SQLite database',
        extension: 'db',
        successMessage: 'Database copied',
        write: (path) => state.backups.copyDatabaseFile(path),
      );
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final canBackUp = state.isAdmin;

    return SectionCard(
      title: 'Backups',
      subtitle: 'A backup carries the entire clinic record, so it is '
          'encrypted with a passphrase you choose.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canBackUp)
            const InlineMessage(
              severity: InfoBarSeverity.info,
              title: 'Administrators only',
              message: 'Taking a backup exports every patient record on this '
                  'machine, so it is restricted to administrator accounts.',
            ),
          Row(
            children: [
              FilledButton(
                onPressed: _busy || !canBackUp ? null : _export,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.arrow_download_20_regular, size: 14),
                    SizedBox(width: 6),
                    Text('Create encrypted backup'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _busy || !canBackUp ? null : _restore,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.arrow_upload_20_regular, size: 14),
                    SizedBox(width: 6),
                    Text('Restore from backup'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _busy || !canBackUp ? null : _copyDatabase,
                child: const Text('Copy database file'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DetailRow(
            'Will contain',
            '${state.storage.totalRows} records · ${state.storage.formattedSize}',
          ),
          DetailRow(
            'Last backup',
            'Sattra does not track this — keep backups where your clinic keeps '
                'its other records.',
          ),
          const SizedBox(height: 6),
          Text(
            'The encrypted backup includes staff accounts and their password '
            'verifiers, so a restored machine can sign people in on its own. '
            'The plain database copy is for administrators who keep their own '
            'snapshots — it is not encrypted, so store it accordingly.',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}


/// Bringing an existing register in from a spreadsheet.
///
/// The sample download comes first deliberately: the reliable way to explain a
/// file format is to hand someone a filled-in example they can open in the
/// program they already use.
class _ImportCard extends StatefulWidget {
  const _ImportCard();

  @override
  State<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends State<_ImportCard> {
  CsvImportKind _kind = CsvImportKind.patients;
  bool _busy = false;
  CsvImportResult? _result;

  Future<void> _downloadSample() async {
    setState(() => _busy = true);
    await guarded(context, () async {
      await FileOutput.saveFile(
        context,
        suggestedName: CsvService.sampleFileName(_kind),
        typeLabel: 'CSV spreadsheet',
        extension: 'csv',
        successMessage: 'Sample file saved',
        write: (path) async {
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsString(_kind.sample);
          return file;
        },
      );
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _import() async {
    final picked = await FileOutput.pickFile(
      typeLabel: 'CSV spreadsheet',
      extension: 'csv',
    );
    if (picked == null || !mounted) return;

    final state = context.read<AppState>();
    setState(() {
      _busy = true;
      _result = null;
    });

    await guarded(context, () async {
      final text = await File(picked.path).readAsString();

      // Read it once without writing anything, so the confirmation can say how
      // many records are actually about to arrive.
      final preview = switch (_kind) {
        CsvImportKind.patients =>
          state.csv.importPatients(text, dryRun: true),
        CsvImportKind.medicines =>
          state.csv.importMedicines(text, dryRun: true),
      };
      if (!mounted) return;

      if (preview.imported == 0) {
        setState(() => _result = preview);
        return;
      }

      final ok = await confirm(
        context,
        title: 'Import ${preview.imported} ${_kind.label.toLowerCase()}?',
        message: 'They will be added to this clinic\'s records.'
            '${preview.hasProblems ? '\n\n${preview.problems.length} row(s) '
                'have problems and will be skipped or imported partially.' : ''}',
        confirmLabel: 'Import',
      );
      if (!ok || !mounted) return;

      final result = switch (_kind) {
        CsvImportKind.patients =>
          state.csv.importPatients(text, by: state.currentUser),
        CsvImportKind.medicines =>
          state.csv.importMedicines(text, by: state.currentUser),
      };
      state.touch();
      if (!mounted) return;
      setState(() => _result = result);
      notify(context, result.summary, title: 'Import finished');
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final canImport = state.isAdmin;
    final result = _result;

    return SectionCard(
      title: 'Import existing records',
      subtitle: 'Bring a register in from Excel, Google Sheets or any other '
          'system that can save a CSV file.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canImport)
            const InlineMessage(
              severity: InfoBarSeverity.info,
              title: 'Administrators only',
              message: 'Importing writes directly into the clinic register, so '
                  'it is restricted to administrator accounts.',
            ),
          RadioGroup<CsvImportKind>(
            groupValue: _kind,
            onChanged: (value) {
              if (!canImport) return;
              setState(() {
                _kind = value ?? _kind;
                _result = null;
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final kind in CsvImportKind.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RadioButton<CsvImportKind>(
                      value: kind,
                      enabled: canImport,
                      content: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(kind.label),
                            Text(
                              kind.description,
                              style: theme.typography.caption?.copyWith(
                                color: theme.resources.textFillColorSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Expected columns', style: theme.typography.bodyStrong),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final column in _kind.columns)
                StatusPill(
                  column,
                  color: column == 'name'
                      ? theme.accentColor.normal
                      : theme.resources.textFillColorSecondary,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Only "name" is required. Column order does not matter, and '
            'headings may use spaces or dashes instead of underscores.',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Button(
                onPressed: _busy || !canImport ? null : _downloadSample,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.arrow_download_20_regular, size: 14),
                    SizedBox(width: 6),
                    Text('Download sample CSV'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy || !canImport ? null : _import,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.document_arrow_up_20_regular, size: 14),
                    SizedBox(width: 6),
                    Text('Choose a CSV file'),
                  ],
                ),
              ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 14),
            InlineMessage(
              message: result.summary,
              severity: result.imported == 0
                  ? InfoBarSeverity.warning
                  : InfoBarSeverity.success,
              title: result.imported == 0
                  ? 'Nothing was imported'
                  : 'Import finished',
            ),
            if (result.hasProblems)
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  color: theme.resources.subtleFillColorSecondary,
                  borderRadius: BorderRadius.circular(5),
                ),
                padding: const EdgeInsets.all(10),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final problem in result.problems)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          problem.toString(),
                          style: theme.typography.caption,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}


/// Clearing records out — after a trial, or after training on made-up data.
class _DangerCard extends StatefulWidget {
  const _DangerCard();

  @override
  State<_DangerCard> createState() => _DangerCardState();
}

class _DangerCardState extends State<_DangerCard> {
  ResetScope _scope = ResetScope.patientRecords;
  bool _busy = false;

  Future<void> _run() async {
    final state = context.read<AppState>();
    final count = state.reset.countFor(_scope);
    if (count == 0) {
      notify(
        context,
        'There is nothing in that category to delete.',
        title: 'Nothing to do',
        severity: InfoBarSeverity.info,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _TypedConfirmDialog(
        title: 'Delete ${_scope.label.toLowerCase()}?',
        body: '$count record(s) will be removed from this clinic.\n\n'
            '${_scope.description}\n\n'
            '${state.settings.mode == DeploymentMode.standalone ? 'This machine is standalone, so the records are removed outright and the database file is compacted.' : 'This machine is on a clinic network, so the deletion will also be sent to the other terminals on the next sync.'}',
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final outcome = state.reset.reset(_scope, by: state.currentUser);
    state.touch();
    if (!mounted) return;
    setState(() => _busy = false);
    notify(context, outcome.summary, title: 'Records deleted');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final canDelete = state.isAdmin;

    return SectionCard(
      title: 'Delete records',
      subtitle: 'For clearing out demo or training data before a clinic goes '
          'live.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canDelete)
            const InlineMessage(
              severity: InfoBarSeverity.info,
              title: 'Administrators only',
              message: 'Deleting records in bulk is restricted to '
                  'administrator accounts.',
            )
          else
            const InlineMessage(
              severity: InfoBarSeverity.warning,
              title: 'This cannot be undone',
              message: 'Take a backup first if there is any chance you will '
                  'want these records back.',
            ),
          RadioGroup<ResetScope>(
            groupValue: _scope,
            onChanged: (value) {
              if (!canDelete) return;
              setState(() => _scope = value ?? _scope);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final scope in ResetScope.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RadioButton<ResetScope>(
                      value: scope,
                      enabled: canDelete,
                      content: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${scope.label} · '
                              '${state.reset.countFor(scope)} record(s)',
                            ),
                            Text(
                              scope.description,
                              style: theme.typography.caption?.copyWith(
                                color: theme.resources.textFillColorSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(SattraTheme.danger),
              ),
              onPressed: _busy || !canDelete ? null : _run,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.delete_20_regular, size: 14),
                  SizedBox(width: 6),
                  Text('Delete these records'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Staff accounts and passwords are never removed here, so you '
            'cannot lock yourself out of the installation.',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation that cannot be clicked through by reflex.
class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({required this.title, required this.body});

  final String title;
  final String body;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches =
        _input.text.trim().toUpperCase() == DataResetService.confirmationPhrase;

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Text(widget.title),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.body),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Type ${DataResetService.confirmationPhrase} to confirm',
            child: TextBox(
              controller: _input,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: const ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(SattraTheme.danger),
          ),
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.title,
    required this.label,
    required this.hint,
    this.confirmTwice = false,
  });

  final String title;
  final String label;
  final String hint;
  final bool confirmTwice;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 460),
      title: Text(widget.title),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) InlineMessage(message: _error!),
          LabeledField(
            label: widget.label,
            hint: widget.hint,
            child: PasswordBox(controller: _first, autofocus: true),
          ),
          if (widget.confirmTwice) ...[
            const SizedBox(height: 12),
            LabeledField(
              label: 'Confirm passphrase',
              child: PasswordBox(controller: _second),
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (widget.confirmTwice) {
              if (_first.text.length < 8) {
                setState(() => _error = 'Use at least 8 characters.');
                return;
              }
              if (_first.text != _second.text) {
                setState(() => _error = 'The passphrases do not match.');
                return;
              }
            } else if (_first.text.isEmpty) {
              setState(() => _error = 'Enter the passphrase.');
              return;
            }
            Navigator.pop(context, _first.text);
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);

    return SectionCard(
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailRow('Application', 'Project सत्र — clinic patient management'),
          DetailRow('This machine', state.settings.mode.label),
          DetailRow('Node id', state.db.nodeId),
          DetailRow(
            'Offline accounts cached here',
            '${state.credentials.cachedAccountCount}',
          ),
          const SizedBox(height: 8),
          Text(
            'Open source, self-hosted, and built to run without an internet '
            'connection. Records stay on the clinic\'s own machines.',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
