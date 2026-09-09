import '../prompt_chains/domain/prompt_chain.dart';
import 'domain/project.dart';
import 'project_overview.dart';
import 'project_review.dart';

enum ProjectListFilter { all, inProgress, completed, closed, archived }

extension ProjectListFilterLabel on ProjectListFilter {
  String get label => switch (this) {
        ProjectListFilter.all => 'Todos',
        ProjectListFilter.inProgress => 'Em andamento',
        ProjectListFilter.completed => 'Concluídos',
        ProjectListFilter.closed => 'Encerrados',
        ProjectListFilter.archived => 'Arquivados',
      };
}

enum ProjectListOrder { recent, oldest, nameAscending, nameDescending }

extension ProjectListOrderLabel on ProjectListOrder {
  String get label => switch (this) {
        ProjectListOrder.recent => 'Mais recentes',
        ProjectListOrder.oldest => 'Mais antigos',
        ProjectListOrder.nameAscending => 'Nome A–Z',
        ProjectListOrder.nameDescending => 'Nome Z–A',
      };
}

ProjectListFilter projectListState(ProjectOverview item) {
  final archived = item.project?.status == ProjectStatus.archived ||
      item.chain?.status == PromptChainStatus.archived;
  if (archived) return ProjectListFilter.archived;
  if (item.project != null &&
      ProjectReview.parse(item.project!.context).isClosed) {
    return ProjectListFilter.closed;
  }
  if (item.chain?.executionCompleted ?? false) {
    return ProjectListFilter.completed;
  }
  return ProjectListFilter.inProgress;
}

List<ProjectOverview> organizeProjects(
  Iterable<ProjectOverview> source, {
  String search = '',
  ProjectListFilter filter = ProjectListFilter.all,
  ProjectListOrder order = ProjectListOrder.recent,
}) {
  final query = _searchText(search);
  final items = source
      .where((item) => query.isEmpty || _searchText(item.name).contains(query))
      .where((item) =>
          filter == ProjectListFilter.all || projectListState(item) == filter)
      .toList();
  int stableName(ProjectOverview left, ProjectOverview right) {
    final byName = _searchText(left.name).compareTo(_searchText(right.name));
    return byName != 0 ? byName : left.key.compareTo(right.key);
  }

  items.sort((left, right) {
    final result = switch (order) {
      ProjectListOrder.recent => right.recentAt.compareTo(left.recentAt),
      ProjectListOrder.oldest => left.recentAt.compareTo(right.recentAt),
      ProjectListOrder.nameAscending => stableName(left, right),
      ProjectListOrder.nameDescending => stableName(right, left),
    };
    return result != 0 ? result : stableName(left, right);
  });
  return items;
}

String _searchText(String value) =>
    value.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
