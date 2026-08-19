import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../data/template_repository.dart';
import '../domain/prompt_template.dart';

class TemplateController extends ChangeNotifier {
  TemplateController(this.repository);
  final TemplateRepositoryContract repository;

  List<PromptTemplateRecord> items = [];
  bool loading = false;
  bool submitting = false;
  String? error;
  String? success;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      items = (await repository.list()).items;
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<PromptTemplateRecord?> get(String id) async {
    try {
      return await repository.get(id);
    } on AppException catch (exception) {
      error = exception.message;
      notifyListeners();
      return null;
    }
  }

  Future<bool> savePrompt(
      String promptId, String name, String? description) async {
    submitting = true;
    error = null;
    success = null;
    notifyListeners();
    try {
      final created = await repository.fromPrompt(promptId, name, description);
      items = [created, ...items];
      success = 'Template salvo com sucesso.';
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<bool> updateTemplate(String id, Map<String, dynamic> values) async {
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final updated = await repository.update(id, values);
      items = [
        for (final item in items)
          if (item.id == id) updated else item
      ];
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<bool> remove(String id) async {
    try {
      await repository.delete(id);
      items = items.where((item) => item.id != id).toList();
      notifyListeners();
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      notifyListeners();
      return false;
    }
  }
}
