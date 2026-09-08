import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/classroom/presentation/classroom_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/note/presentation/note_detail_screen.dart';
import '../../features/splash/splash_screen.dart';

/// Routing, with auth enforced by a single [GoRouter.redirect].
///
/// Gating in one redirect rather than per-screen means there is no window where
/// a protected screen builds before deciding to bounce, and no chance of adding
/// a screen and forgetting its guard.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    // Re-runs `redirect` whenever auth state changes.
    refreshListenable: refreshNotifier,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: Routes.register, builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: Routes.dashboard, builder: (_, __) => const DashboardScreen()),
      GoRoute(
        path: '${Routes.classroom}/:classroomId',
        builder: (_, state) => ClassroomScreen(
          classroomId: state.pathParameters['classroomId']!,
        ),
      ),
      GoRoute(
        path: '${Routes.note}/:noteId',
        builder: (_, state) => NoteDetailScreen(
          noteId: state.pathParameters['noteId']!,
        ),
      ),
    ],
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // Still checking secure storage: hold on the splash screen.
      if (authState is AuthUnknown) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final isSignedIn = authState is AuthAuthenticated;
      final isOnAuthScreen =
          location == Routes.login || location == Routes.register;

      if (!isSignedIn) {
        return isOnAuthScreen ? null : Routes.login;
      }

      // Signed in: keep them out of the splash and auth screens. Classroom and
      // note routes are ordinary signed-in destinations and pass through.
      if (isOnAuthScreen || location == Routes.splash) {
        return Routes.dashboard;
      }

      return null;
    },
  );
});

abstract final class Routes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const dashboard = '/dashboard';
  static const classroom = '/classroom';
  static const note = '/notes';
}

/// Bridges Riverpod state changes to GoRouter's [Listenable]-based refresh.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscription = ref.listen<AuthState>(
      authControllerProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
