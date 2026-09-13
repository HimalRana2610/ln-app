import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/core/network/server_connection.dart';
import 'package:ln_app/core/network/server_locator.dart';

/// A locator that answers from a script instead of the network, and counts
/// what it was asked, so sharing of an in-flight search can be asserted.
class FakeLocator extends ServerLocator {
  FakeLocator({this.found, this.reachable = const {}});

  /// What [discover] resolves to. Null means "nothing on this network".
  String? found;

  /// The addresses [check] accepts.
  Set<String> reachable;

  int discoverCalls = 0;
  int ignoreSavedCalls = 0;
  String? remembered;

  /// Completed by the test to hold a search open.
  Completer<void>? gate;

  @override
  Future<String?> discover({bool ignoreSaved = false}) async {
    discoverCalls++;
    if (ignoreSaved) ignoreSavedCalls++;
    if (gate != null) await gate!.future;
    return found;
  }

  @override
  Future<bool> check(String baseUrl, {Duration? timeout}) async =>
      reachable.contains(baseUrl);

  @override
  Future<String> remember(String baseUrl) async => remembered = baseUrl;
}

void main() {
  group('ensureLocated', () {
    test('adopts the address that was found', () async {
      final connection = ServerConnection(
        locator: FakeLocator(found: 'http://192.168.1.3:8000/api/v1'),
      );
      addTearDown(connection.dispose);

      expect(await connection.ensureLocated(), isTrue);
      expect(connection.baseUrl, 'http://192.168.1.3:8000/api/v1');
      expect(connection.status.value.phase, ServerPhase.connected);
      expect(connection.label, '192.168.1.3:8000');
    });

    test('reports unreachable and keeps the previous address', () async {
      final connection = ServerConnection(
        locator: FakeLocator(),
        initialBaseUrl: 'http://10.0.2.2:8000/api/v1',
      );
      addTearDown(connection.dispose);

      expect(await connection.ensureLocated(), isFalse);
      expect(connection.status.value.phase, ServerPhase.unreachable);
      expect(connection.baseUrl, 'http://10.0.2.2:8000/api/v1');
    });

    test('does not search again once connected', () async {
      final locator = FakeLocator(found: 'http://192.168.1.3:8000/api/v1');
      final connection = ServerConnection(locator: locator);
      addTearDown(connection.dispose);

      await connection.ensureLocated();
      await connection.ensureLocated();

      expect(locator.discoverCalls, 1);
    });

    test('concurrent callers share one search', () async {
      // Every in-flight request fails at once when an address goes stale. If
      // each started its own search, one stale address would mean several
      // concurrent sweeps of the network.
      final locator = FakeLocator(found: 'http://192.168.1.3:8000/api/v1')
        ..gate = Completer<void>();
      final connection = ServerConnection(locator: locator);
      addTearDown(connection.dispose);

      final searches = Future.wait([
        connection.ensureLocated(),
        connection.ensureLocated(),
        connection.ensureLocated(),
      ]);
      locator.gate!.complete();

      expect(await searches, [isTrue, isTrue, isTrue]);
      expect(locator.discoverCalls, 1);
    });

    test('a failed search can be retried', () async {
      final locator = FakeLocator();
      final connection = ServerConnection(locator: locator);
      addTearDown(connection.dispose);

      expect(await connection.ensureLocated(), isFalse);

      locator.found = 'http://192.168.1.3:8000/api/v1';
      expect(await connection.ensureLocated(), isTrue);
      expect(locator.discoverCalls, 2);
    });
  });

  group('relocate', () {
    test('skips the remembered address', () async {
      final locator = FakeLocator(found: 'http://192.168.1.3:8000/api/v1');
      final connection = ServerConnection(locator: locator);
      addTearDown(connection.dispose);

      await connection.relocate();

      expect(locator.ignoreSavedCalls, 1);
    });
  });

  group('useServer', () {
    test('accepts a reachable address and remembers it', () async {
      final locator =
          FakeLocator(reachable: {'http://192.168.1.3:8000/api/v1'});
      final connection = ServerConnection(locator: locator);
      addTearDown(connection.dispose);

      expect(await connection.useServer('192.168.1.3'), isNull);
      expect(connection.baseUrl, 'http://192.168.1.3:8000/api/v1');
      expect(locator.remembered, 'http://192.168.1.3:8000/api/v1');
      expect(connection.status.value.phase, ServerPhase.connected);
    });

    test('rejects an address nothing answers at', () async {
      final connection = ServerConnection(locator: FakeLocator());
      addTearDown(connection.dispose);

      expect(
          await connection.useServer('192.168.1.99'), contains('192.168.1.99'));
      expect(connection.status.value.phase, ServerPhase.unreachable);
    });

    test('rejects text that is not an address', () async {
      final connection = ServerConnection(locator: FakeLocator());
      addTearDown(connection.dispose);

      expect(await connection.useServer('nonsense://x'), isNotNull);
      expect(await connection.useServer(''), isNotNull);
    });
  });
}
