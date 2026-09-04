import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
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
    expect(
      find.descendant(
        of: find.byKey(const Key('workspace_progress')),
        matching: find.text('1 de 3 etapas concluídas'),
      ),
      findsOneWidget,
    );
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

    expect(
      find.descendant(
        of: find.byKey(const Key('workspace_progress')),
        matching: find.text('2 de 2 etapas concluídas'),
      ),
      findsOneWidget,
    );
    expect(find.text('Concluído'), findsNWidgets(2));
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

    expect(
      find.descendant(
        of: find.byKey(const Key('workspace_progress')),
        matching: find.text('2 de 3 etapas concluídas'),
      ),
      findsOneWidget,
    );
    expect(find.text('3. Etapa 3'), findsOneWidget);
    expect(find.text('Atual'), findsOneWidget);
  });

  testWidgets('adiciona, edita, remove e reconstroi memoria do Project',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [projectSample(context: null)];
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    expect(find.byKey(const Key('empty_project_memory')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('edit_project_memory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_memory')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_memory_label_0')), 'Público');
    await tester.enterText(
        find.byKey(const Key('project_memory_value_0')), 'Famílias da região');
    await tester.tap(find.byKey(const Key('add_project_memory')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_memory_label_1')), 'Canal');
    await tester.enterText(
        find.byKey(const Key('project_memory_value_1')), 'Instagram');
    await tester.tap(find.byKey(const Key('save_project_memory')));
    await tester.pumpAndSettle();

    expect(projects.updateCalls, 1);
    expect(projects.items.single.context,
        'Público: Famílias da região\nCanal: Instagram');
    expect(
      find.descendant(
        of: find.byKey(const Key('project_memory_card')),
        matching: find.textContaining('Famílias da região'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('project_memory_card')),
        matching: find.textContaining('Instagram'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('edit_project_memory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_memory')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_memory_value_0')), 'Famílias locais');
    await tester.tap(find.byKey(const Key('remove_project_memory_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_project_memory')));
    await tester.pumpAndSettle();

    expect(projects.items.single.context, 'Público: Famílias locais');
    expect(
      find.descendant(
        of: find.byKey(const Key('project_memory_card')),
        matching: find.textContaining('Famílias locais'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('project_memory_card')),
        matching: find.textContaining('Instagram'),
      ),
      findsNothing,
    );

    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('project_memory_card')),
        matching: find.textContaining('Famílias locais'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Chain sem Project nao cria memoria silenciosamente',
      (tester) async {
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository(),
      chains: FakePromptChainRepository()..items = [chain()],
      target: const ProjectWorkspaceTarget.chain('chain-1'),
    );

    expect(
        find.byKey(const Key('chain_without_project_memory')), findsOneWidget);
    expect(find.byKey(const Key('edit_project_memory')), findsNothing);
    expect(find.byKey(const Key('save_chain_as_project')), findsOneWidget);
  });

  testWidgets(
      'salva Chain como Project sem duplicar e preserva progresso na reabertura',
      (tester) async {
    final steps = [
      step(1, PromptChainStepStatus.completed, result: 'Escopo aprovado'),
      step(2, PromptChainStepStatus.inProgress),
    ];
    final chains = FakePromptChainRepository()
      ..items = [
        chain(completed: 1, current: 'step-2', steps: steps),
      ];
    final projects = FakeProjectRepository();
    projects.onCreateFromChain = (chainId, projectId) async {
      await chains.update(chainId, {'project_id': projectId});
    };
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: chains,
      target: const ProjectWorkspaceTarget.chain('chain-1'),
    );

    await tester.ensureVisible(find.byKey(const Key('save_chain_as_project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_chain_as_project')));
    await tester.pumpAndSettle();
    expect(find.text('Salvar como projeto?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(projects.createFromChainCalls, 0);

    await tester.ensureVisible(find.byKey(const Key('save_chain_as_project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_chain_as_project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_save_chain_as_project')));
    await tester.pumpAndSettle();

    expect(projects.createFromChainCalls, 1);
    expect(projects.items, hasLength(1));
    expect(find.byKey(const Key('chain_without_project_memory')), findsNothing);
    expect(find.byKey(const Key('edit_project_memory')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('workspace_progress')),
        matching: find.text('1 de 2 etapas concluídas'),
      ),
      findsOneWidget,
    );
    expect(chains.items.single.steps.first.result, 'Escopo aprovado');

    final repeated = await projects.createFromChain('chain-1');
    expect(repeated.id, projects.items.single.id);
    expect(projects.items, hasLength(1));

    await pumpWorkspace(
      tester,
      projects: projects,
      chains: chains,
      target: const ProjectWorkspaceTarget.chain('chain-1'),
    );
    expect(find.byKey(const Key('edit_project_memory')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('workspace_progress')),
        matching: find.text('1 de 2 etapas concluídas'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('erro ao salvar Chain como Project mantém fluxo utilizável',
      (tester) async {
    final projects = FakeProjectRepository()
      ..createFromChainError = Exception('falha');
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository()..items = [chain()],
      target: const ProjectWorkspaceTarget.chain('chain-1'),
    );

    await tester.ensureVisible(find.byKey(const Key('save_chain_as_project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_chain_as_project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_save_chain_as_project')));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível salvar este fluxo como projeto.'),
        findsOneWidget);
    expect(find.byKey(const Key('save_chain_as_project')), findsOneWidget);
    expect(find.text('0 de 3 etapas concluídas'), findsOneWidget);
  });

  testWidgets('Salvar como projeto não apresenta overflow no mobile',
      (tester) async {
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository(),
      chains: FakePromptChainRepository()..items = [chain()],
      target: const ProjectWorkspaceTarget.chain('chain-1'),
      size: const Size(390, 844),
    );

    expect(find.byKey(const Key('save_chain_as_project')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor de memoria nao apresenta overflow no mobile',
      (tester) async {
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository()..items = [projectSample(context: null)],
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
      size: const Size(390, 844),
    );

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('edit_project_memory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_memory')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_memory_label_0')), findsOneWidget);
    expect(find.byKey(const Key('project_memory_value_0')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('Saúde compacta combina Project e Chain sem duplicidade',
      (tester) async {
    final project = projectSample(
      context: 'Público: Famílias',
      promptCount: 2,
    );
    final steps = [
      step(1, PromptChainStepStatus.completed),
      step(2, PromptChainStepStatus.inProgress),
    ];
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository()..items = [project],
      chains: FakePromptChainRepository()
        ..items = [
          chain(
            projectId: project.id,
            completed: 1,
            current: 'step-2',
            steps: steps,
          ),
        ],
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    final card = find.byKey(const Key('project_health'));
    expect(card, findsOneWidget);
    expect(
        find.descendant(of: card, matching: find.text('Boa')), findsOneWidget);
    expect(
        find.descendant(of: card, matching: find.text('Contexto configurado')),
        findsOneWidget);
    expect(
        find.descendant(
            of: card, matching: find.text('1 de 2 etapas concluídas')),
        findsOneWidget);
    expect(
        find.descendant(of: card, matching: find.text('2 prompts associados')),
        findsOneWidget);
    expect(find.byKey(const Key('project_health_signal_3')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saúde de Project vazio é responsiva no mobile', (tester) async {
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository()..items = [projectSample(context: null)],
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
      size: const Size(390, 844),
    );

    final card = find.byKey(const Key('project_health'));
    expect(
        find.descendant(
          of: card,
          matching: find.text('Configuração necessária'),
        ),
        findsOneWidget);
    expect(
        find.descendant(
          of: card,
          matching: find.text('Adicione contexto ou crie o primeiro conteúdo'),
        ),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adiciona edita remove e persiste objetivo e critérios',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [projectSample(context: 'Público: Famílias')];
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    expect(find.byKey(const Key('empty_project_goals')), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit_project_goals')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project_goal_objective')),
        'Criar uma campanha regional');
    await tester.tap(find.byKey(const Key('add_project_goal_criterion')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project_goal_criterion_0')),
        'Campanha pronta para Instagram');
    await tester.tap(find.byKey(const Key('add_project_goal_criterion')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project_goal_criterion_1')),
        'Oferta claramente definida');
    await tester.tap(find.byKey(const Key('save_project_goals')));
    await tester.pumpAndSettle();

    expect(projects.items.single.context, contains('Público: Famílias'));
    expect(projects.items.single.context,
        contains('Objetivo: Criar uma campanha regional'));
    expect(find.text('Criar uma campanha regional'), findsOneWidget);
    expect(find.text('Campanha pronta para Instagram'), findsOneWidget);

    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );
    expect(find.text('Criar uma campanha regional'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_project_goals')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_goal_objective')), 'Objetivo revisado');
    await tester.enterText(find.byKey(const Key('project_goal_criterion_0')),
        'Mensagem principal definida');
    await tester.tap(find.byKey(const Key('remove_project_goal_criterion_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_project_goals')));
    await tester.pumpAndSettle();

    expect(
        projects.items.single.context, contains('Objetivo: Objetivo revisado'));
    expect(projects.items.single.context,
        contains('Critério de sucesso: Mensagem principal definida'));
    expect(projects.items.single.context,
        isNot(contains('Oferta claramente definida')));

    await tester.tap(find.byKey(const Key('edit_project_goals')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project_goal_objective')), '');
    await tester.tap(find.byKey(const Key('remove_project_goal_criterion_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_project_goals')));
    await tester.pumpAndSettle();

    expect(projects.items.single.context, 'Público: Famílias');
    expect(find.byKey(const Key('empty_project_goals')), findsOneWidget);
  });

  testWidgets('cancelar e erro da API preservam objetivos anteriores',
      (tester) async {
    const original = 'Objetivo: Meta original\n'
        'Critério de sucesso: Critério original\n'
        'Canal: Instagram';
    final projects = FakeProjectRepository()
      ..items = [projectSample(context: original)];
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    await tester.tap(find.byKey(const Key('edit_project_goals')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_goal_objective')), 'Não salvar');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(projects.items.single.context, original);
    expect(find.text('Meta original'), findsOneWidget);

    projects.updateError = const AppException('falha');
    await tester.tap(find.byKey(const Key('edit_project_goals')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_goal_objective')), 'Também não salvar');
    await tester.tap(find.byKey(const Key('save_project_goals')));
    await tester.pumpAndSettle();

    expect(projects.items.single.context, original);
    expect(find.text('Meta original'), findsOneWidget);
    expect(find.text('Não foi possível salvar os objetivos do projeto.'),
        findsOneWidget);
  });

  testWidgets('editor limita critérios e não cria Project para Chain',
      (tester) async {
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository()..items = [projectSample()],
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );
    await tester.tap(find.byKey(const Key('edit_project_goals')));
    await tester.pumpAndSettle();
    for (var index = 0; index < 5; index++) {
      await tester.tap(find.byKey(const Key('add_project_goal_criterion')));
      await tester.pumpAndSettle();
    }
    final add = tester.widget<TextButton>(
        find.byKey(const Key('add_project_goal_criterion')));
    expect(add.onPressed, isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    final projects = FakeProjectRepository();
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository()..items = [chain()],
      target: const ProjectWorkspaceTarget.chain('chain-1'),
    );
    expect(
        find.byKey(const Key('chain_without_project_goals')), findsOneWidget);
    expect(find.byKey(const Key('edit_project_goals')), findsNothing);
    expect(projects.items, isEmpty);
  });

  testWidgets('objetivos não apresentam overflow no mobile', (tester) async {
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository()..items = [projectSample(context: null)],
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
      size: const Size(390, 844),
    );

    await tester.ensureVisible(find.byKey(const Key('edit_project_goals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_goals')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_goal_objective')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nove entradas permitem salvar três marcos e reabrir',
      (tester) async {
    const context = 'Objetivo: Lançar campanha\n'
        'Critério de sucesso: Campanha aprovada\n'
        'Critério de sucesso: Material revisado\n'
        'Critério de sucesso: Publicação preparada\n'
        'Público: Famílias\n'
        'Canal: Instagram\n'
        'Tom: Profissional\n'
        'Diferencial: Produto artesanal\n'
        'Informação: Atuação regional';
    final projects = FakeProjectRepository()
      ..items = [projectSample(context: context)];
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    const values = [
      'Campanha de lançamento preparada e revisada.',
      'Publicar a campanha no Instagram.',
      'Analisar os resultados iniciais da campanha.',
    ];
    for (var index = 0; index < values.length; index++) {
      await tester.tap(find.byKey(const Key('add_project_milestone')));
      await tester.pump();
      await tester.enterText(
        find.byKey(Key('project_milestone_$index')),
        values[index],
      );
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('save_project_milestones')));
    await tester.pumpAndSettle();
    for (final value in values) {
      expect(projects.items.single.context, contains('Marco: $value'));
    }

    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );
    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    for (var index = 0; index < values.length; index++) {
      expect(
        tester
            .widget<TextFormField>(find.byKey(Key('project_milestone_$index')))
            .controller!
            .text,
        values[index],
      );
    }
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('Adicionar marco reage ao texto e limita o editor a cinco',
      (tester) async {
    final projects = FakeProjectRepository()
      ..items = [projectSample(context: 'Objetivo: Lançar campanha')];
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();

    TextButton addButton() => tester.widget<TextButton>(
          find.byKey(const Key('add_project_milestone')),
        );

    expect(addButton().onPressed, isNotNull);
    for (var index = 0; index < 5; index++) {
      await tester.tap(find.byKey(const Key('add_project_milestone')));
      await tester.pump();
      expect(addButton().onPressed, isNull);
      await tester.enterText(
        find.byKey(Key('project_milestone_$index')),
        'Marco ${index + 1}',
      );
      await tester.pump();
      expect(addButton().onPressed, index < 4 ? isNotNull : isNull);
    }
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('adiciona edita remove persiste e reabre marcos', (tester) async {
    final projects = FakeProjectRepository()
      ..items = [
        projectSample(
          context: 'Objetivo: Lançar campanha\nPúblico: Famílias',
        ),
      ];
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    expect(find.byKey(const Key('empty_project_milestones')), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_project_milestone')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_milestone_0')), 'Definir posicionamento');
    await tester.pump();
    await tester.tap(find.byKey(const Key('add_project_milestone')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_milestone_1')), 'Publicar campanha');
    await tester.tap(find.byKey(const Key('save_project_milestones')));
    await tester.pumpAndSettle();

    expect(projects.items.single.context,
        contains('Marco: Definir posicionamento'));
    expect(projects.items.single.context, contains('Marco: Publicar campanha'));
    expect(
        projects.items.single.context, contains('Objetivo: Lançar campanha'));
    expect(find.text('Definir posicionamento'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('project_memory_card')),
        matching: find.textContaining('Definir posicionamento'),
      ),
      findsNothing,
    );

    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );
    expect(find.text('Publicar campanha'), findsOneWidget);

    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('add_project_milestone')))
          .onPressed,
      isNotNull,
    );
    await tester.enterText(
        find.byKey(const Key('project_milestone_0')), 'Preparar campanha');
    await tester.tap(find.byKey(const Key('remove_project_milestone_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_project_milestones')));
    await tester.pumpAndSettle();
    expect(projects.items.single.context, contains('Marco: Preparar campanha'));
    expect(projects.items.single.context, isNot(contains('Publicar campanha')));
  });

  testWidgets('cancelamento duplicidade limite e erro preservam marcos',
      (tester) async {
    const original = 'Marco: Marco original\nCanal: Instagram';
    final projects = FakeProjectRepository()
      ..items = [projectSample(context: original)];
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
    );

    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_milestone_0')), 'Não salvar');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(projects.items.single.context, original);

    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('add_project_milestone')))
          .onPressed,
      isNotNull,
    );
    for (var index = 1; index < 5; index++) {
      await tester.tap(find.byKey(const Key('add_project_milestone')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(Key('project_milestone_$index')), 'Marco $index');
      await tester.pump();
    }
    final add = tester
        .widget<TextButton>(find.byKey(const Key('add_project_milestone')));
    expect(add.onPressed, isNull);
    await tester.enterText(
        find.byKey(const Key('project_milestone_1')), '  marco   original ');
    await tester.tap(find.byKey(const Key('save_project_milestones')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_milestones_error')), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    projects.updateError = const AppException('falha');
    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_milestone_0')), 'Também não salvar');
    await tester.tap(find.byKey(const Key('save_project_milestones')));
    await tester.pumpAndSettle();
    expect(projects.items.single.context, original);
    expect(find.text('Não foi possível salvar os marcos do projeto.'),
        findsOneWidget);

    projects.updateError = null;
    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('project_milestone_0')), 'Nova tentativa');
    await tester.tap(find.byKey(const Key('save_project_milestones')));
    await tester.pumpAndSettle();
    expect(projects.items.single.context, contains('Marco: Nova tentativa'));
  });

  testWidgets('Chain sem Project não cria marcos nem Project', (tester) async {
    final projects = FakeProjectRepository();
    await pumpWorkspace(
      tester,
      projects: projects,
      chains: FakePromptChainRepository()..items = [chain()],
      target: const ProjectWorkspaceTarget.chain('chain-1'),
    );

    expect(find.byKey(const Key('chain_without_project_milestones')),
        findsOneWidget);
    expect(find.byKey(const Key('edit_project_milestones')), findsNothing);
    expect(projects.items, isEmpty);
  });

  testWidgets('marcos e editor não apresentam overflow no mobile',
      (tester) async {
    await pumpWorkspace(
      tester,
      projects: FakeProjectRepository()
        ..items = [projectSample(context: 'Marco: Preparar campanha')],
      chains: FakePromptChainRepository(),
      target: const ProjectWorkspaceTarget.project('project-1'),
      size: const Size(390, 844),
    );

    await tester
        .ensureVisible(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_project_milestones')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_milestone_0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
