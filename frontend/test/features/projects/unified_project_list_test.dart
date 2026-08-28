import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/presentation/project_list_page.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';
import 'package:gupmax_ai/features/prompt_chains/prompt_chain_providers.dart';

import '../../support/fake_project_repository.dart';
import '../../support/fake_prompt_chain_repository.dart';

void main() {
  Future<void> pumpList(
    WidgetTester tester, {
    required FakeProjectRepository projects,
    required FakePromptChainRepository chains,
    Size size = const Size(1100, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/projects',
      routes: [
        GoRoute(
          path: '/projects',
          builder: (_, __) => const ProjectListPage(),
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
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectRepositoryProvider.overrideWithValue(projects),
          promptChainRepositoryProvider.overrideWithValue(chains),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProjectRecord project(String id) => ProjectRecord(
        id: id,
        name: 'Projeto $id',
        status: ProjectStatus.active,
        promptCount: 0,
        templateCount: 0,
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
      );

  PromptChainRecord chain({
    required String id,
    String? projectId,
    int completed = 0,
    bool finished = false,
    String? current,
  }) =>
      PromptChainRecord(
        id: id,
        name: 'Fluxo $id',
        projectId: projectId,
        status: PromptChainStatus.active,
        stepCount: 3,
        completedStepCount: completed,
        executionCompleted: finished,
        currentStepId: current,
        createdAt: DateTime.utc(2026, 8, 21),
        updatedAt: DateTime.utc(2026, 8, 21),
      );

  testWidgets('lista completa mostra Chain sem Project e navega para o fluxo',
      (tester) async {
    final chains = FakePromptChainRepository()..items = [chain(id: 'planner')];
    await pumpList(
      tester,
      projects: FakeProjectRepository(),
      chains: chains,
    );
    expect(find.byKey(const Key('projects_empty')), findsNothing);
    expect(find.text('Fluxo planner'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open_project_planner')));
    await tester.pumpAndSettle();
    expect(find.text('Fluxo planner'), findsOneWidget);
  });

  testWidgets('Project e Chain associados aparecem uma vez com progresso',
      (tester) async {
    final projects = FakeProjectRepository()..items = [project('delivery')];
    final chains = FakePromptChainRepository()
      ..items = [
        chain(
          id: 'delivery-chain',
          projectId: 'delivery',
          completed: 1,
          current: 'step-4',
        ),
      ];
    await pumpList(tester, projects: projects, chains: chains);
    expect(find.text('Projeto delivery'), findsOneWidget);
    expect(find.text('Fluxo delivery-chain'), findsNothing);
    expect(find.text('1 de 3 etapas'), findsOneWidget);
    expect(find.text('Em andamento'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('lista distingue Chain concluída e em andamento', (tester) async {
    final chains = FakePromptChainRepository()
      ..items = [
        chain(id: 'concluida', completed: 3, finished: true),
        chain(id: 'andamento', completed: 1, current: 'step-2'),
      ];
    await pumpList(
      tester,
      projects: FakeProjectRepository(),
      chains: chains,
    );
    expect(find.text('Concluído'), findsOneWidget);
    expect(find.text('Em andamento'), findsOneWidget);
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('Project sem Chain abre detalhes do Project', (tester) async {
    await pumpList(
      tester,
      projects: FakeProjectRepository()..items = [project('solo')],
      chains: FakePromptChainRepository(),
    );
    await tester.tap(find.byKey(const Key('open_project_solo')));
    await tester.pumpAndSettle();
    expect(find.text('Projeto solo'), findsOneWidget);
  });

  testWidgets('estado vazio é real e layout mobile não apresenta overflow',
      (tester) async {
    await pumpList(
      tester,
      projects: FakeProjectRepository(),
      chains: FakePromptChainRepository(),
      size: const Size(390, 844),
    );
    expect(find.byKey(const Key('projects_empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
