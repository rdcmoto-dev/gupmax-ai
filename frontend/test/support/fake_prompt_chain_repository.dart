import 'package:gupmax_ai/features/prompt_chains/data/prompt_chain_repository.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/templates/domain/prompt_template.dart';

class FakePromptChainRepository implements PromptChainRepositoryContract {
  List<PromptChainRecord> items = [];
  int createCalls = 0;
  int addStepCalls = 0;
  int reorderCalls = 0;

  @override
  Future<List<PromptChainRecord>> list({bool includeArchived = true}) async =>
      items;
  @override
  Future<PromptChainRecord> get(String id) async =>
      items.firstWhere((value) => value.id == id);
  @override
  Future<PromptChainRecord> create(Map<String, dynamic> values) async {
    createCalls++;
    final value = chainSample(name: values['name'] as String);
    items = [value, ...items];
    return value;
  }

  @override
  Future<PromptChainRecord> update(
          String id, Map<String, dynamic> values) async =>
      await get(id);
  @override
  Future<void> delete(String id) async =>
      items = items.where((value) => value.id != id).toList();
  @override
  Future<PromptChainStep> addStep(
      String chainId, Map<String, dynamic> values) async {
    addStepCalls++;
    final chain = await get(chainId);
    final step = PromptChainStep(
      id: 'step-${chain.steps.length + 1}',
      chainId: chainId,
      position: chain.steps.length + 1,
      title: values['title'] as String,
      baseInput: values['base_input'] as String,
      mode: PromptMode.values.byName(values['mode'] as String),
      category: PromptCategory.fromValue(values['category'] as String),
      targetAi: TargetAI.fromValue(values['target_ai'] as String),
      templateId: values['template_id'] as String?,
      variables: detectTemplateVariables(values['base_input'] as String),
      requiresPreviousResult:
          (values['base_input'] as String).contains('{resultado_anterior}'),
    );
    final updated = PromptChainRecord(
      id: chain.id,
      name: chain.name,
      description: chain.description,
      projectId: chain.projectId,
      status: chain.status,
      stepCount: chain.steps.length + 1,
      steps: [...chain.steps, step],
    );
    items = [
      for (final item in items)
        if (item.id == chainId) updated else item
    ];
    return step;
  }

  @override
  Future<PromptChainStep> updateStep(
          String chainId, String stepId, Map<String, dynamic> values) async =>
      stepSample();
  @override
  Future<void> deleteStep(String chainId, String stepId) async {}
  @override
  Future<void> reorder(String chainId, List<String> stepIds) async {
    reorderCalls++;
  }
}

PromptChainStep stepSample({
  String id = 'step-1',
  int position = 1,
  String baseInput = 'Crie para {empresa}',
  bool previous = false,
}) =>
    PromptChainStep(
      id: id,
      chainId: 'chain-1',
      position: position,
      title: 'Posicionamento',
      baseInput: baseInput,
      mode: PromptMode.basic,
      category: PromptCategory.marketing,
      targetAi: TargetAI.chatgpt,
      variables: previous
          ? const []
          : const [TemplateVariable(name: 'empresa', label: 'Empresa')],
      requiresPreviousResult: previous,
    );

PromptChainRecord chainSample(
        {String name = 'Lançamento Donatello', List<PromptChainStep>? steps}) =>
    PromptChainRecord(
        id: 'chain-1',
        name: name,
        status: PromptChainStatus.active,
        stepCount: steps?.length ?? 0,
        steps: steps ?? const []);
