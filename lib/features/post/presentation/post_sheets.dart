import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/form_error.dart';
import '../application/post_controller.dart';
import '../data/attachment_types.dart';
import '../data/post_models.dart';
import 'post_widgets.dart';

Future<void> showPostComposerSheet(
  BuildContext context, {
  required String classroomId,
  required PostKind kind,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PostComposerSheet(classroomId: classroomId, kind: kind),
  );
}

Future<void> showSubmitSheet(
  BuildContext context, {
  required String classroomId,
  required Post post,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SubmitSheet(classroomId: classroomId, post: post),
  );
}

Future<void> showSubmissionsSheet(BuildContext context, {required Post post}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, controller) =>
          _SubmissionsSheet(post: post, scrollController: controller),
    ),
  );
}

/// Pick one attachment, validating type and size before anything is uploaded.
Future<(PlatformFile?, String?)> _pickAttachment() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: attachmentExtensions,
  );
  if (file == null) return (null, null);

  if (attachmentContentType(file.name) == null) {
    return (null, 'That file type is not supported');
  }
  if (await file.length() > maxAttachmentBytes) {
    return (null, 'That file is larger than 100 MB');
  }
  return (file, null);
}

class _UploadProgress extends StatelessWidget {
  const _UploadProgress({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    if (progress == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 4),
          Text(
            'Uploading… ${(progress! * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// -- composer --------------------------------------------------------------

class _PostComposerSheet extends ConsumerStatefulWidget {
  const _PostComposerSheet({required this.classroomId, required this.kind});

  final String classroomId;
  final PostKind kind;

  @override
  ConsumerState<_PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends ConsumerState<_PostComposerSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  PlatformFile? _picked;
  DateTime? _due;
  bool _busy = false;
  double? _progress;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final (file, error) = await _pickAttachment();
    if (!mounted) return;
    setState(() {
      if (file != null) _picked = file;
      _error = error;
    });
  }

  /// A date then a time, both in the device's zone. The repository sends the
  /// resulting instant as UTC, so a student elsewhere sees it in theirs.
  Future<void> _pickDue() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 2),
    );
    if (day == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _due != null
          ? TimeOfDay.fromDateTime(_due!)
          : const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null || !mounted) return;

    setState(
      () =>
          _due = DateTime(day.year, day.month, day.day, time.hour, time.minute),
    );
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return setState(() => _error = 'Give it a title');
    if (widget.kind == PostKind.material && _picked?.path == null) {
      return setState(() => _error = 'Choose the file to share');
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final picked = _picked;
    try {
      if (picked?.path != null) setState(() => _progress = 0);
      await ref.read(postActionsProvider(widget.classroomId)).create(
            kind: widget.kind,
            title: title,
            description: _descriptionController.text.trim(),
            dueDate: widget.kind == PostKind.assignment ? _due : null,
            file: picked?.path != null ? File(picked!.path!) : null,
            filename: picked?.name,
            contentType:
                picked != null ? attachmentContentType(picked.name) : null,
            onProgress: (sent, total) {
              if (total > 0 && mounted) {
                setState(() => _progress = sent / total);
              }
            },
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = widget.kind;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'New ${kind.label.toLowerCase()}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            FormError(message: _error!),
            const SizedBox(height: 16),
          ],
          AppTextField(controller: _titleController, label: 'Title'),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLines: kind == PostKind.announcement ? 5 : 3,
            decoration: InputDecoration(
              labelText: kind == PostKind.announcement
                  ? 'Message'
                  : 'Description (optional)',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (kind == PostKind.assignment) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickDue,
              icon: const Icon(Icons.event),
              label: Text(
                _due == null
                    ? 'Due date: none'
                    : 'Due ${formatLocalDateTime(_due!)}',
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.attach_file),
            label: Text(
              _picked?.name ??
                  (kind == PostKind.material
                      ? 'Choose a file'
                      : 'Attach a file (optional)'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _UploadProgress(progress: _progress),
          const SizedBox(height: 24),
          AppButton(label: 'Post', isLoading: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}

// -- student ---------------------------------------------------------------

class _SubmitSheet extends ConsumerStatefulWidget {
  const _SubmitSheet({required this.classroomId, required this.post});

  final String classroomId;
  final Post post;

  @override
  ConsumerState<_SubmitSheet> createState() => _SubmitSheetState();
}

class _SubmitSheetState extends ConsumerState<_SubmitSheet> {
  PlatformFile? _picked;
  bool _busy = false;
  double? _progress;
  String? _error;

  Future<void> _pickFile() async {
    final (file, error) = await _pickAttachment();
    if (!mounted) return;
    setState(() {
      if (file != null) _picked = file;
      _error = error;
    });
  }

  Future<void> _send() async {
    final picked = _picked;
    if (picked?.path == null) {
      return setState(() => _error = 'Choose a file to submit');
    }

    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });

    try {
      await ref.read(postActionsProvider(widget.classroomId)).submit(
        widget.post,
        File(picked!.path!),
        filename: picked.name,
        contentType: attachmentContentType(picked.name)!,
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = sent / total);
          }
        },
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Work submitted')));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.post;
    final existing = ref.watch(mySubmissionProvider(post.id));
    final overdue =
        post.dueDate != null && post.dueDate!.isBefore(DateTime.now());

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(post.title, style: theme.textTheme.titleLarge),
          if (post.dueDate != null) ...[
            const SizedBox(height: 4),
            Text(
              'Due ${formatLocalDateTime(post.dueDate!)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          if (_error != null) ...[
            FormError(message: _error!),
            const SizedBox(height: 16),
          ],
          existing.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text(error.toString()),
            data: (submission) => submission == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your submission',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      AttachmentTile(asset: submission.asset),
                      Text(
                        'Submitted ${formatLocalDateTime(submission.submittedAt)}'
                        '${submission.isLate ? ' · late' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.attach_file),
            label: Text(
              _picked?.name ??
                  (post.hasSubmitted
                      ? 'Choose a replacement file'
                      : 'Choose your work'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (post.hasSubmitted)
                'Resubmitting replaces your earlier file; your teacher sees only the latest.'
              else
                'Up to 100 MB.',
              if (overdue)
                'The due date has passed — this will be marked late.',
            ].join(' '),
            style: theme.textTheme.bodySmall,
          ),
          _UploadProgress(progress: _progress),
          const SizedBox(height: 24),
          AppButton(
            label: post.hasSubmitted ? 'Resubmit' : 'Submit',
            isLoading: _busy,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}

// -- teacher ---------------------------------------------------------------

class _SubmissionsSheet extends ConsumerWidget {
  const _SubmissionsSheet({required this.post, required this.scrollController});

  final Post post;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final submissions = ref.watch(submissionsProvider(post.id));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(submissionsProvider(post.id)),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Submissions', style: theme.textTheme.titleLarge),
          Text(post.title, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          ...submissions.when(
            loading: () => [const LinearProgressIndicator()],
            error: (error, _) => [Text(error.toString())],
            data: (items) => items.isEmpty
                ? [const Text('Nobody has submitted yet.')]
                : [
                    for (final submission in items)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      submission.studentName,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ),
                                  if (submission.isLate)
                                    const StatusPill(
                                      label: 'Late',
                                      tone: PillTone.warning,
                                    ),
                                ],
                              ),
                              Text(
                                '${submission.studentEmail} · '
                                '${formatLocalDateTime(submission.submittedAt)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              AttachmentTile(asset: submission.asset),
                            ],
                          ),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}
