import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_storage.dart';
import 'models.dart';

/// The only place that knows how auth endpoints are shaped.
///
/// Controllers depend on this, never on Dio directly, so swapping transport or
/// stubbing it in tests touches one file.
class AuthRepository {
  AuthRepository(
      {required ApiClient apiClient, required TokenStorage tokenStorage})
      : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  Future<User> register({
    required String email,
    required String fullName,
    required String password,
    String? institute,
  }) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'email': email,
          'full_name': fullName,
          'password': password,
          if (institute != null && institute.isNotEmpty) 'institute': institute,
        },
      ),
    );
    return User.fromJson(json);
  }

  /// Signs in and persists the token pair.
  Future<User> login({required String email, required String password}) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      ),
    );

    final tokens = TokenPair.fromJson(json);
    await _tokenStorage.save(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );

    return currentUser();
  }

  Future<User> currentUser() async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.get<Map<String, dynamic>>('/users/me'),
    );
    return User.fromJson(json);
  }

  /// Only the fields passed are changed.
  Future<User> updateProfile({String? fullName, String? institute}) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/users/me',
        data: {
          if (fullName != null) 'full_name': fullName,
          if (institute != null) 'institute': institute,
        },
      ),
    );
    return User.fromJson(json);
  }

  /// Deletes the account, then the local session.
  ///
  /// A wrong password comes back as a 400 `incorrect_password` — not a 401,
  /// which the interceptor would treat as an expired session. Local tokens are
  /// only cleared once the server has confirmed the deletion.
  Future<void> deleteAccount({required String password}) async {
    await _apiClient.request<void>(
      (dio) => dio.post<void>(
        '/users/me/delete',
        data: {'password': password},
      ),
    );
    await _tokenStorage.clear();
  }

  /// Ends the session on the server, then locally.
  ///
  /// The network call is best-effort: local tokens are cleared regardless, so a
  /// user who taps "sign out" offline is never left apparently signed in.
  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();

    try {
      await _apiClient.request<void>(
        (dio) => dio.post<void>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        ),
      );
    } on Exception {
      // Deliberately ignored - see above.
    } finally {
      await _tokenStorage.clear();
    }
  }

  /// Restores a session on cold start, or null if there is none.
  ///
  /// Throws [ApiException] when the server could not be reached, rather than
  /// reporting "no session". Discarding tokens because a laptop was asleep or
  /// had changed address would sign the user out of a session that is
  /// perfectly valid, and they would have no way to tell why.
  Future<User?> restoreSession() async {
    if (!await _tokenStorage.hasSession()) return null;

    try {
      return await currentUser();
    } on ApiException catch (error) {
      if (error.isNetworkFailure) rethrow;

      // The interceptor already tried to refresh; reaching here means the
      // session itself is no longer good.
      await _tokenStorage.clear();
      return null;
    } on DioException {
      await _tokenStorage.clear();
      return null;
    }
  }
}
