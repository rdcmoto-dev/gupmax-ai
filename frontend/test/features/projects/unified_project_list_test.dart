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
          path: '/project-workspace/chains/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Central ${state.pathParameters['id']}')),
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
    expect(find.text('Central planner'), findsOneWidget);
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

  testWidgets('Project isolado usa exclusão existente após confirmação',
      (tester) async {
    final projects = FakeProjectRepository()..items = [project('solo')];
    await pumpList(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
    );
    await tester.tap(find.byKey(const Key('remove_project_solo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Projeto solo'), findsWidgets);
    await tester.tap(find.byKey(const Key('confirm_project_remove')));
    await tester.pumpAndSettle();
    expect(projects.deleteCalls, 1);
    expect(projects.items, isEmpty);
  });

  testWidgets('Chain isolada usa exclusão segura e atualiza a lista',
      (tester) async {
    final chains = FakePromptChainRepository()..items = [chain(id: 'planner')];
    await pumpList(
      tester,
      projects: FakeProjectRepository(),
      chains: chains,
    );
    await tester.tap(find.byKey(const Key('remove_project_planner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_project_remove')));
    await tester.pumpAndSettle();
    expect(chains.deleteCalls, 1);
    expect(chains.items, isEmpty);
  });

  testWidgets('Project e Chain associados são arquivados sem cascade delete',
      (tester) async {
    final projects = FakeProjectRepository()..items = [project('delivery')];
    final chains = FakePromptChainRepository()
      ..items = [chain(id: 'flow', projectId: 'delivery')];
    await pumpList(tester, projects: projects, chains: chains);

    await tester.tap(find.byKey(const Key('remove_project_delivery')));
    await tester.pumpAndSettle();
    expect(find.text('Arquivar trabalho?'), findsOneWidget);
    expect(find.textContaining('preservar etapas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_project_remove')));
    await tester.pumpAndSettle();

    expect(projects.deleteCalls, 0);
    expect(chains.deleteCalls, 0);
    expect(projects.items.single.status, ProjectStatus.archived);
    expect(chains.items.single.status, PromptChainStatus.archived);
  });

  testWidgets('cancelar remoção mantém Project e Chain associados',
      (tester) async {
    final projects = FakeProjectRepository()..items = [project('delivery')];
    final chains = FakePromptChainRepository()
      ..items = [chain(id: 'flow', projectId: 'delivery')];
    await pumpList(tester, projects: projects, chains: chains);
    await tester.tap(find.byKey(const Key('remove_project_delivery')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(projects.updateCalls, 0);
    expect(chains.updateCalls, 0);
  });
}
