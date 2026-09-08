import 'package:freezed_annotation/freezed_annotation.dart';

part 'classroom_models.freezed.dart';
part 'classroom_models.g.dart';

/// Stored as `personal` to match the old Firestore documents; shown as
/// "Private" in the UI.
enum ClassroomType {
  @JsonValue('personal')
  personal,
  @JsonValue('public')
  public;

  String get label => this == ClassroomType.personal ? 'Private' : 'Public';
}

enum MemberRole {
  @JsonValue('owner')
  owner,
  @JsonValue('teacher')
  teacher,
  @JsonValue('student')
  student;

  String get label => switch (this) {
        MemberRole.owner => 'Owner',
        MemberRole.teacher => 'Teacher',
        MemberRole.student => 'Student',
      };

  bool get canEditClassroom =>
      this == MemberRole.owner || this == MemberRole.teacher;
}

/// Mirrors the backend's `ClassroomRead` schema.
@freezed
abstract class Classroom with _$Classroom {
  const factory Classroom({
    required String id,
    required String name,
    String? section,
    required String code,
    required ClassroomType type,

    /// Tailwind gradient pair, e.g. "from-blue-500 to-indigo-600".
    /// Mapped to Flutter colours by `ClassroomPalette`.
    @JsonKey(name: 'theme_color') required String themeColor,
    @JsonKey(name: 'owner_id') required String ownerId,
    @JsonKey(name: 'owner_name') required String ownerName,

    /// The viewing user's role in this classroom.
    @JsonKey(name: 'my_role') required MemberRole myRole,
    @JsonKey(name: 'member_count') required int memberCount,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Classroom;

  factory Classroom.fromJson(Map<String, dynamic> json) =>
      _$ClassroomFromJson(json);
}

/// Mirrors the backend's `MemberRead` schema.
@freezed
abstract class ClassroomMember with _$ClassroomMember {
  const factory ClassroomMember({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    required String email,
    @JsonKey(name: 'full_name') required String fullName,
    required MemberRole role,
    @JsonKey(name: 'joined_at') required DateTime joinedAt,
  }) = _ClassroomMember;

  factory ClassroomMember.fromJson(Map<String, dynamic> json) =>
      _$ClassroomMemberFromJson(json);
}
