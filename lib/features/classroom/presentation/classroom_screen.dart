import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../attendance/application/attendance_controller.dart';
import '../../attendance/presentation/attendance_tab.dart';
import '../../attendance/presentation/session_screens.dart';
import '../../security/presentation/student_security_screen.dart';
import '../../note/application/note_controller.dart';
import '../../note/data/note_models.dart';
import '../../note/presentation/create_note_sheet.dart';
import '../../post/data/post_models.dart';
import '../../post/presentation/post_sheets.dart';
import '../../post/presentation/post_widgets.dart';
import '../../quiz/presentation/quiz_tab.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../application/classroom_controller.dart';
import '../data/classroom_models.dart';

/// The classroom's sections, in tab order. Matches the web client.
enum _Section {
  stream('Stream', PostKind.announcement),
  materials('Materials', PostKind.material),
  assignments('Assignments', PostKind.assignment),
  notes('Notes', null),
  attendance('Attendance', null),
  quiz('Quiz', null);

  const _Section(this.label, this.kind);

  final String label;

  /// The post kind shown in this section; null for notes, attendance and quiz.
  final PostKind? kind;
}

/// One classroom: announcements, materials, assignments and notes.
class ClassroomScreen extends ConsumerStatefulWidget {
  const ClassroomScreen({
    required this.classroomId,
    this.initialTab,
    super.key,
  });

  final String classroomId;

  /// A section name such as `assignments`, from the `?tab=` query. The to-do
  /// list uses it to land on the assignment rather than the stream.
  final String? initialTab;

  @override
  ConsumerState<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends ConsumerState<ClassroomScreen>
    with SingleTickerProviderStateMixin {
  Timer? _pollTimer;
  late final TabController _tabs =
      TabController(
    length: _Section.values.length,
    vsync: this,
    initialIndex: _Section.values
        .firstWhere((s) => s.name == widget.initialTab,
            orElse: () => _Section.stream)
        .index,
  )
        // Rebuild so the floating button matches the visible section.
        ..addListener(() {
          if (!_tabs.indexIsChanging) setState(() {});
        });

  String get classroomId => widget.classroomId;

  _Section get _section => _Section.values[_tabs.index];

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabs.dispose();
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

  /// The floating button for the visible section, or null when this person
  /// cannot add anything there.
  Widget? _fab(bool canManage) {
    // The quiz composer lives inside the tab.
    if (_section == _Section.quiz) return null;

    if (_section == _Section.attendance) {
      // Students join a session from its tile; only teachers start one.
      if (!canManage) return null;
      return FloatingActionButton.extended(
        onPressed: () async {
          await showStartSessionSheet(context, classroomId: classroomId);
          ref.invalidate(attendanceSessionsProvider(classroomId));
        },
        icon: const Icon(Icons.bluetooth_audio),
        label: const Text('Take attendance'),
      );
    }

    final kind = _section.kind;
    if (kind == null) {
      return FloatingActionButton.extended(
        onPressed: () => showCreateNoteSheet(context, classroomId: classroomId),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('New note'),
      );
    }
    // Only teachers post. The backend enforces it; hiding the button just
    // avoids offering something that would fail.
    if (!canManage) return null;

    return FloatingActionButton.extended(
      onPressed: () => showPostComposerSheet(
        context,
        classroomId: classroomId,
        kind: kind,
      ),
      icon: Icon(switch (kind) {
        PostKind.announcement => Icons.campaign_outlined,
        PostKind.material => Icons.upload_file,
        PostKind.assignment => Icons.assignment_add,
      }),
      label: Text(switch (kind) {
        PostKind.announcement => 'Announce',
        PostKind.material => 'Upload',
        PostKind.assignment => 'Assign',
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classroom = _classroom(ref);
    final canManage = classroom?.myRole.canEditClassroom ?? false;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (canManage && classroom != null)
            IconButton(
              tooltip: 'Student security',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudentSecurityScreen(
                    classroomId: classroomId,
                    classroomName: classroom.name,
                  ),
                ),
              ),
            ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(classroom?.name ?? 'Classroom'),
            if (classroom != null)
              Text(
                '${classroom.memberCount} '
                '${classroom.memberCount == 1 ? 'member' : 'members'} · '
                'Code ${classroom.code}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final section in _Section.values) Tab(text: section.label)
          ],
        ),
      ),
      floatingActionButton: _fab(canManage),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final section in _Section.values)
            if (section.kind case final kind?)
              PostListView(
                classroomId: classroomId,
                kind: kind,
                canManage: canManage,
              )
            else if (section == _Section.attendance)
              AttendanceTab(classroomId: classroomId, canManage: canManage)
            else if (section == _Section.quiz)
              QuizTab(
                classroomId: classroomId,
                canManage: canManage,
                visible: _section == _Section.quiz,
              )
            else
              _notes(context),
        ],
      ),
    );
  }

  Widget _notes(BuildContext context) {
    final notesAsync = ref.watch(noteListProvider(classroomId));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(noteListProvider(classroomId)),
      child: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [Text(error.toString(), textAlign: TextAlign.center)],
        ),
        data: (cached) {
          final notes = cached.value;
          // Scheduled out of the build pass: starting or cancelling a timer
          // during build would mutate state mid-render.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _syncPolling(notes),
          );

          if (notes.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
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

          return Column(
            children: [
              if (cached.isOffline) const OfflineBanner(),
              Expanded(
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: notes.length,
                  itemBuilder: (context, index) => _NoteTile(
                    note: notes[index],
                    onOpen: () => context.push('/notes/${notes[index].id}'),
                    onDelete: () => _confirmDelete(notes[index]),
                  ),
                ),
              ),
            ],
          );
        },
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
