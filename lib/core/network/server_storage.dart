import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers the server address that last worked.
///
/// Nothing here is a secret; this shares the app's existing secure storage
/// only to avoid adding a second persistence plugin for one string. What
/// matters is that it survives a restart, so a phone that has found the
/// backend once does not sweep the network again on every launch.
///
/// Kept apart from `TokenStorage` on purpose: signing out clears tokens, and
/// it would be perverse for that to also forget where the server is.
class ServerStorage {
  ServerStorage({FlutterSecureStorage? storage})
      : _storage =
            storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  static const _baseUrlKey = 'ln_server_base_url';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _baseUrlKey);

  Future<void> write(String baseUrl) =>
      _storage.write(key: _baseUrlKey, value: baseUrl);

  Future<void> clear() => _storage.delete(key: _baseUrlKey);
}
