import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';
import 'package:gupmax_ai/features/prompt_chains/prompt_chain_providers.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_project_repository.dart';
import '../../support/fake_prompt_chain_repository.dart';

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester, {
    required FakeProjectRepository projects,
    required FakePromptChainRepository chains,
    Size size = const Size(1200, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthController(
      repository: FakeAuthRepository(),
      expiryBus: SessionExpiryBus(),
      restoreOnCreate: false,
    );
    await auth.login(email: 'teste@example.com', password: 'valid-password');
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const DashboardPage(),
        ),
        GoRoute(
          path: '/projects',
          builder: (_, __) => const Scaffold(body: Text('Todos os projetos')),
        ),
        GoRoute(
          path: '/projects/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Projeto ${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/chains/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Fluxo ${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/prompts/new',
          builder: (_, __) => const Scaffold(body: Text('Planejar projeto')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          projectRepositoryProvider.overrideWithValue(projects),
          promptChainRepositoryProvider.overrideWithValue(chains),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProjectRecord project(String id, DateTime updatedAt) => ProjectRecord(
        id: id,
        name: 'Projeto $id',
        status: ProjectStatus.active,
        promptCount: 0,
        templateCount: 0,
        createdAt: updatedAt,
        updatedAt: updatedAt,
      );

  PromptChainRecord chain({
    required String id,
    String? projectId,
    int steps = 3,
    int completed = 0,
    String? current,
    bool finished = false,
    required DateTime updatedAt,
  }) =>
      PromptChainRecord(
        id: id,
        name: 'Fluxo $id',
        projectId: projectId,
        status: PromptChainStatus.active,
        stepCount: steps,
        completedStepCount: completed,
        currentStepId: current,
        executionCompleted: finished,
        createdAt: updatedAt,
        updatedAt: updatedAt,
      );

  testWidgets('estado vazio orienta a criar o primeiro projeto',
      (tester) async {
    await pumpDashboard(
      tester,
      projects: FakeProjectRepository(),
      chains: FakePromptChainRepository(),
    );
    expect(find.text('Você ainda não criou nenhum projeto.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create_first_project')));
    await tester.pumpAndSettle();
    expect(find.text('Planejar projeto'), findsOneWidget);
  });

  testWidgets('combina projetos e fluxos reais, ordena e limita a quatro',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [
        project('antigo', DateTime.utc(2026, 8, 1)),
        project('sem-chain', DateTime.utc(2026, 8, 6)),
      ];
    final chains = FakePromptChainRepository()
      ..items = [
        chain(
          id: 'concluido',
          steps: 9,
          completed: 9,
          finished: true,
          updatedAt: DateTime.utc(2026, 8, 10),
        ),
        chain(
          id: 'andamento',
          steps: 7,
          completed: 3,
          current: 'step-4',
          updatedAt: DateTime.utc(2026, 8, 9),
        ),
        chain(
          id: 'pendente',
          updatedAt: DateTime.utc(2026, 8, 8),
        ),
      ];
    await pumpDashboard(tester, projects: projects, chains: chains);

    expect(find.byKey(const Key('recent_project_concluido')), findsOneWidget);
    expect(find.byKey(const Key('recent_project_andamento')), findsOneWidget);
    expect(find.byKey(const Key('recent_project_pendente')), findsOneWidget);
    expect(find.byKey(const Key('recent_project_sem-chain')), findsOneWidget);
    expect(find.byKey(const Key('recent_project_antigo')), findsNothing);
    expect(find.text('9 de 9 etapas'), findsOneWidget);
    expect(find.text('3 de 7 etapas'), findsOneWidget);
    expect(find.text('Concluído'), findsOneWidget);
    expect(find.text('Em andamento'), findsOneWidget);
    expect(find.text('Pendente'), findsOneWidget);
  });

  testWidgets('Abrir e Continuar usam a rota correta', (tester) async {
    final projects = FakeProjectRepository()
      ..items = [project('solo', DateTime.utc(2026, 8, 8))];
    final chains = FakePromptChainRepository()
      ..items = [
        chain(
          id: 'execucao',
          completed: 1,
          current: 'step-2',
          updatedAt: DateTime.utc(2026, 8, 9),
        ),
      ];
    await pumpDashboard(tester, projects: projects, chains: chains);
    final continueButton = find.byKey(const Key('open_recent_execucao'));
    await tester.ensureVisible(continueButton);
    expect(
        find.descendant(of: continueButton, matching: find.text('Continuar')),
        findsOneWidget);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('Fluxo execucao'), findsOneWidget);
  });

  testWidgets(
      'projeto sem fluxo abre detalhes e fluxo associado não duplica card',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [
        project('associado', DateTime.utc(2026, 8, 9)),
        project('solo', DateTime.utc(2026, 8, 8)),
      ];
    final chains = FakePromptChainRepository()
      ..items = [
        chain(
          id: 'do-projeto',
          projectId: 'associado',
          updatedAt: DateTime.utc(2026, 8, 10),
        ),
      ];
    await pumpDashboard(tester, projects: projects, chains: chains);
    expect(find.text('Projeto associado'), findsOneWidget);
    expect(find.text('Fluxo do-projeto'), findsNothing);

    final openProject = find.byKey(const Key('open_recent_solo'));
    await tester.ensureVisible(openProject);
    await tester.tap(openProject);
    await tester.pumpAndSettle();
    expect(find.text('Projeto solo'), findsOneWidget);
  });

  testWidgets('dashboard mobile com projeto não produz overflow',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [project('mobile', DateTime.utc(2026, 8, 8))];
    await pumpDashboard(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      size: const Size(390, 844),
    );
    expect(find.byKey(const Key('recent_project_mobile')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
