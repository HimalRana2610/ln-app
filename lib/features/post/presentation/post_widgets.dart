import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../application/post_controller.dart';
import '../data/attachment_types.dart';
import '../data/post_models.dart';
import 'download_dialog.dart';
import 'post_sheets.dart';

enum PillTone { neutral, success, warning, danger }

class StatusPill extends StatelessWidget {
  const StatusPill(
      {required this.label, this.tone = PillTone.neutral, super.key});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      PillTone.success => (scheme.primaryContainer, scheme.onPrimaryContainer),
      PillTone.warning => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
      PillTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
      PillTone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: foreground, fontSize: 11)),
    );
  }
}

/// A file row. Tapping downloads it with progress, then opens it.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({required this.asset, super.key});

  final AssetInfo asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => downloadAndOpen(context, asset),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(fileIcon(asset.contentType),
                  color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (asset.sizeBytes != null)
                      Text(
                        formatBytes(asset.sizeBytes),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.download_outlined, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// One classroom section: a list of posts of [kind], refreshable, with teacher
/// controls when [canManage].
class PostListView extends ConsumerWidget {
  const PostListView({
    required this.classroomId,
    required this.kind,
    required this.canManage,
    super.key,
  });

  final String classroomId;
  final PostKind kind;
  final bool canManage;

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Post post,
  ) async {
    final extra = switch (post) {
      Post(kind: PostKind.assignment, submissionCount: final n?) when n > 0 =>
        ' All $n submission${n == 1 ? '' : 's'} and their files are deleted too.',
      Post(asset: _?) => ' Its file is deleted too.',
      _ => '',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${post.kind.label.toLowerCase()}?'),
        content: Text(
            '"${post.title}" will be removed.$extra This cannot be undone.'),
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
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(postActionsProvider(classroomId)).delete(post);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (classroomId, kind);
    final posts = ref.watch(postListProvider(key));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(postListProvider(key)),
      child: posts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [Text(error.toString(), textAlign: TextAlign.center)],
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
              children: [
                Icon(
                  switch (kind) {
                    PostKind.announcement => Icons.campaign_outlined,
                    PostKind.material => Icons.folder_open_outlined,
                    PostKind.assignment => Icons.assignment_outlined,
                  },
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'No ${kind.label.toLowerCase()}s yet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: items.length,
            itemBuilder: (context, index) => _PostCard(
              post: items[index],
              classroomId: classroomId,
              canManage: canManage,
              onDelete: () => _confirmDelete(context, ref, items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.classroomId,
    required this.canManage,
    required this.onDelete,
  });

  final Post post;
  final String classroomId;
  final bool canManage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAssignment = post.kind == PostKind.assignment;
    final overdue = post.isOverdueAt(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        isAssignment
                            ? '${post.dueDate == null ? 'No due date' : 'Due ${formatLocalDateTime(post.dueDate!)}'}'
                                ' · ${post.authorName}'
                            : '${post.authorName} · '
                                '${formatLocalDateTime(post.createdAt, withTime: false)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: overdue && isAssignment && !canManage
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAssignment) ...[
                  const SizedBox(width: 8),
                  _assignmentPill(),
                ],
                if (canManage)
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
              ],
            ),
            if (post.description != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child:
                    Text(post.description!, style: theme.textTheme.bodyMedium),
              ),
            ],
            if (post.asset != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AttachmentTile(asset: post.asset!),
              ),
            ],
            if (isAssignment)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: canManage
                      ? OutlinedButton(
                          onPressed: () =>
                              showSubmissionsSheet(context, post: post),
                          child: const Text('View submissions'),
                        )
                      : FilledButton.tonal(
                          onPressed: () => showSubmitSheet(
                            context,
                            classroomId: classroomId,
                            post: post,
                          ),
                          child: Text(
                            post.hasSubmitted
                                ? 'View or resubmit'
                                : 'Submit work',
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _assignmentPill() {
    if (canManage) {
      return StatusPill(label: '${post.submissionCount ?? 0} submitted');
    }
    if (post.hasSubmitted) {
      return post.submittedLate
          ? const StatusPill(label: 'Submitted late', tone: PillTone.warning)
          : const StatusPill(label: 'Submitted', tone: PillTone.success);
    }
    return const StatusPill(label: 'Not submitted');
  }
}
