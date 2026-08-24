import '../../prompts/domain/prompt_models.dart';

class PromptTemplateRecord {
  const PromptTemplateRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.mode,
    required this.templateContent,
    required this.baseInput,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.sourcePromptId,
    this.tone,
    this.audience,
    this.context,
    this.outputFormat,
    this.constraints = const [],
    this.instructions = const [],
    this.additionalInformation,
    this.isActive = true,
    this.projectId,
    this.targetAi = TargetAI.generic,
  });

  factory PromptTemplateRecord.fromJson(Map<String, dynamic> json) =>
      PromptTemplateRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        sourcePromptId: json['source_prompt_id'] as String?,
        category: PromptCategory.fromValue(json['category'] as String),
        mode: PromptMode.values.byName(json['mode'] as String),
        templateContent: json['template_content'] as String,
        baseInput: json['base_input'] as String,
        language: json['language'] as String? ?? 'pt-BR',
        tone: json['tone'] as String?,
        audience: json['audience'] as String?,
        context: json['context'] as String?,
        outputFormat: json['output_format'] as String?,
        constraints:
            (json['constraints'] as List<dynamic>? ?? const []).cast<String>(),
        instructions:
            (json['instructions'] as List<dynamic>? ?? const []).cast<String>(),
        additionalInformation: json['additional_information'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        projectId: json['project_id'] as String?,
        targetAi: TargetAI.fromValue(json['target_ai'] as String?),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String name;
  final String? description;
  final String? sourcePromptId;
  final PromptCategory category;
  final PromptMode mode;
  final String templateContent;
  final String baseInput;
  final String language;
  final String? tone;
  final String? audience;
  final String? context;
  final String? outputFormat;
  final List<String> constraints;
  final List<String> instructions;
  final String? additionalInformation;
  final bool isActive;
  final String? projectId;
  final TargetAI targetAi;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TemplatePageData {
  const TemplatePageData(this.items, this.total);
  factory TemplatePageData.fromJson(Map<String, dynamic> json) =>
      TemplatePageData(
        (json['items'] as List<dynamic>)
            .map((item) =>
                PromptTemplateRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        json['total'] as int,
      );
  final List<PromptTemplateRecord> items;
  final int total;
}
