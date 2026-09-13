import 'app_config.dart';

/// Turns what a person types, or what discovery finds, into a URL the API
/// client can use.
///
/// Pure string work with no I/O, so the rules are pinned by unit tests rather
/// than discovered on a phone.
abstract final class ServerUrl {
  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  /// Canonicalises [input], or returns null when it cannot be a server address.
  ///
  /// Accepts the shapes people actually type:
  ///
  /// ```
  /// 192.168.1.3                     -> http://192.168.1.3:8000/api/v1
  /// 192.168.1.3:8000                -> http://192.168.1.3:8000/api/v1
  /// http://192.168.1.3:8000/api/v1  -> http://192.168.1.3:8000/api/v1
  /// https://api.example.com         -> https://api.example.com/api/v1
  /// ```
  ///
  /// The port is only filled in for an address on a local network. A deployed
  /// host is reached over 443 and adding `:8000` to it would break it.
  static String? normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // `Uri.parse('192.168.1.3:8000')` reads "192.168.1.3" as the *scheme*, so
    // a scheme has to be supplied before parsing rather than after.
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';

    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final port = uri.hasPort
        ? uri.port
        : (isLanHost(uri.host) ? AppConfig.backendPort : null);
    final authority = port == null ? uri.host : '${uri.host}:$port';

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (!path.endsWith(AppConfig.apiPrefix)) {
      path = '$path${AppConfig.apiPrefix}';
    }

    return '${uri.scheme}://$authority$path';
  }

  /// The liveness endpoint for [baseUrl]. Probing this is what distinguishes
  /// our backend from anything else that happens to have the port open.
  static String healthUrl(String baseUrl) => '$baseUrl/health';

  /// The base URL for a host found on the network.
  static String forHost(String host, {int? port}) =>
      'http://$host:${port ?? AppConfig.backendPort}${AppConfig.apiPrefix}';

  /// A short label for the UI: host and port, without scheme or path.
  static String display(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return baseUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// True for hosts that only exist on the machine or the local network, and
  /// which therefore need the backend port spelled out.
  static bool isLanHost(String host) =>
      host == 'localhost' || host.endsWith('.local') || _ipv4.hasMatch(host);
}
