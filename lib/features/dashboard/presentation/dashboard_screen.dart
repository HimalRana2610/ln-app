import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../../classroom/application/classroom_controller.dart';
import '../../classroom/data/classroom_models.dart';
import '../../classroom/presentation/class_sheets.dart';
import '../../classroom/presentation/widgets/class_card.dart';

/// Home screen: the Public/Private segmented control, the class list, and the
/// create/join actions — laid out to match the web client and the old app.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  ClassroomType _tab = ClassroomType.public;

  Future<void> _confirmDestructiveAction(Classroom classroom) async {
    final isOwner = classroom.myRole == MemberRole.owner;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isOwner ? 'Delete class?' : 'Leave class?'),
        content: Text(
          isOwner
              ? 'This removes "${classroom.name}" for every member and cannot '
                  'be undone.'
              : 'You will need the class code to rejoin "${classroom.name}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isOwner ? 'Delete' : 'Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final controller = ref.read(classroomListProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (isOwner) {
        await controller.delete(classroom);
      } else {
        await controller.leave(classroom);
      }
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final classroomsAsync = ref.watch(classroomListProvider);

    // The router only routes here when authenticated, but the type system does
    // not know that, so handle the other case rather than forcing a cast.
    if (authState is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('LectureNote AI'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCreateClassSheet(context),
        tooltip: 'Create a class',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(classroomListProvider.notifier).refresh(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<ClassroomType>(
                      segments: const [
                        ButtonSegment(
                          value: ClassroomType.public,
                          label: Text('PUBLIC'),
                        ),
                        ButtonSegment(
                          value: ClassroomType.personal,
                          label: Text('PRIVATE'),
                        ),
                      ],
                      selected: {_tab},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          setState(() => _tab = selection.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Join with code',
                    icon: const Icon(Icons.login),
                    onPressed: () => showJoinClassSheet(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: classroomsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorState(
                  message: error.toString(),
                  onRetry: () =>
                      ref.read(classroomListProvider.notifier).refresh(),
                ),
                data: (classrooms) {
                  final visible = classrooms
                      .where((classroom) => classroom.type == _tab)
                      .toList();

                  if (visible.isEmpty) {
                    return _EmptyState(tab: _tab);
                  }

                  return ListView.builder(
                    // Always scrollable so pull-to-refresh works even when the
                    // list is short.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => ClassCard(
                      classroom: visible[index],
                      onOpen: () =>
                          context.push('/classroom/${visible[index].id}'),
                      onDestructiveAction: () =>
                          _confirmDestructiveAction(visible[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab});

  final ClassroomType tab;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      children: [
        Icon(
          Icons.class_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          'No ${tab.label.toLowerCase()} classes yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Create one with the + button, or join with a code.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
