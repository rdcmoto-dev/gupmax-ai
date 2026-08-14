import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/commerce/presentation/commerce_page.dart';
import '../../features/commerce/presentation/payment_return_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/prompts/presentation/prompt_create_page.dart';
import '../../features/prompts/presentation/prompt_detail_page.dart';
import '../../features/prompts/presentation/prompt_list_page.dart';
import '../../features/usage/presentation/usage_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider.notifier);
  return createAppRouter(auth);
});

GoRouter createAppRouter(AuthController auth, {String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: auth,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardPage()),
      GoRoute(path: '/prompts', builder: (_, __) => const PromptListPage()),
      GoRoute(
          path: '/prompts/new', builder: (_, __) => const PromptCreatePage()),
      GoRoute(
        path: '/prompts/:id',
        builder: (_, state) =>
            PromptDetailPage(promptId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/usage', builder: (_, __) => const UsagePage()),
      GoRoute(path: '/credits', builder: (_, __) => const CommercePage()),
      GoRoute(
        path: '/payments/success',
        builder: (_, __) => const PaymentReturnPage(canceled: false),
      ),
      GoRoute(
        path: '/payments/cancel',
        builder: (_, __) => const PaymentReturnPage(canceled: true),
      ),
    ],
    redirect: (context, state) {
      final location = state.matchedLocation;
      final restoredLocation = state.uri.queryParameters['redirect'];
      String? decision(String? target) {
        if (kDebugMode) {
          debugPrint(
            '[router] uri=${state.uri} requested=$location '
            'auth=${auth.status.name} target=${target ?? 'stay'}',
          );
        }
        return target;
      }

      if (auth.status == AuthStatus.restoring) {
        if (location == '/') return decision(null);
        return decision(Uri(
          path: '/',
          queryParameters: {'redirect': state.uri.toString()},
        ).toString());
      }
      final onAuthRoute = location == '/login' || location == '/register';
      if (!auth.isAuthenticated) {
        if (onAuthRoute) return decision(null);
        final destination = _internalLocation(restoredLocation)
            ? restoredLocation!
            : state.uri.toString();
        return decision(Uri(
          path: '/login',
          queryParameters: {'redirect': destination},
        ).toString());
      }
      if ((location == '/' || onAuthRoute) &&
          _internalLocation(restoredLocation)) {
        return decision(restoredLocation);
      }
      if (location == '/' || onAuthRoute) {
        return decision('/dashboard');
      }
      return decision(null);
    },
  );
}

bool _internalLocation(String? value) {
  if (value == null || value.startsWith('//')) return false;
  final uri = Uri.tryParse(value);
  return uri != null && !uri.hasAuthority && uri.path.startsWith('/');
}
