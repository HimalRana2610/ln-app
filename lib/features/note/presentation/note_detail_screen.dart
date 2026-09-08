import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/note_controller.dart';
import '../data/note_models.dart';

/// Renders a generated note.
///
/// Headings use Kalam, the handwriting face from the old app — a small detail
/// that carries most of the product's character.
class NoteDetailScreen extends ConsumerWidget {
  const NoteDetailScreen({required this.noteId, super.key});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteAsync = ref.watch(noteProvider(noteId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Note')),
      body: noteAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(error.toString(), textAlign: TextAlign.center),
          ),
        ),
        data: (note) {
          if (note.status != NoteStatus.ready) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (note.status.isGenerating)
                      const CircularProgressIndicator()
                    else
                      Icon(
                        Icons.error_outline,
                        size: 40,
                        color: theme.colorScheme.error,
                      ),
                    const SizedBox(height: 16),
                    Text(
                      note.status == NoteStatus.failed
                          ? (note.errorMessage ?? 'Generation failed.')
                          : 'Still generating. Pull down on the list to refresh.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }

          return Markdown(
            data: note.markdown,
            selectable: true,
            padding: const EdgeInsets.all(20),
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              h1: theme.textTheme.headlineMedium?.copyWith(
                fontFamily: 'Kalam',
                fontWeight: FontWeight.bold,
              ),
              h2: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'Kalam',
                fontWeight: FontWeight.bold,
              ),
              h3: theme.textTheme.titleLarge?.copyWith(
                fontFamily: 'Kalam',
                fontWeight: FontWeight.w600,
              ),
              blockquoteDecoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                border: Border(
                  left: BorderSide(color: theme.colorScheme.primary, width: 4),
                ),
              ),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        },
      ),
    );
  }
}
