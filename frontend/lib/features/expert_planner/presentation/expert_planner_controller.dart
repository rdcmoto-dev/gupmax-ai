import 'package:flutter/foundation.dart';

import '../../prompts/domain/prompt_models.dart';
import '../data/expert_planner_repository.dart';
import '../domain/expert_plan.dart';

class ExpertPlannerController extends ChangeNotifier {
  ExpertPlannerController(this.repository);
  final ExpertPlannerRepositoryContract repository;

  ExpertPlan? plan;
  bool loading = false;
  bool saving = false;
  String? error;

  Future<void> load(PromptGenerateInput input) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      plan = await repository.plan(input);
    } catch (_) {
      error = 'Não foi possível criar o plano. Tente novamente.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String?> createChain({
    required String name,
    required String? projectId,
    required List<ExpertPlanStep> steps,
  }) async {
    saving = true;
    error = null;
    notifyListeners();
    try {
      return await repository.createChain(
          name: name, projectId: projectId, steps: steps);
    } catch (_) {
      error = 'Não foi possível criar o fluxo.';
      return null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
