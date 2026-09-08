import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the token pair in platform-backed secure storage.
///
/// Keychain on iOS, AES-GCM encrypted storage on Android. Deliberately not
/// plain SharedPreferences: that is plain text on disk and readable by anything
/// with filesystem access on a rooted device.
///
/// `AndroidOptions` takes no `encryptedSharedPreferences` flag as of
/// flutter_secure_storage 11 — encryption is always on, so the default
/// constructor is the secure one.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  static const _accessKey = 'ln_access_token';
  static const _refreshKey = 'ln_refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> save(
      {required String accessToken, required String refreshToken}) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: accessToken),
      _storage.write(key: _refreshKey, value: refreshToken),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }

  Future<bool> hasSession() async => await readRefreshToken() != null;
}
