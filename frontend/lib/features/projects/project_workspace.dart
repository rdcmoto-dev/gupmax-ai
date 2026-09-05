import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../prompt_chains/domain/prompt_chain.dart';
import '../prompt_chains/prompt_chain_providers.dart';
import 'domain/project.dart';
import 'project_providers.dart';
import 'project_review.dart';

enum ProjectWorkspaceKind { project, chain }

class ProjectWorkspaceTarget {
  const ProjectWorkspaceTarget.project(this.id)
      : kind = ProjectWorkspaceKind.project;
  const ProjectWorkspaceTarget.chain(this.id)
      : kind = ProjectWorkspaceKind.chain;

  final ProjectWorkspaceKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ProjectWorkspaceTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

class ProjectWorkspaceData {
  const ProjectWorkspaceData({this.project, this.chain})
      : assert(project != null || chain != null);

  final ProjectRecord? project;
  final PromptChainRecord? chain;

  String get name => project?.name ?? chain!.name;
  String? get description => project?.description ?? chain?.description;
  String? get context => project?.context;
  String? get categoryLabel => chain?.category?.label;

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
    return 'Não iniciado';
  }

  DateTime? get recentAt {
    final projectDate = project?.updatedAt;
    final chainDate = chain?.updatedAt;
    if (projectDate == null) return chainDate;
    if (chainDate == null || projectDate.isAfter(chainDate)) return projectDate;
    return chainDate;
  }
}

final projectWorkspaceProvider = FutureProvider.autoDispose
    .family<ProjectWorkspaceData, ProjectWorkspaceTarget>((ref, target) async {
  final projects = ref.read(projectRepositoryProvider);
  final chains = ref.read(promptChainRepositoryProvider);

  if (target.kind == ProjectWorkspaceKind.chain) {
    final chain = await chains.get(target.id);
    final project =
        chain.projectId == null ? null : await projects.get(chain.projectId!);
    return ProjectWorkspaceData(project: project, chain: chain);
  }

  final project = await projects.get(target.id);
  List<PromptChainRecord> summaries;
  try {
    summaries = await chains.list(includeArchived: true, limit: 100);
  } catch (_) {
    summaries = const [];
  }
  final summary =
      summaries.where((chain) => chain.projectId == project.id).firstOrNull;
  final chain = summary == null ? null : await chains.get(summary.id);
  return ProjectWorkspaceData(project: project, chain: chain);
});
