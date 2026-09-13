import 'dart:io';

/// Build-time configuration, and the addresses used before the real one is
/// known.
///
/// The server address is deliberately **not** fixed at build time.
/// `--dart-define=API_BASE_URL=...` only seeds the search: it is the first
/// address tried, and if it does not answer the app looks for the backend on
/// the network instead. The machine running the backend sits on DHCP, so its
/// address changes whenever the lease is renewed or the laptop joins another
/// network, and rebuilding the app for each new address is not a workable way
/// to develop.
///
/// See [ServerLocator] for how an address is found and [ServerConnection] for
/// how it is applied.
abstract final class AppConfig {
  static const _defineApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// The URL baked in at build time, or empty when none was given.
  static const definedApiBaseUrl = _defineApiBaseUrl;

  /// The port the backend listens on. Discovery scans the network for it.
  static const backendPort =
      int.fromEnvironment('API_PORT', defaultValue: 8000);

  /// The path prefix every endpoint sits behind.
  static const apiPrefix = '/api/v1';

  /// Where requests point before discovery has finished, and what they fall
  /// back to when nothing is found.
  ///
  /// `localhost` inside an Android emulator means the emulator itself, not the
  /// machine hosting it; `10.0.2.2` is the emulator's alias for the host.
  static String get fallbackApiBaseUrl {
    if (definedApiBaseUrl.isNotEmpty) return definedApiBaseUrl;
    if (Platform.isAndroid) return 'http://10.0.2.2:$backendPort$apiPrefix';
    return 'http://localhost:$backendPort$apiPrefix';
  }

  /// True when [baseUrl] is plain HTTP, which in practice means a backend on
  /// this network rather than a deployed one.
  ///
  /// The server picker is only worth offering in that case — a released build
  /// pointed at production has nothing to search for.
  static bool isLocal(String baseUrl) => baseUrl.startsWith('http://');
}
