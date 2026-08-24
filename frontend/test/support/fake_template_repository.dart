import 'dart:async';

import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/templates/data/template_repository.dart';
import 'package:gupmax_ai/features/templates/domain/prompt_template.dart';

class FakeTemplateRepository implements TemplateRepositoryContract {
  List<PromptTemplateRecord> items = [];
  Completer<TemplatePageData>? listCompleter;
  AppException? error;
  int listCalls = 0;
  int saveCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;

  @override
  Future<TemplatePageData> list() async {
    listCalls++;
    if (error case final value?) throw value;
    return listCompleter?.future ?? TemplatePageData(items, items.length);
  }

  @override
  Future<PromptTemplateRecord> get(String id) async =>
      items.firstWhere((item) => item.id == id);

  @override
  Future<PromptTemplateRecord> fromPrompt(
      String promptId, String name, String? description) async {
    saveCalls++;
    if (error case final value?) throw value;
    final created = sample(
        id: 'saved-template',
        name: name,
        description: description,
        sourcePromptId: promptId);
    items = [created, ...items];
    return created;
  }

  @override
  Future<PromptTemplateRecord> update(
      String id, Map<String, dynamic> values) async {
    updateCalls++;
    final current = await get(id);
    final updated = sample(
      id: current.id,
      name: values['name'] as String? ?? current.name,
      description: values.containsKey('description')
          ? values['description'] as String?
          : current.description,
      templateContent:
          values['template_content'] as String? ?? current.templateContent,
      category: values['category'] == null
          ? current.category
          : PromptCategory.fromValue(values['category'] as String),
      mode: values['mode'] == null
          ? current.mode
          : PromptMode.values.byName(values['mode'] as String),
    );
    items = [
      for (final item in items)
        if (item.id == id) updated else item
    ];
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    items = items.where((item) => item.id != id).toList();
  }
}

PromptTemplateRecord sample({
  String id = 'template-1',
  String name = 'Campanha para pizzaria',
  String? description = 'Base para redes sociais',
  String? sourcePromptId = 'prompt-1',
  String templateContent = '## OBJECTIVE\nDivulgar uma pizzaria',
  String baseInput = 'Criar campanha para pizzaria',
  PromptCategory category = PromptCategory.marketing,
  PromptMode mode = PromptMode.basic,
  String tone = 'casual',
  String additionalInformation = 'Canal/plataforma: TikTok',
}) =>
    PromptTemplateRecord(
      id: id,
      name: name,
      description: description,
      sourcePromptId: sourcePromptId,
      category: category,
      mode: mode,
      templateContent: templateContent,
      baseInput: baseInput,
      language: 'pt-BR',
      tone: tone,
      audience: 'clientes locais',
      context: 'Pizzaria de bairro',
      outputFormat: 'lista curta',
      constraints: const ['Não invente preços'],
      instructions: const ['Seja objetivo'],
      additionalInformation: additionalInformation,
      createdAt: DateTime.utc(2026, 8, 19),
      updatedAt: DateTime.utc(2026, 8, 19),
    );
