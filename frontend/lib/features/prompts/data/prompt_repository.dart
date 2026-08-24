import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/prompt_models.dart';

String promptGenerateErrorMessage(int? status) => switch (status) {
      400 =>
        'A solicitação de IA não pôde ser processada. Verifique provider/model ou tente novamente.',
      422 => 'Confira os dados informados.',
      401 => 'Sua sessão expirou. Entre novamente.',
      402 => 'Créditos insuficientes para otimizar com IA.',
      403 => 'A otimização com IA não está disponível para esta conta.',
      404 => 'Prompt não encontrado.',
      409 => 'A solicitação conflita com o estado atual.',
      429 => 'Limite de uso atingido. Tente novamente mais tarde.',
      502 || 503 => 'O serviço de IA está temporariamente indisponível.',
      _ => 'Não foi possível conectar ao serviço. Tente novamente.',
    };

String promptEstimateErrorMessage(int? status) => status == 404
    ? 'Não foi possível calcular a estimativa.'
    : promptGenerateErrorMessage(status);

abstract interface class PromptRepositoryContract {
  Future<PromptRecord> generate(PromptGenerateInput input);
  Future<List<MultiTargetPreview>> compare(PromptGenerateInput input);
  Future<AiCreditEstimate> estimate(PromptGenerateInput input);
  Future<PromptPageData> list({required int offset, int limit = 20});
  Future<PromptRecord> get(String id);
  Future<PromptRecord> update(String id, PromptUpdateInput input);
  Future<PromptRecord> refine(String id, PromptRefineInput input);
  Future<PromptVersionPageData> versions(String id);
  Future<PromptQualityScore> score(String id);
  Future<AiCreditEstimate> estimateRefinement(
      PromptRecord prompt, PromptRefineInput input);
  Future<void> delete(String id);
}

class PromptRepository implements PromptRepositoryContract {
  const PromptRepository(this._client);
  final ApiClient _client;

  static void _debugHttp(String method, String endpoint,
      {Response<dynamic>? response, Object? error}) {
    if (!kDebugMode) return;
    final dioError = error is DioException ? error : null;
    final status = response?.statusCode ?? dioError?.response?.statusCode;
    final data = dioError?.response?.data;
    final detail = data is Map<String, dynamic> && data['detail'] is String
        ? data['detail'] as String
        : null;
    debugPrint(
      '[prompt_http] method=$method endpoint=$endpoint '
      'status=${status ?? 'none'} detail=${detail ?? 'none'}',
    );
  }

  @override
  Future<List<MultiTargetPreview>> compare(PromptGenerateInput input) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/prompts/compare-targets',
        data: {
          ...input.toJson(),
          'optimize_with_ai': false,
          'target_ais':
              input.comparisonTargetAis.map((target) => target.value).toList(),
        },
      );
      return (response.data!['items'] as List<dynamic>)
          .map((item) =>
              MultiTargetPreview.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<PromptRecord> generate(PromptGenerateInput input) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/prompts/generate',
        data: input.toJson(),
        options: Options(headers: {
          'Idempotency-Key':
              'flutter-prompt-${DateTime.now().microsecondsSinceEpoch}',
        }),
      );
      return PromptRecord.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<AiCreditEstimate> estimate(PromptGenerateInput input) async {
    try {
      final estimatedInputTokens =
          (input.toJson().toString().length / 4).ceil();
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/credits/estimate',
        data: {
          'operation_type': 'prompt_optimization',
          'provider': input.provider,
          'model': input.model,
          'estimated_input_tokens': estimatedInputTokens,
          'max_output_tokens': 2000,
        },
      );
      _debugHttp('POST', '/credits/estimate', response: response);
      return AiCreditEstimate.fromJson(response.data!);
    } catch (error) {
      _debugHttp('POST', '/credits/estimate', error: error);
      _mapEstimateError(error);
    }
  }

  @override
  Future<AiCreditEstimate> estimateRefinement(
      PromptRecord prompt, PromptRefineInput input) async {
    try {
      final estimatedInputTokens =
          ((prompt.generatedPrompt.length + input.instruction.length) / 4)
              .ceil();
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/credits/estimate',
        data: {
          'operation_type': 'prompt_optimization',
          'provider': input.provider,
          'model': input.model,
          'estimated_input_tokens': estimatedInputTokens,
          'max_output_tokens': 2000,
        },
      );
      _debugHttp('POST', '/credits/estimate', response: response);
      return AiCreditEstimate.fromJson(response.data!);
    } catch (error) {
      _debugHttp('POST', '/credits/estimate', error: error);
      _mapEstimateError(error);
    }
  }

  @override
  Future<PromptPageData> list({required int offset, int limit = 20}) async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        '/prompts',
        queryParameters: {'offset': offset, 'limit': limit, 'order': 'desc'},
      );
      return PromptPageData.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<PromptRecord> get(String id) async {
    try {
      final response =
          await _client.dio.get<Map<String, dynamic>>('/prompts/$id');
      _debugHttp('GET', '/prompts/{id}', response: response);
      return PromptRecord.fromJson(response.data!);
    } catch (error) {
      _debugHttp('GET', '/prompts/{id}', error: error);
      _mapError(error);
    }
  }

  @override
  Future<PromptRecord> update(String id, PromptUpdateInput input) async {
    try {
      final response = await _client.dio.put<Map<String, dynamic>>(
        '/prompts/$id',
        data: input.toJson(),
      );
      return PromptRecord.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<PromptRecord> refine(String id, PromptRefineInput input) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/prompts/$id/refine',
        data: input.toJson(),
        options: Options(headers: {
          'Idempotency-Key':
              'flutter-refine-${DateTime.now().microsecondsSinceEpoch}',
        }),
      );
      _debugHttp('POST', '/prompts/{id}/refine', response: response);
      return PromptRecord.fromJson(response.data!);
    } catch (error) {
      _debugHttp('POST', '/prompts/{id}/refine', error: error);
      _mapError(error);
    }
  }

  @override
  Future<PromptVersionPageData> versions(String id) async {
    try {
      final response =
          await _client.dio.get<Map<String, dynamic>>('/prompts/$id/versions');
      _debugHttp('GET', '/prompts/{id}/versions', response: response);
      return PromptVersionPageData.fromJson(response.data!);
    } catch (error) {
      _debugHttp('GET', '/prompts/{id}/versions', error: error);
      _mapError(error);
    }
  }

  @override
  Future<PromptQualityScore> score(String id) async {
    try {
      final response =
          await _client.dio.get<Map<String, dynamic>>('/prompts/$id/score');
      return PromptQualityScore.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _client.dio.delete<void>('/prompts/$id');
    } catch (error) {
      _mapError(error);
    }
  }

  Never _mapError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final message = promptGenerateErrorMessage(status);
      throw AppException(message, statusCode: status);
    }
    throw const AppException('Ocorreu um erro inesperado. Tente novamente.');
  }

  Never _mapEstimateError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      throw AppException(promptEstimateErrorMessage(status),
          statusCode: status);
    }
    throw const AppException('Ocorreu um erro inesperado. Tente novamente.');
  }
}
