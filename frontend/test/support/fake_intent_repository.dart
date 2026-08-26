import 'package:gupmax_ai/features/intent_engine/data/intent_repository.dart';
import 'package:gupmax_ai/features/intent_engine/domain/intent_analysis.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

class FakeIntentRepository implements IntentRepositoryContract {
  IntentAnalysis result = const IntentAnalysis(
    summary: 'Criar anúncio para vender tênis no Instagram',
    intent: 'sales',
    suggestedCategory: PromptCategory.marketing,
    detectedEntities: {'product': 'tênis feminino', 'platform': 'Instagram'},
    missingInformation: ['audience', 'offer_details'],
    suggestedQuestions: [
      IntentQuestion(key: 'audience', label: 'Qual é o público-alvo?'),
      IntentQuestion(key: 'offer_details', label: 'Quais são os diferenciais?'),
    ],
    confidence: 0.9,
  );
  int calls = 0;
  PromptMode? mode;
  TargetAI? targetAi;
  String? projectId;
  String? templateId;

  @override
  Future<IntentAnalysis> analyze({
    required String input,
    required PromptMode mode,
    required TargetAI targetAi,
    String? projectId,
    String? templateId,
  }) async {
    calls++;
    this.mode = mode;
    this.targetAi = targetAi;
    this.projectId = projectId;
    this.templateId = templateId;
    return result;
  }
}
