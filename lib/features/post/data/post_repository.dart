import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'post_models.dart';

/// The only place that knows how post, submission and download endpoints are
/// shaped. Uploads reuse `NoteRepository`'s presign-and-PUT.
class PostRepository {
  PostRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Post>> list(String classroomId, PostKind kind) async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) => dio.get<List<dynamic>>(
        '/classrooms/$classroomId/posts',
        queryParameters: {'kind': kind.wire},
      ),
    );
    return json
        .map((item) => Post.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Post> create(
    String classroomId, {
    required PostKind kind,
    required String title,
    String? description,
    DateTime? dueDate,
    String? assetId,
  }) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/classrooms/$classroomId/posts',
        data: {
          'kind': kind.wire,
          'title': title,
          if (description != null && description.isNotEmpty)
            'description': description,
          // Sent as UTC with a `Z`. The backend refuses a timestamp without a
          // zone, and a local one converted here is unambiguous.
          if (dueDate != null) 'due_date': dueDate.toUtc().toIso8601String(),
          if (assetId != null) 'asset_id': assetId,
        },
      ),
    );
    return Post.fromJson(json);
  }

  Future<void> delete(String postId) =>
      _apiClient.request<void>((dio) => dio.delete<void>('/posts/$postId'));

  Future<Submission> submit(String postId, {required String assetId}) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/posts/$postId/submissions',
        data: {'asset_id': assetId},
      ),
    );
    return Submission.fromJson(json);
  }

  Future<List<Submission>> listSubmissions(String postId) async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) => dio.get<List<dynamic>>('/posts/$postId/submissions'),
    );
    return json
        .map((item) => Submission.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// The student's own submission, or null when they have not submitted.
  Future<Submission?> mySubmission(String postId) async {
    try {
      final json = await _apiClient.request<Map<String, dynamic>>(
        (dio) => dio.get<Map<String, dynamic>>('/posts/$postId/submissions/me'),
      );
      return Submission.fromJson(json);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// A fresh presigned URL. Never cache it — it expires.
  Future<DownloadLink> downloadLink(String assetId) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.get<Map<String, dynamic>>('/assets/$assetId/download'),
    );
    return DownloadLink.fromJson(json);
  }

  /// Stream a file from storage to [savePath].
  ///
  /// Uses [ApiClient.refreshClient], which carries no auth interceptor: a
  /// bearer token on a presigned URL is at best ignored and at worst makes
  /// storage reject the request as ambiguously authenticated.
  Future<void> downloadTo(
    DownloadLink link, {
    required String savePath,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      await _apiClient.refreshClient.download(
        link.url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          // The client's default lets 4xx through for the auth interceptor;
          // here an expired link must fail rather than save an XML error page
          // under the student's filename.
          validateStatus: (status) => status != null && status < 300,
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      final status = error.response?.statusCode;
      if (status != null) {
        // Storage answered, but not with the file: the link expired while the
        // download queued, or the file was deleted a moment ago.
        throw ApiException(
          statusCode: status,
          code: 'download_failed',
          message: 'The file could not be downloaded ($status). Try again.',
        );
      }
      throw ApiException.network(error);
    }
  }
}
