import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../prompts/domain/prompt_models.dart';
import '../domain/interview_models.dart';

abstract interface class InterviewRepositoryContract {
  Future<InterviewSession> create({
    required String initialRequest,
    required PromptMode mode,
    required PromptCategory category,
  });
  Future<InterviewSession> get(String id);
  Future<InterviewSession> answer(String id, String questionKey, Object value);
  Future<InterviewCompleteResult> complete(String id);
}

class InterviewRepository implements InterviewRepositoryContract {
  const InterviewRepository(this._client);
  final ApiClient _client;

  @override
  Future<InterviewSession> create({
    required String initialRequest,
    required PromptMode mode,
    required PromptCategory category,
  }) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/interviews',
        data: {
          'initial_request': initialRequest,
          'mode': mode.name,
          'category': category.value,
        },
      );
      return InterviewSession.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<InterviewSession> get(String id) async {
    try {
      final response =
          await _client.dio.get<Map<String, dynamic>>('/interviews/$id');
      return InterviewSession.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<InterviewSession> answer(
      String id, String questionKey, Object value) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/interviews/$id/answers',
        data: {
          'answers': [
            {'question_key': questionKey, 'value': value}
          ],
        },
      );
      return InterviewSession.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<InterviewCompleteResult> complete(String id) async {
    try {
      final response = await _client.dio
          .post<Map<String, dynamic>>('/interviews/$id/complete');
      return InterviewCompleteResult.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  Never _mapError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final detail = data is Map<String, dynamic> ? data['detail'] : null;
      if (status == 404) {
        throw const AppException('Entrevista não encontrada.', statusCode: 404);
      }
      if (status == 409 && detail == 'Interview expired') {
        throw const AppException('Esta entrevista expirou.', statusCode: 409);
      }
      if (status == 409) {
        throw const AppException('A entrevista ainda não pode ser concluída.',
            statusCode: 409);
      }
      if (status == 422) {
        throw const AppException('Confira a resposta informada.',
            statusCode: 422);
      }
      if (status == 401) {
        throw const AppException('Sua sessão expirou. Entre novamente.',
            statusCode: 401);
      }
      throw AppException(
        'Não foi possível conectar ao serviço. Tente novamente.',
        statusCode: status,
      );
    }
    throw const AppException('Ocorreu um erro inesperado. Tente novamente.');
  }
}
