import 'dart:async';

import 'package:gupmax_ai/features/projects/data/project_repository.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/project_library.dart';

class FakeProjectRepository implements ProjectRepositoryContract {
  List<ProjectRecord> items = [];
  Completer<ProjectPageData>? listCompleter;
  int assignPromptCalls = 0;
  int assignTemplateCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int createFromChainCalls = 0;
  Object? createFromChainError;
  ProjectLibraryData? libraryData;
  Future<void> Function(String chainId, String projectId)? onCreateFromChain;

  @override
  Future<ProjectPageData> list(
      {bool includeArchived = true, int limit = 20}) async {
    if (listCompleter != null) return listCompleter!.future;
    return ProjectPageData(items.take(limit).toList(), items.length);
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
  Future<ProjectRecord> createFromChain(String chainId) async {
    createFromChainCalls++;
    if (createFromChainError != null) throw createFromChainError!;
    final existing =
        items.where((item) => item.id == 'project-$chainId').firstOrNull;
    if (existing != null) return existing;
    final created = projectSample(
      id: 'project-$chainId',
      name: 'Plano de entrega',
      context: 'Execução organizada do projeto.',
    );
    items = [created, ...items];
    await onCreateFromChain?.call(chainId, created.id);
    return created;
  }

  @override
  Future<ProjectLibraryData> library(String projectId,
          {int offset = 0, int limit = 20}) async =>
      libraryData ??
      ProjectLibraryData(
          projectId: projectId,
          prompts: const [],
          promptTotal: 0,
          chains: const [],
          completedStepCount: 0,
          activity: const [],
          lastActivityAt: DateTime.utc(2026, 8, 20),
          offset: offset,
          limit: limit);

  @override
  Future<ProjectRecord> update(String id, Map<String, dynamic> values) async {
    updateCalls++;
    final current = await get(id);
    final updated = projectSample(
      id: id,
      name: values['name'] as String? ?? current.name,
      context: values.containsKey('context')
          ? values['context'] as String?
          : current.context,
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
    deleteCalls++;
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
  String? context = 'Pizzaria com delivery',
  DateTime? updatedAt,
}) =>
    ProjectRecord(
      id: id,
      name: name,
      description: 'Marketing e vendas',
      context: context,
      status: status,
      promptCount: 0,
      templateCount: 0,
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 20),
    );
