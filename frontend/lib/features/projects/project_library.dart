import '../prompts/domain/prompt_models.dart';

class ProjectLibraryPrompt {
  const ProjectLibraryPrompt(
      {required this.id,
      required this.title,
      required this.category,
      required this.mode,
      required this.targetAi,
      required this.versionCount,
      required this.updatedAt});
  factory ProjectLibraryPrompt.fromJson(Map<String, dynamic> json) =>
      ProjectLibraryPrompt(
          id: json['id'] as String,
          title: json['title'] as String,
          category: PromptCategory.fromValue(json['category'] as String),
          mode: PromptMode.values.byName(json['mode'] as String),
          targetAi: TargetAI.fromValue(json['target_ai'] as String),
          versionCount: json['version_count'] as int,
          updatedAt: DateTime.parse(json['updated_at'] as String));
  final String id;
  final String title;
  final PromptCategory category;
  final PromptMode mode;
  final TargetAI targetAi;
  final int versionCount;
  final DateTime updatedAt;
}

class ProjectLibraryStep {
  const ProjectLibraryStep(
      {required this.id,
      required this.position,
      required this.title,
      required this.status,
      required this.hasResult,
      this.resultPreview});
  factory ProjectLibraryStep.fromJson(Map<String, dynamic> json) =>
      ProjectLibraryStep(
          id: json['id'] as String,
          position: json['position'] as int,
          title: json['title'] as String,
          status: json['status'] as String,
          hasResult: json['has_result'] as bool,
          resultPreview: json['result_preview'] as String?);
  final String id;
  final int position;
  final String title;
  final String status;
  final bool hasResult;
  final String? resultPreview;
}

class ProjectLibraryChain {
  const ProjectLibraryChain(
      {required this.id,
      required this.name,
      required this.completedCount,
      required this.stepCount,
      required this.steps,
      this.currentStepId});
  factory ProjectLibraryChain.fromJson(Map<String, dynamic> json) =>
      ProjectLibraryChain(
          id: json['id'] as String,
          name: json['name'] as String,
          completedCount: json['completed_count'] as int,
          stepCount: json['step_count'] as int,
          currentStepId: json['current_step_id'] as String?,
          steps: (json['steps'] as List<dynamic>)
              .map((item) =>
                  ProjectLibraryStep.fromJson(item as Map<String, dynamic>))
              .toList());
  final String id;
  final String name;
  final int completedCount;
  final int stepCount;
  final String? currentStepId;
  final List<ProjectLibraryStep> steps;
}

class ProjectActivity {
  const ProjectActivity(this.label, this.occurredAt);
  factory ProjectActivity.fromJson(Map<String, dynamic> json) =>
      ProjectActivity(json['label'] as String,
          DateTime.parse(json['occurred_at'] as String));
  final String label;
  final DateTime occurredAt;
}

class ProjectLibraryData {
  const ProjectLibraryData(
      {required this.projectId,
      required this.prompts,
      required this.promptTotal,
      required this.chains,
      required this.completedStepCount,
      required this.activity,
      required this.lastActivityAt,
      required this.offset,
      required this.limit});
  factory ProjectLibraryData.fromJson(Map<String, dynamic> json) =>
      ProjectLibraryData(
          projectId: json['project_id'] as String,
          prompts: (json['prompts'] as List<dynamic>)
              .map((item) =>
                  ProjectLibraryPrompt.fromJson(item as Map<String, dynamic>))
              .toList(),
          promptTotal: json['prompt_total'] as int,
          offset: json['offset'] as int,
          limit: json['limit'] as int,
          chains: (json['chains'] as List<dynamic>)
              .map((item) =>
                  ProjectLibraryChain.fromJson(item as Map<String, dynamic>))
              .toList(),
          completedStepCount: json['completed_step_count'] as int,
          activity: (json['activity'] as List<dynamic>)
              .map((item) =>
                  ProjectActivity.fromJson(item as Map<String, dynamic>))
              .toList(),
          lastActivityAt: DateTime.parse(json['last_activity_at'] as String));
  final String projectId;
  final List<ProjectLibraryPrompt> prompts;
  final int promptTotal;
  final int offset;
  final int limit;
  final List<ProjectLibraryChain> chains;
  final int completedStepCount;
  final List<ProjectActivity> activity;
  final DateTime lastActivityAt;
}
