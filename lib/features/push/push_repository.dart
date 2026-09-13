import '../../core/network/api_client.dart';

/// The only place that knows how device push-token endpoints are shaped.
class PushRepository {
  PushRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<void> registerToken(String token, {required String platform}) =>
      _apiClient.request<void>(
        (dio) => dio.post<void>(
          '/me/devices/push-token',
          data: {'token': token, 'platform': platform},
        ),
      );

  /// A POST rather than DELETE-with-body, which some proxies strip.
  Future<void> removeToken(String token) => _apiClient.request<void>(
        (dio) => dio.post<void>(
          '/me/devices/push-token/remove',
          data: {'token': token},
        ),
      );
}
