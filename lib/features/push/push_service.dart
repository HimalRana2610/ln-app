import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/storage/local_store.dart';
import '../auth/application/auth_controller.dart';
import 'firebase_push_service.dart';
import 'push_repository.dart';

/// What the app needs from a push provider, and nothing more.
///
/// Firebase sits behind this so the app still builds, runs and tests without
/// a Firebase project: [NoopPushService] stands in whenever initialisation
/// fails, which is always the case until `google-services.json` is added.
abstract class PushService {
  bool get isAvailable;

  /// Asks the OS to show notifications (Android 13+, iOS). True if allowed.
  Future<bool> requestPermission();

  Future<String?> getToken();

  Stream<String> get onTokenRefresh;

  /// The `data` of each notification the person taps, including the one that
  /// launched the app.
  Stream<Map<String, dynamic>> get onOpened;
}

class NoopPushService implements PushService {
  const NoopPushService();

  @override
  bool get isAvailable => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get onOpened => const Stream.empty();
}

/// Firebase if it initialises, otherwise the no-op service.
Future<PushService> createPushService() async {
  try {
    return await FirebasePushService.initialize();
  } on Object catch (error) {
    // No google-services.json, no Play services, or a misconfigured project.
    // None of these should stop the app; they only turn push off.
    debugPrint('Push notifications disabled: $error');
    return const NoopPushService();
  }
}

/// Overridden in `main` with whatever [createPushService] produced.
final pushServiceProvider =
    Provider<PushService>((ref) => const NoopPushService());

final pushRepositoryProvider = Provider<PushRepository>((ref) {
  return PushRepository(apiClient: ref.watch(apiClientProvider));
});

final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  final registrar = PushRegistrar(
    service: ref.watch(pushServiceProvider),
    repository: ref.watch(pushRepositoryProvider),
    store: ref.watch(localStoreProvider),
  );
  ref.onDispose(registrar.dispose);
  return registrar;
});

/// Keeps this device's push token registered with the backend while signed in.
class PushRegistrar {
  PushRegistrar({
    required PushService service,
    required PushRepository repository,
    required LocalStore store,
  })  : _service = service,
        _repository = repository,
        _store = store;

  static const enabledKey = 'push_enabled';

  final PushService _service;
  final PushRepository _repository;
  final LocalStore _store;

  StreamSubscription<String>? _refreshSubscription;
  String? _registeredToken;

  bool get isAvailable => _service.isAvailable;

  /// On unless the person switched it off in Settings.
  Future<bool> isEnabled() async => await _store.read(enabledKey) != false;

  /// Called after sign-in and on a restored session. Best-effort throughout:
  /// failing to register must never get in the way of using the app.
  Future<void> onSignedIn() async {
    if (!_service.isAvailable || !await isEnabled()) return;

    try {
      // Android 13+ shows the POST_NOTIFICATIONS prompt here, once.
      await _service.requestPermission();
      final token = await _service.getToken();
      if (token != null) await _register(token);

      _refreshSubscription ??= _service.onTokenRefresh.listen(
        (token) => _register(token).catchError((Object _) {}),
      );
    } on Object catch (error) {
      debugPrint('Push registration failed: $error');
    }
  }

  /// Called before sign-out clears tokens — the removal call needs them.
  Future<void> onSigningOut() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;

    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;

    try {
      await _repository.removeToken(token);
    } on Object {
      // The backend prunes tokens FCM rejects, so a missed removal heals.
    }
  }

  /// After the account is deleted the server has dropped the token already.
  Future<void> forget() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    _registeredToken = null;
  }

  /// The Settings toggle. Returns whether push ended up on.
  Future<bool> setEnabled(bool enabled) async {
    await _store.write(enabledKey, enabled);
    if (enabled) {
      await onSignedIn();
      return _registeredToken != null;
    }
    await onSigningOut();
    return false;
  }

  Future<void> _register(String token) async {
    await _repository.registerToken(token, platform: _platform);
    _registeredToken = token;
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  void dispose() {
    _refreshSubscription?.cancel();
  }
}

/// Opens the classroom named in a tapped notification's `classroom_id`.
///
/// A tap that launched the app arrives before the session is restored, so the
/// destination is held until the person is signed in.
final pushNavigationProvider = Provider<void>((ref) {
  String? pending;

  void flush() {
    final classroomId = pending;
    if (classroomId == null) return;
    if (ref.read(authControllerProvider) is! AuthAuthenticated) return;
    pending = null;
    ref.read(routerProvider).push('${Routes.classroom}/$classroomId');
  }

  final subscription = ref.watch(pushServiceProvider).onOpened.listen((data) {
    final classroomId = data['classroom_id'];
    if (classroomId is! String || classroomId.isEmpty) return;
    pending = classroomId;
    flush();
  });

  ref.listen<AuthState>(authControllerProvider, (_, __) => flush());
  ref.onDispose(subscription.cancel);
});
