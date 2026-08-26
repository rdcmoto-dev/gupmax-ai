import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../prompts/domain/prompt_models.dart';
import '../data/intent_repository.dart';
import '../domain/intent_analysis.dart';

class IntentController extends ChangeNotifier {
  IntentController(this.repository);
  final IntentRepositoryContract repository;
  IntentAnalysis? analysis;
  bool loading = false;
  String? error;

  Future<IntentAnalysis?> analyze({
    required String input,
    required PromptMode mode,
    required TargetAI targetAi,
    String? projectId,
    String? templateId,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      analysis = await repository.analyze(
        input: input,
        mode: mode,
        targetAi: targetAi,
        projectId: projectId,
        templateId: templateId,
      );
      return analysis;
    } on AppException catch (exception) {
      error = exception.message;
      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
