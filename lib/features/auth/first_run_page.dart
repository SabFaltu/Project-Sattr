import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../services/crypto_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../common/widgets.dart';

/// Setup shown once, on a database with no accounts in it.
///
/// It asks only what cannot be guessed and cannot be changed later without
/// pain: what the clinic is called, how this machine fits into the network,
/// and who the first administrator is.
class FirstRunPage extends StatefulWidget {
  const FirstRunPage({super.key});

  @override
  State<FirstRunPage> createState() => _FirstRunPageState();
}

class _FirstRunPageState extends State<FirstRunPage> {
  final _clinic = TextEditingController(text: 'Sattra Clinic');
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _hubHost = TextEditingController();
  final _hubPort = TextEditingController(text: '${SettingsService.defaultPort}');
  final _clinicKey = TextEditingController();

  DeploymentMode _mode = DeploymentMode.standalone;
  int _step = 0;
  bool _busy = false;
  String? _error;
  String? _testResult;

  @override
  void dispose() {
    for (final c in [
      _clinic,
      _fullName,
      _username,
      _password,
      _confirm,
      _hubHost,
      _hubPort,
      _clinicKey,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateStepOne() {
    if (_clinic.text.trim().isEmpty) return 'Give the clinic a name.';
    if (_mode != DeploymentMode.standalone && _clinicKey.text.trim().isEmpty) {
      return 'A clinic key is required to join or serve a network.';
    }
    if (_mode == DeploymentMode.terminal) {
      if (_hubHost.text.trim().isEmpty) {
        return 'Enter the address of the clinic hub.';
      }
      if (int.tryParse(_hubPort.text.trim()) == null) {
        return 'The hub port must be a number.';
      }
    }
    return null;
  }

  String? _validateStepTwo() {
    if (_fullName.text.trim().isEmpty) return 'Enter the administrator\'s name.';
    final username = _username.text.trim();
    if (username.length < 3) {
      return 'Choose a username of at least 3 characters.';
    }
    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(username.toLowerCase())) {
      return 'Usernames may contain letters, numbers, dots, dashes and '
          'underscores only.';
    }
    if (_password.text.length < 6) {
      return 'Choose a password of at least 6 characters.';
    }
    if (_password.text != _confirm.text) return 'The passwords do not match.';
    return null;
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _testResult = null;
    });
    final result = await context.read<AppState>().testHub(
          host: _hubHost.text.trim(),
          port: int.tryParse(_hubPort.text.trim()) ?? SettingsService.defaultPort,
          clinicKey: _clinicKey.text.trim(),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _testResult = result.message;
      _error = result.ok ? null : result.message;
    });
  }

  Future<void> _finish() async {
    // A terminal never reaches the second step, so there are no administrator
    // fields to check — validating them would fail on inputs the user has not
    // been shown.
    if (_mode != DeploymentMode.terminal) {
      final problem = _validateStepTwo();
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final state = context.read<AppState>();
    final settings = state.settings;
    settings.clinicName = _clinic.text.trim();
    settings.mode = _mode;
    if (_mode != DeploymentMode.standalone) {
      settings.clinicKey = _clinicKey.text.trim();
    }
    if (_mode == DeploymentMode.terminal) {
      settings.hubHost = _hubHost.text.trim();
      settings.hubPort =
          int.tryParse(_hubPort.text.trim()) ?? SettingsService.defaultPort;
    }

    // A terminal's accounts come from the hub, so it does not mint a local
    // administrator; a hub or standalone install must have one.
    if (_mode != DeploymentMode.terminal) {
      await state.auth.createFirstAdmin(
        username: _username.text.trim().toLowerCase(),
        fullName: _fullName.text.trim(),
        password: _password.text,
      );
    }
    await state.reconfigureNetworking();
    if (!mounted) return;
    setState(() => _busy = false);
    state.touch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ScaffoldPage(
      content: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: SizedBox(
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      FluentIcons.heart_pulse_24_regular,
                      size: 28,
                      color: theme.accentColor.normal,
                    ),
                    const SizedBox(width: 10),
                    Text('Set up Project सत्र',
                        style: theme.typography.titleLarge),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _step == 0
                      ? 'Step 1 of 2 — this clinic and this machine'
                      : 'Step 2 of 2 — the first administrator',
                  textAlign: TextAlign.center,
                  style: theme.typography.body?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null) InlineMessage(message: _error!),
                      if (_step == 0) ..._clinicStep(theme) else ..._adminStep(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_step == 1)
                      Button(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _step = 0;
                                  _error = null;
                                }),
                        child: const Text('Back'),
                      )
                    else
                      const SizedBox.shrink(),
                    FilledButton(
                      onPressed: _busy ? null : _next,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _busy
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: ProgressRing(strokeWidth: 2),
                              )
                            : Text(_nextLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _nextLabel {
    if (_step == 0) {
      return _mode == DeploymentMode.terminal ? 'Join clinic' : 'Continue';
    }
    return 'Create account and start';
  }

  void _next() {
    if (_step == 0) {
      final problem = _validateStepOne();
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
      // A terminal takes its accounts from the hub, so there is no second step.
      if (_mode == DeploymentMode.terminal) {
        _finish();
        return;
      }
      setState(() {
        _step = 1;
        _error = null;
      });
      return;
    }
    _finish();
  }

  List<Widget> _clinicStep(FluentThemeData theme) => [
        LabeledField(
          label: 'Clinic name',
          hint: 'Appears on the printed case sheets and prescriptions.',
          child: TextBox(controller: _clinic, autofocus: true),
        ),
        const SizedBox(height: 16),
        Text('How this machine is used', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        RadioGroup<DeploymentMode>(
          groupValue: _mode,
          onChanged: (value) => setState(() {
            _mode = value ?? _mode;
            _error = null;
            _testResult = null;
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final mode in DeploymentMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: RadioButton<DeploymentMode>(
                    value: mode,
                    content: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(mode.label, style: theme.typography.body),
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
            hint: _mode == DeploymentMode.hub
                ? 'Every terminal must be given this exact key. It encrypts all '
                    'traffic between machines, so treat it like a password.'
                : 'Type the key shown on the clinic hub.',
            child: Row(
              children: [
                Expanded(child: TextBox(controller: _clinicKey)),
                if (_mode == DeploymentMode.hub) ...[
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () => setState(
                      () => _clinicKey.text = CryptoService.newClinicKey(),
                    ),
                    child: const Text('Generate'),
                  ),
                ],
              ],
            ),
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
                    controller: _hubHost,
                    placeholder: 'e.g. 192.168.1.10',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LabeledField(
                  label: 'Port',
                  child: TextBox(controller: _hubPort),
                ),
              ),
              const SizedBox(width: 10),
              Button(
                onPressed: _busy ? null : _testConnection,
                child: const Text('Test'),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 10),
            InlineMessage(
              message: _testResult!,
              severity: _error == null
                  ? InfoBarSeverity.success
                  : InfoBarSeverity.error,
              title: _error == null ? 'Hub reachable' : 'Could not reach the hub',
            ),
          ],
        ],
      ];

  List<Widget> _adminStep() => [
        LabeledField(
          label: 'Full name',
          child: TextBox(controller: _fullName, autofocus: true),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Username',
          hint: 'Used to sign in. Lower case, no spaces.',
          child: TextBox(controller: _username, placeholder: 'e.g. s.sharma'),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Password',
          hint: 'At least 6 characters.',
          child: PasswordBox(controller: _password),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Confirm password',
          child: PasswordBox(
            controller: _confirm,
            onSubmitted: (_) => _finish(),
          ),
        ),
      ];
}
