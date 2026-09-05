import '../prompt_chains/domain/prompt_chain.dart';
import 'domain/project.dart';
import 'project_memory.dart';
import 'project_milestones.dart';
import 'project_review.dart';

enum ProjectHealthState { good, attention, needsSetup, completed }

enum ProjectHealthSignalKind { positive, attention }

class ProjectHealthSignal {
  const ProjectHealthSignal(this.label, this.kind);

  final String label;
  final ProjectHealthSignalKind kind;

  @override
  bool operator ==(Object other) =>
      other is ProjectHealthSignal &&
      other.label == label &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(label, kind);
}

class ProjectHealth {
  const ProjectHealth({required this.state, required this.signals})
      : assert(signals.length <= maxSignals);

  static const maxSignals = 3;

  final ProjectHealthState state;
  final List<ProjectHealthSignal> signals;

  String get label => switch (state) {
        ProjectHealthState.good => 'Boa',
        ProjectHealthState.attention => 'Atenção',
        ProjectHealthState.needsSetup => 'Configuração necessária',
        ProjectHealthState.completed => 'Concluído',
      };

  @override
  bool operator ==(Object other) =>
      other is ProjectHealth &&
      other.state == state &&
      _sameSignals(other.signals, signals);

  @override
  int get hashCode => Object.hash(state, Object.hashAll(signals));
}

/// Derives a conservative, read-only health summary from workspace data.
ProjectHealth projectHealthFor({
  ProjectRecord? project,
  PromptChainRecord? chain,
}) {
  assert(project != null || chain != null);
  final signals = <ProjectHealthSignal>[];
  final totalSteps = chain == null
      ? 0
      : chain.steps.isEmpty
          ? chain.stepCount
          : chain.steps.length;
  final hasContext = project != null &&
      ProjectMemory.parse(project.context).any((entry) =>
          !ProjectMilestones.isMilestoneEntry(entry) &&
          !ProjectReview.isReviewEntry(entry));
  final hasPrompts = project != null && project.promptCount > 0;

  void add(String label, ProjectHealthSignalKind kind) {
    if (signals.length < ProjectHealth.maxSignals &&
        !signals.any((signal) => signal.label == label)) {
      signals.add(ProjectHealthSignal(label, kind));
    }
  }

  if (chain?.executionCompleted ?? false) {
    add(
      '${chain!.completedStepCount} de $totalSteps etapas concluídas',
      ProjectHealthSignalKind.positive,
    );
    if (hasPrompts) {
      add(_promptLabel(project.promptCount), ProjectHealthSignalKind.positive);
    }
    add(
      project == null
          ? 'Fluxo pronto para revisão'
          : 'Projeto pronto para revisão',
      ProjectHealthSignalKind.positive,
    );
    return ProjectHealth(
      state: ProjectHealthState.completed,
      signals: List.unmodifiable(signals),
    );
  }

  if (chain == null && project!.status == ProjectStatus.archived) {
    if (hasContext) {
      add('Contexto configurado', ProjectHealthSignalKind.positive);
    }
    if (hasPrompts) {
      add(_promptLabel(project.promptCount), ProjectHealthSignalKind.positive);
    }
    add('Projeto pronto para revisão', ProjectHealthSignalKind.positive);
    return ProjectHealth(
      state: ProjectHealthState.completed,
      signals: List.unmodifiable(signals),
    );
  }

  if (project == null) {
    if (totalSteps == 0) {
      add(
        'Fluxo ainda não possui etapas',
        ProjectHealthSignalKind.attention,
      );
      return ProjectHealth(
        state: ProjectHealthState.needsSetup,
        signals: List.unmodifiable(signals),
      );
    }
    _addChainSignal(add, chain!, totalSteps);
    return ProjectHealth(
      state: ProjectHealthState.good,
      signals: List.unmodifiable(signals),
    );
  }

  if (chain == null && !hasContext && !hasPrompts) {
    add(
      'Adicione contexto ou crie o primeiro conteúdo',
      ProjectHealthSignalKind.attention,
    );
    return ProjectHealth(
      state: ProjectHealthState.needsSetup,
      signals: List.unmodifiable(signals),
    );
  }

  add(
    hasContext ? 'Contexto configurado' : 'Contexto ainda não configurado',
    hasContext
        ? ProjectHealthSignalKind.positive
        : ProjectHealthSignalKind.attention,
  );
  if (chain != null) _addChainSignal(add, chain, totalSteps);
  if (hasPrompts) {
    add(_promptLabel(project.promptCount), ProjectHealthSignalKind.positive);
  }

  return ProjectHealth(
    state: hasContext ? ProjectHealthState.good : ProjectHealthState.attention,
    signals: List.unmodifiable(signals),
  );
}

void _addChainSignal(
  void Function(String, ProjectHealthSignalKind) add,
  PromptChainRecord chain,
  int totalSteps,
) {
  if (chain.completedStepCount > 0 || chain.currentStepId != null) {
    add(
      '${chain.completedStepCount} de $totalSteps etapas concluídas',
      ProjectHealthSignalKind.positive,
    );
  } else {
    add(
      'Fluxo com $totalSteps etapas pronto',
      ProjectHealthSignalKind.positive,
    );
  }
}

String _promptLabel(int count) =>
    count == 1 ? '1 prompt associado' : '$count prompts associados';

bool _sameSignals(
  List<ProjectHealthSignal> left,
  List<ProjectHealthSignal> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
