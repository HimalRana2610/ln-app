import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_url.dart';
import '../../../core/network/server_connection.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';

/// Opens the server picker.
Future<void> showServerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ServerSheet(),
  );
}

/// A line showing which backend the app is talking to, with a way to change it.
///
/// Only shown for a backend on this network. A released build points at a
/// deployed server that never moves, and offering to search for it there would
/// be noise.
class ServerStatusBar extends ConsumerWidget {
  const ServerStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serverConnectionProvider);
    final theme = Theme.of(context);

    return ValueListenableBuilder<ServerStatus>(
      valueListenable: connection.status,
      builder: (context, status, _) {
        if (!status.isLocal) return const SizedBox.shrink();

        final isLocating = status.phase == ServerPhase.locating;
        final isUnreachable = status.phase == ServerPhase.unreachable;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUnreachable ? Icons.cloud_off : Icons.dns_outlined,
              size: 16,
              color: isUnreachable
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isLocating
                    ? 'Looking for the server…'
                    : isUnreachable
                        ? 'No server found'
                        : status.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isUnreachable
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline,
                ),
              ),
            ),
            TextButton(
              onPressed: isLocating ? null : () => showServerSheet(context),
              child: const Text('Change'),
            ),
          ],
        );
      },
    );
  }
}

class _ServerSheet extends ConsumerStatefulWidget {
  const _ServerSheet();

  @override
  ConsumerState<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends ConsumerState<_ServerSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: ServerUrl.display(ref.read(serverConnectionProvider).baseUrl),
  );

  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ServerConnection get _connection => ref.read(serverConnectionProvider);

  Future<void> _save() async {
    // Captured before the await: after the sheet pops, its context can no
    // longer look either of these up.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isBusy = true;
      _error = null;
    });

    final error = await _connection.useServer(_controller.text);
    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _error = error;
    });

    if (error == null) {
      _close(navigator, messenger, 'Connected to ${_connection.label}');
    }
  }

  Future<void> _search() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isBusy = true;
      _error = null;
    });

    final found = await _connection.relocate();
    if (!mounted) return;

    setState(() {
      _isBusy = false;
      _error = found
          ? null
          : 'No LectureNote server found on this network. Check the backend '
              'is running and that the phone is on the same Wi-Fi.';
      if (found) _controller.text = ServerUrl.display(_connection.baseUrl);
    });

    if (found) _close(navigator, messenger, 'Found ${_connection.label}');
  }

  void _close(
    NavigatorState navigator,
    ScaffoldMessengerState messenger,
    String message,
  ) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Keeps the field above the keyboard.
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Server', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'The app finds the backend on its own. Set an address here only '
            'when it cannot — on a network that blocks devices from seeing '
            'each other, for example.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _controller,
            label: 'Address',
            hintText: '192.168.1.3:8000',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            helperText: 'Host and port, or a full URL',
            onFieldSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: 'Test and save',
            isLoading: _isBusy,
            onPressed: _save,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _isBusy ? null : _search,
            icon: const Icon(Icons.wifi_find_outlined),
            label: const Text('Search this network'),
          ),
        ],
      ),
    );
  }
}
