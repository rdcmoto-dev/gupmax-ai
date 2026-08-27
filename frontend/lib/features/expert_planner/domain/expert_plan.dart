import '../../prompts/domain/prompt_models.dart';

class ExpertPlanStep {
  const ExpertPlanStep({
    required this.position,
    required this.title,
    required this.objective,
    required this.baseInput,
    required this.category,
    required this.mode,
    required this.targetAi,
    required this.requiresPreviousResult,
  });

  factory ExpertPlanStep.fromJson(Map<String, dynamic> json) => ExpertPlanStep(
        position: json['position'] as int,
        title: json['title'] as String,
        objective: json['objective'] as String,
        baseInput: json['base_input'] as String,
        category: PromptCategory.fromValue(json['category'] as String),
        mode: PromptMode.values.byName(json['mode'] as String),
        targetAi: TargetAI.fromValue(json['target_ai'] as String),
        requiresPreviousResult:
            json['requires_previous_result'] as bool? ?? false,
      );

  final int position;
  final String title;
  final String objective;
  final String baseInput;
  final PromptCategory category;
  final PromptMode mode;
  final TargetAI targetAi;
  final bool requiresPreviousResult;

  ExpertPlanStep copyWith({
    int? position,
    String? title,
    String? objective,
    String? baseInput,
    PromptCategory? category,
    PromptMode? mode,
    TargetAI? targetAi,
  }) =>
      ExpertPlanStep(
        position: position ?? this.position,
        title: title ?? this.title,
        objective: objective ?? this.objective,
        baseInput: baseInput ?? this.baseInput,
        category: category ?? this.category,
        mode: mode ?? this.mode,
        targetAi: targetAi ?? this.targetAi,
        requiresPreviousResult:
            (baseInput ?? this.baseInput).contains('{resultado_anterior}'),
      );

  Map<String, dynamic> toStepJson() => {
        'title': title,
        'base_input': baseInput,
        'category': category.value,
        'mode': mode.name,
        'target_ai': targetAi.value,
      };
}

class ExpertPlan {
  const ExpertPlan({
    required this.summary,
    required this.suggestedName,
    required this.planningRecommended,
    required this.planType,
    required this.steps,
  });

  factory ExpertPlan.fromJson(Map<String, dynamic> json) => ExpertPlan(
        summary: json['summary'] as String,
        suggestedName: json['suggested_name'] as String,
        planningRecommended: json['planning_recommended'] as bool,
        planType: json['plan_type'] as String,
        steps: (json['steps'] as List<dynamic>)
            .map(
                (item) => ExpertPlanStep.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String summary;
  final String suggestedName;
  final bool planningRecommended;
  final String planType;
  final List<ExpertPlanStep> steps;
}
