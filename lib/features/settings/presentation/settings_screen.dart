import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/theme_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../push/push_service.dart';

/// Profile, appearance, notifications, security and the account itself.
/// Ported from the old app's `pages/Settings.tsx`.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    if (authState is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _Header('Profile'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user.fullName),
            subtitle: Text([user.email, if (user.institute != null) user.institute!]
                .join(' · ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const _EditProfileDialog(),
            ),
          ),
          const _Header('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
              ],
              selected: {themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).set(selection.first),
            ),
          ),
          const _Header('Notifications'),
          const _PushToggle(),
          const _Header('Account'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Account security'),
            subtitle: const Text('Email, bound phone and face data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.security),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(authControllerProvider.notifier).logout(),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined,
                color: theme.colorScheme.error),
            title: Text('Delete account',
                style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text(
                'Removes your account, classes you own, notes and files'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const _DeleteAccountDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _PushToggle extends ConsumerStatefulWidget {
  const _PushToggle();

  @override
  ConsumerState<_PushToggle> createState() => _PushToggleState();
}

class _PushToggleState extends ConsumerState<_PushToggle> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(pushRegistrarProvider).isEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final registrar = ref.watch(pushRegistrarProvider);

    if (!registrar.isAvailable) {
      return const ListTile(
        leading: Icon(Icons.notifications_off_outlined),
        title: Text('Push notifications'),
        subtitle: Text('Not set up in this build'),
      );
    }

    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: const Text('Push notifications'),
      subtitle: const Text('New materials, assignments and attendance'),
      value: _enabled ?? true,
      onChanged: _busy || _enabled == null
          ? null
          : (value) async {
              setState(() {
                _busy = true;
                _enabled = value;
              });
              await registrar.setEnabled(value);
              if (mounted) setState(() => _busy = false);
            },
    );
  }
}

class _EditProfileDialog extends ConsumerStatefulWidget {
  const _EditProfileDialog();

  @override
  ConsumerState<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<_EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _institute;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = ref.read(authControllerProvider);
    final user = state is AuthAuthenticated ? state.user : null;
    _name = TextEditingController(text: user?.fullName ?? '');
    _institute = TextEditingController(text: user?.institute ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _institute.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            fullName: _name.text.trim(),
            institute: _institute.text.trim(),
          );
      navigator.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter your name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _institute,
              decoration: const InputDecoration(labelText: 'Institute'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(password: _password.text);
      // The session is gone; the router redirect has already moved to /login.
      if (navigator.mounted && navigator.canPop()) navigator.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.code == 'incorrect_password' ? 'Incorrect password' : error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes your account and everything you own. '
            'It cannot be undone. Enter your password to confirm.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error,
            ),
            onSubmitted: (_) => _delete(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: _busy ? null : _delete,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
