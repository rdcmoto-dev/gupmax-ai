import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../prompt_chains/domain/prompt_chain.dart';
import '../prompt_chains/prompt_chain_providers.dart';
import 'domain/project.dart';
import 'project_providers.dart';
import 'project_review.dart';

class ProjectOverviewQuery {
  const ProjectOverviewQuery({this.limit, this.includeArchived = false});

  final int? limit;
  final bool includeArchived;

  @override
  bool operator ==(Object other) =>
      other is ProjectOverviewQuery &&
      other.limit == limit &&
      other.includeArchived == includeArchived;

  @override
  int get hashCode => Object.hash(limit, includeArchived);
}

final projectOverviewsProvider = FutureProvider.autoDispose
    .family<List<ProjectOverview>, ProjectOverviewQuery>((ref, query) async {
  final results = await Future.wait([
    ref.read(projectRepositoryProvider).list(
          includeArchived: query.includeArchived,
          limit: query.limit ?? 100,
        ),
    ref.read(promptChainRepositoryProvider).list(
          includeArchived: query.includeArchived,
          limit: 100,
        ),
  ]);
  return composeProjectOverviews(
    projects: (results[0] as ProjectPageData).items,
    chains: results[1] as List<PromptChainRecord>,
    limit: query.limit,
  );
});

List<ProjectOverview> composeProjectOverviews({
  required List<ProjectRecord> projects,
  required List<PromptChainRecord> chains,
  int? limit,
}) {
  final usedChains = <String>{};
  final items = <ProjectOverview>[];
  for (final project in projects) {
    final associated =
        chains.where((chain) => chain.projectId == project.id).firstOrNull;
    if (associated != null) usedChains.add(associated.id);
    items.add(ProjectOverview(project: project, chain: associated));
  }
  items.addAll(
    chains
        .where((chain) => !usedChains.contains(chain.id))
        .map((chain) => ProjectOverview(chain: chain)),
  );
  items.sort((left, right) => right.recentAt.compareTo(left.recentAt));
  return limit == null ? items : items.take(limit).toList();
}

class ProjectOverview {
  const ProjectOverview({this.project, this.chain})
      : assert(project != null || chain != null);

  final ProjectRecord? project;
  final PromptChainRecord? chain;

  String get key => project?.id ?? chain!.id;
  String get name => project?.name ?? chain!.name;
  DateTime get recentAt {
    final projectDate = project?.updatedAt;
    final chainDate = chain?.updatedAt;
    if (projectDate == null) {
      return chainDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (chainDate == null || projectDate.isAfter(chainDate)) return projectDate;
    return chainDate;
  }

  String get statusLabel {
    if (project != null && ProjectReview.parse(project!.context).isClosed) {
      return 'Encerrado';
    }
    final value = chain;
    if (value == null) {
      return project!.status == ProjectStatus.archived ? 'Arquivado' : 'Ativo';
    }
    if (value.executionCompleted) return 'Concluído';
    if (value.completedStepCount > 0 || value.currentStepId != null) {
      return 'Em andamento';
    }
    return 'Pendente';
  }

  String? get progressLabel => chain == null
      ? null
      : '${chain!.completedStepCount} de ${chain!.stepCount} etapas';
  String? get categoryLabel => chain?.category?.label;
  bool get canContinue =>
      !(project != null && ProjectReview.parse(project!.context).isClosed) &&
      chain != null &&
      !chain!.executionCompleted &&
      (chain!.completedStepCount > 0 || chain!.currentStepId != null);
  String get route => project != null
      ? '/projects/${project!.id}'
      : '/project-workspace/chains/${chain!.id}';
}
