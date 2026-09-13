import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/core/network/server_locator.dart';
import 'package:ln_app/core/network/server_storage.dart';

/// In-memory stand-in for the platform's secure storage.
class FakeStorage extends ServerStorage {
  FakeStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String baseUrl) async => value = baseUrl;

  @override
  Future<void> clear() async => value = null;
}

/// Builds a locator whose every piece of I/O is answered from these tables,
/// so the search order is asserted without a network.
ServerLocator buildLocator({
  FakeStorage? storage,
  Set<String> answering = const {},
  List<String> deviceAddresses = const [],
  Set<String> openPorts = const {},
  List<String>? probeLog,
}) {
  return ServerLocator(
    storage: storage ?? FakeStorage(),
    probe: (baseUrl, _) async {
      probeLog?.add(baseUrl);
      return answering.contains(baseUrl);
    },
    localAddresses: () async => deviceAddresses,
    isPortOpen: (host, _, __) async => openPorts.contains(host),
  );
}

void main() {
  group('candidates', () {
    test('tries the remembered address first', () async {
      final locator = buildLocator(
        storage: FakeStorage('http://192.168.1.9:8000/api/v1'),
      );

      final candidates = await locator.candidates();

      expect(candidates.first, 'http://192.168.1.9:8000/api/v1');
      // localhost is always worth a try: it is what `adb reverse` provides.
      expect(candidates, contains('http://localhost:8000/api/v1'));
    });

    test('normalizes whatever was stored', () async {
      final locator = buildLocator(storage: FakeStorage('192.168.1.9'));

      expect(
        (await locator.candidates()).first,
        'http://192.168.1.9:8000/api/v1',
      );
    });

    test('omits the remembered address when asked to', () async {
      final locator = buildLocator(
        storage: FakeStorage('http://192.168.1.9:8000/api/v1'),
      );

      expect(
        await locator.candidates(includeSaved: false),
        isNot(contains('http://192.168.1.9:8000/api/v1')),
      );
    });
  });

  group('discover', () {
    test('returns the first candidate that answers, and remembers it',
        () async {
      final storage = FakeStorage('http://192.168.1.9:8000/api/v1');
      final locator = buildLocator(
        storage: storage,
        answering: {'http://192.168.1.9:8000/api/v1'},
      );

      expect(await locator.discover(), 'http://192.168.1.9:8000/api/v1');
      expect(storage.value, 'http://192.168.1.9:8000/api/v1');
    });

    test('skips the remembered address when it is the stale one', () async {
      final probes = <String>[];
      final locator = buildLocator(
        storage: FakeStorage('http://192.168.1.9:8000/api/v1'),
        answering: {'http://192.168.1.3:8000/api/v1'},
        deviceAddresses: ['192.168.1.42'],
        openPorts: {'192.168.1.3'},
        probeLog: probes,
      );

      expect(
        await locator.discover(ignoreSaved: true),
        'http://192.168.1.3:8000/api/v1',
      );
      expect(probes, isNot(contains('http://192.168.1.9:8000/api/v1')));
    });

    test('sweeps the subnet when no known address answers', () async {
      final storage = FakeStorage();
      final locator = buildLocator(
        storage: storage,
        answering: {'http://192.168.1.3:8000/api/v1'},
        deviceAddresses: ['192.168.1.42'],
        openPorts: {'192.168.1.3'},
      );

      expect(await locator.discover(), 'http://192.168.1.3:8000/api/v1');
      expect(storage.value, 'http://192.168.1.3:8000/api/v1');
    });

    test('ignores a device that has the port open but is not the backend',
        () async {
      // A router admin page or a printer on port 8000 must not be adopted as
      // the server; only a correct /health answer counts.
      final locator = buildLocator(
        deviceAddresses: ['192.168.1.42'],
        openPorts: {'192.168.1.7'},
      );

      expect(await locator.discover(), isNull);
    });

    test('returns null when nothing on the network is serving', () async {
      final locator = buildLocator(deviceAddresses: ['192.168.1.42']);

      expect(await locator.discover(), isNull);
    });
  });

  group('subnetHosts', () {
    test('covers the /24 and excludes the device itself', () {
      final hosts = ServerLocator.subnetHosts('192.168.1.42');

      expect(hosts, hasLength(253));
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
      expect(hosts, isNot(contains('192.168.1.42')));
      expect(hosts, isNot(contains('192.168.1.0')));
      expect(hosts, isNot(contains('192.168.1.255')));
    });

    test('returns nothing for an address it cannot parse', () {
      expect(ServerLocator.subnetHosts('not-an-address'), isEmpty);
      expect(ServerLocator.subnetHosts('192.168.1'), isEmpty);
    });
  });

  group('isPrivateIPv4', () {
    test('accepts the RFC 1918 ranges', () {
      expect(ServerLocator.isPrivateIPv4('192.168.1.42'), isTrue);
      expect(ServerLocator.isPrivateIPv4('10.0.0.5'), isTrue);
      expect(ServerLocator.isPrivateIPv4('172.20.10.3'), isTrue);
    });

    test('rejects link-local and public addresses', () {
      // 169.254 is what a disconnected adapter holds; sweeping it would cost a
      // full scan and reach nothing.
      expect(ServerLocator.isPrivateIPv4('169.254.170.168'), isFalse);
      expect(ServerLocator.isPrivateIPv4('172.15.0.1'), isFalse);
      expect(ServerLocator.isPrivateIPv4('8.8.8.8'), isFalse);
      expect(ServerLocator.isPrivateIPv4('not-an-address'), isFalse);
    });
  });
}
