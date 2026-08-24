import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';

class ProjectController extends ChangeNotifier {
  ProjectController(this.repository);
  final ProjectRepositoryContract repository;
  List<ProjectRecord> items = [];
  ProjectRecord? selected;
  bool loading = false;
  String? error;

  Future<void> load() async => _run(() async {
        items = (await repository.list()).items;
      });
  Future<void> loadDetail(String id) async => _run(() async {
        selected = await repository.get(id);
      });
  Future<bool> create(Map<String, dynamic> values) async {
    var ok = true;
    await _run(() async => items = [await repository.create(values), ...items],
        onError: () => ok = false);
    return ok;
  }

  Future<void> update(String id, Map<String, dynamic> values) async =>
      _run(() async {
        final updated = await repository.update(id, values);
        items = [
          for (final item in items)
            if (item.id == id) updated else item
        ];
        if (selected?.id == id) selected = await repository.get(id);
      });
  Future<void> remove(String id) async => _run(() async {
        await repository.delete(id);
        items = items.where((item) => item.id != id).toList();
      });
  Future<void> assignPrompt(String projectId, String promptId) async =>
      _run(() async {
        await repository.assignPrompt(projectId, promptId);
        selected = await repository.get(projectId);
      });
  Future<void> removePrompt(String projectId, String promptId) async =>
      _run(() async {
        await repository.removePrompt(projectId, promptId);
        selected = await repository.get(projectId);
      });
  Future<void> assignTemplate(String projectId, String templateId) async =>
      _run(() async {
        await repository.assignTemplate(projectId, templateId);
        selected = await repository.get(projectId);
      });
  Future<void> removeTemplate(String projectId, String templateId) async =>
      _run(() async {
        await repository.removeTemplate(projectId, templateId);
        selected = await repository.get(projectId);
      });

  Future<void> _run(Future<void> Function() operation,
      {VoidCallback? onError}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } on AppException catch (exception) {
      error = exception.message;
      onError?.call();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
