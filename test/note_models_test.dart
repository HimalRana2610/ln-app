import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/note/data/note_models.dart';

void main() {
  // A real payload from GET /api/v1/classrooms/{id}/notes.
  Map<String, dynamic> summaryPayload() => {
    'id': '11111111-2222-3333-4444-555555555555',
    'classroom_id': '82ad84fc-0f66-4357-a982-d46a23d592ee',
    'date': '2026-09-07',
    'title': 'Graph Theory',
    'status': 'ready',
    'source_type': 'audio',
    'author_id': '66666666-7777-8888-9999-000000000000',
    'author_name': 'Grace Hopper',
    'duration_seconds': 3600,
    'error_message': null,
    'created_at': '2026-09-07T10:30:00Z',
  };

  group('NoteSummary.fromJson', () {
    test('maps snake_case wire fields onto camelCase Dart fields', () {
      final note = NoteSummary.fromJson(summaryPayload());

      expect(note.title, 'Graph Theory');
      expect(note.sourceType, NoteSourceType.audio);
      expect(note.authorName, 'Grace Hopper');
      expect(note.durationSeconds, 3600);
      expect(note.date.year, 2026);
    });

    test('carries the failure reason when generation failed', () {
      final note = NoteSummary.fromJson({
        ...summaryPayload(),
        'status': 'failed',
        'error_message': 'GEMINI_API_KEY is not set on the server',
      });

      expect(note.status, NoteStatus.failed);
      expect(note.errorMessage, contains('GEMINI_API_KEY'));
    });
  });

  group('NoteStatus', () {
    test('pending and processing mean keep polling', () {
      expect(NoteStatus.pending.isGenerating, isTrue);
      expect(NoteStatus.processing.isGenerating, isTrue);
      expect(NoteStatus.pending.isTerminal, isFalse);
    });

    test('ready and failed mean stop polling', () {
      // Getting this wrong either leaves a screen polling forever or stops
      // before the note is finished.
      expect(NoteStatus.ready.isTerminal, isTrue);
      expect(NoteStatus.failed.isTerminal, isTrue);
      expect(NoteStatus.ready.isGenerating, isFalse);
    });

    test('labels are the ones shown on the status chip', () {
      expect(NoteStatus.pending.label, 'Queued');
      expect(NoteStatus.processing.label, 'Generating');
      expect(NoteStatus.ready.label, 'Ready');
      expect(NoteStatus.failed.label, 'Failed');
    });
  });

  group('NoteSourceType', () {
    test('decodes every value the backend can send', () {
      for (final entry in {
        'audio': NoteSourceType.audio,
        'text': NoteSourceType.text,
        'pdf': NoteSourceType.pdf,
        'youtube': NoteSourceType.youtube,
      }.entries) {
        final note = NoteSummary.fromJson({
          ...summaryPayload(),
          'source_type': entry.key,
        });
        expect(note.sourceType, entry.value, reason: entry.key);
      }
    });
  });

  group('Note.fromJson', () {
    test('includes the Markdown body the list view omits', () {
      final note = Note.fromJson({
        ...summaryPayload(),
        'markdown': '# Graph Theory\n\n## Definitions',
      });

      expect(note.markdown, contains('## Definitions'));
    });
  });

  group('PresignedUpload.fromJson', () {
    test('parses the upload slot', () {
      final slot = PresignedUpload.fromJson({
        'asset_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'upload_url': 'http://localhost:9000/lecture-note/uploads/x?signed=1',
        'content_type': 'audio/m4a',
        'expires_in': 900,
      });

      expect(slot.uploadUrl, startsWith('http://'));
      // The PUT must carry exactly this, or the signature will not match.
      expect(slot.contentType, 'audio/m4a');
      expect(slot.expiresIn, 900);
    });
  });
}
