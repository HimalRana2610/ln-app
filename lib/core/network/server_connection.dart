import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/server_url.dart';
import 'server_locator.dart';
import 'server_storage.dart';

/// Where the search for the backend has got to.
enum ServerPhase {
  /// Nothing has been tried yet; the address is only a guess.
  unknown,

  /// A search is running.
  locating,

  /// The backend answered at this address.
  connected,

  /// Nothing on this network is serving the backend.
  unreachable,
}

/// The address the app is using, and how much confidence there is in it.
@immutable
class ServerStatus {
  const ServerStatus({required this.baseUrl, required this.phase});

  final String baseUrl;
  final ServerPhase phase;

  /// Host and port, for showing a person.
  String get label => ServerUrl.display(baseUrl);

  /// True while pointed at a backend on this network, where searching for a
  /// moved address makes sense.
  bool get isLocal => AppConfig.isLocal(baseUrl);

  @override
  bool operator ==(Object other) =>
      other is ServerStatus && other.baseUrl == baseUrl && other.phase == phase;

  @override
  int get hashCode => Object.hash(baseUrl, phase);

  @override
  String toString() => 'ServerStatus($baseUrl, $phase)';
}

/// Owns the address the app talks to.
///
/// Hand-written rather than a Riverpod notifier so that [ApiClient] can depend
/// on it directly. The dependency runs one way — the client asks this where to
/// send, and this knows nothing about the client — which keeps a moved server
/// from rebuilding providers and discarding screen state mid-request.
class ServerConnection {
  ServerConnection({ServerLocator? locator, String? initialBaseUrl})
      : _locator = locator ?? ServerLocator(),
        status = ValueNotifier(
          ServerStatus(
            baseUrl: initialBaseUrl ?? AppConfig.fallbackApiBaseUrl,
            phase: ServerPhase.unknown,
          ),
        );

  final ServerLocator _locator;

  /// Listenable so the splash and login screens can say what is happening
  /// without a provider rebuild on every phase change.
  final ValueNotifier<ServerStatus> status;

  Future<bool>? _inFlight;

  String get baseUrl => status.value.baseUrl;

  /// Host and port, for showing a person.
  String get label => status.value.label;

  /// Finds the server if it has not been found yet. Cheap to call repeatedly.
  Future<bool> ensureLocated() {
    if (status.value.phase == ServerPhase.connected) return Future.value(true);
    return _locate(ignoreSaved: false);
  }

  /// Searches again after a failure, skipping the remembered address.
  ///
  /// That address is the most likely one to have just gone stale, and
  /// re-testing it first would add a timeout to every recovery.
  Future<bool> relocate() => _locate(ignoreSaved: true);

  /// Points the app at [input] after checking something is really there.
  ///
  /// Returns null on success, or a message to show the person.
  Future<String?> useServer(String input) async {
    final normalized = ServerUrl.normalize(input);
    if (normalized == null) {
      return 'That does not look like a server address.';
    }

    _set(phase: ServerPhase.locating);

    if (!await _locator.check(normalized)) {
      _set(phase: ServerPhase.unreachable);
      return 'Nothing answered at ${ServerUrl.display(normalized)}. '
          'Check the backend is running and the phone is on the same network.';
    }

    await _locator.remember(normalized);
    _set(baseUrl: normalized, phase: ServerPhase.connected);
    return null;
  }

  void dispose() => status.dispose();

  Future<bool> _locate({required bool ignoreSaved}) {
    // When an address goes stale every in-flight request fails at once. They
    // share one search rather than each starting their own, which would
    // otherwise mean several concurrent sweeps of the network.
    return _inFlight ??= _runLocate(ignoreSaved: ignoreSaved).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<bool> _runLocate({required bool ignoreSaved}) async {
    _set(phase: ServerPhase.locating);

    final found = await _locator.discover(ignoreSaved: ignoreSaved);
    if (found == null) {
      _set(phase: ServerPhase.unreachable);
      return false;
    }

    _set(baseUrl: found, phase: ServerPhase.connected);
    return true;
  }

  void _set({String? baseUrl, required ServerPhase phase}) {
    status.value = ServerStatus(
      baseUrl: baseUrl ?? status.value.baseUrl,
      phase: phase,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final serverStorageProvider = Provider<ServerStorage>((ref) => ServerStorage());

final serverLocatorProvider = Provider<ServerLocator>(
  (ref) => ServerLocator(storage: ref.watch(serverStorageProvider)),
);

final serverConnectionProvider = Provider<ServerConnection>((ref) {
  final connection =
      ServerConnection(locator: ref.watch(serverLocatorProvider));
  ref.onDispose(connection.dispose);
  return connection;
});
