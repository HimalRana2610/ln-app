import 'package:flutter/material.dart';

import '../data/security_models.dart';

/// Ported from the old `pages/BlockedStudent.tsx`.
///
/// Scoped to one class: the rest of the app — notes, materials — keeps
/// working. The message says who can fix it, because a student wrongly
/// blocked before an exam needs to know where to go, fast.
class BlockedStudentView extends StatelessWidget {
  const BlockedStudentView({required this.block, super.key});

  final BlockInfo block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.block, size: 48, color: scheme.onErrorContainer),
            const SizedBox(height: 12),
            Text(
              'Attendance blocked',
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            Text(
              'Your teacher has blocked you from marking attendance in '
              '${block.classroomName}.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            if (block.reason != null) ...[
              const SizedBox(height: 8),
              Text(
                'Reason: ${block.reason}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'If this is a mistake, speak to your teacher. Only they can clear it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}
