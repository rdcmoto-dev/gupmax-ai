import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../prompts/domain/prompt_models.dart';
import '../domain/intent_analysis.dart';

abstract interface class IntentRepositoryContract {
  Future<IntentAnalysis> analyze({
    required String input,
    required PromptMode mode,
    required TargetAI targetAi,
    String? projectId,
    String? templateId,
  });
}

class IntentRepository implements IntentRepositoryContract {
  const IntentRepository(this.client);
  final ApiClient client;

  @override
  Future<IntentAnalysis> analyze({
    required String input,
    required PromptMode mode,
    required TargetAI targetAi,
    String? projectId,
    String? templateId,
  }) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/intent/analyze',
        data: {
          'input': input,
          'mode': mode.name,
          'target_ai': targetAi.value,
          if (projectId != null) 'project_id': projectId,
          if (templateId != null) 'template_id': templateId,
        },
      );
      return IntentAnalysis.fromJson(response.data!);
    } catch (_) {
      throw const AppException('Não foi possível entender sua ideia.');
    }
  }
}
