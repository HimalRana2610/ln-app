import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/server_connection.dart';

/// Shown while the server is located and the session restored from secure
/// storage.
///
/// Exists so a returning user never sees the login screen flash before their
/// stored session is checked. It also says when the wait is a network search
/// rather than a hung app — that search can take a few seconds on a cold start
/// when the backend has moved.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serverConnectionProvider);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            ValueListenableBuilder<ServerStatus>(
              valueListenable: connection.status,
              builder: (context, status, _) => Text(
                status.phase == ServerPhase.locating
                    ? 'Looking for the server…'
                    : '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
