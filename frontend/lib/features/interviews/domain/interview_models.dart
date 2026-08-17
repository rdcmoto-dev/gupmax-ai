import '../../prompts/domain/prompt_models.dart';

enum InterviewStatus { active, ready, completed, expired }

enum InterviewQuestionType {
  text,
  multiline,
  singleChoice,
  multiChoice,
  boolean;

  static InterviewQuestionType fromValue(String value) => switch (value) {
        'text' => text,
        'multiline' => multiline,
        'single_choice' => singleChoice,
        'multi_choice' => multiChoice,
        'boolean' => boolean,
        _ => throw FormatException('Tipo de pergunta desconhecido: $value'),
      };
}

class InterviewQuestion {
  const InterviewQuestion({
    required this.key,
    required this.text,
    required this.type,
    required this.required,
    required this.options,
  });

  factory InterviewQuestion.fromJson(Map<String, dynamic> json) =>
      InterviewQuestion(
        key: json['key'] as String,
        text: json['text'] as String,
        type: InterviewQuestionType.fromValue(json['type'] as String),
        required: json['required'] as bool,
        options: (json['options'] as List<dynamic>? ?? const []).cast<String>(),
      );

  final String key;
  final String text;
  final InterviewQuestionType type;
  final bool required;
  final List<String> options;
}

class InterviewAnswer {
  const InterviewAnswer({required this.questionKey, required this.value});

  factory InterviewAnswer.fromJson(Map<String, dynamic> json) =>
      InterviewAnswer(
        questionKey: json['question_key'] as String,
        value: json['value'],
      );

  final String questionKey;
  final Object? value;
}

class InterviewProgress {
  const InterviewProgress({
    required this.answered,
    required this.total,
    required this.requiredAnswered,
    required this.requiredTotal,
  });

  factory InterviewProgress.fromJson(Map<String, dynamic> json) =>
      InterviewProgress(
        answered: json['answered'] as int,
        total: json['total'] as int,
        requiredAnswered: json['required_answered'] as int,
        requiredTotal: json['required_total'] as int,
      );

  final int answered;
  final int total;
  final int requiredAnswered;
  final int requiredTotal;
}

class InterviewSession {
  const InterviewSession({
    required this.id,
    required this.status,
    required this.mode,
    required this.category,
    required this.initialRequest,
    required this.questions,
    required this.answers,
    required this.progress,
    this.structuredPrompt,
  });

  factory InterviewSession.fromJson(Map<String, dynamic> json) =>
      InterviewSession(
        id: json['id'] as String,
        status: InterviewStatus.values.byName(json['status'] as String),
        mode: PromptMode.values.byName(json['mode'] as String),
        category: PromptCategory.fromValue(json['category'] as String),
        initialRequest: json['initial_request'] as String,
        questions: (json['questions'] as List<dynamic>)
            .map((item) =>
                InterviewQuestion.fromJson(item as Map<String, dynamic>))
            .toList(),
        answers: (json['answers'] as List<dynamic>)
            .map((item) =>
                InterviewAnswer.fromJson(item as Map<String, dynamic>))
            .toList(),
        progress: InterviewProgress.fromJson(
            json['progress'] as Map<String, dynamic>),
        structuredPrompt: json['structured_prompt'] == null
            ? null
            : PromptGenerateInput.fromJson(
                json['structured_prompt'] as Map<String, dynamic>),
      );

  final String id;
  final InterviewStatus status;
  final PromptMode mode;
  final PromptCategory category;
  final String initialRequest;
  final List<InterviewQuestion> questions;
  final List<InterviewAnswer> answers;
  final InterviewProgress progress;
  final PromptGenerateInput? structuredPrompt;

  InterviewQuestion? get nextQuestion {
    final answered = answers.map((answer) => answer.questionKey).toSet();
    for (final question in questions) {
      if (!answered.contains(question.key)) return question;
    }
    return null;
  }
}

class InterviewCompleteResult {
  const InterviewCompleteResult({
    required this.interview,
    required this.promptInput,
  });

  factory InterviewCompleteResult.fromJson(Map<String, dynamic> json) =>
      InterviewCompleteResult(
        interview: InterviewSession.fromJson(
            json['interview'] as Map<String, dynamic>),
        promptInput: PromptGenerateInput.fromJson(
            json['prompt_input'] as Map<String, dynamic>),
      );

  final InterviewSession interview;
  final PromptGenerateInput promptInput;
}
