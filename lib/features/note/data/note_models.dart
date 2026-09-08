import 'package:freezed_annotation/freezed_annotation.dart';

part 'note_models.freezed.dart';
part 'note_models.g.dart';

enum NoteStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('processing')
  processing,
  @JsonValue('ready')
  ready,
  @JsonValue('failed')
  failed;

  /// Whether the client can stop polling.
  bool get isTerminal => this == NoteStatus.ready || this == NoteStatus.failed;

  bool get isGenerating => !isTerminal;

  String get label => switch (this) {
        NoteStatus.pending => 'Queued',
        NoteStatus.processing => 'Generating',
        NoteStatus.ready => 'Ready',
        NoteStatus.failed => 'Failed',
      };
}

enum NoteSourceType {
  @JsonValue('audio')
  audio,
  @JsonValue('text')
  text,
  @JsonValue('pdf')
  pdf,
  @JsonValue('youtube')
  youtube;

  String get label => switch (this) {
        NoteSourceType.audio => 'Recording',
        NoteSourceType.text => 'Text',
        NoteSourceType.pdf => 'PDF',
        NoteSourceType.youtube => 'YouTube',
      };
}

/// Mirrors the backend's `NoteSummary`.
///
/// Has no `markdown`: the list endpoint omits it, because a classroom's notes
/// can add up to hundreds of kilobytes that nobody has opened yet.
@freezed
abstract class NoteSummary with _$NoteSummary {
  const factory NoteSummary({
    required String id,
    @JsonKey(name: 'classroom_id') required String classroomId,
    required DateTime date,
    required String title,
    required NoteStatus status,
    @JsonKey(name: 'source_type') required NoteSourceType sourceType,
    @JsonKey(name: 'author_id') required String authorId,
    @JsonKey(name: 'author_name') required String authorName,
    @JsonKey(name: 'duration_seconds') int? durationSeconds,
    @JsonKey(name: 'error_message') String? errorMessage,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _NoteSummary;

  factory NoteSummary.fromJson(Map<String, dynamic> json) =>
      _$NoteSummaryFromJson(json);
}

/// Mirrors the backend's `NoteRead` — the summary plus the generated body.
@freezed
abstract class Note with _$Note {
  const factory Note({
    required String id,
    @JsonKey(name: 'classroom_id') required String classroomId,
    required DateTime date,
    required String title,
    required NoteStatus status,
    @JsonKey(name: 'source_type') required NoteSourceType sourceType,
    @JsonKey(name: 'author_id') required String authorId,
    @JsonKey(name: 'author_name') required String authorName,
    @JsonKey(name: 'duration_seconds') int? durationSeconds,
    @JsonKey(name: 'error_message') String? errorMessage,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    required String markdown,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
}

/// Mirrors the backend's `PresignUploadResponse`.
@freezed
abstract class PresignedUpload with _$PresignedUpload {
  const factory PresignedUpload({
    @JsonKey(name: 'asset_id') required String assetId,
    @JsonKey(name: 'upload_url') required String uploadUrl,

    /// Must be sent as the `Content-Type` header on the PUT, or the signature
    /// will not match.
    @JsonKey(name: 'content_type') required String contentType,
    @JsonKey(name: 'expires_in') required int expiresIn,
  }) = _PresignedUpload;

  factory PresignedUpload.fromJson(Map<String, dynamic> json) =>
      _$PresignedUploadFromJson(json);
}
