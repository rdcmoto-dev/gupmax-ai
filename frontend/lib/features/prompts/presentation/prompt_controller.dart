import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../data/prompt_repository.dart';
import '../domain/prompt_models.dart';

class PromptController extends ChangeNotifier {
  PromptController(this._repository);
  final PromptRepositoryContract _repository;

  bool isSubmitting = false;
  bool isLoading = false;
  String? error;
  String? versionsError;
  String? refinementError;
  String? refinementEstimateError;
  PromptRecord? selected;
  AiCreditEstimate? estimate;
  bool isEstimating = false;
  List<PromptRecord> items = [];
  List<PromptRecord> versions = [];
  int total = 0;
  int offset = 0;
  static const pageSize = 20;

  void _setRefinementError(String? value, String source) {
    if (kDebugMode) {
      debugPrint(
        '[prompt_refinement] controller=${identityHashCode(this)} '
        'source=$source before=${refinementError ?? 'null'} '
        'after=${value ?? 'null'}',
      );
    }
    refinementError = value;
  }

  Future<void> estimateOptimization(PromptGenerateInput input) async {
    isEstimating = true;
    estimate = null;
    notifyListeners();
    try {
      estimate = await _repository.estimate(input);
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isEstimating = false;
      notifyListeners();
    }
  }

  void clearEstimate() {
    if (kDebugMode) {
      debugPrint(
        '[prompt_refinement] controller=${identityHashCode(this)} '
        'event=clear_estimate estimate=${estimate == null ? 'no' : 'yes'} '
        'refinement_error=${refinementError ?? 'null'} '
        'estimate_error=${refinementEstimateError ?? 'null'}',
      );
    }
    estimate = null;
    refinementEstimateError = null;
    notifyListeners();
  }

  void beginRefinement() {
    _setRefinementError(null, 'begin_refinement');
    refinementEstimateError = null;
    estimate = null;
    notifyListeners();
  }

  Future<PromptRecord?> generate(PromptGenerateInput input) async {
    if (isSubmitting) return null;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      selected = await _repository.generate(input);
      return selected;
    } on AppException catch (exception) {
      error = exception.message;
      return null;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> loadPage({int newOffset = 0}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _repository.list(offset: newOffset, limit: pageSize);
      items = page.items;
      total = page.total;
      offset = page.offset;
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<PromptRecord?> load(String id) async {
    isLoading = true;
    error = null;
    versionsError = null;
    _setRefinementError(null, 'load');
    refinementEstimateError = null;
    selected = null;
    versions = [];
    notifyListeners();
    try {
      selected = await _repository.get(id);
      try {
        final page = await _repository.versions(id);
        versions = page.items;
      } on AppException catch (exception) {
        versions = [selected!];
        if (exception.statusCode != 404) {
          versionsError = 'Não foi possível carregar o histórico de versões.';
        }
      }
      error = null;
      return selected;
    } on AppException catch (exception) {
      error = exception.message;
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> estimateRefinement(
      PromptRecord prompt, PromptRefineInput input) async {
    if (kDebugMode) {
      debugPrint(
        '[prompt_refinement] controller=${identityHashCode(this)} '
        'event=estimate_start optimize_with_ai=${input.optimizeWithAi}',
      );
    }
    isEstimating = true;
    estimate = null;
    refinementEstimateError = null;
    notifyListeners();
    try {
      estimate = await _repository.estimateRefinement(prompt, input);
    } on AppException catch (exception) {
      refinementEstimateError = exception.message;
      if (kDebugMode) {
        debugPrint(
          '[prompt_refinement] controller=${identityHashCode(this)} '
          'source=estimate_error estimate_error=${exception.message}',
        );
      }
    } finally {
      isEstimating = false;
      notifyListeners();
    }
  }

  Future<PromptRecord?> refine(
      PromptRecord prompt, PromptRefineInput input) async {
    if (kDebugMode) {
      debugPrint(
        '[prompt_refinement] controller=${identityHashCode(this)} '
        'event=refine_start optimize_with_ai=${input.optimizeWithAi}',
      );
    }
    if (isSubmitting) return null;
    isSubmitting = true;
    _setRefinementError(null, 'refine_start');
    notifyListeners();
    try {
      selected = await _repository.refine(prompt.id, input);
      final page = await _repository.versions(selected!.id);
      versions = page.items;
      estimate = null;
      return selected;
    } on AppException catch (exception) {
      _setRefinementError(exception.message, 'refine_error');
      return null;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  void selectVersion(PromptRecord prompt) {
    selected = prompt;
    notifyListeners();
  }

  Future<bool> update(String id, PromptUpdateInput input) async {
    if (isSubmitting) return false;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      selected = await _repository.update(id, input);
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> remove(String id) async {
    if (isSubmitting) return false;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      await _repository.delete(id);
      items.removeWhere((item) => item.id == id);
      total = total > 0 ? total - 1 : 0;
      selected = null;
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
