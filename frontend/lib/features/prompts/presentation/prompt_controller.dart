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
  PromptRecord? selected;
  AiCreditEstimate? estimate;
  bool isEstimating = false;
  List<PromptRecord> items = [];
  int total = 0;
  int offset = 0;
  static const pageSize = 20;

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
    notifyListeners();
    try {
      selected = await _repository.get(id);
      return selected;
    } on AppException catch (exception) {
      error = exception.message;
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
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
