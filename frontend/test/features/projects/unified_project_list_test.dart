import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/presentation/project_list_page.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/projects/project_tags.dart';
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
          projectTagsProvider.overrideWith((ref) async => []),
          projectRepositoryProvider.overrideWithValue(projects),
          promptChainRepositoryProvider.overrideWithValue(chains),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProjectRecord project(
    String id, {
    String? name,
    String? context,
    ProjectStatus status = ProjectStatus.active,
    bool isPinned = false,
    int day = 20,
  }) =>
      ProjectRecord(
        id: id,
        name: name ?? 'Projeto $id',
        context: context,
        status: status,
        promptCount: 0,
        templateCount: 0,
        isPinned: isPinned,
        createdAt: DateTime.utc(2026, 8, day),
        updatedAt: DateTime.utc(2026, 8, day),
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
    await pumpList(
      tester,
      projects: projects,
      chains: chains,
    );
    expect(find.text('Projeto delivery'), findsOneWidget);
    expect(find.text('Fluxo delivery-chain'), findsNothing);
    expect(find.text('1 de 3 etapas'), findsOneWidget);
    expect(find.text('Em andamento'), findsNWidgets(2));
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
    expect(find.text('Em andamento'), findsNWidgets(2));
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

  testWidgets('busca filtro e ordenação combinam e preservam ações dos cards',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [
        project('pizzaria-old', name: 'Pizzaria Antiga', day: 20),
        project('pizzaria-new', name: 'Pizzaria Nova', day: 22),
        project('encerrado',
            name: 'Pizzaria Encerrada',
            context: 'Projeto encerrado: sim',
            day: 23),
        project('arquivado',
            name: 'Pizzaria Arquivada',
            status: ProjectStatus.archived,
            day: 24),
      ];
    final chains = FakePromptChainRepository()
      ..items = [
        chain(id: 'old-chain', projectId: 'pizzaria-old', current: 'step-1'),
        chain(id: 'new-chain', projectId: 'pizzaria-new', current: 'step-1'),
      ];
    await pumpList(
      tester,
      projects: projects,
      chains: chains,
      size: const Size(700, 900),
    );

    await tester.enterText(
        find.byKey(const Key('project_search')), '  PIZZARIA   ');
    await tester.tap(find.byKey(const Key('project_filter_inProgress')));
    await tester.pumpAndSettle();
    expect(find.text('Pizzaria Antiga'), findsOneWidget);
    expect(find.text('Pizzaria Nova'), findsOneWidget);
    expect(find.text('Pizzaria Encerrada'), findsNothing);
    expect(find.text('Pizzaria Arquivada'), findsNothing);

    await tester.tap(find.byKey(const Key('project_order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nome A–Z').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('project_pizzaria-old'))).dy,
      lessThan(
          tester.getTopLeft(find.byKey(const Key('project_pizzaria-new'))).dy),
    );
    expect(find.text('Continuar'), findsNWidgets(2));
    expect(find.text('Editar'), findsNWidgets(2));
    expect(find.text('Arquivar'), findsNWidgets(2));
  });

  testWidgets('nenhum resultado e controles não apresentam overflow no mobile',
      (tester) async {
    await pumpList(
      tester,
      projects: FakeProjectRepository()
        ..items = [project('mobile', name: 'Projeto Mobile')],
      chains: FakePromptChainRepository(),
      size: const Size(390, 844),
    );
    expect(find.byKey(const Key('project_search')), findsOneWidget);
    expect(find.byKey(const Key('project_order')), findsOneWidget);
    expect(find.text('Arquivados'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('project_search')), 'não existe');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects_no_results')), findsOneWidget);
    expect(find.text('Nenhum projeto encontrado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorita e desfavorita no desktop sem abrir o projeto',
      (tester) async {
    final projects = FakeProjectRepository()..items = [project('favorite')];
    await pumpList(tester,
        projects: projects, chains: FakePromptChainRepository());
    final star = find.byKey(const Key('favorite_favorite'));
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(projects.items.single.isFavorite, isTrue);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byKey(const Key('project_search')), findsOneWidget);
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(projects.items.single.isFavorite, isFalse);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(projects.favoriteCalls, 2);
    expect(projects.updateCalls, 0);
  });

  testWidgets('fixados criam atalho independente da lista e podem desafixar',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [
        project('pin-1', isPinned: true),
        project('pin-2', isPinned: true),
        project('regular'),
      ];
    await pumpList(tester,
        projects: projects, chains: FakePromptChainRepository(), size: const Size(390, 844));
    expect(find.text('Projetos fixados'), findsOneWidget);
    expect(find.byKey(const Key('open_pinned_pin-1')), findsOneWidget);
    expect(find.byKey(const Key('unpin_pinned_pin-2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('unpin_pinned_pin-2')));
    await tester.pumpAndSettle();
    expect(projects.pinCalls, 1);
    expect(find.byKey(const Key('project_pin-2')), findsOneWidget);
    expect(find.byKey(const Key('project_blueprints')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limite de pins restaura o card e mostra mensagem espec?fica',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [project('fourth')]
      ..pinError = const AppException(
        'Você pode fixar até 3 projetos. Desafixe um projeto para continuar.',
        code: 'project_pin_limit_reached',
        statusCode: 409,
      );
    await pumpList(tester, projects: projects, chains: FakePromptChainRepository());
    final pin = find.byKey(const Key('pin_fourth'));
    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(projects.pinCalls, 1);
    expect(projects.items.single.isPinned, isFalse);
    expect(find.text('Você pode fixar até 3 projetos. Desafixe um projeto para continuar.'), findsOneWidget);
    expect(find.textContaining('?'), findsNothing);
  });

  testWidgets('erro gen?rico de pin restaura o card e permite retry', (tester) async {
    final projects = FakeProjectRepository()
      ..items = [project('offline')]
      ..pinError = const AppException('offline');
    await pumpList(tester, projects: projects, chains: FakePromptChainRepository());
    await tester.tap(find.byKey(const Key('pin_offline')));
    await tester.pumpAndSettle();
    expect(projects.items.single.isPinned, isFalse);
    expect(find.text('Não foi possível atualizar o projeto fixado. Tente novamente.'), findsOneWidget);
    projects.pinError = null;
    await tester.tap(find.byKey(const Key('pin_offline')));
    await tester.pumpAndSettle();
    expect(projects.items.single.isPinned, isTrue);
  });

  testWidgets('sem fixados nÃ£o exibe a seÃ§Ã£o vazia', (tester) async {
    await pumpList(tester,
        projects: FakeProjectRepository()..items = [project('normal')],
        chains: FakePromptChainRepository());
    expect(find.text('Projetos fixados'), findsNothing);
    expect(find.byKey(const Key('pin_normal')), findsOneWidget);
  });

  testWidgets('favorito bloqueia double submit e permite retry após erro',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [project('favorite')]
      ..favoriteCompleter = Completer<void>();
    await pumpList(tester,
        projects: projects, chains: FakePromptChainRepository());
    final star = find.byKey(const Key('favorite_favorite'));
    final callback = tester.widget<IconButton>(star).onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(projects.favoriteCalls, 1);
    expect(tester.widget<IconButton>(star).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    projects.favoriteError = Exception('offline');
    projects.favoriteCompleter!.complete();
    await tester.pumpAndSettle();
    expect(projects.items.single.isFavorite, isFalse);
    expect(find.text('Não foi possível atualizar o favorito. Tente novamente.'),
        findsOneWidget);
    projects.favoriteError = null;
    projects.favoriteCompleter = null;
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(projects.items.single.isFavorite, isTrue);
  });

  testWidgets('Favoritos no mobile combina busca e fica vazio ao desfavoritar',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [
        projectSample(
            id: 'fav',
            name:
                'Projeto importante com nome longo para validar quebra de linha no mobile',
            isFavorite: true),
        projectSample(id: 'normal', name: 'Projeto normal'),
      ];
    await pumpList(tester,
        projects: projects,
        chains: FakePromptChainRepository()..items = [chain(id: 'independent')],
        size: const Size(390, 844));
    expect(find.byKey(const Key('favorite_independent')), findsNothing);
    expect(find.text(projects.items.first.name), findsOneWidget);
    expect(
        find.byKey(const Key('create_project')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    final filter = find.byKey(const Key('project_filter_favorites'));
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('Projeto normal'), findsNothing);
    expect(find.byKey(const Key('favorite_fav')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('project_search')), '  IMPORTANTE  ');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('favorite_fav')), findsOneWidget);
    await tester.tap(find.byKey(const Key('favorite_fav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects_no_results')), findsOneWidget);
    expect(
        find.byKey(const Key('create_project')).hitTestable(), findsOneWidget);
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
