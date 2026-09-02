import 'package:gupmax_ai/features/prompt_chains/data/prompt_chain_repository.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/templates/domain/prompt_template.dart';

class FakePromptChainRepository implements PromptChainRepositoryContract {
  List<PromptChainRecord> items = [];
  int createCalls = 0;
  int addStepCalls = 0;
  int reorderCalls = 0;
  int startExecutionCalls = 0;
  int deleteCalls = 0;
  int updateCalls = 0;

  @override
  Future<List<PromptChainRecord>> list(
          {bool includeArchived = true, int limit = 20}) async =>
      items.take(limit).toList();
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
      String id, Map<String, dynamic> values) async {
    updateCalls++;
    final current = await get(id);
    final updated = PromptChainRecord(
      id: current.id,
      name: values['name'] as String? ?? current.name,
      description: values['description'] as String? ?? current.description,
      projectId: values.containsKey('project_id')
          ? values['project_id'] as String?
          : current.projectId,
      status: values['status'] == null
          ? current.status
          : PromptChainStatus.values.byName(values['status'] as String),
      stepCount: current.stepCount,
      steps: current.steps,
      completedStepCount: current.completedStepCount,
      currentStepId: current.currentStepId,
      executionCompleted: current.executionCompleted,
      category: current.category,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
    );
    items = [
      for (final item in items)
        if (item.id == id) updated else item,
    ];
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    items = items.where((value) => value.id != id).toList();
  }

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

  @override
  Future<PromptChainRecord> startExecution(String chainId) async {
    startExecutionCalls++;
    final chain = await get(chainId);
    final current = chain.steps.indexWhere(
        (step) => step.executionStatus != PromptChainStepStatus.completed);
    if (current < 0) return chain;
    return _replaceChain(chain, [
      for (var i = 0; i < chain.steps.length; i++)
        _copyStep(
          chain.steps[i],
          status: i == current
              ? PromptChainStepStatus.inProgress
              : chain.steps[i].executionStatus,
        ),
    ]);
  }

  @override
  Future<PromptChainRecord> completeStep(
      String chainId, String stepId, String result) async {
    final chain = await get(chainId);
    final index = chain.steps.indexWhere((step) => step.id == stepId);
    final steps = [
      for (var i = 0; i < chain.steps.length; i++)
        _copyStep(
          chain.steps[i],
          status: i == index
              ? PromptChainStepStatus.completed
              : i == index + 1
                  ? PromptChainStepStatus.inProgress
                  : chain.steps[i].executionStatus,
          result: i == index ? result : chain.steps[i].result,
        ),
    ];
    return _replaceChain(chain, steps);
  }

  PromptChainRecord _replaceChain(
      PromptChainRecord chain, List<PromptChainStep> steps) {
    final completed = steps
        .where((s) => s.executionStatus == PromptChainStepStatus.completed)
        .length;
    final current = steps
        .where((s) => s.executionStatus != PromptChainStepStatus.completed)
        .firstOrNull;
    final updated = PromptChainRecord(
      id: chain.id,
      name: chain.name,
      status: chain.status,
      stepCount: steps.length,
      description: chain.description,
      projectId: chain.projectId,
      steps: steps,
      completedStepCount: completed,
      currentStepId: current?.id,
      executionCompleted: steps.isNotEmpty && completed == steps.length,
      createdAt: chain.createdAt,
      updatedAt: chain.updatedAt,
      category: chain.category,
    );
    items = [
      for (final item in items)
        if (item.id == chain.id) updated else item
    ];
    return updated;
  }
}

PromptChainStep _copyStep(
  PromptChainStep step, {
  required PromptChainStepStatus status,
  String? result,
}) =>
    PromptChainStep(
      id: step.id,
      chainId: step.chainId,
      position: step.position,
      title: step.title,
      baseInput: step.baseInput,
      mode: step.mode,
      category: step.category,
      targetAi: step.targetAi,
      templateId: step.templateId,
      variables: step.variables,
      requiresPreviousResult: step.requiresPreviousResult,
      executionStatus: status,
      result: result,
    );

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
