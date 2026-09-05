import '../prompt_chains/domain/prompt_chain.dart';
import 'domain/project.dart';
import 'project_goals.dart';
import 'project_health.dart';
import 'project_memory.dart';
import 'project_milestones.dart';

class ProjectReview {
  const ProjectReview({this.conclusion, this.isClosed = false});

  static const conclusionLabel = 'Conclusão do projeto';
  static const closedLabel = 'Projeto encerrado';
  static const maxConclusionLength = 1000;

  final String? conclusion;
  final bool isClosed;

  static ProjectReview parse(String? context) {
    String? conclusion;
    var closed = false;
    for (final entry in ProjectMemory.parse(context)) {
      final label = _fold(entry.label);
      if (_conclusionLabels.contains(label) && conclusion == null) {
        conclusion = entry.value;
      } else if (label == _fold(closedLabel) && _fold(entry.value) == 'sim') {
        closed = true;
      }
    }
    return ProjectReview(conclusion: conclusion, isClosed: closed);
  }

  static bool isReviewEntry(ProjectMemoryEntry entry) {
    final label = _fold(entry.label);
    return _conclusionLabels.contains(label) || label == _fold(closedLabel);
  }

  static String? merge({
    required String? context,
    String? conclusion,
    required bool isClosed,
  }) {
    final normalized = conclusion?.trim();
    if ((normalized?.length ?? 0) > maxConclusionLength) {
      throw const FormatException(
        'A conclusão deve ter no máximo 1.000 caracteres.',
      );
    }
    final others = ProjectMemory.parse(context)
        .where((entry) => !isReviewEntry(entry))
        .toList(growable: false);
    final review = <ProjectMemoryEntry>[
      if (normalized != null && normalized.isNotEmpty)
        ProjectMemoryEntry(label: conclusionLabel, value: normalized),
      if (isClosed) const ProjectMemoryEntry(label: closedLabel, value: 'sim'),
    ];
    if (others.length + review.length > ProjectMemory.maxEntries) {
      throw const FormatException(
        'Limite de informações do projeto atingido. Remova uma informação para salvar a revisão.',
      );
    }
    return ProjectMemory.serialize([...others, ...review]);
  }

  static const _conclusionLabels = {
    'conclusao do projeto',
    'conclusao final',
    'observacoes finais',
  };

  static String _fold(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàãâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòõôö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

class ProjectReviewSummary {
  const ProjectReviewSummary({
    required this.objective,
    required this.criteriaCount,
    required this.confirmedCriteriaCount,
    required this.milestoneCount,
    required this.confirmedMilestoneCount,
    required this.completedSteps,
    required this.totalSteps,
    required this.promptCount,
    required this.health,
  });

  final String? objective;
  final int criteriaCount;
  final int confirmedCriteriaCount;
  final int milestoneCount;
  final int confirmedMilestoneCount;
  final int completedSteps;
  final int totalSteps;
  final int promptCount;
  final ProjectHealth health;

  bool get hasPendingItems =>
      confirmedCriteriaCount < criteriaCount ||
      confirmedMilestoneCount < milestoneCount ||
      completedSteps < totalSteps;
}

ProjectReviewSummary projectReviewSummaryFor({
  required ProjectRecord project,
  PromptChainRecord? chain,
}) {
  final goals = ProjectGoals.parse(project.context);
  final milestones = ProjectMilestones.parse(project.context);
  final totalSteps = chain == null
      ? 0
      : chain.steps.isEmpty
          ? chain.stepCount
          : chain.steps.length;
  return ProjectReviewSummary(
    objective: goals.objective,
    criteriaCount: goals.criteria.length,
    confirmedCriteriaCount:
        goals.criteria.where(goals.isCriterionCompleted).length,
    milestoneCount: milestones.items.length,
    confirmedMilestoneCount:
        milestones.items.where(milestones.isCompleted).length,
    completedSteps: chain?.completedStepCount ?? 0,
    totalSteps: totalSteps,
    promptCount: project.promptCount,
    health: projectHealthFor(project: project, chain: chain),
  );
}
