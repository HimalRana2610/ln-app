import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_storage.dart';
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
    final user = await _repository.restoreSession();
    state =
        user == null ? const AuthUnauthenticated() : AuthAuthenticated(user);
  }

  /// Signs in. Throws [ApiException] so the form can show the message.
  Future<void> login({required String email, required String password}) async {
    final user = await _repository.login(email: email, password: password);
    state = AuthAuthenticated(user);
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

  Future<void> logout() async {
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
