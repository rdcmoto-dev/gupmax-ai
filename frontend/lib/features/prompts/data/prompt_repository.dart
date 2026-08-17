import 'package:dio/dio.dart';

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

abstract interface class PromptRepositoryContract {
  Future<PromptRecord> generate(PromptGenerateInput input);
  Future<AiCreditEstimate> estimate(PromptGenerateInput input);
  Future<PromptPageData> list({required int offset, int limit = 20});
  Future<PromptRecord> get(String id);
  Future<PromptRecord> update(String id, PromptUpdateInput input);
  Future<void> delete(String id);
}

class PromptRepository implements PromptRepositoryContract {
  const PromptRepository(this._client);
  final ApiClient _client;

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
      return AiCreditEstimate.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
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
      return PromptRecord.fromJson(response.data!);
    } catch (error) {
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
}
