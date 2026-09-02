import '../prompt_chains/domain/prompt_chain.dart';
import 'domain/project.dart';
import 'project_memory.dart';

enum ProjectInsightAction {
  continueChain,
  startChain,
  editContext,
  createPrompt,
  viewContent,
  viewCompletedChain,
  none,
}

enum ProjectInsightState { preparing, inProgress, completed }

class ProjectInsight {
  const ProjectInsight({
    required this.state,
    required this.recommendation,
    required this.explanation,
    required this.action,
    required this.actionLabel,
  });

  final ProjectInsightState state;
  final String recommendation;
  final String explanation;
  final ProjectInsightAction action;
  final String? actionLabel;
}

/// Chooses the next useful action exclusively from already-loaded project data.
///
/// Priority: active execution, pending execution, missing context, first prompt,
/// completed execution, existing content, completed/archived project.
ProjectInsight projectInsightFor({
  ProjectRecord? project,
  PromptChainRecord? chain,
}) {
  assert(project != null || chain != null);

  if (chain != null && !chain.executionCompleted) {
    final pending =
        chain.completedStepCount == 0 && chain.currentStepId == null;
    if (!pending) {
      final current = chain.steps
          .where((step) => step.id == chain.currentStepId)
          .firstOrNull;
      return ProjectInsight(
        state: ProjectInsightState.inProgress,
        recommendation: current == null
            ? 'Continue o projeto'
            : 'Continue a etapa “${current.title}”',
        explanation:
            'Você concluiu ${chain.completedStepCount} de ${_total(chain)} etapas.',
        action: ProjectInsightAction.continueChain,
        actionLabel: 'Continuar projeto',
      );
    }
    return ProjectInsight(
      state: ProjectInsightState.preparing,
      recommendation: 'Inicie o fluxo “${chain.name}”',
      explanation: 'As ${_total(chain)} etapas estão prontas para começar.',
      action: ProjectInsightAction.startChain,
      actionLabel: 'Iniciar projeto',
    );
  }

  if (chain == null && project != null) {
    if (project.status == ProjectStatus.archived) {
      return const ProjectInsight(
        state: ProjectInsightState.completed,
        recommendation: 'Projeto concluído',
        explanation: 'Não há uma próxima ação pendente.',
        action: ProjectInsightAction.none,
        actionLabel: null,
      );
    }
    if (ProjectMemory.parse(project.context).isEmpty) {
      return const ProjectInsight(
        state: ProjectInsightState.preparing,
        recommendation: 'Adicione contexto ao projeto',
        explanation: 'O projeto ainda não possui informações salvas.',
        action: ProjectInsightAction.editContext,
        actionLabel: 'Editar contexto',
      );
    }
    if (project.promptCount == 0) {
      return const ProjectInsight(
        state: ProjectInsightState.preparing,
        recommendation: 'Crie o primeiro prompt deste projeto',
        explanation: 'O contexto está pronto para apoiar um novo prompt.',
        action: ProjectInsightAction.createPrompt,
        actionLabel: 'Criar prompt',
      );
    }
  }

  if (chain?.executionCompleted ?? false) {
    return ProjectInsight(
      state: ProjectInsightState.completed,
      recommendation: 'Revise o conteúdo concluído',
      explanation:
          'Todas as ${_total(chain!)} etapas do fluxo foram concluídas.',
      action: project == null
          ? ProjectInsightAction.viewCompletedChain
          : ProjectInsightAction.viewContent,
      actionLabel: project == null ? 'Ver projeto concluído' : 'Ver conteúdo',
    );
  }

  return const ProjectInsight(
    state: ProjectInsightState.inProgress,
    recommendation: 'Revise o conteúdo do projeto',
    explanation: 'O projeto já possui prompts associados.',
    action: ProjectInsightAction.viewContent,
    actionLabel: 'Ver conteúdo',
  );
}

int _total(PromptChainRecord chain) =>
    chain.steps.isEmpty ? chain.stepCount : chain.steps.length;
