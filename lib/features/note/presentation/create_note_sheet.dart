import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/form_error.dart';
import '../application/note_controller.dart';

/// Opens the "new note" sheet.
Future<void> showCreateNoteSheet(
  BuildContext context, {
  required String classroomId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CreateNoteSheet(classroomId: classroomId),
  );
}

enum _Source { upload, text, youtube }

class _CreateNoteSheet extends ConsumerStatefulWidget {
  const _CreateNoteSheet({required this.classroomId});

  final String classroomId;

  @override
  ConsumerState<_CreateNoteSheet> createState() => _CreateNoteSheetState();
}

class _CreateNoteSheetState extends ConsumerState<_CreateNoteSheet> {
  static const _allowedExtensions = [
    'mp3',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'flac',
    'webm',
    'pdf',
  ];
  static const _maxUploadBytes = 200 * 1024 * 1024;

  final _textController = TextEditingController();
  final _youtubeController = TextEditingController();

  _Source _source = _Source.upload;
  PlatformFile? _picked;
  DateTime? _date;

  bool _busy = false;
  double? _uploadProgress;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  /// Content type from the extension.
  ///
  /// Android reports no MIME type for several audio containers, so trusting it
  /// would refuse perfectly valid recordings. The header must match what the
  /// presigned URL was signed for.
  String _contentTypeFor(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    return switch (extension) {
      'pdf' => 'application/pdf',
      'mp3' => 'audio/mpeg',
      'm4a' || 'mp4' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'flac' => 'audio/flac',
      'webm' => 'audio/webm',
      _ => 'audio/mpeg',
    };
  }

  Future<void> _pickFile() async {
    // file_picker 12 exposes static methods; `FilePicker.platform` was removed.
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (file == null) return;

    // PlatformFile exposes length() rather than a `size` field: native pickers
    // do not always report a size, so it may require reading the file.
    if (await file.length() > _maxUploadBytes) {
      if (mounted) setState(() => _error = 'That file is larger than 200 MB');
      return;
    }
    if (!mounted) return;

    setState(() {
      _picked = file;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (chosen != null) setState(() => _date = chosen);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final actions = ref.read(noteActionsProvider(widget.classroomId));

    try {
      switch (_source) {
        case _Source.text:
          final text = _textController.text.trim();
          if (text.length < 20) {
            setState(() => _error = 'Paste at least a paragraph to work from');
            return;
          }
          await actions.createFromText(text, date: _date);

        case _Source.youtube:
          final url = _youtubeController.text.trim();
          if (url.isEmpty) {
            setState(() => _error = 'Paste a YouTube link');
            return;
          }
          await actions.createFromYoutube(url, date: _date);

        case _Source.upload:
          final file = _picked;
          if (file?.path == null) {
            setState(() => _error = 'Choose a recording or PDF first');
            return;
          }
          setState(() => _uploadProgress = 0);
          await actions.createFromFile(
            File(file!.path!),
            filename: file.name,
            contentType: _contentTypeFor(file.name),
            date: _date,
            onProgress: (sent, total) {
              if (total > 0 && mounted) {
                setState(() => _uploadProgress = sent / total);
              }
            },
          );
      }

      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          Text('New note', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Notes are generated in the background. You can close this and come '
            'back — the list updates itself.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          SegmentedButton<_Source>(
            segments: const [
              ButtonSegment(value: _Source.upload, label: Text('File')),
              ButtonSegment(value: _Source.text, label: Text('Text')),
              ButtonSegment(value: _Source.youtube, label: Text('YouTube')),
            ],
            selected: {_source},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _source = selection.first),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            FormError(message: _error!),
            const SizedBox(height: 16),
          ],
          if (_source == _Source.upload) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_picked?.name ?? 'Choose a recording or PDF'),
            ),
            if (_uploadProgress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 4),
              Text(
                'Uploading… ${((_uploadProgress ?? 0) * 100).round()}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
          if (_source == _Source.text)
            TextField(
              controller: _textController,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Lecture material',
                hintText: 'Paste a transcript, your rough notes, or a handout…',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          if (_source == _Source.youtube)
            AppTextField(
              controller: _youtubeController,
              label: 'YouTube link',
              hintText: 'https://youtu.be/…',
              keyboardType: TextInputType.url,
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickDate,
            icon: const Icon(Icons.event),
            label: Text(
              _date == null
                  ? 'Lecture date: today'
                  : 'Lecture date: ${_date!.day}/${_date!.month}/${_date!.year}',
            ),
          ),
          const SizedBox(height: 24),
          AppButton(label: 'Generate', isLoading: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}
