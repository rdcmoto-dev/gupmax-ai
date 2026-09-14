import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/api_client.dart';
import 'package:gupmax_ai/core/storage/session_storage.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/project_tags.dart';
import 'package:gupmax_ai/features/projects/project_organization.dart';
import 'package:gupmax_ai/features/projects/project_overview.dart';
import 'package:gupmax_ai/features/projects/presentation/project_list_page.dart';
import 'package:gupmax_ai/features/projects/data/project_repository.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/prompt_chains/prompt_chain_providers.dart';

import '../../support/fake_prompt_chain_repository.dart';

ApiClient client(Dio dio) => ApiClient(
    storage: MemorySessionStorage(), onSessionExpired: () async {}, dio: dio);

ProjectRecord project(String id,
        {bool favorite = true,
        ProjectStatus status = ProjectStatus.active,
        List<ProjectTag> tags = const [ProjectTag('t1', 'Cliente')]}) =>
    ProjectRecord(
        id: id,
        name: 'Projeto $id',
        status: status,
        isFavorite: favorite,
        tags: tags,
        promptCount: 0,
        templateCount: 0,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026));

class FakeTags extends TagRepository {
  FakeTags() : super(client(Dio()));
  List<ProjectTag> items = [const ProjectTag('t1', 'Cliente')];
  final links = <String>{};
  int saves = 0;
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<List<ProjectTag>> list() async => items;
  @override
  Future<List<ProjectTag>> associations(String projectId) async =>
      items.where((tag) => links.contains(tag.id)).toList();
  @override
  Future<ProjectTag> save(String name, {String? id}) async {
    saves++;
    if (pending != null) await pending!.future;
    if (fail) throw const AppException('Falha teste');
    final tag = ProjectTag(id ?? 't2', name);
    items = [...items.where((item) => item.id != tag.id), tag];
    return tag;
  }

  @override
  Future<void> associate(String projectId, String tagId, bool selected) async {
    if (selected) {
      links.add(tagId);
    } else {
      links.remove(tagId);
    }
  }

  @override
  Future<void> delete(String id) async {
    items = items.where((tag) => tag.id != id).toList();
  }
}

void main() {
  testWidgets(
      'persist association then load real repositories and filter by UUID',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const tagId = '92265783-55fc-4548-a6b2-f3da1efe4d24';
    const projectId = '10000000-0000-4000-8000-000000000001';
    const otherId = '10000000-0000-4000-8000-000000000002';
    final links = <String, Set<String>>{};
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final api = client(dio);
    var listRequests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      Object? data;
      if (options.method == 'PUT') {
        expect(options.path, '/project-tags/projects/$projectId/$tagId');
        links.putIfAbsent(projectId, () => {}).add(tagId);
      } else if (options.path == '/project-tags') {
        data = [
          {'id': tagId, 'name': 'Marketing'}
        ];
      } else {
        expect(options.path, '/projects');
        listRequests++;
        data = {
          'total': 2,
          'items': [
            for (final id in [projectId, otherId])
              {
                'id': id,
                'name': id == projectId
                    ? 'Lançamento Pizzaria Donatello'
                    : 'Sem Marketing',
                'status': 'active',
                'created_at': '2026-09-12T00:00:00Z',
                'updated_at': '2026-09-12T00:00:00Z',
                'tags': [
                  for (final saved in links[id] ?? <String>{})
                    {'id': saved, 'name': 'Marketing'},
                ],
              },
          ],
        };
      }
      handler.resolve(Response(
          requestOptions: options,
          statusCode: options.method == 'PUT' ? 204 : 200,
          data: data));
    }));
    final repository = ProjectRepository(api);
    await tester.runAsync(() async {
      expect(
          (await repository.list()).items.every((p) => p.tags.isEmpty), isTrue);
      await TagRepository(api).associate(projectId, tagId, true);
    });
    await tester.pumpWidget(ProviderScope(overrides: [
      projectRepositoryProvider.overrideWithValue(repository),
      tagRepositoryProvider.overrideWithValue(TagRepository(api)),
      promptChainRepositoryProvider
          .overrideWithValue(FakePromptChainRepository()),
    ], child: const MaterialApp(home: ProjectListPage())));
    await tester.pumpAndSettle();
    expect(listRequests, 2);
    expect(find.byKey(const Key('project_$projectId')), findsOneWidget);
    expect(find.byKey(const Key('project_$otherId')), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marketing').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_$projectId')), findsOneWidget);
    expect(find.byKey(const Key('project_$otherId')), findsNothing);
    expect(find.text('Nenhum projeto encontrado.'), findsNothing);
  });

  for (final size in [const Size(1100, 900), const Size(390, 844)]) {
    testWidgets('tag catalog loads over HTTP and dropdown selects at $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const marketing = ProjectTag('marketing', 'Marketing');
      const instagram = ProjectTag('instagram', 'Instagram');
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      var catalogRequests = 0;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.method, 'GET');
        expect(options.path, '/project-tags');
        catalogRequests++;
        handler
            .resolve(Response(requestOptions: options, statusCode: 200, data: [
          {'id': instagram.id, 'name': instagram.name},
          {'id': marketing.id, 'name': marketing.name},
          {'id': 'unused', 'name': 'Sem associação'},
        ]));
      }));
      await tester.pumpWidget(ProviderScope(overrides: [
        tagRepositoryProvider.overrideWithValue(TagRepository(client(dio))),
        projectOverviewsProvider(
                const ProjectOverviewQuery(includeArchived: true))
            .overrideWith((ref) async => [
                  ProjectOverview(project: project('A', tags: [marketing])),
                  ProjectOverview(project: project('B', tags: [instagram])),
                  ProjectOverview(
                      project:
                          project('C', favorite: false, tags: [instagram])),
                  ProjectOverview(
                      project: project('D',
                          status: ProjectStatus.archived, tags: [instagram])),
                ]),
      ], child: const MaterialApp(home: ProjectListPage())));
      await tester.pumpAndSettle();
      expect(catalogRequests, 1);

      Future<void> choose(String label) async {
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        final option = find.text(label).hitTestable().last;
        expect(option, findsOneWidget);
        await tester.tap(option);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      // Verify visible overlay entries, including a catalog Tag absent from cards.
      expect(find.text('Marketing').hitTestable(), findsWidgets);
      expect(find.text('Instagram').hitTestable(), findsWidgets);
      expect(find.text('Sem associação').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Marketing').hitTestable().last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('project_A')), findsOneWidget);
      expect(find.byKey(const Key('project_B')), findsNothing);
      await choose('Instagram');
      expect(find.byKey(const Key('project_A')), findsNothing);
      expect(find.byKey(const Key('project_B')), findsOneWidget);
      await choose('Sem associação');
      expect(find.text('Nenhum projeto encontrado.'), findsOneWidget);
      await choose('Todas as Tags');
      expect(find.byKey(const Key('project_A')), findsOneWidget);
      await choose('Instagram');
      final favorites = find.byKey(const Key('project_filter_favorites'));
      await tester.ensureVisible(favorites);
      await tester.pumpAndSettle();
      await tester.tap(favorites);
      await tester.pumpAndSettle();
      final active = find.byKey(const Key('project_filter_inProgress'));
      await tester.ensureVisible(active);
      await tester.pumpAndSettle();
      await tester.tap(active);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('project_search')), 'Projeto B');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project_order')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nome Z–A').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('project_B')), findsOneWidget);
      for (final id in ['A', 'C', 'D']) {
        expect(find.byKey(Key('project_$id')), findsNothing);
      }
      expect(catalogRequests, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('catalog loading and error are explicit and retry fills dropdown',
      (tester) async {
    final pending = Completer<List<ProjectTag>>();
    var attempts = 0;
    await tester.pumpWidget(ProviderScope(overrides: [
      projectTagsProvider.overrideWith((ref) {
        attempts++;
        return attempts == 1
            ? pending.future
            : Future.value([const ProjectTag('marketing', 'Marketing')]);
      }),
      projectOverviewsProvider(
              const ProjectOverviewQuery(includeArchived: true))
          .overrideWith((ref) async =>
              [ProjectOverview(project: project('A', tags: []))]),
    ], child: const MaterialApp(home: ProjectListPage())));
    await tester.pumpAndSettle();
    expect(find.text('Carregando Tags...'), findsOneWidget);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .onChanged,
        isNull);
    pending.completeError(const AppException('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar Tags.'), findsOneWidget);
    await tester.tap(find.byTooltip('Recarregar Tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Marketing').hitTestable(), findsOneWidget);
    expect(attempts, 2);
  });

  Future<void> panel(WidgetTester tester, FakeTags repository,
      {Size size = const Size(1000, 900)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [tagRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
            home: Scaffold(
                body: ProjectTagsPanel(project: project('p1', tags: []))))));
    await tester.tap(find.byKey(const Key('manage_project_tags')));
    await tester.pumpAndSettle();
  }

  test('HTTP CRUD and associations use authenticated client and strict payload',
      () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.method == 'GET'
              ? [
                  {'id': 't1', 'name': 'Cliente'}
                ]
              : {'id': 't1', 'name': 'Cliente'}));
    }));
    final repository = TagRepository(client(dio));
    expect((await repository.list()).single.name, 'Cliente');
    await repository.save(' Cliente ');
    await repository.save('Cliente', id: 't1');
    await repository.associate('p1', 't1', true);
    await repository.associate('p1', 't1', false);
    await repository.delete('t1');
    expect(requests.map((r) => '${r.method} ${r.path}'), [
      'GET /project-tags',
      'POST /project-tags',
      'PUT /project-tags/t1',
      'PUT /project-tags/projects/p1/t1',
      'DELETE /project-tags/projects/p1/t1',
      'DELETE /project-tags/t1'
    ]);
    expect(requests[1].data, {'name': 'Cliente'});
    expect(requests[3].data, isNull);
  });

  test('Tags compose with search, status, favorites and all orders', () {
    final items = [
      ProjectOverview(project: project('B')),
      ProjectOverview(project: project('A')),
      ProjectOverview(project: project('C', favorite: false)),
      ProjectOverview(project: project('D', status: ProjectStatus.archived)),
      ProjectOverview(project: project('E', tags: []))
    ];
    for (final order in ProjectListOrder.values) {
      final result = organizeProjects(items,
          tagId: 't1',
          search: ' PROJETO ',
          filter: ProjectListFilter.inProgress,
          favoritesOnly: true,
          order: order);
      expect(result.map((item) => item.key).toSet(), {'A', 'B'});
    }
    expect(organizeProjects(items, tagId: 'missing'), isEmpty);
    expect(
        organizeProjects(items,
                tagId: 't1', order: ProjectListOrder.nameAscending)
            .first
            .key,
        'A');
    expect(
        organizeProjects(items,
                tagId: 't1', order: ProjectListOrder.nameDescending)
            .first
            .key,
        'D');
  });

  testWidgets('create, select, detach, rename and confirm global delete',
      (tester) async {
    final repository = FakeTags();
    await panel(tester, repository);
    await tester.tap(find.byKey(const Key('save_tag')));
    await tester.pump();
    expect(find.byKey(const Key('tag_error')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tag_name')), 'Novo');
    await tester.tap(find.byKey(const Key('save_tag')));
    await tester.pumpAndSettle();
    expect(find.text('Novo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tag_select_t2')));
    await tester.pumpAndSettle();
    expect(repository.links, {'t2'});
    await tester.tap(find.byKey(const Key('tag_select_t2')));
    await tester.pumpAndSettle();
    expect(repository.links, isEmpty);
    await tester.tap(find.byTooltip('Editar Novo'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('tag_name')), 'Renomeado');
    await tester.tap(find.byKey(const Key('save_tag')));
    await tester.pumpAndSettle();
    expect(find.text('Renomeado'), findsOneWidget);
    await tester.tap(find.byTooltip('Excluir Renomeado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repository.items.length, 2);
    await tester.tap(find.byTooltip('Excluir Renomeado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(repository.items.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading prevents double submit; failure retains name for retry',
      (tester) async {
    final repository = FakeTags()
      ..pending = Completer<void>()
      ..fail = true;
    await panel(tester, repository);
    await tester.enterText(find.byKey(const Key('tag_name')), 'Retry');
    await tester.tap(find.byKey(const Key('save_tag')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_tag')));
    expect(repository.saves, 1);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Concluir'))
            .onPressed,
        isNull);
    repository.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Falha teste'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    repository.fail = false;
    repository.pending = null;
    await tester.tap(find.byKey(const Key('save_tag')));
    await tester.pumpAndSettle();
    expect(repository.saves, 2);
    expect(find.text('Falha teste'), findsNothing);
  });

  testWidgets('mobile long tag keeps edit and delete accessible',
      (tester) async {
    final repository = FakeTags()..items = [ProjectTag('t1', 'M' * 60)];
    await panel(tester, repository, size: const Size(390, 844));
    expect(find.byType(FilterChip), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards display tags and tag filter combines with favorites',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(overrides: [
      tagRepositoryProvider.overrideWithValue(FakeTags()),
      projectOverviewsProvider(
              const ProjectOverviewQuery(includeArchived: true))
          .overrideWith((ref) async => [
                ProjectOverview(project: project('A')),
                ProjectOverview(project: project('B', tags: []))
              ]),
    ], child: const MaterialApp(home: ProjectListPage())));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'Cliente'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente').last);
    await tester.pumpAndSettle();
    expect(find.text('Projeto A'), findsOneWidget);
    expect(find.text('Projeto B'), findsNothing);
    await tester.enterText(find.byKey(const Key('project_search')), 'ausente');
    await tester.pumpAndSettle();
    expect(find.text('Nenhum projeto encontrado.'), findsOneWidget);
  });
}
