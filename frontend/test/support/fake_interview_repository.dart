import 'dart:async';

import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/interviews/data/interview_repository.dart';
import 'package:gupmax_ai/features/interviews/domain/interview_models.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

class FakeInterviewRepository implements InterviewRepositoryContract {
  InterviewSession? current;
  AppException? error;
  Completer<InterviewCompleteResult>? completeCompleter;
  PromptMode? createdMode;
  PromptCategory? createdCategory;
  String? createdRequest;
  int answerCalls = 0;
  int completeCalls = 0;
  int getCalls = 0;

  InterviewSession sample({
    String id = 'interview-1',
    InterviewStatus status = InterviewStatus.active,
    PromptMode mode = PromptMode.pro,
    List<InterviewQuestion>? questions,
    List<InterviewAnswer> answers = const [],
    PromptGenerateInput? structuredPrompt,
  }) {
    final items = questions ??
        const [
          InterviewQuestion(
            key: 'channel',
            text: 'Em qual canal será usado?',
            type: InterviewQuestionType.singleChoice,
            required: true,
            options: ['Site', 'Rede social'],
          ),
        ];
    return InterviewSession(
      id: id,
      status: status,
      mode: mode,
      category: PromptCategory.marketing,
      initialRequest: 'Crie uma campanha',
      questions: items,
      answers: answers,
      progress: InterviewProgress(
        answered: answers.length,
        total: items.length,
        requiredAnswered: answers.length,
        requiredTotal: items.where((item) => item.required).length,
      ),
      structuredPrompt: structuredPrompt,
    );
  }

  @override
  Future<InterviewSession> create({
    required String initialRequest,
    required PromptMode mode,
    required PromptCategory category,
  }) async {
    if (error != null) throw error!;
    createdRequest = initialRequest;
    createdMode = mode;
    createdCategory = category;
    return current = sample(mode: mode);
  }

  @override
  Future<InterviewSession> get(String id) async {
    getCalls++;
    if (error != null) throw error!;
    return current ??= sample(id: id);
  }

  @override
  Future<InterviewSession> answer(
      String id, String questionKey, Object value) async {
    answerCalls++;
    if (error != null) throw error!;
    final previous = current ?? sample(id: id);
    final answers = [
      ...previous.answers.where((item) => item.questionKey != questionKey),
      InterviewAnswer(questionKey: questionKey, value: value),
    ];
    final required = previous.questions.where((item) => item.required).length;
    current = InterviewSession(
      id: previous.id,
      status: answers.length >= required
          ? InterviewStatus.ready
          : InterviewStatus.active,
      mode: previous.mode,
      category: previous.category,
      initialRequest: previous.initialRequest,
      questions: previous.questions,
      answers: answers,
      progress: InterviewProgress(
        answered: answers.length,
        total: previous.questions.length,
        requiredAnswered: answers.length,
        requiredTotal: required,
      ),
    );
    return current!;
  }

  @override
  Future<InterviewCompleteResult> complete(String id) async {
    completeCalls++;
    if (error != null) throw error!;
    if (completeCompleter != null) return completeCompleter!.future;
    final input = const PromptGenerateInput(
      input: 'Crie uma campanha',
      category: PromptCategory.marketing,
      mode: PromptMode.pro,
    );
    final previous = current ?? sample(id: id, status: InterviewStatus.ready);
    current = InterviewSession(
      id: previous.id,
      status: InterviewStatus.completed,
      mode: previous.mode,
      category: previous.category,
      initialRequest: previous.initialRequest,
      questions: previous.questions,
      answers: previous.answers,
      progress: previous.progress,
      structuredPrompt: input,
    );
    return InterviewCompleteResult(interview: current!, promptInput: input);
  }
}
