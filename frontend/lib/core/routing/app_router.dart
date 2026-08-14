import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  return createAppRouter(auth);
});

GoRouter createAppRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardPage()),
    ],
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (auth.status == AuthStatus.restoring) {
        return location == '/' ? null : '/';
      }
      final onAuthRoute = location == '/login' || location == '/register';
      if (!auth.isAuthenticated) {
        return onAuthRoute ? null : '/login';
      }
      if (location == '/' || onAuthRoute) {
        return '/dashboard';
      }
      return null;
    },
  );
}
