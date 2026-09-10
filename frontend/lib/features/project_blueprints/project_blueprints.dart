import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import '../auth/auth_providers.dart';
import '../projects/domain/project.dart';
import '../prompts/domain/prompt_models.dart';

class ProjectBlueprint {
  const ProjectBlueprint(
      {required this.id,
      required this.name,
      required this.category,
      required this.createdAt,
      required this.updatedAt,
      this.description,
      this.structure});
  factory ProjectBlueprint.fromJson(Map<String, dynamic> json) =>
      ProjectBlueprint(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        category: PromptCategory.values
            .firstWhere((value) => value.value == json['category']),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        structure: json['structure'] as Map<String, dynamic>?,
      );
  final String id;
  final String name;
  final String? description;
  final PromptCategory category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? structure;
}

class BlueprintPageData {
  const BlueprintPageData(this.items, this.total);
  final List<ProjectBlueprint> items;
  final int total;
}

abstract interface class BlueprintRepositoryContract {
  Future<BlueprintPageData> list({int offset = 0});
  Future<ProjectBlueprint> get(String id);
  Future<ProjectBlueprint> create(
      String projectId, Map<String, dynamic> values);
  Future<ProjectBlueprint> update(String id, Map<String, dynamic> values);
  Future<void> delete(String id);
  Future<ProjectRecord> use(String id, String name);
}

class BlueprintRepository implements BlueprintRepositoryContract {
  const BlueprintRepository(this.client);
  final ApiClient client;
  Future<dynamic> _request(String method, String suffix,
      [Map<String, dynamic>? data]) async {
    try {
      final response = await client.dio.request<dynamic>(
          '/project-blueprints$suffix',
          data: data,
          options: Options(method: method));
      return response.data;
    } catch (_) {
      throw const AppException(
          'Não foi possível concluir a operação com o modelo. Tente novamente.');
    }
  }

  @override
  Future<BlueprintPageData> list({int offset = 0}) async {
    final data = await _request('GET', '?offset=$offset&limit=20')
        as Map<String, dynamic>;
    return BlueprintPageData(
        (data['items'] as List)
            .map((item) =>
                ProjectBlueprint.fromJson(item as Map<String, dynamic>))
            .toList(),
        data['total'] as int);
  }

  @override
  Future<ProjectBlueprint> get(String id) async => ProjectBlueprint.fromJson(
      await _request('GET', '/$id') as Map<String, dynamic>);
  @override
  Future<ProjectBlueprint> create(
          String projectId, Map<String, dynamic> values) async =>
      ProjectBlueprint.fromJson(await _request(
              'POST', '', {...values, 'source_project_id': projectId})
          as Map<String, dynamic>);
  @override
  Future<ProjectBlueprint> update(
          String id, Map<String, dynamic> values) async =>
      ProjectBlueprint.fromJson(
          await _request('PUT', '/$id', values) as Map<String, dynamic>);
  @override
  Future<void> delete(String id) async {
    await _request('DELETE', '/$id');
  }

  @override
  Future<ProjectRecord> use(String id, String name) async =>
      ProjectRecord.fromJson(await _request(
          'POST', '/$id/projects', {'name': name}) as Map<String, dynamic>);
}

final blueprintRepositoryProvider = Provider<BlueprintRepositoryContract>(
    (ref) => BlueprintRepository(ref.watch(apiClientProvider)));
final blueprintListProvider = FutureProvider.autoDispose
    .family<BlueprintPageData, int>((ref, offset) =>
        ref.watch(blueprintRepositoryProvider).list(offset: offset));
