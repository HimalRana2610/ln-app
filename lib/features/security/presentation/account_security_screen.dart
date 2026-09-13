import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../application/security_controller.dart';
import '../data/security_models.dart';

/// Email, bound phone, and face data — what is stored and how to remove it.
class AccountSecurityScreen extends ConsumerWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mySecurityProvider);
    final face = ref.watch(faceStatusProvider);
    final theme = Theme.of(context);

    Future<void> refresh() async {
      ref
        ..invalidate(mySecurityProvider)
        ..invalidate(faceStatusProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account security')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: status.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(padding: const EdgeInsets.all(32), child: Text('$e')),
          ]),
          data: (s) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    s.emailVerified ? Icons.verified : Icons.mark_email_unread,
                    color: s.emailVerified
                        ? Colors.green
                        : theme.colorScheme.error,
                  ),
                  title: const Text('Email'),
                  subtitle: Text(s.emailVerified
                      ? 'Verified'
                      : 'Not verified — needed to mark attendance'),
                  trailing: s.emailVerified
                      ? null
                      : FilledButton(
                          onPressed: () async {
                            await context.push(Routes.verifyEmail);
                            await refresh();
                          },
                          child: const Text('Verify'),
                        ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: const Text('Attendance phone'),
                  subtitle: Text(s.device == null
                      ? 'No phone bound yet. It binds the first time you open an attendance session.'
                      : 'Bound to ${s.device!.label}. Attendance can only be marked '
                          'from this phone; ask a teacher to reset it if you change phones.'),
                ),
              ),
              face.when(
                loading: () => const Card(child: LinearProgressIndicator()),
                error: (e, _) => Card(child: ListTile(title: Text('$e'))),
                data: (f) => _FaceCard(status: f, onChanged: refresh),
              ),
              for (final block in s.blocks)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: Text('Blocked in ${block.classroomName}'),
                    subtitle: Text(block.reason ?? 'Speak to your teacher.'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaceCard extends ConsumerStatefulWidget {
  const _FaceCard({required this.status, required this.onChanged});

  final FaceStatus status;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_FaceCard> createState() => _FaceCardState();
}

class _FaceCardState extends ConsumerState<_FaceCard> {
  bool _busy = false;
  String? _error;

  /// The old `FaceCaptureStep`: front, then left, then right.
  static const _poses = [
    ('front', 'Look straight at the camera'),
    ('left', 'Turn your head slightly to the left'),
    ('right', 'Turn your head slightly to the right'),
  ];

  Future<void> _enrol() async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enrol your face?'),
        content: const Text(
          'You will take three photos. They are sent to the server, turned into '
          'numbers that describe your face, and deleted. Only those numbers are '
          'kept — never a photo — and you can delete them at any time here.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('I agree')),
        ],
      ),
    );
    if (consent != true || !mounted) return;

    final picker = ImagePicker();
    final files = <String, File>{};
    for (final (pose, instruction) in _poses) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('Photo ${files.length + 1} of 3: $instruction')));
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (shot == null) return;
      files[pose] = File(shot.path);
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(securityRepositoryProvider).enrollFace(
            front: files['front']!,
            left: files['left']!,
            right: files['right']!,
          );
      await widget.onChanged();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      // The photos were only ever needed for the upload.
      for (final file in files.values) {
        if (file.existsSync()) file.deleteSync();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(securityRepositoryProvider).deleteFace();
      await widget.onChanged();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.face_retouching_natural),
              title: const Text('Face data'),
              subtitle: Text(!status.available
                  ? 'Face recognition is not set up on this server.'
                  : status.enrolled
                      ? 'Enrolled. Only a numerical description is stored, never a photo.'
                      : 'Not enrolled.'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (status.available)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status.enrolled)
                      TextButton(
                          onPressed: _busy ? null : _delete,
                          child: const Text('Delete')),
                    FilledButton.tonal(
                      onPressed: _busy ? null : _enrol,
                      child: Text(status.enrolled ? 'Enrol again' : 'Enrol'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
