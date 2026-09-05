import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/project.dart';
import '../project_export.dart';
import '../project_library.dart';

abstract interface class ProjectRepositoryContract {
  Future<ProjectPageData> list({bool includeArchived = true, int limit = 20});
  Future<ProjectRecord> get(String id);
  Future<ProjectRecord> create(Map<String, dynamic> values);
  Future<ProjectRecord> createFromChain(String chainId);
  Future<ProjectLibraryData> library(String projectId,
      {int offset = 0, int limit = 20});
  Future<ProjectExportFile> export(
      String projectId, String projectName, ProjectExportFormat format);
  Future<ProjectRecord> update(String id, Map<String, dynamic> values);
  Future<void> delete(String id);
  Future<void> assignPrompt(String projectId, String promptId);
  Future<void> removePrompt(String projectId, String promptId);
  Future<void> assignTemplate(String projectId, String templateId);
  Future<void> removeTemplate(String projectId, String templateId);
}

class ProjectRepository implements ProjectRepositoryContract {
  const ProjectRepository(this.client);
  final ApiClient client;

  @override
  Future<ProjectPageData> list(
      {bool includeArchived = true, int limit = 20}) async {
    try {
      final response = await client.dio
          .get<Map<String, dynamic>>('/projects', queryParameters: {
        'include_archived': includeArchived,
        'limit': limit,
      });
      return ProjectPageData.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<ProjectRecord> get(String id) => _write('get', id, null);
  @override
  Future<ProjectRecord> create(Map<String, dynamic> values) =>
      _write('post', '', values);
  @override
  Future<ProjectRecord> createFromChain(String chainId) async {
    try {
      final response = await client.dio
          .post<Map<String, dynamic>>('/chains/$chainId/project');
      return ProjectRecord.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<ProjectLibraryData> library(String projectId,
      {int offset = 0, int limit = 20}) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
          '/projects/$projectId/library',
          queryParameters: {'offset': offset, 'limit': limit});
      return ProjectLibraryData.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<ProjectExportFile> export(
      String projectId, String projectName, ProjectExportFormat format) async {
    try {
      final response = await client.dio.get<List<int>>(
        '/projects/$projectId/export',
        queryParameters: {'format': format.queryValue},
        options: Options(responseType: ResponseType.bytes),
      );
      return ProjectExportFile(
        bytes: Uint8List.fromList(response.data ?? const []),
        filename: safeExportFilename(
          response.headers.value('content-disposition'),
          projectName: projectName,
          format: format,
        ),
        mimeType: response.headers.value('content-type') ?? format.mimeType,
      );
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<ProjectRecord> update(String id, Map<String, dynamic> values) =>
      _write('put', id, values);

  Future<ProjectRecord> _write(
      String method, String id, Map<String, dynamic>? values) async {
    try {
      final path = id.isEmpty ? '/projects' : '/projects/$id';
      final response = method == 'get'
          ? await client.dio.get<Map<String, dynamic>>(path)
          : method == 'post'
              ? await client.dio.post<Map<String, dynamic>>(path, data: values)
              : await client.dio.put<Map<String, dynamic>>(path, data: values);
      return ProjectRecord.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<void> delete(String id) => _association('delete', '/projects/$id');
  @override
  Future<void> assignPrompt(String projectId, String promptId) =>
      _association('put', '/projects/$projectId/prompts/$promptId');
  @override
  Future<void> removePrompt(String projectId, String promptId) =>
      _association('delete', '/projects/$projectId/prompts/$promptId');
  @override
  Future<void> assignTemplate(String projectId, String templateId) =>
      _association('put', '/projects/$projectId/templates/$templateId');
  @override
  Future<void> removeTemplate(String projectId, String templateId) =>
      _association('delete', '/projects/$projectId/templates/$templateId');

  Future<void> _association(String method, String path) async {
    try {
      if (method == 'put') {
        await client.dio.put<void>(path);
      } else {
        await client.dio.delete<void>(path);
      }
    } catch (error) {
      _map(error);
    }
  }

  Never _map(Object error) {
    final code = error is DioException ? error.response?.statusCode : null;
    throw AppException(code == 404
        ? 'Projeto não encontrado.'
        : 'Não foi possível concluir a operação com o projeto.');
  }
}
