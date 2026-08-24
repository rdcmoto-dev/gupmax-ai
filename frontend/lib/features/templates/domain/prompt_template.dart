import '../../prompts/domain/prompt_models.dart';

class TemplateVariable {
  const TemplateVariable({
    required this.name,
    required this.label,
    this.required = true,
  });

  factory TemplateVariable.fromJson(Map<String, dynamic> json) =>
      TemplateVariable(
        name: json['name'] as String,
        label: json['label'] as String,
        required: json['required'] as bool? ?? true,
      );

  final String name;
  final String label;
  final bool required;
}

List<TemplateVariable> detectTemplateVariables(String content) {
  final result = <TemplateVariable>[];
  final seen = <String>{};
  final pattern = RegExp(r'\{([A-Za-z][A-Za-z0-9_]{0,63})\}');
  for (final match in pattern.allMatches(content)) {
    if ((match.start > 0 && content[match.start - 1] == '{') ||
        (match.end < content.length && content[match.end] == '}')) {
      continue;
    }
    final name = match.group(1)!.toLowerCase();
    if (seen.add(name)) {
      final label = switch (name) {
        'publico' => 'Público',
        'publico_alvo' => 'Público alvo',
        'servico' => 'Serviço',
        _ =>
          '${name[0].toUpperCase()}${name.substring(1).replaceAll('_', ' ')}',
      };
      result.add(TemplateVariable(name: name, label: label));
    }
  }
  return result;
}

List<TemplateVariable> _templateVariablesFromJson(Map<String, dynamic> json) {
  final declared = (json['variables'] as List<dynamic>? ?? const [])
      .map((item) => TemplateVariable.fromJson(item as Map<String, dynamic>))
      .toList();
  if (declared.isNotEmpty) return declared;
  final contents = <String>[
    for (final key in [
      'template_content',
      'base_input',
      'tone',
      'audience',
      'context',
      'output_format',
      'additional_information',
    ])
      if (json[key] case final String value) value,
    ...(json['instructions'] as List<dynamic>? ?? const []).cast<String>(),
    ...(json['constraints'] as List<dynamic>? ?? const []).cast<String>(),
  ];
  return detectTemplateVariables(contents.join('\n'));
}

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
    this.variables = const [],
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
        variables: _templateVariablesFromJson(json),
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
  final List<TemplateVariable> variables;
  bool get hasVariables => variables.isNotEmpty;
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
