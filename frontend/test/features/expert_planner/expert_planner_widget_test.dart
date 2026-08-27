import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/features/expert_planner/expert_planner_providers.dart';
import 'package:gupmax_ai/features/expert_planner/presentation/expert_planner_page.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

import '../../support/fake_expert_planner_repository.dart';

const input = PromptGenerateInput(
  input: 'Quero criar um aplicativo de delivery para restaurantes',
  category: PromptCategory.programming,
  mode: PromptMode.expert,
  projectId: 'project-1',
);

Widget app(FakeExpertPlannerRepository repository,
    {String initialLocation = '/plan'}) {
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => Scaffold(
        body: TextButton(
          key: const Key('open_planner'),
          onPressed: () => context.push('/plan'),
          child: const Text('Abrir planner'),
        ),
      ),
    ),
    GoRoute(
        path: '/plan',
        builder: (_, __) => const ExpertPlannerPage(input: input)),
    GoRoute(
        path: '/chains/:id',
        builder: (_, state) => Text('Fluxo ${state.pathParameters['id']}')),
  ]);
  return ProviderScope(
    overrides: [expertPlannerRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('mostra loading e renderiza plano determinístico',
      (tester) async {
    final repository = FakeExpertPlannerRepository()
      ..planCompleter = Completer();
    await tester.pumpWidget(app(repository));
    await tester.pump();
    expect(find.byKey(const Key('planner_loading')), findsOneWidget);
    repository.planCompleter!.complete(repository.result);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expert_plan')), findsOneWidget);
    expect(find.byKey(const Key('planner_step_0')), findsOneWidget);
    expect(find.text('Este projeto se beneficia de várias etapas.'),
        findsOneWidget);
  });

  testWidgets('mostra erro de planejamento sem persistir', (tester) async {
    final repository = FakeExpertPlannerRepository()..failPlanning = true;
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('planner_error')), findsOneWidget);
    expect(repository.createCalls, 0);
  });

  testWidgets('cancelar volta sem criar fluxo', (tester) async {
    final repository = FakeExpertPlannerRepository();
    await tester.pumpWidget(app(repository, initialLocation: '/home'));
    await tester.tap(find.byKey(const Key('open_planner')));
    await tester.pumpAndSettle();
    await tester.fling(
        find.byKey(const Key('expert_plan')), const Offset(0, -1200), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('planner_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open_planner')), findsOneWidget);
    expect(repository.createCalls, 0);
  });

  testWidgets('revisa, reordena, remove, adiciona e cria fluxo',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeExpertPlannerRepository();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('planner_edit_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('planner_edit_title')), 'Requisitos revisados');
    await tester.enterText(
        find.byKey(const Key('planner_edit_base')), 'Base revisada');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('1. Requisitos revisados'), findsOneWidget);

    await tester.tap(find.byKey(const Key('planner_down_0')));
    await tester.pump();
    expect(find.text('2. Requisitos revisados'), findsOneWidget);
    await tester.tap(find.byKey(const Key('planner_remove_2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('planner_add_step')));
    await tester.pump();
    expect(find.textContaining('Nova etapa'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('planner_chain_name')), 'Delivery Restaurantes');
    await tester.ensureVisible(find.byKey(const Key('planner_create_chain')));
    await tester.tap(find.byKey(const Key('planner_create_chain')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
    expect(repository.createdName, 'Delivery Restaurantes');
    expect(repository.createdProjectId, 'project-1');
    expect(repository.createdSteps.length, 3);
    expect(find.text('Fluxo created-chain'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout mobile não apresenta overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(FakeExpertPlannerRepository()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expert_plan')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
