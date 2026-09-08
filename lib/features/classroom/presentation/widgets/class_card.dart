import 'package:flutter/material.dart';

import '../../data/classroom_models.dart';
import '../classroom_palette.dart';

/// Class card, matching the web client and the old app: gradient header with an
/// overlapping avatar tile, then role and join code on a plain body.
class ClassCard extends StatelessWidget {
  const ClassCard({
    required this.classroom,
    required this.onOpen,
    required this.onDestructiveAction,
    super.key,
  });

  final Classroom classroom;

  /// Opens the classroom's notes.
  final VoidCallback onOpen;

  /// Delete when the viewer owns the class, leave otherwise.
  final VoidCallback onDestructiveAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = classroom.myRole == MemberRole.owner;
    final initial = classroom.name.trim().isEmpty
        ? '?'
        : classroom.name.trim()[0].toUpperCase();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Gradient header. The avatar overflows its bottom edge, so the
            // Stack must not clip.
            SizedBox(
              height: 140,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient:
                          ClassroomPalette.gradientFor(classroom.themeColor),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 20, 52, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          classroom.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (classroom.section != null &&
                            classroom.section!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            classroom.section!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      tooltip: 'Class options',
                      onSelected: (_) => onDestructiveAction(),
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'destructive',
                          child: Text(
                            isOwner ? 'Delete class' : 'Leave class',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Avatar tile, half outside the header.
                  Positioned(
                    right: 20,
                    bottom: -24,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: ClassroomPalette.gradientFor(
                              classroom.themeColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ROLE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    classroom.myRole.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Divider(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Class Code',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          classroom.code,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${classroom.memberCount} '
                    '${classroom.memberCount == 1 ? 'member' : 'members'} · '
                    '${classroom.ownerName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
