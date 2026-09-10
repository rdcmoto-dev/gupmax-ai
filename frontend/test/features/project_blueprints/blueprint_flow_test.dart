import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/features/project_blueprints/blueprint_dialog.dart';
import 'package:gupmax_ai/features/project_blueprints/blueprint_list_page.dart';
import 'package:gupmax_ai/features/project_blueprints/project_blueprints.dart';
import 'package:gupmax_ai/features/projects/presentation/project_list_page.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/prompt_chains/prompt_chain_providers.dart';

import '../../support/fake_blueprint_repository.dart';
import '../../support/fake_project_repository.dart';
import '../../support/fake_prompt_chain_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester, FakeBlueprintRepository repository,
      {String route = '/project-blueprints',
      Size size = const Size(1100, 900),
      bool settle = true}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(initialLocation: route, routes: [
      GoRoute(
          path: '/project-blueprints',
          builder: (_, __) => const BlueprintListPage()),
      GoRoute(
          path: '/save',
          builder: (_, __) =>
              Scaffold(body: SaveBlueprintButton(project: projectSample()))),
      GoRoute(path: '/projects', builder: (_, __) => const ProjectListPage()),
      GoRoute(
          path: '/projects/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Novo ${state.pathParameters['id']}'))),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      blueprintRepositoryProvider.overrideWithValue(repository),
      projectRepositoryProvider.overrideWithValue(
          FakeProjectRepository()..items = [projectSample()]),
      promptChainRepositoryProvider
          .overrideWithValue(FakePromptChainRepository()),
    ], child: MaterialApp.router(routerConfig: router)));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
      'salvar sugere nome, valida formulário, edita descrição e confirma',
      (tester) async {
    final repository = FakeBlueprintRepository();
    await pump(tester, repository, route: '/save');
    await tester.tap(find.byKey(const Key('save_project_blueprint')));
    await tester.pumpAndSettle();
    expect(find.text('Pizzaria Donatello'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('blueprint_name')), 'x');
    await tester.tap(find.byKey(const Key('confirm_blueprint')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 0);
    await tester.enterText(
        find.byKey(const Key('blueprint_name')), 'Modelo pessoal');
    await tester.enterText(find.byKey(const Key('blueprint_description')),
        'Campanha reutilizável');
    await tester.tap(find.byKey(const Key('confirm_blueprint')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
    expect(repository.sourceId, 'project-1');
    expect(repository.lastValues,
        {'name': 'Modelo pessoal', 'description': 'Campanha reutilizável'});
    expect(find.text('Modelo de projeto salvo.'), findsOneWidget);
  });

  testWidgets('salvar bloqueia double submit e permite retry após erro API',
      (tester) async {
    final repository = FakeBlueprintRepository()..mutation = Completer<void>();
    await pump(tester, repository, route: '/save');
    await tester.tap(find.byKey(const Key('save_project_blueprint')));
    await tester.pumpAndSettle();
    final callback = tester
        .widget<FilledButton>(find.byKey(const Key('confirm_blueprint')))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(repository.createCalls, 1);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm_blueprint')))
            .onPressed,
        isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.error = Exception('API');
    repository.mutation!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blueprint_error')), findsOneWidget);
    repository.error = null;
    repository.mutation = null;
    await tester.tap(find.byKey(const Key('confirm_blueprint')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 2);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('lista apresenta loading, erro, retry e estado vazio',
      (tester) async {
    final repository = FakeBlueprintRepository()
      ..loading = Completer<void>()
      ..listError = Exception('API');
    await pump(tester, repository, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.loading!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar os modelos.'), findsOneWidget);
    repository.listError = null;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Você ainda não possui modelos'), findsOneWidget);
  });

  testWidgets(
      'usar revisa estrutura, cria independente e abre novo Project no mobile',
      (tester) async {
    final repository = FakeBlueprintRepository()..items = [blueprintSample()];
    await pump(tester, repository, size: const Size(390, 844));
    expect(find.text('Marketing'), findsOneWidget);
    expect(find.textContaining('Criado: 09/09/2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('use_blueprint_bp-1')));
    await tester.pumpAndSettle();
    expect(find.text('Objetivo: Publicar campanha'), findsOneWidget);
    expect(find.text('Critério: Material pronto'), findsOneWidget);
    expect(find.text('Marco: Publicar'), findsOneWidget);
    expect(find.text('Campanha base'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
        find.byKey(const Key('blueprint_name')), 'Nova campanha');
    await tester.tap(find.byKey(const Key('confirm_blueprint')));
    await tester.pumpAndSettle();
    expect(repository.useCalls, 1);
    expect(repository.lastValues, {'name': 'Nova campanha'});
    expect(find.text('Novo created-project'), findsOneWidget);
  });

  testWidgets('editar metadados e excluir com cancelamento e confirmação',
      (tester) async {
    final repository = FakeBlueprintRepository()..items = [blueprintSample()];
    await pump(tester, repository);
    await tester.tap(find.byKey(const Key('edit_blueprint_bp-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('blueprint_name')), 'Modelo editado');
    await tester.enterText(
        find.byKey(const Key('blueprint_description')), 'Descrição editada');
    await tester.tap(find.byKey(const Key('confirm_blueprint')));
    await tester.pumpAndSettle();
    expect(repository.updateCalls, 1);
    expect(find.text('Modelo editado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete_blueprint_bp-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);
    await tester.tap(find.byKey(const Key('delete_blueprint_bp-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Os projetos já criados serão preservados'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_blueprint')));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 1);
    expect(
        find.textContaining('Você ainda não possui modelos'), findsOneWidget);
  });

  testWidgets('usar bloqueia double submit e mantém diálogo após falha',
      (tester) async {
    final repository = FakeBlueprintRepository()
      ..items = [blueprintSample()]
      ..mutation = Completer<void>();
    await pump(tester, repository);
    await tester.tap(find.byKey(const Key('use_blueprint_bp-1')));
    await tester.pumpAndSettle();
    final callback = tester
        .widget<FilledButton>(find.byKey(const Key('confirm_blueprint')))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(repository.useCalls, 1);
    repository.error = Exception('API');
    repository.mutation!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blueprint_error')), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
      'Meus projetos preserva organização e Novo projeto ao acessar modelos',
      (tester) async {
    final repository = FakeBlueprintRepository();
    await pump(tester, repository,
        route: '/projects', size: const Size(390, 844));
    expect(find.byKey(const Key('project_search')), findsOneWidget);
    expect(find.byKey(const Key('project_order')), findsOneWidget);
    expect(find.byKey(const Key('favorite_project-1')), findsOneWidget);
    expect(find.text('Modelos de projeto'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('project_blueprints'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('project_search'))).dy),
    );
    expect(
        find.byKey(const Key('create_project')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('project_blueprints')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Você ainda não possui modelos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app_back_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_search')), findsOneWidget);
  });

  testWidgets('lista pagina todos os modelos sem truncamento silencioso',
      (tester) async {
    final repository = FakeBlueprintRepository()
      ..items = List.generate(
          21, (i) => blueprintSample(id: 'bp-$i', name: 'Modelo $i'));
    await pump(tester, repository);
    await tester.scrollUntilVisible(find.text('Próxima'), 800);
    await tester.tap(find.text('Próxima'));
    await tester.pumpAndSettle();
    expect(find.text('Modelo 20'), findsOneWidget);
    expect(find.text('21–21 de 21'), findsOneWidget);
  });
}
