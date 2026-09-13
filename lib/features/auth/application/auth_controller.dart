import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/server_connection.dart';
import '../../../core/network/token_storage.dart';
import '../../push/push_service.dart';
import '../data/auth_repository.dart';
import '../data/models.dart';

/// What the rest of the app knows about the session.
///
/// [unknown] is a distinct state from [unauthenticated] on purpose: at cold
/// start we have not yet checked storage, and treating "not yet known" as
/// "signed out" would bounce a returning user to the login screen for a frame.
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.message});

  /// Set when a session ended unexpectedly, so the login screen can explain why.
  final String? message;
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final User user;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    // Where to send is decided per request, so a backend that changes address
    // is followed without rebuilding this provider and everything under it.
    server: ref.watch(serverConnectionProvider),
    // When a refresh fails, the interceptor calls this and the whole app
    // reacts - the router redirect sends the user to /login.
    onSessionExpired: () async {
      ref.read(authControllerProvider.notifier).handleSessionExpired();
    },
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  );
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Owns the session. The router watches this to decide what to show.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Kick off restore without blocking the first frame; the splash route
    // renders while state is AuthUnknown.
    Future.microtask(restoreSession);
    return const AuthUnknown();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<void> restoreSession() async {
    // Find the backend before the first request rather than as a side effect of
    // it, so the login screen can show which server it is about to talk to and
    // signing in is not delayed by the search.
    await ref.read(serverConnectionProvider).ensureLocated();

    try {
      final user = await _repository.restoreSession();
      state =
          user == null ? const AuthUnauthenticated() : AuthAuthenticated(user);
      if (user != null) _registerPush();
    } on ApiException catch (error) {
      // The server could not be reached. The stored session is still valid, so
      // it is kept — this is a network problem, not a signed-out user.
      state = AuthUnauthenticated(message: error.message);
    }
  }

  /// Signs in. Throws [ApiException] so the form can show the message.
  Future<void> login({required String email, required String password}) async {
    final user = await _repository.login(email: email, password: password);
    state = AuthAuthenticated(user);
    _registerPush();
  }

  /// Not awaited: asking for notification permission and reaching FCM must not
  /// hold up the dashboard.
  void _registerPush() {
    ref.read(pushRegistrarProvider).onSignedIn();
  }

  /// Registers, then signs in with the same credentials.
  Future<void> register({
    required String email,
    required String fullName,
    required String password,
    String? institute,
  }) async {
    await _repository.register(
      email: email,
      fullName: fullName,
      password: password,
      institute: institute,
    );
    await login(email: email, password: password);
  }

  /// Re-reads the profile, e.g. after the email was verified.
  Future<void> refreshUser() async {
    state = AuthAuthenticated(await _repository.currentUser());
  }

  /// Saves profile changes and shows them everywhere at once.
  Future<void> updateProfile({String? fullName, String? institute}) async {
    state = AuthAuthenticated(await _repository.updateProfile(
      fullName: fullName,
      institute: institute,
    ));
  }

  /// Throws [ApiException] (400 `incorrect_password`) on a wrong password, leaving the session as it
  /// was. On success the router redirect takes the person to /login.
  Future<void> deleteAccount({required String password}) async {
    await _repository.deleteAccount(password: password);
    await ref.read(pushRegistrarProvider).forget();
    state = const AuthUnauthenticated(message: 'Your account was deleted.');
  }

  Future<void> logout() async {
    // Before the tokens go: removing the push token is an authenticated call.
    await ref.read(pushRegistrarProvider).onSigningOut();
    await _repository.logout();
    state = const AuthUnauthenticated();
  }

  /// Called by the interceptor when a refresh fails.
  void handleSessionExpired() {
    state = const AuthUnauthenticated(
      message: 'Your session expired. Please sign in again.',
    );
  }
}
