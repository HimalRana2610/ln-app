/// Security API shapes. Plain classes: small, read-only, and parsed in one place.
library;

DateTime _date(Object? v) => DateTime.parse(v! as String);
DateTime? _dateOrNull(Object? v) =>
    v == null ? null : DateTime.parse(v as String);

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.platform,
    required this.model,
    required this.boundAt,
    required this.lastSeenAt,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        id: j['id'] as String,
        platform: j['platform'] as String,
        model: j['model'] as String?,
        boundAt: _date(j['bound_at']),
        lastSeenAt: _date(j['last_seen_at']),
      );

  final String id;
  final String platform;
  final String? model;
  final DateTime boundAt;
  final DateTime lastSeenAt;

  String get label => model ?? platform;
}

class BlockInfo {
  const BlockInfo({
    required this.classroomId,
    required this.classroomName,
    required this.reason,
  });

  factory BlockInfo.fromJson(Map<String, dynamic> j) => BlockInfo(
        classroomId: j['classroom_id'] as String,
        classroomName: j['classroom_name'] as String,
        reason: j['reason'] as String?,
      );

  final String classroomId;
  final String classroomName;
  final String? reason;
}

class MySecurityStatus {
  const MySecurityStatus({
    required this.emailVerified,
    required this.device,
    required this.faceEnrolled,
    required this.blocks,
  });

  factory MySecurityStatus.fromJson(Map<String, dynamic> j) => MySecurityStatus(
        emailVerified: j['email_verified'] as bool,
        device: j['device'] == null
            ? null
            : DeviceInfo.fromJson(j['device'] as Map<String, dynamic>),
        faceEnrolled: j['face_enrolled'] as bool,
        blocks: [
          for (final b in j['blocks'] as List<dynamic>)
            BlockInfo.fromJson(b as Map<String, dynamic>),
        ],
      );

  final bool emailVerified;
  final DeviceInfo? device;
  final bool faceEnrolled;
  final List<BlockInfo> blocks;

  BlockInfo? blockFor(String classroomId) {
    for (final b in blocks) {
      if (b.classroomId == classroomId) return b;
    }
    return null;
  }
}

class StudentSecurity {
  const StudentSecurity({
    required this.studentId,
    required this.fullName,
    required this.email,
    required this.emailVerified,
    required this.device,
    required this.faceEnrolled,
    required this.blocked,
    required this.blockReason,
    required this.unreadAlerts,
  });

  factory StudentSecurity.fromJson(Map<String, dynamic> j) => StudentSecurity(
        studentId: j['student_id'] as String,
        fullName: j['full_name'] as String,
        email: j['email'] as String,
        emailVerified: j['email_verified'] as bool,
        device: j['device'] == null
            ? null
            : DeviceInfo.fromJson(j['device'] as Map<String, dynamic>),
        faceEnrolled: j['face_enrolled'] as bool,
        blocked: j['blocked'] as bool,
        blockReason: j['block_reason'] as String?,
        unreadAlerts: j['unread_alerts'] as int,
      );

  final String studentId;
  final String fullName;
  final String email;
  final bool emailVerified;
  final DeviceInfo? device;
  final bool faceEnrolled;
  final bool blocked;
  final String? blockReason;
  final int unreadAlerts;
}

class SecurityAlert {
  const SecurityAlert({
    required this.id,
    required this.studentName,
    required this.type,
    required this.severity,
    required this.message,
    required this.createdAt,
    required this.readAt,
  });

  factory SecurityAlert.fromJson(Map<String, dynamic> j) => SecurityAlert(
        id: j['id'] as String,
        studentName: j['student_name'] as String,
        type: j['type'] as String,
        severity: j['severity'] as String,
        message: j['message'] as String,
        createdAt: _date(j['created_at']),
        readAt: _dateOrNull(j['read_at']),
      );

  final String id;
  final String studentName;
  final String type;
  final String severity;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get critical => severity == 'critical';

  String get label => switch (type) {
        'multi_device' => 'Tried a second phone',
        'shared_device' => 'Phone belongs to another student',
        'wrong_device' => 'Marked from the wrong phone',
        'invalid_signature' => 'Request failed verification',
        _ => type,
      };
}

class FaceStatus {
  const FaceStatus({
    required this.available,
    required this.enrolled,
    required this.enrolledAt,
  });

  factory FaceStatus.fromJson(Map<String, dynamic> j) => FaceStatus(
        available: j['available'] as bool,
        enrolled: j['enrolled'] as bool,
        enrolledAt: _dateOrNull(j['enrolled_at']),
      );

  final bool available;
  final bool enrolled;
  final DateTime? enrolledAt;
}
