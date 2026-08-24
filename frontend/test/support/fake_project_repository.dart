import 'dart:async';

import 'package:gupmax_ai/features/projects/data/project_repository.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';

class FakeProjectRepository implements ProjectRepositoryContract {
  List<ProjectRecord> items = [];
  Completer<ProjectPageData>? listCompleter;
  int assignPromptCalls = 0;
  int assignTemplateCalls = 0;

  @override
  Future<ProjectPageData> list({bool includeArchived = true}) async {
    if (listCompleter != null) return listCompleter!.future;
    return ProjectPageData(items, items.length);
  }

  @override
  Future<ProjectRecord> get(String id) async =>
      items.firstWhere((item) => item.id == id);

  @override
  Future<ProjectRecord> create(Map<String, dynamic> values) async {
    final created = projectSample(name: values['name'] as String);
    items = [created, ...items];
    return created;
  }

  @override
  Future<ProjectRecord> update(String id, Map<String, dynamic> values) async {
    final current = await get(id);
    final updated = projectSample(
      id: id,
      name: values['name'] as String? ?? current.name,
      status: values['status'] == null
          ? current.status
          : ProjectStatus.values.byName(values['status'] as String),
    );
    items = [
      for (final item in items)
        if (item.id == id) updated else item
    ];
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    items = items.where((item) => item.id != id).toList();
  }

  @override
  Future<void> assignPrompt(String projectId, String promptId) async {
    assignPromptCalls++;
  }

  @override
  Future<void> removePrompt(String projectId, String promptId) async {}
  @override
  Future<void> assignTemplate(String projectId, String templateId) async {
    assignTemplateCalls++;
  }

  @override
  Future<void> removeTemplate(String projectId, String templateId) async {}
}

ProjectRecord projectSample({
  String id = 'project-1',
  String name = 'Pizzaria Donatello',
  ProjectStatus status = ProjectStatus.active,
}) =>
    ProjectRecord(
      id: id,
      name: name,
      description: 'Marketing e vendas',
      context: 'Pizzaria com delivery',
      status: status,
      promptCount: 0,
      templateCount: 0,
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20),
    );
