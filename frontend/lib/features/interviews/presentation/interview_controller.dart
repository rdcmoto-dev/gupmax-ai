import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../prompts/domain/prompt_models.dart';
import '../data/interview_repository.dart';
import '../domain/interview_models.dart';

class InterviewController extends ChangeNotifier {
  InterviewController(this._repository);
  final InterviewRepositoryContract _repository;

  InterviewSession? session;
  bool isLoading = false;
  bool isSubmitting = false;
  bool isExpired = false;
  String? error;

  Future<InterviewSession?> start({
    required String initialRequest,
    required PromptMode mode,
    required PromptCategory category,
    PromptGenerateInput? knownFields,
  }) async {
    if (isSubmitting) return null;
    isSubmitting = true;
    error = null;
    isExpired = false;
    notifyListeners();
    try {
      session = await _repository.create(
        initialRequest: initialRequest,
        mode: mode,
        category: category,
        knownFields: knownFields,
      );
      return session;
    } on AppException catch (exception) {
      error = exception.message;
      return null;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> load(String id) async {
    if (isLoading) return;
    isLoading = true;
    error = null;
    isExpired = false;
    notifyListeners();
    try {
      session = await _repository.get(id);
    } on AppException catch (exception) {
      error = exception.message;
      isExpired = exception.statusCode == 409 &&
          exception.message == 'Esta entrevista expirou.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> answer(String questionKey, Object value) async {
    if (isSubmitting || session == null) return false;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      session = await _repository.answer(session!.id, questionKey, value);
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<PromptGenerateInput?> complete() async {
    if (isSubmitting || session == null) return null;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      final result = await _repository.complete(session!.id);
      session = result.interview;
      return result.promptInput;
    } on AppException catch (exception) {
      error = exception.message;
      return null;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
