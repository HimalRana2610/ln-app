import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../config/server_url.dart';
import 'server_storage.dart';

/// Probes one base URL and reports whether our backend answered there.
typedef ServerProbe = Future<bool> Function(String baseUrl, Duration timeout);

/// Answers "where is the backend right now?".
///
/// The address cannot be fixed at build time. The machine running the backend
/// is on DHCP, so it changes address when the lease renews or the laptop moves
/// between Wi-Fi and Ethernet or onto another network — and every one of those
/// used to mean rebuilding the app with a new `--dart-define`.
///
/// The search runs in two stages, cheapest first:
///
/// 1. **Known addresses** — the one that worked last time, the one baked in at
///    build time, `localhost` (which works over `adb reverse`, and on desktop),
///    and the Android emulator's host alias.
/// 2. **A sweep of the phone's own subnet** — every address on the /24, tested
///    for an open backend port and then confirmed with a real `/health` call.
///
/// Confirming with `/health` matters: a home network has other devices, and
/// something else answering on port 8000 would otherwise be adopted as the
/// backend.
///
/// Every piece of I/O is injectable so the search order and the sweep are
/// tested without touching a real network.
class ServerLocator {
  ServerLocator({
    ServerStorage? storage,
    ServerProbe? probe,
    Future<List<String>> Function()? localAddresses,
    Future<bool> Function(String host, int port, Duration timeout)? isPortOpen,
  })  : _storage = storage ?? ServerStorage(),
        _probe = probe ?? httpProbe,
        _localAddresses = localAddresses ?? deviceAddresses,
        _isPortOpen = isPortOpen ?? tcpPortOpen;

  /// Long enough for a busy dev machine to answer, short enough that three
  /// dead candidates do not visibly delay startup.
  static const probeTimeout = Duration(milliseconds: 1500);

  /// A LAN round trip is sub-millisecond; anything not answering this fast is
  /// almost certainly not there. 254 addresses at 400ms each would be a
  /// minute and a half if they ran one at a time, hence [sweepBatchSize].
  static const sweepConnectTimeout = Duration(milliseconds: 400);

  /// How many addresses are tried at once. Enough to sweep a /24 in a few
  /// seconds; low enough not to exhaust the socket limit on a phone.
  static const sweepBatchSize = 48;

  final ServerStorage _storage;
  final ServerProbe _probe;
  final Future<List<String>> Function() _localAddresses;
  final Future<bool> Function(String host, int port, Duration timeout)
      _isPortOpen;

  /// The address that worked last time, if there is one.
  Future<String?> saved() async {
    final stored = await _storage.read();
    return stored == null ? null : ServerUrl.normalize(stored);
  }

  /// The known addresses, in the order they are tried.
  Future<List<String>> candidates({bool includeSaved = true}) async {
    final urls = <String>[];

    void add(String? url) {
      if (url == null || url.isEmpty) return;
      final normalized = ServerUrl.normalize(url);
      if (normalized != null && !urls.contains(normalized)) {
        urls.add(normalized);
      }
    }

    if (includeSaved) add(await _storage.read());
    add(AppConfig.definedApiBaseUrl);
    // Reachable when the phone is tethered with `adb reverse tcp:8000
    // tcp:8000`, and on desktop. Costs nothing to try: a wrong guess here is
    // refused immediately rather than timing out.
    add('http://localhost:${AppConfig.backendPort}');
    if (Platform.isAndroid) {
      add('http://10.0.2.2:${AppConfig.backendPort}');
    }

    return urls;
  }

  /// True when our backend answers at [baseUrl].
  Future<bool> check(String baseUrl, {Duration? timeout}) =>
      _probe(baseUrl, timeout ?? probeTimeout);

  /// Finds the backend, or returns null when nothing on this network is
  /// serving it.
  ///
  /// Pass [ignoreSaved] after a failure: the remembered address is the most
  /// likely one to have just gone stale, and re-testing it first only adds a
  /// timeout to every recovery.
  Future<String?> discover({bool ignoreSaved = false}) async {
    for (final url in await candidates(includeSaved: !ignoreSaved)) {
      if (await _probe(url, probeTimeout)) return remember(url);
    }

    final found = await _sweep();
    return found == null ? null : remember(found);
  }

  /// Stores [baseUrl] as the address to try first next time.
  Future<String> remember(String baseUrl) async {
    await _storage.write(baseUrl);
    return baseUrl;
  }

  Future<void> forget() => _storage.clear();

  Future<String?> _sweep() async {
    for (final address in await _localAddresses()) {
      final hosts = subnetHosts(address);

      for (var start = 0; start < hosts.length; start += sweepBatchSize) {
        final batch =
            hosts.sublist(start, min(start + sweepBatchSize, hosts.length));

        final open = await Future.wait(
          batch.map(
            (host) async => await _isPortOpen(
                    host, AppConfig.backendPort, sweepConnectTimeout)
                ? host
                : null,
          ),
        );

        for (final host in open.whereType<String>()) {
          final url = ServerUrl.forHost(host);
          if (await _probe(url, probeTimeout)) return url;
        }
      }
    }
    return null;
  }

  /// Every other address on [address]'s /24.
  ///
  /// A /24 is assumed rather than read from the interface: it is what home and
  /// campus networks hand out, and sweeping a larger prefix would take long
  /// enough that nobody would wait for it.
  static List<String> subnetHosts(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return const [];

    final own = int.tryParse(parts[3]);
    if (own == null) return const [];

    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    return [
      for (var host = 1; host <= 254; host++)
        if (host != own) '$prefix.$host',
    ];
  }

  /// True for RFC 1918 ranges — the only ones a phone and a laptop share on a
  /// home or campus network.
  ///
  /// This is what keeps the sweep off the 169.254 addresses that unplugged
  /// adapters hold, which route nowhere and would each cost a full scan.
  static bool isPrivateIPv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return false;

    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) return false;

    if (first == 10) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    if (first == 192 && second == 168) return true;
    return false;
  }

  /// The device's own private IPv4 addresses, one per connected network.
  static Future<List<String>> deviceAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (isPrivateIPv4(address.address)) address.address,
    ];
  }

  /// Asks [baseUrl] for `/health` and checks the answer is ours.
  static Future<bool> httpProbe(String baseUrl, Duration timeout) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    try {
      final response = await dio.getUri<dynamic>(
        Uri.parse(ServerUrl.healthUrl(baseUrl)),
      );
      final body = response.data;
      return response.statusCode == 200 &&
          body is Map &&
          body['status'] == 'ok';
    } on Exception {
      return false;
    } finally {
      dio.close(force: true);
    }
  }

  /// A bare TCP connect, used to skip the 253 addresses that are not listening
  /// before spending an HTTP request on the one that is.
  static Future<bool> tcpPortOpen(
    String host,
    int port,
    Duration timeout,
  ) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } on Exception {
      return false;
    }
  }
}
