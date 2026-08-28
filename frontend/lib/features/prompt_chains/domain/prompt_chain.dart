import '../../prompts/domain/prompt_models.dart';
import '../../templates/domain/prompt_template.dart';

enum PromptChainStatus { active, archived }

enum PromptChainStepStatus { pending, inProgress, completed }

PromptChainStepStatus _stepStatus(String? value) => switch (value) {
      'in_progress' => PromptChainStepStatus.inProgress,
      'completed' => PromptChainStepStatus.completed,
      _ => PromptChainStepStatus.pending,
    };

class PromptChainStep {
  const PromptChainStep({
    required this.id,
    required this.chainId,
    required this.position,
    required this.title,
    required this.baseInput,
    required this.mode,
    required this.category,
    required this.targetAi,
    this.templateId,
    this.variables = const [],
    this.requiresPreviousResult = false,
    this.executionStatus = PromptChainStepStatus.pending,
    this.result,
    this.startedAt,
    this.completedAt,
  });

  factory PromptChainStep.fromJson(Map<String, dynamic> json) {
    final baseInput = json['base_input'] as String;
    final detected = detectTemplateVariables(baseInput);
    return PromptChainStep(
      id: json['id'] as String,
      chainId: json['chain_id'] as String,
      position: json['position'] as int,
      title: json['title'] as String,
      baseInput: baseInput,
      mode: PromptMode.values.byName(json['mode'] as String),
      category: PromptCategory.fromValue(json['category'] as String),
      targetAi: TargetAI.fromValue(json['target_ai'] as String?),
      templateId: json['template_id'] as String?,
      variables: (json['variables'] as List<dynamic>? ?? detected)
          .map((value) => value is TemplateVariable
              ? value
              : TemplateVariable.fromJson(value as Map<String, dynamic>))
          .where((variable) => variable.name != 'resultado_anterior')
          .toList(),
      requiresPreviousResult:
          detected.any((variable) => variable.name == 'resultado_anterior'),
      executionStatus: _stepStatus(json['execution_status'] as String?),
      result: json['result'] as String?,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
    );
  }

  final String id;
  final String chainId;
  final int position;
  final String title;
  final String baseInput;
  final PromptMode mode;
  final PromptCategory category;
  final TargetAI targetAi;
  final String? templateId;
  final List<TemplateVariable> variables;
  final bool requiresPreviousResult;
  final PromptChainStepStatus executionStatus;
  final String? result;
  final DateTime? startedAt;
  final DateTime? completedAt;
}

class PromptChainRecord {
  const PromptChainRecord({
    required this.id,
    required this.name,
    required this.status,
    required this.stepCount,
    this.description,
    this.projectId,
    this.steps = const [],
    this.completedStepCount = 0,
    this.currentStepId,
    this.executionCompleted = false,
    this.createdAt,
    this.updatedAt,
    this.category,
  });

  factory PromptChainRecord.fromJson(Map<String, dynamic> json) =>
      PromptChainRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        projectId: json['project_id'] as String?,
        status: PromptChainStatus.values.byName(json['status'] as String),
        stepCount: json['step_count'] as int? ?? 0,
        steps: (json['steps'] as List<dynamic>? ?? const [])
            .map((value) =>
                PromptChainStep.fromJson(value as Map<String, dynamic>))
            .toList(),
        completedStepCount: json['completed_step_count'] as int? ?? 0,
        currentStepId: json['current_step_id'] as String?,
        executionCompleted: json['execution_completed'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
        category: json['category'] == null
            ? null
            : PromptCategory.fromValue(json['category'] as String),
      );

  final String id;
  final String name;
  final String? description;
  final String? projectId;
  final PromptChainStatus status;
  final int stepCount;
  final List<PromptChainStep> steps;
  final int completedStepCount;
  final String? currentStepId;
  final bool executionCompleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final PromptCategory? category;
}
