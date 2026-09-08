import 'dart:io';

/// Build-time configuration.
///
/// Values come from `--dart-define`, so no secret or environment-specific URL is
/// ever committed:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
/// ```
///
/// The default is deliberately emulator-aware. `localhost` inside an Android
/// emulator means the emulator itself, not your machine — `10.0.2.2` is the
/// host loopback alias. Getting this wrong is the single most common reason a
/// freshly built app "cannot reach the server".
abstract final class AppConfig {
  static const _defineApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_defineApiBaseUrl.isNotEmpty) return _defineApiBaseUrl;
    return _defaultLocalBaseUrl;
  }

  static String get _defaultLocalBaseUrl {
    // Android emulator reaches the host at 10.0.2.2; the iOS simulator shares
    // the host network, so localhost works there.
    if (Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
    return 'http://localhost:8000/api/v1';
  }

  /// True when running against a local backend over plain HTTP.
  static bool get isLocal => apiBaseUrl.startsWith('http://');
}
