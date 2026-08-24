import '../../prompts/domain/prompt_models.dart';
import '../../templates/domain/prompt_template.dart';

enum ProjectStatus { active, archived }

class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.name,
    required this.status,
    required this.promptCount,
    required this.templateCount,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.context,
    this.prompts = const [],
    this.templates = const [],
  });

  factory ProjectRecord.fromJson(Map<String, dynamic> json) => ProjectRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        context: json['context'] as String?,
        status: ProjectStatus.values.byName(json['status'] as String),
        promptCount: json['prompt_count'] as int? ?? 0,
        templateCount: json['template_count'] as int? ?? 0,
        prompts: (json['prompts'] as List<dynamic>? ?? const [])
            .map((item) => PromptRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        templates: (json['templates'] as List<dynamic>? ?? const [])
            .map((item) =>
                PromptTemplateRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String name;
  final String? description;
  final String? context;
  final ProjectStatus status;
  final int promptCount;
  final int templateCount;
  final List<PromptRecord> prompts;
  final List<PromptTemplateRecord> templates;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ProjectPageData {
  const ProjectPageData(this.items, this.total);
  factory ProjectPageData.fromJson(Map<String, dynamic> json) =>
      ProjectPageData(
        (json['items'] as List<dynamic>)
            .map((item) => ProjectRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        json['total'] as int,
      );
  final List<ProjectRecord> items;
  final int total;
}
