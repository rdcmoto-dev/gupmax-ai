import 'dart:async';

import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/prompts/data/prompt_repository.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

class FakePromptRepository implements PromptRepositoryContract {
  final records = <PromptRecord>[];
  AppException? error;
  AppException? getError;
  AppException? versionsError;
  AppException? estimateRefinementError;
  int estimateRefinementCalls = 0;
  int refineCalls = 0;
  int getCalls = 0;
  int versionsCalls = 0;
  int scoreCalls = 0;
  AppException? scoreError;
  final Map<String, PromptQualityScore> scoreResults = {};
  Completer<PromptRecord>? generateCompleter;
  PromptGenerateInput? generatedInput;
  int? requestedOffset;
  int totalOverride = 0;
  bool deleted = false;
  PromptRefineInput? refinedInput;
  AiCreditEstimate estimateResult = const AiCreditEstimate(
      estimatedCredits: 8, availableCredits: 100, canExecute: true);

  PromptRecord sample({
    String id = 'prompt-1',
    String title = 'Prompt de teste',
    String status = 'generated',
    String? provider,
    String? model,
    String generatedPrompt = '## OBJECTIVE\nCrie uma campanha',
    PromptMode mode = PromptMode.pro,
    int? totalTokens,
    int versionNumber = 1,
    String? parentPromptId,
    String? rootPromptId,
  }) {
    final now = DateTime.utc(2026, 8, 14);
    return PromptRecord(
      id: id,
      userId: 'user-1',
      title: title,
      originalInput: 'Crie uma campanha',
      generatedPrompt: generatedPrompt,
      category: PromptCategory.marketing,
      language: 'pt-BR',
      tone: 'persuasivo',
      mode: mode,
      status: status,
      provider: provider,
      model: model,
      totalTokens: totalTokens,
      createdAt: now,
      updatedAt: now,
      versionNumber: versionNumber,
      parentPromptId: parentPromptId,
      rootPromptId: rootPromptId,
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
  Future<AiCreditEstimate> estimateRefinement(
      PromptRecord prompt, PromptRefineInput input) async {
    estimateRefinementCalls += 1;
    if (estimateRefinementError != null) throw estimateRefinementError!;
    if (error != null) _throw();
    return estimateResult;
  }

  @override
  Future<PromptRecord> get(String id) async {
    getCalls += 1;
    if (getError != null) throw getError!;
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
  Future<PromptRecord> refine(String id, PromptRefineInput input) async {
    refineCalls += 1;
    if (error != null) _throw();
    refinedInput = input;
    final source = await get(id);
    final refined = PromptRecord(
      id: 'prompt-${source.versionNumber + 1}',
      userId: source.userId,
      title: source.title,
      originalInput: source.originalInput,
      generatedPrompt:
          '${source.generatedPrompt}\n\n## REFINEMENT\n${input.instruction}',
      category: source.category,
      language: source.language,
      tone: input.instruction.toLowerCase().contains('persuasivo')
          ? 'persuasivo'
          : source.tone,
      mode: source.mode,
      status: input.optimizeWithAi ? 'optimized' : 'generated',
      provider: input.optimizeWithAi ? input.provider : null,
      model: input.optimizeWithAi ? (input.model ?? 'gpt-5.6-luna') : null,
      parentPromptId: source.id,
      rootPromptId: source.rootPromptId ?? source.id,
      versionNumber: source.versionNumber + 1,
      refinementInstruction: input.instruction,
      createdAt: source.createdAt.add(const Duration(minutes: 1)),
      updatedAt: source.updatedAt.add(const Duration(minutes: 1)),
    );
    records.add(refined);
    return refined;
  }

  @override
  Future<PromptVersionPageData> versions(String id) async {
    versionsCalls += 1;
    if (versionsError != null) throw versionsError!;
    if (error != null) _throw();
    final current = await get(id);
    final root = current.rootPromptId ?? current.id;
    final result = records
        .where((item) => item.id == root || item.rootPromptId == root)
        .toList()
      ..sort((a, b) => a.versionNumber.compareTo(b.versionNumber));
    if (result.isEmpty) result.add(current);
    return PromptVersionPageData(items: result, total: result.length);
  }

  @override
  Future<PromptQualityScore> score(String id) async {
    scoreCalls += 1;
    if (scoreError != null) throw scoreError!;
    return scoreResults[id] ??
        PromptQualityScore(
          promptId: id,
          score: 72,
          rating: 'good',
          criteria: const [
            PromptQualityCriterion(
              key: 'objective',
              label: 'Objetivo',
              score: 18,
              maxScore: 20,
              status: 'good',
              feedback: 'O objetivo está claro.',
            ),
          ],
          strengths: const ['Objetivo está bem definido.'],
          improvements: const ['Detalhe melhor: público.'],
          suggestions: const ['Defina para quem a resposta será criada.'],
        );
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
      parentPromptId: current.parentPromptId,
      rootPromptId: current.rootPromptId,
      versionNumber: current.versionNumber,
      refinementInstruction: current.refinementInstruction,
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
