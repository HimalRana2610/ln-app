import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import 'security_models.dart';

/// The only place that knows how the security endpoints are shaped.
class SecurityRepository {
  SecurityRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<int> sendOtp() async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>('/auth/otp/send'),
    );
    return json['resend_after_seconds'] as int;
  }

  Future<void> verifyOtp(String code) =>
      _apiClient.request<Map<String, dynamic>>(
        (dio) => dio.post<Map<String, dynamic>>(
          '/auth/otp/verify',
          data: {'code': code},
        ),
      );

  Future<DeviceInfo> registerDevice({
    required String publicKey,
    required String fingerprintHash,
    required String platform,
    String? model,
  }) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/devices/register',
        data: {
          'public_key': publicKey,
          'fingerprint_hash': fingerprintHash,
          'platform': platform,
          if (model != null) 'model': model,
        },
      ),
    );
    return DeviceInfo.fromJson(json);
  }

  Future<MySecurityStatus> myStatus() async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.get<Map<String, dynamic>>('/users/me/security'),
    );
    return MySecurityStatus.fromJson(json);
  }

  Future<List<StudentSecurity>> students(String classroomId) async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) =>
          dio.get<List<dynamic>>('/classrooms/$classroomId/students/security'),
    );
    return [
      for (final j in json) StudentSecurity.fromJson(j as Map<String, dynamic>),
    ];
  }

  Future<List<SecurityAlert>> alerts(String classroomId) async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) => dio.get<List<dynamic>>(
        '/security/alerts',
        queryParameters: {'classroom_id': classroomId},
      ),
    );
    return [
      for (final j in json) SecurityAlert.fromJson(j as Map<String, dynamic>),
    ];
  }

  Future<void> markAlertRead(String alertId) => _apiClient.request<void>(
        (dio) => dio.post<void>('/security/alerts/$alertId/read'),
      );

  Future<void> setBlock(
    String classroomId,
    String studentId, {
    required bool blocked,
    String? reason,
  }) =>
      _apiClient.request<void>(
        (dio) => dio.post<void>(
          '/classrooms/$classroomId/students/$studentId/block',
          data: {'blocked': blocked, 'reason': reason},
        ),
      );

  Future<void> resetEnrollment(String classroomId, String studentId) =>
      _apiClient.request<void>(
        (dio) => dio.post<void>(
          '/classrooms/$classroomId/students/$studentId/reset-enrollment',
        ),
      );

  Future<FaceStatus> faceStatus() async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.get<Map<String, dynamic>>('/face/status'),
    );
    return FaceStatus.fromJson(json);
  }

  Future<FaceStatus> enrollFace({
    required File front,
    required File left,
    required File right,
  }) async {
    Future<MultipartFile> part(File file, String name) =>
        MultipartFile.fromFile(file.path,
            filename: '$name.jpg', contentType: DioMediaType('image', 'jpeg'));

    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) async => dio.post<Map<String, dynamic>>(
        '/face/enrollment',
        // A fresh FormData per attempt: a retry after the server relocates
        // cannot reuse one whose streams were already consumed.
        data: FormData.fromMap({
          'front': await part(front, 'front'),
          'left': await part(left, 'left'),
          'right': await part(right, 'right'),
          'consent': 'true',
        }),
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      ),
    );
    return FaceStatus.fromJson(json);
  }

  Future<void> deleteFace() =>
      _apiClient.request<void>((dio) => dio.delete<void>('/face/enrollment'));
}
