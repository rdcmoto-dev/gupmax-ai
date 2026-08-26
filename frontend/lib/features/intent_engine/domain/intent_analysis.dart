import '../../prompts/domain/prompt_models.dart';

class IntentQuestion {
  const IntentQuestion({required this.key, required this.label});
  factory IntentQuestion.fromJson(Map<String, dynamic> json) => IntentQuestion(
      key: json['key'] as String, label: json['label'] as String);
  final String key;
  final String label;
}

class IntentAnalysis {
  const IntentAnalysis({
    required this.summary,
    required this.intent,
    required this.suggestedCategory,
    required this.detectedEntities,
    required this.missingInformation,
    required this.suggestedQuestions,
    required this.confidence,
  });

  factory IntentAnalysis.fromJson(Map<String, dynamic> json) => IntentAnalysis(
        summary: json['summary'] as String,
        intent: json['intent'] as String,
        suggestedCategory:
            PromptCategory.fromValue(json['suggested_category'] as String),
        detectedEntities: (json['detected_entities'] as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, value as String)),
        missingInformation:
            (json['missing_information'] as List<dynamic>).cast<String>(),
        suggestedQuestions: (json['suggested_questions'] as List<dynamic>)
            .map((value) =>
                IntentQuestion.fromJson(value as Map<String, dynamic>))
            .toList(),
        confidence: (json['confidence'] as num).toDouble(),
      );

  final String summary;
  final String intent;
  final PromptCategory suggestedCategory;
  final Map<String, String> detectedEntities;
  final List<String> missingInformation;
  final List<IntentQuestion> suggestedQuestions;
  final double confidence;
}
