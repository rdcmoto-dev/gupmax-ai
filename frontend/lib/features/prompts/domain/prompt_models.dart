enum PromptMode { basic, pro, expert }

class PromptQualityCriterion {
  const PromptQualityCriterion({
    required this.key,
    required this.label,
    required this.score,
    required this.maxScore,
    required this.status,
    required this.feedback,
  });

  factory PromptQualityCriterion.fromJson(Map<String, dynamic> json) =>
      PromptQualityCriterion(
        key: json['key'] as String,
        label: json['label'] as String,
        score: json['score'] as int,
        maxScore: json['max_score'] as int,
        status: json['status'] as String,
        feedback: json['feedback'] as String,
      );

  final String key;
  final String label;
  final int score;
  final int maxScore;
  final String status;
  final String feedback;
}

class PromptQualityScore {
  const PromptQualityScore({
    required this.promptId,
    required this.score,
    required this.rating,
    required this.criteria,
    required this.strengths,
    required this.improvements,
    required this.suggestions,
  });

  factory PromptQualityScore.fromJson(Map<String, dynamic> json) =>
      PromptQualityScore(
        promptId: json['prompt_id'] as String,
        score: json['score'] as int,
        rating: json['rating'] as String,
        criteria: (json['criteria'] as List<dynamic>)
            .map((item) =>
                PromptQualityCriterion.fromJson(item as Map<String, dynamic>))
            .toList(),
        strengths: (json['strengths'] as List<dynamic>).cast<String>(),
        improvements: (json['improvements'] as List<dynamic>).cast<String>(),
        suggestions: (json['suggestions'] as List<dynamic>).cast<String>(),
      );

  final String promptId;
  final int score;
  final String rating;
  final List<PromptQualityCriterion> criteria;
  final List<String> strengths;
  final List<String> improvements;
  final List<String> suggestions;

  String get ratingLabel => switch (rating) {
        'excellent' => 'Excelente',
        'very_good' => 'Muito bom',
        'good' => 'Bom',
        'needs_improvement' => 'Pode melhorar',
        _ => 'Fraco',
      };
}

enum PromptCategory {
  marketing('marketing', 'Marketing'),
  sales('vendas', 'Vendas'),
  socialMedia('redes_sociais', 'Redes sociais'),
  ecommerce('ecommerce', 'E-commerce'),
  programming('programacao', 'Programação'),
  business('negocios', 'Negócios'),
  education('educacao', 'Educação'),
  writing('escrita', 'Escrita'),
  image('imagem', 'Imagem'),
  video('video', 'Vídeo'),
  productivity('produtividade', 'Produtividade'),
  general('geral', 'Geral');

  const PromptCategory(this.value, this.label);
  final String value;
  final String label;

  static PromptCategory fromValue(String value) =>
      values.firstWhere((item) => item.value == value);
}

class PromptGenerateInput {
  const PromptGenerateInput({
    required this.input,
    this.category = PromptCategory.general,
    this.language = 'pt-BR',
    this.tone,
    this.mode = PromptMode.basic,
    this.optimizeWithAi = false,
    this.title,
    this.context,
    this.audience,
    this.role,
    this.instructions = const [],
    this.constraints = const [],
    this.outputFormat,
    this.additionalInformation,
    this.provider = 'openai',
    this.model,
    this.projectId,
  });

  final String input;
  final PromptCategory category;
  final String language;
  final String? tone;
  final PromptMode mode;
  final bool optimizeWithAi;
  final String? title;
  final String? context;
  final String? audience;
  final String? role;
  final List<String> instructions;
  final List<String> constraints;
  final String? outputFormat;
  final String? additionalInformation;
  final String provider;
  final String? model;
  final String? projectId;

  factory PromptGenerateInput.fromJson(Map<String, dynamic> json) =>
      PromptGenerateInput(
        input: json['input'] as String,
        category: PromptCategory.fromValue(json['category'] as String),
        language: json['language'] as String? ?? 'pt-BR',
        tone: json['tone'] as String?,
        mode: PromptMode.values.byName(json['mode'] as String),
        optimizeWithAi: json['optimize_with_ai'] as bool? ?? false,
        title: json['title'] as String?,
        context: json['context'] as String?,
        audience: json['audience'] as String?,
        role: json['role'] as String?,
        instructions:
            (json['instructions'] as List<dynamic>? ?? const []).cast<String>(),
        constraints:
            (json['constraints'] as List<dynamic>? ?? const []).cast<String>(),
        outputFormat: json['output_format'] as String?,
        additionalInformation: json['additional_information'] as String?,
        provider: json['provider'] as String? ?? 'openai',
        model: json['model'] as String?,
        projectId: json['project_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'input': input,
        'category': category.value,
        'language': language,
        'tone': tone,
        'mode': mode.name,
        'optimize_with_ai': optimizeWithAi,
        'title': title,
        'context': context,
        'audience': audience,
        'role': role,
        'instructions': instructions,
        'constraints': constraints,
        'output_format': outputFormat,
        'additional_information': additionalInformation,
        'provider': provider,
        'model': model,
        'project_id': projectId,
      };
}

class AiCreditEstimate {
  const AiCreditEstimate({
    required this.estimatedCredits,
    required this.availableCredits,
    required this.canExecute,
  });

  factory AiCreditEstimate.fromJson(Map<String, dynamic> json) =>
      AiCreditEstimate(
        estimatedCredits: json['estimated_credits'] as int,
        availableCredits: json['available_credits'] as int,
        canExecute: json['can_execute'] as bool,
      );

  final int estimatedCredits;
  final int availableCredits;
  final bool canExecute;
}

class PromptUpdateInput {
  const PromptUpdateInput({
    this.title,
    this.generatedPrompt,
    this.category,
    this.language,
    this.tone,
    this.mode,
  });

  final String? title;
  final String? generatedPrompt;
  final PromptCategory? category;
  final String? language;
  final String? tone;
  final PromptMode? mode;

  Map<String, dynamic> toJson() => {
        'title': title,
        'generated_prompt': generatedPrompt,
        'category': category?.value,
        'language': language,
        'tone': tone,
        'mode': mode?.name,
      }..removeWhere((_, value) => value == null);
}

class PromptRefineInput {
  const PromptRefineInput({
    required this.instruction,
    this.optimizeWithAi = false,
    this.provider = 'openai',
    this.model,
  });

  final String instruction;
  final bool optimizeWithAi;
  final String provider;
  final String? model;

  Map<String, dynamic> toJson() => {
        'instruction': instruction,
        'optimize_with_ai': optimizeWithAi,
        'provider': provider,
        'model': model,
      };
}

class PromptRecord {
  const PromptRecord({
    required this.id,
    required this.userId,
    required this.title,
    required this.originalInput,
    required this.generatedPrompt,
    required this.category,
    required this.language,
    required this.mode,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.tone,
    this.provider,
    this.model,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.parentPromptId,
    this.rootPromptId,
    this.versionNumber = 1,
    this.refinementInstruction,
    this.projectId,
  });

  factory PromptRecord.fromJson(Map<String, dynamic> json) => PromptRecord(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String,
        originalInput: json['original_input'] as String,
        generatedPrompt: json['generated_prompt'] as String,
        category: PromptCategory.fromValue(json['category'] as String),
        language: json['language'] as String,
        tone: json['tone'] as String?,
        mode: PromptMode.values.byName(json['mode'] as String),
        status: json['status'] as String,
        provider: json['provider'] as String?,
        model: json['model'] as String?,
        inputTokens: json['input_tokens'] as int?,
        outputTokens: json['output_tokens'] as int?,
        totalTokens: json['total_tokens'] as int?,
        parentPromptId: json['parent_prompt_id'] as String?,
        rootPromptId: json['root_prompt_id'] as String?,
        versionNumber: json['version_number'] as int? ?? 1,
        refinementInstruction: json['refinement_instruction'] as String?,
        projectId: json['project_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String userId;
  final String title;
  final String originalInput;
  final String generatedPrompt;
  final PromptCategory category;
  final String language;
  final String? tone;
  final PromptMode mode;
  final String status;
  final String? provider;
  final String? model;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final String? parentPromptId;
  final String? rootPromptId;
  final int versionNumber;
  final String? refinementInstruction;
  final String? projectId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PromptVersionPageData {
  const PromptVersionPageData({required this.items, required this.total});

  factory PromptVersionPageData.fromJson(Map<String, dynamic> json) =>
      PromptVersionPageData(
        items: (json['items'] as List<dynamic>)
            .map((item) => PromptRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
      );

  final List<PromptRecord> items;
  final int total;
}

class PromptPageData {
  const PromptPageData(
      {required this.items,
      required this.total,
      required this.offset,
      required this.limit});

  factory PromptPageData.fromJson(Map<String, dynamic> json) => PromptPageData(
        items: (json['items'] as List<dynamic>)
            .map((item) => PromptRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        offset: json['offset'] as int,
        limit: json['limit'] as int,
      );

  final List<PromptRecord> items;
  final int total;
  final int offset;
  final int limit;
}
