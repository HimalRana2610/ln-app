import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../application/todo_controller.dart';
import '../data/todo_models.dart';

/// Every assignment from every class, split into Assigned / Missing / Done.
///
/// Grouping uses the status the server sent, verbatim, and keeps the server's
/// order inside each tab.
class ToDoScreen extends ConsumerWidget {
  const ToDoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(toDoListProvider);

    return DefaultTabController(
      length: ToDoStatus.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('To-do'),
          bottom: TabBar(
            tabs: [
              for (final status in ToDoStatus.values)
                Tab(
                  text: switch (itemsAsync.value) {
                    final items? =>
                      '${status.label} (${items.where((i) => i.status == status).length})',
                    null => status.label,
                  },
                ),
            ],
          ),
        ),
        body: itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(toDoListProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          data: (items) => TabBarView(
            children: [
              for (final status in ToDoStatus.values)
                _ToDoList(
                  status: status,
                  items: items.where((item) => item.status == status).toList(),
                  onRefresh: () async => ref.invalidate(toDoListProvider),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToDoList extends StatelessWidget {
  const _ToDoList({
    required this.status,
    required this.items,
    required this.onRefresh,
  });

  final ToDoStatus status;
  final List<ToDoItem> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
              children: [
                Icon(Icons.task_alt,
                    size: 48, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  switch (status) {
                    ToDoStatus.assigned => 'Nothing due. Nice.',
                    ToDoStatus.missing => 'Nothing missing.',
                    ToDoStatus.done => 'Nothing handed in yet.',
                  },
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: items.length,
              itemBuilder: (context, index) => ToDoTile(item: items[index]),
            ),
    );
  }
}

class ToDoTile extends StatelessWidget {
  const ToDoTile({required this.item, super.key});

  final ToDoItem item;

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final detail = switch (item) {
      ToDoItem(submittedAt: final at?) =>
        'Handed in ${_date(at)}${item.isLate ? ' · late' : ''}',
      ToDoItem(dueDate: final due?) => 'Due ${_date(due)}',
      _ => 'No due date',
    };

    final (background, foreground) = switch (item.status) {
      ToDoStatus.missing => (scheme.errorContainer, scheme.onErrorContainer),
      ToDoStatus.done => (scheme.primaryContainer, scheme.onPrimaryContainer),
      ToDoStatus.assigned => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => context.push(
          '${Routes.classroom}/${item.classroomId}?tab=assignments',
        ),
        leading: const Icon(Icons.assignment_outlined),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${item.classroomName} · $detail'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            item.status.label,
            style: TextStyle(color: foreground, fontSize: 11),
          ),
        ),
      ),
    );
  }
}
