import 'package:flutter/foundation.dart';

import '../data/prompt_chain_repository.dart';
import '../domain/prompt_chain.dart';

class PromptChainController extends ChangeNotifier {
  PromptChainController(this.repository);
  final PromptChainRepositoryContract repository;
  List<PromptChainRecord> items = [];
  PromptChainRecord? selected;
  bool loading = false;
  String? error;

  Future<void> load() async =>
      _run(() async => items = await repository.list());
  Future<void> open(String id) async =>
      _run(() async => selected = await repository.get(id));
  Future<void> create(Map<String, dynamic> values) async => _run(() async {
        final value = await repository.create(values);
        items = [value, ...items];
      });
  Future<void> update(String id, Map<String, dynamic> values) async =>
      _run(() async {
        await repository.update(id, values);
        await load();
      });
  Future<void> remove(String id) async => _run(() async {
        await repository.delete(id);
        items = items.where((item) => item.id != id).toList();
      });
  Future<void> addStep(String id, Map<String, dynamic> values) async =>
      _run(() async {
        await repository.addStep(id, values);
        selected = await repository.get(id);
      });
  Future<void> updateStep(
          String id, String stepId, Map<String, dynamic> values) async =>
      _run(() async {
        await repository.updateStep(id, stepId, values);
        selected = await repository.get(id);
      });
  Future<void> deleteStep(String id, String stepId) async => _run(() async {
        await repository.deleteStep(id, stepId);
        selected = await repository.get(id);
      });
  Future<void> move(String id, int from, int to) async => _run(() async {
        final steps = [...selected!.steps];
        final moved = steps.removeAt(from);
        steps.insert(to, moved);
        await repository.reorder(id, steps.map((step) => step.id).toList());
        selected = await repository.get(id);
      });
  Future<void> startExecution(String id) async =>
      _run(() async => selected = await repository.startExecution(id));
  Future<void> completeStep(String id, String stepId, String result) async =>
      _run(() async =>
          selected = await repository.completeStep(id, stepId, result));

  Future<void> _run(Future<void> Function() operation) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (_) {
      error = 'Não foi possível concluir a operação com o fluxo.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
