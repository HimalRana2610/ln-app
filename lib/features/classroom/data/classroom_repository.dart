import '../../../core/network/api_client.dart';
import 'classroom_models.dart';

/// The only place that knows how classroom endpoints are shaped.
class ClassroomRepository {
  ClassroomRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Classroom>> listMine() async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) => dio.get<List<dynamic>>('/classrooms'),
    );
    return json
        .map((item) => Classroom.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Classroom> create({
    required String name,
    String? section,
    required ClassroomType type,
    required String themeColor,
  }) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/classrooms',
        data: {
          'name': name,
          if (section != null && section.isNotEmpty) 'section': section,
          'type': type.name,
          'theme_color': themeColor,
        },
      ),
    );
    return Classroom.fromJson(json);
  }

  Future<Classroom> joinByCode(String code) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/classrooms/join',
        // Codes are stored uppercase; normalise before sending so the user can
        // type in any case.
        data: {'code': code.trim().toUpperCase()},
      ),
    );
    return Classroom.fromJson(json);
  }

  Future<List<ClassroomMember>> members(String classroomId) async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) => dio.get<List<dynamic>>('/classrooms/$classroomId/members'),
    );
    return json
        .map((item) => ClassroomMember.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> leave(String classroomId) => _apiClient.request<void>(
        (dio) => dio.post<void>('/classrooms/$classroomId/leave'),
      );

  Future<void> delete(String classroomId) => _apiClient.request<void>(
        (dio) => dio.delete<void>('/classrooms/$classroomId'),
      );
}
