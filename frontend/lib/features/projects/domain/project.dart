import '../../prompts/domain/prompt_models.dart';
import '../../templates/domain/prompt_template.dart';

class ProjectTag {
  const ProjectTag(this.id, this.name);
  factory ProjectTag.fromJson(Map<String, dynamic> json) =>
      ProjectTag(json['id'] as String, json['name'] as String);
  final String id;
  final String name;
}

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
    this.isFavorite = false,
    this.isPinned = false,
    this.tags = const [],
    this.description,
    this.context,
    this.prompts = const [],
    this.templates = const [],
  });

  factory ProjectRecord.fromJson(Map<String, dynamic> json) => ProjectRecord(
        tags: (json['tags'] as List? ?? const [])
            .map((item) => ProjectTag.fromJson(item as Map<String, dynamic>))
            .toList(),
        id: json['id'] as String,
        name: json['name'] as String,
        isFavorite: json['is_favorite'] as bool? ?? false,
        isPinned: json['is_pinned'] as bool? ?? false,
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
  final bool isFavorite;
  final bool isPinned;
  final List<ProjectTag> tags;
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
