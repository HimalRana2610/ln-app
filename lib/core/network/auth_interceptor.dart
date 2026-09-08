import 'dart:async';

import 'package:dio/dio.dart';

import 'token_storage.dart';

/// Attaches the access token and transparently refreshes it on a 401.
///
/// Two things make this harder than it looks, and both are handled here:
///
/// 1. **Concurrent 401s.** Several requests can fail at once when a token
///    expires. Without care each spawns its own refresh, and because the backend
///    rotates refresh tokens, the second one replays an already-used token —
///    which the backend treats as theft and revokes every session. A single
///    shared [_refreshCompleter] means only the first caller refreshes; the rest
///    await the same future.
/// 2. **Refresh must not recurse.** The refresh call itself goes through a
///    separate [Dio] with no interceptors, so a failing refresh cannot trigger
///    another refresh.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio refreshClient,
    required TokenStorage tokenStorage,
    required Future<void> Function() onSessionExpired,
  })  : _refreshClient = refreshClient,
        _tokenStorage = tokenStorage,
        _onSessionExpired = onSessionExpired;

  final Dio _refreshClient;
  final TokenStorage _tokenStorage;
  final Future<void> Function() _onSessionExpired;

  /// Non-null while a refresh is in flight; every concurrent 401 awaits it.
  Completer<bool>? _refreshCompleter;

  static const _authPathsWithoutToken = {
    '/auth/login',
    '/auth/register',
    '/auth/refresh'
  };

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_authPathsWithoutToken.contains(options.path)) {
      final token = await _tokenStorage.readAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final isUnauthorized = err.response?.statusCode == 401;
    final path = err.requestOptions.path;

    // A 401 from login/refresh is a real answer, not a stale token.
    if (!isUnauthorized || _authPathsWithoutToken.contains(path)) {
      return handler.next(err);
    }

    final refreshed = await _refreshOnce();
    if (!refreshed) {
      return handler.next(err);
    }

    try {
      final token = await _tokenStorage.readAccessToken();
      final retried = await _refreshClient.fetch<dynamic>(
        err.requestOptions..headers['Authorization'] = 'Bearer $token',
      );
      return handler.resolve(retried);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }

  /// Refreshes the pair, collapsing concurrent callers onto one request.
  Future<bool> _refreshOnce() {
    final inFlight = _refreshCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    unawaited(
      _performRefresh().then((success) {
        _refreshCompleter = null;
        completer.complete(success);
      }).catchError((Object _) {
        _refreshCompleter = null;
        completer.complete(false);
      }),
    );

    return completer.future;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      await _onSessionExpired();
      return false;
    }

    try {
      final response = await _refreshClient.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      final data = response.data;
      if (data == null) return false;

      await _tokenStorage.save(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );
      return true;
    } on DioException {
      // Refresh token expired or revoked - the session is over.
      await _tokenStorage.clear();
      await _onSessionExpired();
      return false;
    }
  }
}
