import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/core/theme/app_theme.dart';
import 'package:gupmax_ai/features/projects/presentation/project_workspace_page.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/projects/project_workspace.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';
import 'package:gupmax_ai/features/prompt_chains/prompt_chain_providers.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

import '../../support/fake_project_repository.dart';
import '../../support/fake_prompt_chain_repository.dart';

void main() {
  PromptChainStep step(
    int position,
    PromptChainStepStatus status, {
    String? result,
  }) =>
      PromptChainStep(
        id: 'step-$position',
        chainId: 'chain-1',
        position: position,
        title: 'Etapa $position',
        baseInput: 'Execute a etapa $position',
        mode: PromptMode.expert,
        category: PromptCategory.programming,
        targetAi: TargetAI.codingAssistant,
        executionStatus: status,
        result: result,
      );

  PromptChainRecord chain({
    String? projectId,
    int completed = 0,
    String? current,
    bool finished = false,
    List<PromptChainStep>? steps,
  }) =>
      PromptChainRecord(
        id: 'chain-1',
        name: 'Plano de entrega',
        description: 'Execução organizada do projeto.',
        projectId: projectId,
        status: PromptChainStatus.active,
        stepCount: steps?.length ?? 3,
        steps: steps ?? const [],
        completedStepCount: completed,
        currentStepId: current,
        executionCompleted: finished,
        category: PromptCategory.programming,
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 22),
      );

  Future<GoRouter> pumpWorkspace(
    WidgetTester tester, {
    required FakeProjectRepository projects,
    required FakePromptChainRepository chains,
    required ProjectWorkspaceTarget target,
    Size size = const Size(1200, 900),
    bool completionRoute = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/workspace',
      routes: [
        GoRoute(
          path: '/workspace',
          builder: (_, __) => ProjectWorkspacePage(target: target),
        ),
        GoRoute(
          path: '/chains/:id',
          builder: (context, state) => Scaffold(
            body: Center(
              child: completionRoute
                  ? FilledButton(
                      key: const Key('finish_current_and_back'),
                      onPressed: () async {
                        await chains.completeStep(
                            state.pathParameters['id']!, 'step-2', 'Pronto');
                        if (context.mounted) context.pop();
                      },
                      child: const Text('Concluir e voltar'),
                    )
                  : Text('Execução ${state.pathParameters['id']}'),
            ),
          ),
        ),
        GoRoute(
          path: '/projects',
          builder: (_, __) => const Scaffold(body: Text('Projetos')),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('Dashboard')),
        ),
        GoRoute(
          path: '/prompts/new',
          builder: (_, __) => const Scaffold(body: Text('Novo prompt')),
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
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('Project sem Chain mostra ações compatíveis e sem progresso',
      (tester) async {
    final project = projectSample(id: 'project-1', name: 'Projeto avulso');
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository()..items = [project],
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    expect(find.text('Projeto avulso'), findsOneWidget);
    expect(find.byKey(const Key('workspace_progress')), findsNothing);
    expect(find.byKey(const Key('create_prompt_in_project')), findsOneWidget);
    expect(find.text('Nenhum prompt associado.'), findsOneWidget);
  });

  testWidgets('Chain sem Project inicia e abre execução guiada',
      (tester) async {
    final steps = [
      step(1, PromptChainStepStatus.pending),
      step(2, PromptChainStepStatus.pending),
    ];
    final chains = FakePromptChainRepository()..items = [chain(steps: steps)];
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository(),
      chains: chains,
      target: const ProjectWorkspaceTarget.chain('chain-1'),
    );

    expect(find.text('0 de 2 etapas concluídas'), findsOneWidget);
    expect(find.text('Iniciar projeto'), findsOneWidget);
    await tester.tap(find.byKey(const Key('workspace_primary_action')));
    await tester.pumpAndSettle();
    expect(chains.startExecutionCalls, 1);
    expect(find.text('Execução chain-1'), findsOneWidget);
  });

  testWidgets('Project e Chain associados formam uma Central sem duplicidade',
      (tester) async {
    final project = projectSample(id: 'project-1', name: 'Delivery');
    final steps = [
      step(1, PromptChainStepStatus.completed, result: 'Escopo'),
      step(2, PromptChainStepStatus.inProgress),
      step(3, PromptChainStepStatus.pending),
    ];
    final chains = FakePromptChainRepository()
      ..items = [
        chain(
          projectId: project.id,
          completed: 1,
          current: 'step-2',
          steps: steps,
        ),
      ];
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository()..items = [project],
      chains: chains,
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('Plano de entrega'), findsNothing);
    expect(find.text('1 de 3 etapas concluídas'), findsOneWidget);
    expect(find.text('Continuar projeto'), findsOneWidget);
    expect(find.text('2. Etapa 2'), findsOneWidget);
    expect(find.text('Atual'), findsOneWidget);
  });

  testWidgets('Chain concluída mostra N de N e ação de consulta',
      (tester) async {
    final steps = [
      step(1, PromptChainStepStatus.completed, result: 'Um'),
      step(2, PromptChainStepStatus.completed, result: 'Dois'),
    ];
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository(),
      chains: FakePromptChainRepository()
        ..items = [
          chain(completed: 2, finished: true, steps: steps),
        ],
      target: const ProjectWorkspaceTarget.chain('chain-1'),
    );

    expect(find.text('2 de 2 etapas concluídas'), findsOneWidget);
    expect(find.text('Concluído'), findsOneWidget);
    expect(find.text('Ver projeto concluído'), findsOneWidget);
  });

  testWidgets('retorno da execução atualiza progresso e próxima etapa',
      (tester) async {
    final steps = [
      step(1, PromptChainStepStatus.completed, result: 'Um'),
      step(2, PromptChainStepStatus.inProgress),
      step(3, PromptChainStepStatus.pending),
    ];
    final chains = FakePromptChainRepository()
      ..items = [
        chain(completed: 1, current: 'step-2', steps: steps),
      ];
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository(),
      chains: chains,
      target: const ProjectWorkspaceTarget.chain('chain-1'),
      completionRoute: true,
    );

    await tester.tap(find.byKey(const Key('workspace_primary_action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish_current_and_back')));
    await tester.pumpAndSettle();

    expect(find.text('2 de 3 etapas concluídas'), findsOneWidget);
    expect(find.text('3. Etapa 3'), findsOneWidget);
    expect(find.text('Atual'), findsOneWidget);
  });

  testWidgets('Central permanece sem overflow no mobile', (tester) async {
    final steps = [
      step(1, PromptChainStepStatus.completed),
      step(2, PromptChainStepStatus.inProgress),
    ];
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository(),
      chains: FakePromptChainRepository()
        ..items = [
          chain(completed: 1, current: 'step-2', steps: steps),
        ],
      target: const ProjectWorkspaceTarget.chain('chain-1'),
      size: const Size(390, 844),
    );

    expect(find.byKey(const Key('workspace_progress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
