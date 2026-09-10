import 'dart:async';

import 'package:gupmax_ai/features/project_blueprints/project_blueprints.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

import 'fake_project_repository.dart';

ProjectBlueprint blueprintSample(
        {String id = 'bp-1', String name = 'Modelo de campanha'}) =>
    ProjectBlueprint(
      id: id,
      name: name,
      description: 'Modelo reutilizável',
      category: PromptCategory.marketing,
      createdAt: DateTime.utc(2026, 9, 9),
      updatedAt: DateTime.utc(2026, 9, 9),
      structure: {
        'version': 1,
        'project_name': 'Campanha base',
        'description': 'Descrição original',
        'objective': 'Publicar campanha',
        'success_criteria': ['Material pronto'],
        'milestones': ['Publicar'],
        'context': 'Público: Famílias',
        'chains': [
          {
            'name': 'Fluxo base',
            'description': null,
            'steps': [
              {
                'title': 'Planejar',
                'base_input': 'Planeje {produto}',
                'mode': 'pro',
                'category': 'marketing',
                'target_ai': 'claude'
              }
            ]
          }
        ]
      },
    );

class FakeBlueprintRepository implements BlueprintRepositoryContract {
  List<ProjectBlueprint> items = [];
  int createCalls = 0;
  int useCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int listCalls = 0;
  String? sourceId;
  Map<String, dynamic>? lastValues;
  Completer<void>? mutation;
  Completer<void>? loading;
  Object? error;
  Object? listError;
  @override
  Future<BlueprintPageData> list({int offset = 0}) async {
    listCalls++;
    await loading?.future;
    if (listError != null) throw listError!;
    return BlueprintPageData(
        items.skip(offset).take(20).toList(), items.length);
  }

  @override
  Future<ProjectBlueprint> get(String id) async =>
      items.firstWhere((item) => item.id == id);
  Future<void> _wait() async {
    await mutation?.future;
    if (error != null) throw error!;
  }

  @override
  Future<ProjectBlueprint> create(
      String projectId, Map<String, dynamic> values) async {
    createCalls++;
    sourceId = projectId;
    lastValues = values;
    await _wait();
    final item = blueprintSample(name: values['name'] as String);
    items = [...items, item];
    return item;
  }

  @override
  Future<ProjectBlueprint> update(
      String id, Map<String, dynamic> values) async {
    updateCalls++;
    lastValues = values;
    await _wait();
    final original = await get(id);
    final item = ProjectBlueprint(
        id: id,
        name: values['name'] as String,
        description: values['description'] as String?,
        category: PromptCategory.values
            .firstWhere((v) => v.value == values['category']),
        createdAt: original.createdAt,
        updatedAt: original.updatedAt,
        structure: original.structure);
    items = [
      for (final value in items)
        if (value.id == id) item else value
    ];
    return item;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    await _wait();
    items = items.where((item) => item.id != id).toList();
  }

  @override
  Future<ProjectRecord> use(String id, String name) async {
    useCalls++;
    lastValues = {'name': name};
    await _wait();
    return projectSample(id: 'created-project', name: name);
  }
}
