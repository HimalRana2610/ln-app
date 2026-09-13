import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/auth_controller.dart';
import '../application/security_controller.dart';

/// Six digits in, "123 456" and pasted codes included.
String? normaliseOtp(String input) {
  final digits = input.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{6}$').hasMatch(digits) ? digits : null;
}

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  int _cooldown = 0;
  String? _error;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wait = await ref.read(securityRepositoryProvider).sendOtp();
      if (!mounted) return;
      setState(() => _sent = true);
      _startCooldown(wait);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = normaliseOtp(_code.text);
    if (code == null) {
      setState(() => _error = 'Enter the six-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(securityRepositoryProvider).verifyOtp(code);
      await ref.read(authControllerProvider.notifier).refreshUser();
      ref.invalidate(mySecurityProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final email = auth is AuthAuthenticated ? auth.user.email : '';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _sent
                ? 'Enter the code sent to $email. It expires in 10 minutes.'
                : 'We will email a six-digit code to $email. '
                    'You need a verified email to mark attendance.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          if (_sent) ...[
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [LengthLimitingTextInputFormatter(9)],
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
              decoration: const InputDecoration(
                labelText: 'Verification code',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _busy ? null : (_sent ? _verify : _send),
            child: Text(_sent ? 'Verify email' : 'Send code'),
          ),
          if (_sent)
            TextButton(
              onPressed: _busy || _cooldown > 0 ? null : _send,
              child: Text(
                  _cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend code'),
            ),
        ],
      ),
    );
  }
}
