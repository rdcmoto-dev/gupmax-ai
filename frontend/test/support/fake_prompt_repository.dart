import 'dart:async';

import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/prompts/data/prompt_repository.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

class FakePromptRepository implements PromptRepositoryContract {
  final records = <PromptRecord>[];
  AppException? error;
  Completer<PromptRecord>? generateCompleter;
  PromptGenerateInput? generatedInput;
  int? requestedOffset;
  int totalOverride = 0;
  bool deleted = false;
  AiCreditEstimate estimateResult = const AiCreditEstimate(
      estimatedCredits: 8, availableCredits: 100, canExecute: true);

  PromptRecord sample({
    String id = 'prompt-1',
    String title = 'Prompt de teste',
    String status = 'generated',
    String? provider,
    String? model,
  }) {
    final now = DateTime.utc(2026, 8, 14);
    return PromptRecord(
      id: id,
      userId: 'user-1',
      title: title,
      originalInput: 'Crie uma campanha',
      generatedPrompt: '## OBJECTIVE\nCrie uma campanha',
      category: PromptCategory.marketing,
      language: 'pt-BR',
      tone: 'persuasivo',
      mode: PromptMode.pro,
      status: status,
      provider: provider,
      model: model,
      createdAt: now,
      updatedAt: now,
    );
  }

  Never _throw() => throw error!;

  @override
  Future<PromptRecord> generate(PromptGenerateInput input) async {
    generatedInput = input;
    if (error != null) _throw();
    if (generateCompleter != null) return generateCompleter!.future;
    final result = sample();
    records.insert(0, result);
    return result;
  }

  @override
  Future<AiCreditEstimate> estimate(PromptGenerateInput input) async {
    if (error != null) _throw();
    return estimateResult;
  }

  @override
  Future<PromptRecord> get(String id) async {
    if (error != null) _throw();
    return records.firstWhere((item) => item.id == id,
        orElse: () => sample(id: id));
  }

  @override
  Future<PromptPageData> list({required int offset, int limit = 20}) async {
    requestedOffset = offset;
    if (error != null) _throw();
    return PromptPageData(
        items: records,
        total: totalOverride == 0 ? records.length : totalOverride,
        offset: offset,
        limit: limit);
  }

  @override
  Future<PromptRecord> update(String id, PromptUpdateInput input) async {
    if (error != null) _throw();
    final current = await get(id);
    final updated = PromptRecord(
      id: current.id,
      userId: current.userId,
      title: input.title ?? current.title,
      originalInput: current.originalInput,
      generatedPrompt: input.generatedPrompt ?? current.generatedPrompt,
      category: input.category ?? current.category,
      language: input.language ?? current.language,
      tone: input.tone ?? current.tone,
      mode: input.mode ?? current.mode,
      status: current.status,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
    );
    records.removeWhere((item) => item.id == id);
    records.add(updated);
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    if (error != null) _throw();
    deleted = true;
    records.removeWhere((item) => item.id == id);
  }
}
