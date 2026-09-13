import 'package:freezed_annotation/freezed_annotation.dart';

part 'post_models.freezed.dart';
part 'post_models.g.dart';

enum PostKind {
  @JsonValue('material')
  material,
  @JsonValue('announcement')
  announcement,
  @JsonValue('assignment')
  assignment;

  /// The value the API expects in `?kind=` and request bodies.
  String get wire => name;

  String get label => switch (this) {
        PostKind.material => 'Material',
        PostKind.announcement => 'Announcement',
        PostKind.assignment => 'Assignment',
      };
}

/// A file's metadata. Deliberately no URL: presigned URLs expire, so one is
/// requested per download.
@freezed
abstract class AssetInfo with _$AssetInfo {
  const factory AssetInfo({
    required String id,
    required String filename,
    @JsonKey(name: 'content_type') required String contentType,
    @JsonKey(name: 'size_bytes') int? sizeBytes,
  }) = _AssetInfo;

  factory AssetInfo.fromJson(Map<String, dynamic> json) =>
      _$AssetInfoFromJson(json);
}

/// Mirrors the backend's `PostRead`.
@freezed
abstract class Post with _$Post {
  const Post._();

  const factory Post({
    required String id,
    @JsonKey(name: 'classroom_id') required String classroomId,
    required PostKind kind,
    required String title,
    String? description,

    /// An instant. Parsed as UTC; call `.toLocal()` to show it.
    @JsonKey(name: 'due_date') DateTime? dueDate,
    @JsonKey(name: 'author_id') required String authorId,
    @JsonKey(name: 'author_name') required String authorName,
    AssetInfo? asset,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,

    /// Assignments, teacher view.
    @JsonKey(name: 'submission_count') int? submissionCount,

    /// Assignments, student view. Null until they submit.
    @JsonKey(name: 'my_submitted_at') DateTime? mySubmittedAt,
  }) = _Post;

  factory Post.fromJson(Map<String, dynamic> json) => _$PostFromJson(json);

  bool get hasSubmitted => mySubmittedAt != null;

  /// Past the deadline with nothing handed in. Compared as instants, so the
  /// device's timezone cannot change the answer.
  bool isOverdueAt(DateTime now) =>
      dueDate != null && !hasSubmitted && dueDate!.isBefore(now);

  bool get submittedLate =>
      dueDate != null &&
      mySubmittedAt != null &&
      mySubmittedAt!.isAfter(dueDate!);
}

/// Mirrors the backend's `SubmissionRead`.
@freezed
abstract class Submission with _$Submission {
  const factory Submission({
    required String id,
    @JsonKey(name: 'post_id') required String postId,
    @JsonKey(name: 'student_id') required String studentId,
    @JsonKey(name: 'student_name') required String studentName,
    @JsonKey(name: 'student_email') required String studentEmail,
    required AssetInfo asset,
    @JsonKey(name: 'submitted_at') required DateTime submittedAt,
    @JsonKey(name: 'is_late') required bool isLate,
  }) = _Submission;

  factory Submission.fromJson(Map<String, dynamic> json) =>
      _$SubmissionFromJson(json);
}

/// Mirrors the backend's `DownloadLink`.
@freezed
abstract class DownloadLink with _$DownloadLink {
  const factory DownloadLink({
    required String url,
    required String filename,
    @JsonKey(name: 'content_type') required String contentType,
    @JsonKey(name: 'size_bytes') int? sizeBytes,
    @JsonKey(name: 'expires_in') required int expiresIn,
  }) = _DownloadLink;

  factory DownloadLink.fromJson(Map<String, dynamic> json) =>
      _$DownloadLinkFromJson(json);
}
