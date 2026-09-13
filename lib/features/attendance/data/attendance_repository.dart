import '../../../core/network/api_client.dart';
import 'attendance_models.dart';

/// The only place that knows how attendance endpoints are shaped.
class AttendanceRepository {
  AttendanceRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<AttendanceSession>> list(String classroomId) async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) => dio
          .get<List<dynamic>>('/classrooms/$classroomId/attendance/sessions'),
    );
    return json
        .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AttendanceSession> get(String sessionId) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.get<Map<String, dynamic>>('/attendance/sessions/$sessionId'),
    );
    return AttendanceSession.fromJson(json);
  }

  Future<AttendanceSession> start(
    String classroomId, {
    required DateTime localDate,
    required SessionSettings settings,
    double? latitude,
    double? longitude,
  }) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/classrooms/$classroomId/attendance/sessions',
        data: {
          // The device's own calendar day. The server's would be UTC, which
          // is yesterday for a 5 a.m. lecture in Kathmandu.
          'date': '${localDate.year.toString().padLeft(4, '0')}-'
              '${localDate.month.toString().padLeft(2, '0')}-'
              '${localDate.day.toString().padLeft(2, '0')}',
          'threshold_minutes': settings.thresholdMinutes,
          'radius_meters': settings.radiusMeters,
          'rssi_threshold': settings.rssiThreshold,
          'hop_depth': settings.hopDepth,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
        },
      ),
    );
    return AttendanceSession.fromJson(json);
  }

  Future<AttendanceSession> _setStatus(String sessionId, String status) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/attendance/sessions/$sessionId',
        data: {'status': status},
      ),
    );
    return AttendanceSession.fromJson(json);
  }

  Future<AttendanceSession> openVerification(String sessionId) =>
      _setStatus(sessionId, 'active');

  Future<AttendanceSession> end(String sessionId) =>
      _setStatus(sessionId, 'ended');

  Future<List<AttendanceRecord>> records(String sessionId) async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) =>
          dio.get<List<dynamic>>('/attendance/sessions/$sessionId/records'),
    );
    return json
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AttendanceRecord> correct(String recordId, RecordStatus status) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/attendance/records/$recordId',
        data: {'status': status == RecordStatus.present ? 'present' : 'absent'},
      ),
    );
    return AttendanceRecord.fromJson(json);
  }

  /// Submits a body built by `AttendanceSigner.signedBody`. Unsigned requests
  /// are refused by the server, so there is deliberately no other way in.
  Future<VerifyResult> verifySigned(
    String sessionId,
    Map<String, Object> signedBody,
  ) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/attendance/sessions/$sessionId/verify',
        data: signedBody,
      ),
    );
    return VerifyResult.fromJson(json);
  }
}
