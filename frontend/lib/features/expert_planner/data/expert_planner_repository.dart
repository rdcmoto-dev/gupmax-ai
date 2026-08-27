import '../../../core/network/api_client.dart';
import '../../prompts/domain/prompt_models.dart';
import '../domain/expert_plan.dart';

abstract interface class ExpertPlannerRepositoryContract {
  Future<ExpertPlan> plan(PromptGenerateInput input);
  Future<String> createChain({
    required String name,
    required String? projectId,
    required List<ExpertPlanStep> steps,
  });
}

class ExpertPlannerRepository implements ExpertPlannerRepositoryContract {
  const ExpertPlannerRepository(this.client);
  final ApiClient client;

  @override
  Future<ExpertPlan> plan(PromptGenerateInput input) async {
    final response = await client.dio.post<Map<String, dynamic>>(
      '/expert-planner/plan',
      data: {
        'input': input.input,
        'project_id': input.projectId,
        'category': input.category.value,
        'mode': input.mode.name,
        'target_ai': input.targetAi.value,
        'smart_answers': input.smartAnswers,
      },
    );
    return ExpertPlan.fromJson(response.data!);
  }

  @override
  Future<String> createChain({
    required String name,
    required String? projectId,
    required List<ExpertPlanStep> steps,
  }) async {
    final response = await client.dio.post<Map<String, dynamic>>(
      '/expert-planner/chains',
      data: {
        'name': name,
        'project_id': projectId,
        'steps': steps.map((step) => step.toStepJson()).toList(),
      },
    );
    return (response.data!['chain'] as Map<String, dynamic>)['id'] as String;
  }
}
