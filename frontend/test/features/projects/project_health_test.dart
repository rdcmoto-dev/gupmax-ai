import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/project_health.dart';
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
    int total = 2,
  }) {
    final steps = List.generate(total, (index) {
      final position = index + 1;
      return step(
        position,
        position <= completed
            ? PromptChainStepStatus.completed
            : current == 'step-$position'
                ? PromptChainStepStatus.inProgress
                : PromptChainStepStatus.pending,
      );
    });
    return PromptChainRecord(
      id: 'chain-1',
      name: 'Fluxo',
      projectId: projectId,
      status: PromptChainStatus.active,
      stepCount: total,
      steps: steps,
      completedStepCount: completed,
      currentStepId: current,
      executionCompleted: finished,
    );
  }

  test('Project vazio precisa de configuração', () {
    final health = projectHealthFor(project: project());
    expect(health.state, ProjectHealthState.needsSetup);
    expect(health.label, 'Configuração necessária');
  });

  test('contexto útil melhora Project para saúde boa', () {
    final health = projectHealthFor(project: project(context: 'Público: PMEs'));
    expect(health.state, ProjectHealthState.good);
    expect(health.signals.single.label, 'Contexto configurado');
  });

  test('prompts sem contexto deixam Project em atenção', () {
    final health = projectHealthFor(project: project(prompts: 2));
    expect(health.state, ProjectHealthState.attention);
    expect(health.signals.map((signal) => signal.label), [
      'Contexto ainda não configurado',
      '2 prompts associados',
    ]);
  });

  test('Chain pendente estruturada está boa', () {
    final health = projectHealthFor(chain: chain());
    expect(health.state, ProjectHealthState.good);
    expect(health.signals.single.label, 'Fluxo com 2 etapas pronto');
  });

  test('Chain parcialmente concluída usa progresso real', () {
    final health = projectHealthFor(
      chain: chain(completed: 1, current: 'step-2'),
    );
    expect(health.state, ProjectHealthState.good);
    expect(health.signals.single.label, '1 de 2 etapas concluídas');
  });

  test('Chain totalmente concluída fica concluída', () {
    final health = projectHealthFor(
      chain: chain(completed: 2, finished: true),
    );
    expect(health.state, ProjectHealthState.completed);
    expect(health.label, 'Concluído');
    expect(health.signals.first.label, '2 de 2 etapas concluídas');
  });

  test('Project e Chain são uma unidade sem indicadores duplicados', () {
    final health = projectHealthFor(
      project: project(context: 'Canal: Site', prompts: 2),
      chain: chain(
        projectId: 'project-1',
        completed: 1,
        current: 'step-2',
      ),
    );
    expect(health.state, ProjectHealthState.good);
    expect(health.signals.map((signal) => signal.label), [
      'Contexto configurado',
      '1 de 2 etapas concluídas',
      '2 prompts associados',
    ]);
    expect(health.signals.map((signal) => signal.label).toSet(),
        hasLength(health.signals.length));
  });

  test('Chain independente não trata memória inexistente como problema', () {
    final health = projectHealthFor(
      chain: chain(completed: 1, current: 'step-2'),
    );
    expect(health.state, ProjectHealthState.good);
    expect(health.signals.any((signal) => signal.label.contains('Contexto')),
        isFalse);
  });

  test('saúde é read-only e não altera Project nem Chain', () {
    final originalProject = project(context: 'Canal: Site', prompts: 3);
    final originalChain = chain(completed: 1, current: 'step-2');
    final contextBefore = originalProject.context;
    final statusesBefore =
        originalChain.steps.map((item) => item.executionStatus).toList();

    projectHealthFor(project: originalProject, chain: originalChain);

    expect(originalProject.context, contextBefore);
    expect(originalProject.promptCount, 3);
    expect(originalChain.completedStepCount, 1);
    expect(originalChain.currentStepId, 'step-2');
    expect(originalChain.steps.map((item) => item.executionStatus),
        statusesBefore);
  });

  test('mesma entrada produz exatamente a mesma saída', () {
    final inputProject = project(context: 'Público: PMEs', prompts: 4);
    final inputChain = chain(completed: 1, current: 'step-2');
    expect(
      projectHealthFor(project: inputProject, chain: inputChain),
      projectHealthFor(project: inputProject, chain: inputChain),
    );
  });

  test('saúde nunca apresenta mais de três indicadores', () {
    final health = projectHealthFor(
      project: project(context: 'Público: PMEs', prompts: 5),
      chain: chain(projectId: 'project-1', completed: 2, finished: true),
    );
    expect(health.signals.length, lessThanOrEqualTo(ProjectHealth.maxSignals));
  });
}
