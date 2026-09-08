import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'note_models.dart';

/// The only place that knows how note endpoints are shaped.
class NoteRepository {
  NoteRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<NoteSummary>> list(String classroomId) async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) => dio.get<List<dynamic>>('/classrooms/$classroomId/notes'),
    );
    return json
        .map((item) => NoteSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Note> get(String noteId) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.get<Map<String, dynamic>>('/notes/$noteId'),
    );
    return Note.fromJson(json);
  }

  Future<void> delete(String noteId) => _apiClient.request<void>(
        (dio) => dio.delete<void>('/notes/$noteId'),
      );

  Future<Note> _create(String classroomId, Map<String, dynamic> body) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/classrooms/$classroomId/notes',
        data: body,
      ),
    );
    return Note.fromJson(json);
  }

  Future<Note> createFromText(
    String classroomId, {
    required String text,
    DateTime? date,
  }) =>
      _create(classroomId,
          {'text': text, if (date != null) 'date': _isoDate(date)});

  Future<Note> createFromYoutube(
    String classroomId, {
    required String url,
    DateTime? date,
  }) =>
      _create(
        classroomId,
        {'youtube_url': url, if (date != null) 'date': _isoDate(date)},
      );

  Future<Note> createFromAsset(
    String classroomId, {
    required String assetId,
    DateTime? date,
  }) =>
      _create(
        classroomId,
        {'asset_id': assetId, if (date != null) 'date': _isoDate(date)},
      );

  /// Reserve a storage slot for a file.
  Future<PresignedUpload> presignUpload({
    required String filename,
    required String contentType,
    required int sizeBytes,
  }) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/uploads/presign',
        data: {
          'filename': filename,
          'content_type': contentType,
          'size_bytes': sizeBytes,
        },
      ),
    );
    return PresignedUpload.fromJson(json);
  }

  /// PUT the file straight to object storage.
  ///
  /// Uses [ApiClient.refreshClient] deliberately: that Dio carries no auth
  /// interceptor, and attaching our bearer token to a presigned S3 URL would
  /// make the request's signature invalid.
  Future<void> uploadFile({
    required PresignedUpload slot,
    required File file,
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await file.length();

    try {
      await _apiClient.refreshClient.put<void>(
        slot.uploadUrl,
        data: file.openRead(),
        onSendProgress: onProgress,
        options: Options(
          headers: {
            Headers.contentTypeHeader: slot.contentType,
            Headers.contentLengthHeader: length,
          },
          // The presigned URL is absolute, so it must not inherit the API base.
          followRedirects: false,
        ),
      );
    } on DioException catch (error) {
      throw ApiException.network(error);
    }
  }

  /// The backend stores a lecture date, not a timestamp.
  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
