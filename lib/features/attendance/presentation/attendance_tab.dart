import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/attendance_controller.dart';
import '../data/attendance_models.dart';
import 'session_screens.dart';

/// A classroom's attendance sessions, newest first.
class AttendanceTab extends ConsumerWidget {
  const AttendanceTab({
    required this.classroomId,
    required this.canManage,
    super.key,
  });

  final String classroomId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(attendanceSessionsProvider(classroomId));
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(attendanceSessionsProvider(classroomId)),
      child: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [Text(error.toString(), textAlign: TextAlign.center)],
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
              children: [
                Icon(Icons.bluetooth_searching,
                    size: 48, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text('No attendance taken yet.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge),
                const SizedBox(height: 8),
                Text(
                  canManage
                      ? 'Start a session when the lecture begins. Students in the room are marked present over Bluetooth.'
                      : 'When your teacher starts a session, it appears here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: sessions.length,
            itemBuilder: (context, index) => SessionTile(
              session: sessions[index],
              canManage: canManage,
              onOpen: () async {
                await openSessionScreen(context,
                    session: sessions[index], canManage: canManage);
                ref.invalidate(attendanceSessionsProvider(classroomId));
              },
            ),
          );
        },
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({
    required this.session,
    required this.canManage,
    required this.onOpen,
    super.key,
  });

  final AttendanceSession session;
  final bool canManage;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = session.status.isRunning;
    final started = session.startedAt.toLocal();
    final time =
        '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}';

    final subtitle = canManage || session.myStatus == null
        ? '${session.presentCount} of ${session.recordCount} present · ${session.startedByName}'
        : 'You: ${session.myStatus!.label}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: running ? scheme.primaryContainer : null,
      child: ListTile(
        onTap: onOpen,
        leading: Icon(
          running ? Icons.bluetooth_audio : Icons.event_available_outlined,
          color: running ? scheme.onPrimaryContainer : null,
        ),
        title: Text('${session.date} · $time'),
        subtitle: Text(subtitle),
        trailing: _Chip(
          label: session.status.label,
          highlighted: session.status == SessionStatus.active,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.highlighted});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: highlighted
              ? scheme.onTertiaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
