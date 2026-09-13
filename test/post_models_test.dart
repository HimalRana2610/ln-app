import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/post/data/attachment_types.dart';
import 'package:ln_app/features/post/data/post_models.dart';

void main() {
  // Shaped like a real GET /api/v1/classrooms/{id}/posts?kind=assignment item.
  Map<String, dynamic> assignmentPayload() => {
        'id': '11111111-2222-3333-4444-555555555555',
        'classroom_id': '82ad84fc-0f66-4357-a982-d46a23d592ee',
        'kind': 'assignment',
        'title': 'Implement a scheduler',
        'description': 'Round robin, then MLFQ.',
        'due_date': '2099-01-01T18:14:00Z',
        'author_id': '66666666-7777-8888-9999-000000000000',
        'author_name': 'Grace Hopper',
        'asset': {
          'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          'filename': 'brief.pdf',
          'content_type': 'application/pdf',
          'size_bytes': 5015,
        },
        'created_at': '2026-09-13T09:00:00Z',
        'updated_at': '2026-09-13T09:00:00Z',
        'submission_count': null,
        'my_submitted_at': null,
      };

  group('Post.fromJson', () {
    test('maps every wire field', () {
      final post = Post.fromJson(assignmentPayload());

      expect(post.kind, PostKind.assignment);
      expect(post.authorName, 'Grace Hopper');
      expect(post.asset?.filename, 'brief.pdf');
      expect(post.asset?.sizeBytes, 5015);
      expect(post.hasSubmitted, isFalse);
    });

    test('keeps the due date as the same instant', () {
      final post = Post.fromJson(assignmentPayload());
      expect(post.dueDate!.isUtc, isTrue);
      expect(post.dueDate, DateTime.utc(2099, 1, 1, 18, 14));
    });

    test('decodes a post with no file, description or deadline', () {
      final post = Post.fromJson({
        ...assignmentPayload(),
        'kind': 'announcement',
        'description': null,
        'due_date': null,
        'asset': null,
      });
      expect(post.kind, PostKind.announcement);
      expect(post.asset, isNull);
      expect(post.dueDate, isNull);
    });

    test('decodes every kind the backend can send', () {
      for (final entry in {
        'material': PostKind.material,
        'announcement': PostKind.announcement,
        'assignment': PostKind.assignment,
      }.entries) {
        final post = Post.fromJson({...assignmentPayload(), 'kind': entry.key});
        expect(post.kind, entry.value);
        expect(post.kind.wire, entry.key, reason: 'used in ?kind=');
      }
    });
  });

  group('deadlines', () {
    test('overdue compares instants, not wall-clock text', () {
      // 23:59 in Kathmandu is 18:14 UTC.
      final post = Post.fromJson({
        ...assignmentPayload(),
        'due_date': '2026-09-20T23:59:00+05:45',
      });

      expect(post.isOverdueAt(DateTime.utc(2026, 9, 20, 18, 20)), isTrue);
      expect(post.isOverdueAt(DateTime.utc(2026, 9, 20, 18, 10)), isFalse);
    });

    test('work already handed in is never shown as overdue', () {
      final post = Post.fromJson({
        ...assignmentPayload(),
        'due_date': '2000-01-01T00:00:00Z',
        'my_submitted_at': '2000-01-02T00:00:00Z',
      });
      expect(post.isOverdueAt(DateTime.utc(2026)), isFalse);
      expect(post.submittedLate, isTrue);
    });
  });

  group('Submission.fromJson', () {
    test('parses a teacher-view row', () {
      final submission = Submission.fromJson({
        'id': '99999999-2222-3333-4444-555555555555',
        'post_id': '11111111-2222-3333-4444-555555555555',
        'student_id': '77777777-2222-3333-4444-555555555555',
        'student_name': 'Alan Turing',
        'student_email': 'student@example.edu',
        'asset': {
          'id': 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee',
          'filename': 'answer.txt',
          'content_type': 'text/plain',
          'size_bytes': null,
        },
        'submitted_at': '2026-09-13T10:00:00Z',
        'is_late': false,
      });

      expect(submission.studentName, 'Alan Turing');
      expect(submission.asset.sizeBytes, isNull);
      expect(submission.isLate, isFalse);
    });
  });

  group('attachment rules', () {
    test('derive the content type from the extension', () {
      // Android reports no MIME type for many documents.
      expect(attachmentContentType('Essay.DOCX'),
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(attachmentContentType('slides.pdf'), 'application/pdf');
      expect(attachmentContentType('notes.md'), 'text/markdown');
    });

    test('refuse what the backend refuses', () {
      expect(attachmentContentType('setup.exe'), isNull);
      expect(attachmentContentType('no-extension'), isNull);
      expect(attachmentExtensions, isNot(contains('exe')));
    });

    test('mirror the backend size cap', () {
      expect(maxAttachmentBytes, 100 * 1024 * 1024);
    });

    test('format sizes', () {
      expect(formatBytes(null), '');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('make a filename safe to write to disk', () {
      expect(safeFilename('a/b\\c:d*?.pdf'), 'a_b_c_d__.pdf');
      expect(safeFilename('Week 3 — नोट्स.pdf'), 'Week 3 — नोट्स.pdf');
      expect(safeFilename('   '), 'download');
    });
  });

  group('formatLocalDateTime', () {
    test('shows the instant in the device zone, not UTC', () {
      final instant = DateTime.utc(2026, 9, 20, 18, 14);
      final local = instant.toLocal();
      final expected = '${local.day} Sep 2026, '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';

      expect(formatLocalDateTime(instant), expected);
    });

    test('can omit the time', () {
      expect(
        formatLocalDateTime(DateTime(2026, 1, 5, 12), withTime: false),
        '5 Jan 2026',
      );
    });
  });
}
