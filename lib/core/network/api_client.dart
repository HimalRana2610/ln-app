import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'server_connection.dart';
import 'token_storage.dart';

/// Configured [Dio] instances for the app.
///
/// Two clients exist on purpose:
///
/// * [client] — carries [AuthInterceptor], used for every normal call.
/// * [refreshClient] — no interceptors, used to refresh tokens and to retry a
///   request after refreshing. Sharing one client would let a failing refresh
///   trigger another refresh, forever.
///
/// The address is taken from [ServerConnection] on each request rather than
/// fixed at construction, because the backend runs on a machine whose DHCP
/// address changes.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    required ServerConnection server,
    required Future<void> Function() onSessionExpired,
  }) : _server = server {
    refreshClient = Dio(_baseOptions);
    client = Dio(_baseOptions)
      ..interceptors.add(
        AuthInterceptor(
          refreshClient: refreshClient,
          tokenStorage: tokenStorage,
          onSessionExpired: onSessionExpired,
        ),
      );
    _applyBaseUrl();
  }

  static BaseOptions get _baseOptions => BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        // Let non-2xx through to the interceptor rather than throwing early,
        // so a 401 can be turned into a refresh-and-retry.
        validateStatus: (status) => status != null && status < 500,
      );

  final ServerConnection _server;

  late final Dio client;
  late final Dio refreshClient;

  /// Issues a request and maps any failure onto [ApiException].
  ///
  /// Callers therefore handle one exception type instead of picking apart
  /// [DioException] at every call site.
  Future<T> request<T>(Future<Response<dynamic>> Function(Dio dio) send) async {
    // The first call of a session is also what starts the search for the
    // server, so no screen has to remember to kick it off.
    await _server.ensureLocated();
    return _send<T>(send, allowRelocate: true);
  }

  Future<T> _send<T>(
    Future<Response<dynamic>> Function(Dio dio) send, {
    required bool allowRelocate,
  }) async {
    _applyBaseUrl();

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

      // Nothing answered at all. By far the most common cause is that the
      // backend has moved to a new DHCP address, so look for it again and
      // retry once. A changed address then heals itself instead of surfacing
      // as an error the person can do nothing about.
      if (allowRelocate && _isUnreachable(error) && await _server.relocate()) {
        return _send<T>(send, allowRelocate: false);
      }

      throw ApiException.network(error);
    }
  }

  /// Points both clients at the current address.
  ///
  /// Dio reads `options.baseUrl` when it builds a request, so doing this per
  /// request means an address found mid-session takes effect immediately —
  /// without rebuilding clients, repositories or providers, which would
  /// discard whatever the screen was showing.
  void _applyBaseUrl() {
    final baseUrl = _server.baseUrl;
    client.options.baseUrl = baseUrl;
    refreshClient.options.baseUrl = baseUrl;
  }

  static bool _isUnreachable(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout;
}
