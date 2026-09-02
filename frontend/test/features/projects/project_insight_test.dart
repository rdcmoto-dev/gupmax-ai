import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/project_insight.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

void main() {
  ProjectRecord project({
    String? context,
    int prompts = 0,
    ProjectStatus status = ProjectStatus.active,
  }) =>
      ProjectRecord(
        id: 'project-1',
        name: 'Projeto',
        context: context,
        status: status,
        promptCount: prompts,
        templateCount: 0,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  PromptChainStep step(int position, PromptChainStepStatus status) =>
      PromptChainStep(
        id: 'step-$position',
        chainId: 'chain-1',
        position: position,
        title: 'Etapa $position',
        baseInput: 'Faça',
        mode: PromptMode.expert,
        category: PromptCategory.programming,
        targetAi: TargetAI.codingAssistant,
        executionStatus: status,
      );

  PromptChainRecord chain({
    String? projectId,
    int completed = 0,
    String? current,
    bool finished = false,
  }) {
    final steps = [
      step(
          1,
          completed >= 1
              ? PromptChainStepStatus.completed
              : current == 'step-1'
                  ? PromptChainStepStatus.inProgress
                  : PromptChainStepStatus.pending),
      step(
          2,
          completed >= 2
              ? PromptChainStepStatus.completed
              : current == 'step-2'
                  ? PromptChainStepStatus.inProgress
                  : PromptChainStepStatus.pending),
    ];
    return PromptChainRecord(
      id: 'chain-1',
      name: 'Lançamento',
      projectId: projectId,
      status: PromptChainStatus.active,
      stepCount: steps.length,
      steps: steps,
      completedStepCount: completed,
      currentStepId: current,
      executionCompleted: finished,
    );
  }

  test('projeto sem Chain e memória recomenda contexto', () {
    final insight = projectInsightFor(project: project());
    expect(insight.action, ProjectInsightAction.editContext);
    expect(insight.state, ProjectInsightState.preparing);
  });

  test('projeto com memória e sem prompts recomenda primeiro prompt', () {
    final insight =
        projectInsightFor(project: project(context: 'Público: PMEs'));
    expect(insight.action, ProjectInsightAction.createPrompt);
  });

  test('projeto com prompts recomenda revisar conteúdo', () {
    final insight = projectInsightFor(
      project: project(context: 'Público: PMEs', prompts: 2),
    );
    expect(insight.action, ProjectInsightAction.viewContent);
  });

  test('Chain pendente recomenda iniciar', () {
    expect(projectInsightFor(chain: chain()).action,
        ProjectInsightAction.startChain);
  });

  test('Chain em andamento usa a etapa atual correta', () {
    final insight = projectInsightFor(
      chain: chain(completed: 1, current: 'step-2'),
    );
    expect(insight.action, ProjectInsightAction.continueChain);
    expect(insight.recommendation, 'Continue a etapa “Etapa 2”');
    expect(insight.explanation, 'Você concluiu 1 de 2 etapas.');
  });

  test('Chain concluída sem Project abre resultado sem recomeçar', () {
    final insight = projectInsightFor(
      chain: chain(completed: 2, finished: true),
    );
    expect(insight.action, ProjectInsightAction.viewCompletedChain);
    expect(insight.state, ProjectInsightState.completed);
  });

  test('Project e Chain priorizam a execução em andamento', () {
    final insight = projectInsightFor(
      project: project(),
      chain: chain(
        projectId: 'project-1',
        completed: 1,
        current: 'step-2',
      ),
    );
    expect(insight.action, ProjectInsightAction.continueChain);
  });

  test('Chain concluída com Project recomenda conteúdo', () {
    final insight = projectInsightFor(
      project: project(),
      chain: chain(projectId: 'project-1', completed: 2, finished: true),
    );
    expect(insight.action, ProjectInsightAction.viewContent);
  });

  test('projeto arquivado fica concluído sem urgência inventada', () {
    final insight = projectInsightFor(
      project: project(status: ProjectStatus.archived),
    );
    expect(insight.action, ProjectInsightAction.none);
    expect(insight.actionLabel, isNull);
  });

  test('decisão não altera memória, progresso ou biblioteca', () {
    final originalProject = project(context: 'Canal: Site', prompts: 3);
    final originalChain = chain(completed: 1, current: 'step-2');
    final contextBefore = originalProject.context;
    final promptCountBefore = originalProject.promptCount;
    final statusesBefore =
        originalChain.steps.map((item) => item.executionStatus).toList();

    projectInsightFor(project: originalProject, chain: originalChain);

    expect(originalProject.context, contextBefore);
    expect(originalProject.promptCount, promptCountBefore);
    expect(originalChain.completedStepCount, 1);
    expect(originalChain.currentStepId, 'step-2');
    expect(originalChain.steps.map((item) => item.executionStatus),
        statusesBefore);
  });
}
