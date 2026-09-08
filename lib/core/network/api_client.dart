import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'token_storage.dart';

/// Configured [Dio] instances for the app.
///
/// Two clients exist on purpose:
///
/// * [client] — carries [AuthInterceptor], used for every normal call.
/// * [refreshClient] — no interceptors, used to refresh tokens and to retry a
///   request after refreshing. Sharing one client would let a failing refresh
///   trigger another refresh, forever.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    required Future<void> Function() onSessionExpired,
  }) {
    refreshClient = Dio(_baseOptions);
    client = Dio(_baseOptions)
      ..interceptors.add(
        AuthInterceptor(
          refreshClient: refreshClient,
          tokenStorage: tokenStorage,
          onSessionExpired: onSessionExpired,
        ),
      );
  }

  static BaseOptions get _baseOptions => BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        // Let non-2xx through to the interceptor rather than throwing early,
        // so a 401 can be turned into a refresh-and-retry.
        validateStatus: (status) => status != null && status < 500,
      );

  late final Dio client;
  late final Dio refreshClient;

  /// Issues a request and maps any failure onto [ApiException].
  ///
  /// Callers therefore handle one exception type instead of picking apart
  /// [DioException] at every call site.
  Future<T> request<T>(Future<Response<dynamic>> Function(Dio dio) send) async {
    try {
      final response = await send(client);
      final status = response.statusCode ?? 0;

      if (status >= 400) {
        throw ApiException.fromResponse(status, response.data);
      }
      return response.data as T;
    } on DioException catch (error) {
      if (error.response != null) {
        throw ApiException.fromResponse(
          error.response!.statusCode ?? 0,
          error.response!.data,
        );
      }
      throw ApiException.network(error);
    }
  }
}
