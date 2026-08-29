import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/account/presentation/account_page.dart';
import '../../features/commerce/presentation/commerce_page.dart';
import '../../features/commerce/presentation/payment_return_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/expert_planner/presentation/expert_planner_page.dart';
import '../../features/interviews/presentation/interview_page.dart';
import '../../features/payments_history/presentation/payment_detail_page.dart';
import '../../features/payments_history/presentation/payment_history_page.dart';
import '../../features/prompts/domain/prompt_models.dart';
import '../../features/prompts/presentation/prompt_create_page.dart';
import '../../features/prompts/presentation/prompt_compare_page.dart';
import '../../features/prompts/presentation/prompt_detail_page.dart';
import '../../features/prompts/presentation/prompt_list_page.dart';
import '../../features/projects/presentation/project_detail_page.dart';
import '../../features/projects/presentation/project_list_page.dart';
import '../../features/prompt_chains/presentation/prompt_chain_detail_page.dart';
import '../../features/prompt_chains/presentation/prompt_chain_list_page.dart';
import '../../features/templates/presentation/template_list_page.dart';
import '../../features/usage/presentation/usage_page.dart';
import '../widgets/app_shell.dart';

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
      ShellRoute(
        builder: (_, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
              path: '/dashboard', builder: (_, __) => const DashboardPage()),
          GoRoute(path: '/account', builder: (_, __) => const AccountPage()),
          GoRoute(path: '/prompts', builder: (_, __) => const PromptListPage()),
          GoRoute(
            path: '/prompts/new',
            builder: (_, state) => PromptCreatePage(
              templateId: state.uri.queryParameters['template'],
              projectId: state.uri.queryParameters['project'],
              chainId: state.uri.queryParameters['chain'],
              chainStepId: state.uri.queryParameters['step'],
              initialMode: state.uri.queryParameters['mode'] == 'expert'
                  ? PromptMode.expert
                  : PromptMode.basic,
              initialMultiTarget:
                  state.uri.queryParameters['compare'] == 'true',
            ),
          ),
          GoRoute(
              path: '/chains', builder: (_, __) => const PromptChainListPage()),
          GoRoute(
            path: '/expert-planner',
            builder: (_, state) => ExpertPlannerPage(
              input: state.extra is PromptGenerateInput
                  ? state.extra! as PromptGenerateInput
                  : null,
            ),
          ),
          GoRoute(
              path: '/chains/:id',
              builder: (_, state) =>
                  PromptChainDetailPage(chainId: state.pathParameters['id']!)),
          GoRoute(
              path: '/projects', builder: (_, __) => const ProjectListPage()),
          GoRoute(
              path: '/projects/:id',
              builder: (_, state) =>
                  ProjectDetailPage(projectId: state.pathParameters['id']!)),
          GoRoute(
              path: '/templates', builder: (_, __) => const TemplateListPage()),
          GoRoute(
            path: '/interviews/:id',
            builder: (_, state) =>
                InterviewPage(interviewId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/prompts/compare',
            builder: (_, __) => const PromptComparePage(),
          ),
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
          GoRoute(
            path: '/payments',
            builder: (_, __) => const PaymentHistoryPage(),
          ),
          GoRoute(
            path: '/payments/:id',
            builder: (_, state) =>
                PaymentDetailPage(paymentId: state.pathParameters['id']!),
          ),
        ],
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
