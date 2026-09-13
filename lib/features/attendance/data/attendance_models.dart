import 'package:freezed_annotation/freezed_annotation.dart';

part 'attendance_models.freezed.dart';
part 'attendance_models.g.dart';

enum SessionStatus {
  @JsonValue('monitoring')
  monitoring,
  @JsonValue('active')
  active,
  @JsonValue('ended')
  ended;

  String get label => switch (this) {
        SessionStatus.monitoring => 'Monitoring',
        SessionStatus.active => 'Verification open',
        SessionStatus.ended => 'Ended',
      };

  /// Beacons are advertised and relayed only while this is true.
  bool get isRunning => this != SessionStatus.ended;
}

enum RecordStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('present')
  present,
  @JsonValue('absent')
  absent;

  String get label => switch (this) {
        RecordStatus.pending => 'Not yet marked',
        RecordStatus.present => 'Present',
        RecordStatus.absent => 'Absent',
      };
}

/// Mirrors the backend's `SessionRead`.
@freezed
abstract class AttendanceSession with _$AttendanceSession {
  const factory AttendanceSession({
    required String id,
    @JsonKey(name: 'classroom_id') required String classroomId,
    @JsonKey(name: 'started_by') required String startedBy,
    @JsonKey(name: 'started_by_name') required String startedByName,

    /// The classroom's calendar day, `YYYY-MM-DD`.
    required String date,
    required SessionStatus status,
    @JsonKey(name: 'started_at') required DateTime startedAt,
    @JsonKey(name: 'verification_opens_at')
    required DateTime verificationOpensAt,
    @JsonKey(name: 'ended_at') DateTime? endedAt,
    double? latitude,
    double? longitude,
    @JsonKey(name: 'radius_meters') required int radiusMeters,
    @JsonKey(name: 'threshold_minutes') required int thresholdMinutes,
    @JsonKey(name: 'rssi_threshold') required int rssiThreshold,
    @JsonKey(name: 'hop_depth') required int hopDepth,
    @JsonKey(name: 'session_tag') required String sessionTag,
    @JsonKey(name: 'window_seconds') required int windowSeconds,
    @JsonKey(name: 'server_time') required DateTime serverTime,

    /// Teachers only.
    @JsonKey(name: 'beacon_secret') String? beaconSecret,
    @JsonKey(name: 'present_count') required int presentCount,
    @JsonKey(name: 'record_count') required int recordCount,

    /// Students only.
    @JsonKey(name: 'my_status') RecordStatus? myStatus,
  }) = _AttendanceSession;

  factory AttendanceSession.fromJson(Map<String, dynamic> json) =>
      _$AttendanceSessionFromJson(json);
}

/// Mirrors the backend's `RecordRead`.
@freezed
abstract class AttendanceRecord with _$AttendanceRecord {
  const factory AttendanceRecord({
    required String id,
    @JsonKey(name: 'session_id') required String sessionId,
    @JsonKey(name: 'student_id') required String studentId,
    @JsonKey(name: 'student_name') required String studentName,
    @JsonKey(name: 'student_email') required String studentEmail,
    required RecordStatus status,
    @JsonKey(name: 'marked_at') DateTime? markedAt,
    required bool corrected,
  }) = _AttendanceRecord;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      _$AttendanceRecordFromJson(json);
}

/// Mirrors the backend's `VerifyResult`.
@freezed
abstract class VerifyResult with _$VerifyResult {
  const factory VerifyResult({
    required bool accepted,
    String? reason,
    required String message,
    @JsonKey(name: 'valid_windows') required int validWindows,
    @JsonKey(name: 'elapsed_windows') required int elapsedWindows,
    @JsonKey(name: 'required_windows') required int requiredWindows,
    AttendanceRecord? record,
  }) = _VerifyResult;

  factory VerifyResult.fromJson(Map<String, dynamic> json) =>
      _$VerifyResultFromJson(json);
}

/// What a teacher chooses when starting a session.
class SessionSettings {
  const SessionSettings({
    this.thresholdMinutes = 5,
    this.radiusMeters = 15,
    this.rssiThreshold = -80,
    this.hopDepth = 2,
  });

  final int thresholdMinutes;
  final int radiusMeters;
  final int rssiThreshold;
  final int hopDepth;
}
