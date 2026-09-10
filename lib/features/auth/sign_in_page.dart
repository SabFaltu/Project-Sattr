import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../common/widgets.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim();
    if (username.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter both a username and a password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    final result =
        await context.read<AppState>().signIn(username, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.ok ? null : result.error;
      _notice = result.notice;
    });
    // A successful sign-in swaps this whole page out via the root widget, so
    // there is nothing more to do here.
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      content: Center(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    FluentIcons.heart_pulse_24_regular,
                    size: 30,
                    color: theme.accentColor.normal,
                  ),
                  const SizedBox(width: 10),
                  Text('Project सत्र', style: theme.typography.titleLarge),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                state.settings.clinicName,
                textAlign: TextAlign.center,
                style: theme.typography.body?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      InlineMessage(message: _error!, title: 'Cannot sign in'),
                    if (_notice != null)
                      InlineMessage(
                        message: _notice!,
                        severity: InfoBarSeverity.warning,
                        title: 'Working offline',
                      ),
                    LabeledField(
                      label: 'Username',
                      child: TextBox(
                        controller: _username,
                        autofocus: true,
                        placeholder: 'e.g. s.sharma',
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                      label: 'Password',
                      child: PasswordBox(
                        controller: _password,
                        focusNode: _passwordFocus,
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _busy
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: ProgressRing(strokeWidth: 2),
                              )
                            : const Text('Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _ModeFootnote(mode: state.settings.mode),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tells the user where their password is actually being checked.
///
/// Worth stating plainly: on a terminal, a sign-in needs the hub, and staff
/// should understand why a network outage changes what they can do.
class _ModeFootnote extends StatelessWidget {
  const _ModeFootnote({required this.mode});

  final DeploymentMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final text = switch (mode) {
      DeploymentMode.hub =>
        'This machine is the clinic hub. Accounts are verified here.',
      DeploymentMode.terminal =>
        'This is a terminal. Your password is checked by the clinic hub; if the '
            'hub is unreachable, accounts that have signed in here before can '
            'still work offline.',
      DeploymentMode.standalone =>
        'This machine is standalone. Accounts are verified here.',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          FluentIcons.info_20_regular,
          size: 14,
          color: theme.resources.textFillColorTertiary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Exposed so the shell can offer the same channel wording in its status bar.
String describeAuthChannel(AuthChannel channel) => switch (channel) {
      AuthChannel.local => 'Verified on this machine',
      AuthChannel.hub => 'Verified by the clinic hub',
      AuthChannel.cached => 'Signed in offline',
    };
