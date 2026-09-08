import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../note/application/note_controller.dart';
import '../../note/data/note_models.dart';
import '../../note/presentation/create_note_sheet.dart';
import '../application/classroom_controller.dart';
import '../data/classroom_models.dart';

/// One classroom: its notes, and the button to generate a new one.
class ClassroomScreen extends ConsumerStatefulWidget {
  const ClassroomScreen({required this.classroomId, super.key});

  final String classroomId;

  @override
  ConsumerState<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends ConsumerState<ClassroomScreen> {
  Timer? _pollTimer;

  String get classroomId => widget.classroomId;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Re-check while anything is still generating, and stop once it settles, so
  /// an idle screen makes no requests.
  void _syncPolling(List<NoteSummary> notes) {
    final generating = notes.any((note) => note.status.isGenerating);

    if (!generating) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    _pollTimer ??= Timer.periodic(
      notePollInterval,
      (_) => ref.invalidate(noteListProvider(classroomId)),
    );
  }

  Classroom? _classroom(WidgetRef ref) {
    final classrooms =
        ref.watch(classroomListProvider).value ?? const <Classroom>[];
    for (final classroom in classrooms) {
      if (classroom.id == classroomId) return classroom;
    }
    return null;
  }

  Future<void> _confirmDelete(NoteSummary note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        content:
            Text('"${note.title}" will be removed. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    // `mounted` on the State, not on a context captured before the await —
    // the analyzer cannot prove a captured context is still valid, and nor can
    // we if the screen was popped while the dialog was open.
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(noteActionsProvider(classroomId)).delete(note.id);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final classroom = _classroom(ref);
    final notesAsync = ref.watch(noteListProvider(classroomId));

    return Scaffold(
      appBar: AppBar(
        title: Text(classroom?.name ?? 'Classroom'),
        bottom: classroom == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${classroom.memberCount} '
                      '${classroom.memberCount == 1 ? 'member' : 'members'} · '
                      'Code ${classroom.code}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateNoteSheet(context, classroomId: classroomId),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('New note'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(noteListProvider(classroomId)),
        child: notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(32),
            children: [Text(error.toString(), textAlign: TextAlign.center)],
          ),
          data: (notes) {
            // Scheduled out of the build pass: starting or cancelling a timer
            // during build would mutate state mid-render.
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _syncPolling(notes),
            );

            if (notes.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
                children: [
                  Icon(
                    Icons.note_alt_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notes yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload a recording, paste text, or drop in a YouTube link.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: notes.length,
              itemBuilder: (context, index) => _NoteTile(
                note: notes[index],
                onOpen: () => context.push('/notes/${notes[index].id}'),
                onDelete: () => _confirmDelete(notes[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.onOpen,
    required this.onDelete,
  });

  final NoteSummary note;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = note.status == NoteStatus.ready;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        // Only a finished note has anything to show.
        onTap: ready ? onOpen : null,
        title: Text(note.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${note.date.day}/${note.date.month}/${note.date.year} · '
              '${note.sourceType.label} · ${note.authorName}',
              style: theme.textTheme.bodySmall,
            ),
            if (note.status == NoteStatus.failed &&
                note.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                note.errorMessage!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusChip(status: note.status),
            IconButton(
              tooltip: 'Delete note',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final NoteStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (background, foreground) = switch (status) {
      NoteStatus.ready => (scheme.primaryContainer, scheme.onPrimaryContainer),
      NoteStatus.failed => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: foreground, fontSize: 11),
      ),
    );
  }
}
