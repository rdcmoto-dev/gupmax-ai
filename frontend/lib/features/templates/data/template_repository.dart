import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/prompt_template.dart';

abstract interface class TemplateRepositoryContract {
  Future<TemplatePageData> list();
  Future<PromptTemplateRecord> get(String id);
  Future<PromptTemplateRecord> create(Map<String, dynamic> values);
  Future<PromptTemplateRecord> fromPrompt(
      String promptId, String name, String? description);
  Future<PromptTemplateRecord> update(String id, Map<String, dynamic> values);
  Future<void> delete(String id);
}

class TemplateRepository implements TemplateRepositoryContract {
  const TemplateRepository(this.client);
  final ApiClient client;

  @override
  Future<TemplatePageData> list() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>('/templates');
      return TemplatePageData.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<PromptTemplateRecord> create(Map<String, dynamic> values) async {
    try {
      final response = await client.dio
          .post<Map<String, dynamic>>('/templates', data: values);
      return PromptTemplateRecord.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<PromptTemplateRecord> get(String id) async {
    try {
      final response =
          await client.dio.get<Map<String, dynamic>>('/templates/$id');
      return PromptTemplateRecord.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<PromptTemplateRecord> fromPrompt(
      String promptId, String name, String? description) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/templates/from-prompt/$promptId',
        data: {'name': name, 'description': description},
      );
      return PromptTemplateRecord.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<PromptTemplateRecord> update(
      String id, Map<String, dynamic> values) async {
    try {
      final response = await client.dio
          .put<Map<String, dynamic>>('/templates/$id', data: values);
      return PromptTemplateRecord.fromJson(response.data!);
    } catch (error) {
      _map(error);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await client.dio.delete<void>('/templates/$id');
    } catch (error) {
      _map(error);
    }
  }

  Never _map(Object error) {
    final status = error is DioException ? error.response?.statusCode : null;
    throw AppException(
      status == 404
          ? 'Template não encontrado.'
          : 'Não foi possível concluir a operação com o template.',
      statusCode: status,
    );
  }
}
