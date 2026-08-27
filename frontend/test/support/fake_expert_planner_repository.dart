import 'dart:async';

import 'package:gupmax_ai/features/expert_planner/data/expert_planner_repository.dart';
import 'package:gupmax_ai/features/expert_planner/domain/expert_plan.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

class FakeExpertPlannerRepository implements ExpertPlannerRepositoryContract {
  ExpertPlan result = ExpertPlan(
    summary: 'Criar aplicativo',
    suggestedName: 'Aplicativo delivery',
    planningRecommended: true,
    planType: 'software',
    steps: [
      step(1, 'Definir requisitos'),
      step(2, 'Projetar arquitetura', previous: true),
      step(3, 'Definir testes', previous: true),
    ],
  );
  Completer<ExpertPlan>? planCompleter;
  int planCalls = 0;
  int createCalls = 0;
  bool failPlanning = false;
  String? createdName;
  String? createdProjectId;
  List<ExpertPlanStep> createdSteps = [];

  static ExpertPlanStep step(int position, String title,
          {bool previous = false}) =>
      ExpertPlanStep(
        position: position,
        title: title,
        objective: 'Objetivo de $title',
        baseInput:
            'Execute $title${previous ? ' com {resultado_anterior}' : ''}',
        category: PromptCategory.programming,
        mode: PromptMode.expert,
        targetAi: TargetAI.codingAssistant,
        requiresPreviousResult: previous,
      );

  @override
  Future<ExpertPlan> plan(PromptGenerateInput input) async {
    planCalls++;
    if (failPlanning) throw Exception('Falha controlada');
    return planCompleter?.future ?? result;
  }

  @override
  Future<String> createChain({
    required String name,
    required String? projectId,
    required List<ExpertPlanStep> steps,
  }) async {
    createCalls++;
    createdName = name;
    createdProjectId = projectId;
    createdSteps = [...steps];
    return 'created-chain';
  }
}
