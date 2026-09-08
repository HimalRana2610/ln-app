import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/classroom/data/classroom_models.dart';

void main() {
  // A real payload from GET /api/v1/classrooms.
  Map<String, dynamic> payload() => {
        'id': '0f5a3e1c-1b2d-4e5f-8a9b-0c1d2e3f4a5b',
        'name': 'Discrete Mathematics',
        'section': 'B',
        'code': '6W6CAZ',
        'type': 'public',
        'theme_color': 'from-rose-500 to-pink-600',
        'owner_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'owner_name': 'Grace Hopper',
        'my_role': 'owner',
        'member_count': 2,
        'created_at': '2026-09-05T10:30:00Z',
      };

  group('Classroom.fromJson', () {
    test('maps snake_case wire fields onto camelCase Dart fields', () {
      final classroom = Classroom.fromJson(payload());

      expect(classroom.name, 'Discrete Mathematics');
      expect(classroom.themeColor, 'from-rose-500 to-pink-600');
      expect(classroom.ownerName, 'Grace Hopper');
      expect(classroom.memberCount, 2);
      expect(classroom.createdAt.year, 2026);
    });

    test('decodes the enums the backend sends', () {
      final classroom = Classroom.fromJson(payload());

      expect(classroom.type, ClassroomType.public);
      expect(classroom.myRole, MemberRole.owner);
    });

    test('accepts a null section', () {
      final classroom = Classroom.fromJson({...payload(), 'section': null});
      expect(classroom.section, isNull);
    });

    test('decodes personal, which the UI labels Private', () {
      final classroom = Classroom.fromJson({...payload(), 'type': 'personal'});

      expect(classroom.type, ClassroomType.personal);
      expect(classroom.type.label, 'Private');
    });
  });

  group('MemberRole', () {
    test('owners and teachers may edit, students may not', () {
      expect(MemberRole.owner.canEditClassroom, isTrue);
      expect(MemberRole.teacher.canEditClassroom, isTrue);
      expect(MemberRole.student.canEditClassroom, isFalse);
    });

    test('labels are capitalised for display', () {
      expect(MemberRole.owner.label, 'Owner');
      expect(MemberRole.student.label, 'Student');
    });
  });

  group('ClassroomMember.fromJson', () {
    test('parses a member row', () {
      final member = ClassroomMember.fromJson({
        'id': '11111111-2222-3333-4444-555555555555',
        'user_id': '66666666-7777-8888-9999-000000000000',
        'email': 'alan@example.edu',
        'full_name': 'Alan Turing',
        'role': 'student',
        'joined_at': '2026-09-05T11:00:00Z',
      });

      expect(member.fullName, 'Alan Turing');
      expect(member.role, MemberRole.student);
    });
  });
}
