import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/core/network/api_client.dart';
import 'package:gupmax_ai/core/storage/session_storage.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/presentation/project_list_page.dart';
import 'package:gupmax_ai/features/projects/presentation/project_workspace_page.dart';
import 'package:gupmax_ai/features/projects/project_tags.dart';
import 'package:gupmax_ai/features/projects/project_workspace.dart';

const _id = '10000000-0000-4000-8000-000000000001';
const _marketing = '92265783-55fc-4548-a6b2-f3da1efe4d24';
const _instagram = '696972af-1dc2-43f4-b76e-187ad6a9b87a';

// Fake HTTP persistence, not fake repositories or prepopulated UI models.
class _Server {
  final catalog = <String, String>{
    _marketing: 'Marketing',
    _instagram: 'Instagram'
  };
  final links = <String>{};
  bool ignoreWrites = false;
  List<Map<String, dynamic>> tags(Iterable<String> ids) => [
        for (final id in ids) {'id': id, 'name': catalog[id]},
      ];
  Map<String, dynamic> project(String id) => {
        'id': id,
        'name': id == _id ? 'Lançamento Pizzaria Donatello' : 'Outro Project',
        'status': 'active',
        'tags': tags(id == _id ? links : []),
        'created_at': '2026-09-12T00:00:00Z',
        'updated_at': '2026-09-12T00:00:00Z',
      };
  void handle(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    Object? data;
    var status = 200;
    if (path.startsWith('/project-tags/projects/')) {
      final id = path.split('/').last;
      if (!ignoreWrites) {
        if (options.method == 'PUT') {
          links.add(id);
        } else {
          links.remove(id);
        }
      }
      status = 204;
    } else if (path == '/project-tags' && options.method == 'POST') {
      const id = '33333333-3333-4333-8333-333333333333';
      catalog[id] = (options.data as Map)['name'] as String;
      data = tags([id]).single;
      status = 201;
    } else if (path == '/project-tags') {
      data = tags(catalog.keys);
    } else if (path == '/projects') {
      data = {
        'total': 2,
        'items': [project(_id), project('other')]
      };
    } else if (path == '/projects/$_id') {
      data = project(_id);
    } else if (path == '/chains') {
      data = {'total': 0, 'items': <dynamic>[]};
    } else {
      throw StateError('Unexpected request: ${options.method} $path');
    }
    handler.resolve(
        Response(requestOptions: options, statusCode: status, data: data));
  }
}

Future<void> _flow(WidgetTester tester, ApiClient api, String projectId,
    {bool exactTwoTags = false}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Future<T> fetch<T>(Future<T> Function() request) async =>
      (await tester.runAsync(request)) as T;

  final repository = TagRepository(api);
  late List<ProjectTag> catalog;
  catalog = await fetch(repository.list);
  final marketing = catalog.singleWhere((tag) => tag.name == 'Marketing').id;
  final instagram = catalog.singleWhere((tag) => tag.name == 'Instagram').id;

  Future<void> settle() => tester.pumpAndSettle();

  late GoRouter router;
  Future<void> mount() async {
    router = GoRouter(initialLocation: '/projects', routes: [
      GoRoute(path: '/projects', builder: (_, __) => const ProjectListPage()),
      GoRoute(
          path: '/projects/:id',
          builder: (_, state) => ProjectWorkspacePage(
              target:
                  ProjectWorkspaceTarget.project(state.pathParameters['id']!))),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold()),
    ]);
    await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp.router(routerConfig: router)));
    await settle();
  }

  Future<void> openManager() async {
    router.go('/projects/$projectId');
    await settle();
    final manage = find.byKey(const Key('manage_project_tags'));
    await tester.ensureVisible(manage);
    await settle();
    await tester.tap(manage);
    await settle();
  }

  Future<void> select(String id, bool selected) async {
    final finder = find.byKey(Key('tag_select_$id'));
    if (tester.widget<FilterChip>(finder).selected != selected) {
      await tester.ensureVisible(finder);
      await settle();
      await tester.tap(finder);
      await settle();
    }
    expect(tester.widget<FilterChip>(finder).selected, selected);
    expect(find.byKey(const Key('tag_error')), findsNothing);
  }

  Future<void> filter(String label, bool expected) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle();
    await tester.tap(find.text(label).hitTestable().last);
    await settle();
    expect(find.byKey(Key('project_$projectId')),
        expected ? findsOneWidget : findsNothing);
  }

  await mount();
  await openManager();
  await select(marketing, true);
  await select(instagram, true);
  expect(
      tester
          .widget<FilterChip>(find.byKey(Key('tag_select_$marketing')))
          .selected,
      isTrue);
  await tester.tap(find.text('Concluir'));
  await settle();
  router.go('/projects');
  await settle();
  await filter('Marketing', true);
  await filter('Instagram', true);

  if (exactTwoTags) {
    expect(
        (await fetch(() => repository.associations(projectId)))
            .map((tag) => tag.id)
            .toSet(),
        {marketing, instagram});
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await mount();
    await filter('Marketing', true);
    await filter('Instagram', true);
    await openManager();
    expect(
        tester
            .widget<FilterChip>(find.byKey(Key('tag_select_$marketing')))
            .selected,
        isTrue);
    expect(
        tester
            .widget<FilterChip>(find.byKey(Key('tag_select_$instagram')))
            .selected,
        isTrue);
    await select(instagram, false);
    expect(
        tester
            .widget<FilterChip>(find.byKey(Key('tag_select_$marketing')))
            .selected,
        isTrue);
    await tester.tap(find.text('Concluir'));
    await settle();
    router.go('/projects');
    await settle();
    await filter('Marketing', true);
    await filter('Instagram', false);
    expect(
        (await fetch(() => repository.associations(projectId)))
            .map((tag) => tag.id)
            .toSet(),
        {marketing});
    expect((await fetch(repository.list)).any((tag) => tag.id == instagram),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    return;
  }

  await openManager();
  if (!catalog.any((tag) => tag.name == 'Teste935')) {
    await tester.enterText(find.byKey(const Key('tag_name')), 'Teste935');
    await tester.tap(find.byKey(const Key('save_tag')));
    await settle();
  }
  catalog = await fetch(repository.list);
  final testId = catalog.singleWhere((tag) => tag.name == 'Teste935').id;
  await select(testId, true);
  await tester.tap(find.text('Concluir'));
  await settle();
  router.go('/projects');
  await settle();
  await filter('Teste935', true);

  // A fresh app/provider tree reloads the associations from HTTP, like F5.
  await tester.pumpWidget(const SizedBox());
  router.dispose();
  await mount();
  await filter('Marketing', true);
  await filter('Instagram', true);
  await filter('Teste935', true);
  await openManager();
  await select(testId, false);
  await tester.tap(find.text('Concluir'));
  await settle();
  router.go('/projects');
  await settle();
  await filter('Teste935', false);
  await filter('Marketing', true);
  await filter('Instagram', true);
  expect((await fetch(repository.list)).any((tag) => tag.id == testId), isTrue);
  final persisted = await fetch(() => repository.associations(projectId));
  expect(persisted.map((tag) => tag.id).toSet(),
      containsAll([marketing, instagram]));
  expect(persisted.any((tag) => tag.id == testId), isFalse);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  router.dispose();
}

void main() {
  testWidgets(
      'Project A retains Marketing after adding, reloading and removing Instagram',
      (tester) async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final server = _Server();
    dio.interceptors.add(InterceptorsWrapper(onRequest: server.handle));
    final api = ApiClient(
        storage: MemorySessionStorage(),
        onSessionExpired: () async {},
        dio: dio);
    await _flow(tester, api, _id, exactTwoTags: true);
    expect(server.links, {_marketing});
  });
  testWidgets('manager replaces stale snapshot with persisted associations',
      (tester) async {
    final server = _Server()..links.add(_instagram);
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: server.handle));
    final api = ApiClient(
        storage: MemorySessionStorage(),
        onSessionExpired: () async {},
        dio: dio);
    final stale = ProjectRecord.fromJson({
      ...server.project(_id),
      'tags': server.tags([_marketing])
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
            home: Scaffold(body: ProjectTagsPanel(project: stale)))));
    await tester.tap(find.byKey(const Key('manage_project_tags')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('tag_select_$_instagram')))
            .selected,
        isTrue);
    expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('tag_select_$_marketing')))
            .selected,
        isFalse);
    await tester.tap(find.byKey(const Key('tag_select_$_marketing')));
    await tester.pumpAndSettle();
    expect(server.links, {_marketing, _instagram});
  });

  testWidgets('Workspace persists multiple Tags, reloads and detaches only one',
      (tester) async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final server = _Server();
    dio.interceptors.add(InterceptorsWrapper(onRequest: server.handle));
    final api = ApiClient(
        storage: MemorySessionStorage(),
        onSessionExpired: () async {},
        dio: dio);
    await _flow(tester, api, _id);
  });

  testWidgets(
      'filter refreshes a previously loaded list after persisted links change',
      (tester) async {
    final server = _Server()..links.add(_marketing);
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: server.handle));
    final api = ApiClient(
        storage: MemorySessionStorage(),
        onSessionExpired: () async {},
        dio: dio);
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: ProjectListPage())));
    await tester.pumpAndSettle();
    // Simulates another Workspace/session persisting Instagram while this list is open.
    await tester
        .runAsync(() => TagRepository(api).associate(_id, _instagram, true));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instagram').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_$_id')), findsOneWidget);
  });

  testWidgets('204 alone cannot present an unpersisted association as selected',
      (tester) async {
    final server = _Server()..ignoreWrites = true;
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: server.handle));
    final api = ApiClient(
        storage: MemorySessionStorage(),
        onSessionExpired: () async {},
        dio: dio);
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
            home: Scaffold(
                body: ProjectTagsPanel(
                    project: ProjectRecord.fromJson(server.project(_id)))))));
    await tester.tap(find.byKey(const Key('manage_project_tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tag_select_$_instagram')));
    await tester.pumpAndSettle();
    expect(find.text('A associação não foi confirmada. Tente novamente.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('tag_select_$_instagram')))
            .selected,
        isFalse);
  });
}
