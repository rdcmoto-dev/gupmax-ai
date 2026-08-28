import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/prompt_chain.dart';

abstract interface class PromptChainRepositoryContract {
  Future<List<PromptChainRecord>> list(
      {bool includeArchived = true, int limit = 20});
  Future<PromptChainRecord> get(String id);
  Future<PromptChainRecord> create(Map<String, dynamic> values);
  Future<PromptChainRecord> update(String id, Map<String, dynamic> values);
  Future<void> delete(String id);
  Future<PromptChainStep> addStep(String chainId, Map<String, dynamic> values);
  Future<PromptChainStep> updateStep(
      String chainId, String stepId, Map<String, dynamic> values);
  Future<void> deleteStep(String chainId, String stepId);
  Future<void> reorder(String chainId, List<String> stepIds);
  Future<PromptChainRecord> startExecution(String chainId);
  Future<PromptChainRecord> completeStep(
      String chainId, String stepId, String result);
}

class PromptChainRepository implements PromptChainRepositoryContract {
  const PromptChainRepository(this.client);
  final ApiClient client;

  @override
  Future<List<PromptChainRecord>> list(
      {bool includeArchived = true, int limit = 20}) async {
    try {
      final response = await client.dio
          .get<Map<String, dynamic>>('/chains', queryParameters: {
        'include_archived': includeArchived,
        'limit': limit,
      });
      return (response.data!['items'] as List<dynamic>)
          .map((item) =>
              PromptChainRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const AppException('Não foi possível carregar os fluxos.');
    }
  }

  @override
  Future<PromptChainRecord> get(String id) async => PromptChainRecord.fromJson(
      (await client.dio.get<Map<String, dynamic>>('/chains/$id')).data!);

  @override
  Future<PromptChainRecord> create(Map<String, dynamic> values) async =>
      PromptChainRecord.fromJson(
          (await client.dio.post<Map<String, dynamic>>('/chains', data: values))
              .data!);

  @override
  Future<PromptChainRecord> update(
          String id, Map<String, dynamic> values) async =>
      PromptChainRecord.fromJson((await client.dio
              .put<Map<String, dynamic>>('/chains/$id', data: values))
          .data!);

  @override
  Future<void> delete(String id) async => client.dio.delete('/chains/$id');

  @override
  Future<PromptChainStep> addStep(
          String chainId, Map<String, dynamic> values) async =>
      PromptChainStep.fromJson((await client.dio.post<Map<String, dynamic>>(
              '/chains/$chainId/steps',
              data: values))
          .data!);

  @override
  Future<PromptChainStep> updateStep(
          String chainId, String stepId, Map<String, dynamic> values) async =>
      PromptChainStep.fromJson((await client.dio.put<Map<String, dynamic>>(
              '/chains/$chainId/steps/$stepId',
              data: values))
          .data!);

  @override
  Future<void> deleteStep(String chainId, String stepId) async =>
      client.dio.delete('/chains/$chainId/steps/$stepId');

  @override
  Future<void> reorder(String chainId, List<String> stepIds) async => client.dio
      .put('/chains/$chainId/steps/reorder', data: {'step_ids': stepIds});

  @override
  Future<PromptChainRecord> startExecution(String chainId) async =>
      PromptChainRecord.fromJson((await client.dio
              .post<Map<String, dynamic>>('/chains/$chainId/execution/start'))
          .data!);

  @override
  Future<PromptChainRecord> completeStep(
          String chainId, String stepId, String result) async =>
      PromptChainRecord.fromJson((await client.dio.put<Map<String, dynamic>>(
              '/chains/$chainId/steps/$stepId/complete',
              data: {'result': result}))
          .data!);
}
