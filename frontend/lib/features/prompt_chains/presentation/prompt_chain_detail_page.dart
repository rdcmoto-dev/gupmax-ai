import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../../prompts/domain/prompt_models.dart';
import '../../templates/domain/prompt_template.dart';
import '../../templates/template_providers.dart';
import '../domain/prompt_chain.dart';
import '../prompt_chain_providers.dart';

class PromptChainDetailPage extends ConsumerStatefulWidget {
  const PromptChainDetailPage({required this.chainId, super.key});
  final String chainId;

  @override
  ConsumerState<PromptChainDetailPage> createState() => _DetailState();
}

class _DetailState extends ConsumerState<PromptChainDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(promptChainControllerProvider).open(widget.chainId));
  }

  Future<Map<String, dynamic>?> _stepDialog([
    PromptChainStep? step,
    List<PromptTemplateRecord> templates = const [],
  ]) async {
    final title = TextEditingController(text: step?.title);
    final input = TextEditingController(text: step?.baseInput);
    var mode = step?.mode ?? PromptMode.basic;
    var category = step?.category ?? PromptCategory.general;
    var target = step?.targetAi ?? TargetAI.generic;
    String? templateId = step?.templateId;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(step == null ? 'Adicionar etapa' : 'Editar etapa'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (step == null)
                  DropdownButtonFormField<String?>(
                    key: const Key('step_template'),
                    isExpanded: true,
                    initialValue: templateId,
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Sem template')),
                      ...templates.map((template) => DropdownMenuItem<String?>(
                          value: template.id, child: Text(template.name))),
                    ],
                    onChanged: (value) {
                      setDialogState(() => templateId = value);
                      if (value == null) return;
                      final selected =
                          templates.firstWhere((item) => item.id == value);
                      input.text = selected.baseInput;
                      mode = selected.mode;
                      category = selected.category;
                      target = selected.targetAi;
                    },
                    decoration:
                        const InputDecoration(labelText: 'Template (opcional)'),
                  ),
                TextField(
                  key: Key(step == null ? 'step_title' : 'edit_step_title'),
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Título *'),
                ),
                TextField(
                  key: Key(step == null ? 'step_input' : 'edit_step_input'),
                  controller: input,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(labelText: 'Prompt/base *'),
                ),
                if (step == null) ...[
                  DropdownButtonFormField(
                    isExpanded: true,
                    initialValue: mode,
                    items: PromptMode.values
                        .map((v) => DropdownMenuItem(
                            value: v, child: Text(v.name.toUpperCase())))
                        .toList(),
                    onChanged: (v) => setDialogState(() => mode = v!),
                    decoration: const InputDecoration(labelText: 'Modo'),
                  ),
                  DropdownButtonFormField(
                    isExpanded: true,
                    initialValue: category,
                    items: PromptCategory.values
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text(v.label)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => category = v!),
                    decoration: const InputDecoration(labelText: 'Categoria'),
                  ),
                  DropdownButtonFormField(
                    isExpanded: true,
                    initialValue: target,
                    items: TargetAI.values
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text(v.label)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => target = v!),
                    decoration: const InputDecoration(labelText: 'Target AI'),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              key: Key(step == null ? 'save_step' : 'save_step_edit'),
              onPressed: () {
                if (title.text.trim().length < 3 ||
                    input.text.trim().length < 3) {
                  return;
                }
                Navigator.pop(context, {
                  'title': title.text.trim(),
                  'base_input': input.text.trim(),
                  if (step == null) ...{
                    'template_id': templateId,
                    'mode': mode.name,
                    'category': category.value,
                    'target_ai': target.value,
                  },
                });
              },
              child: Text(step == null ? 'Adicionar' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      title.dispose();
      input.dispose();
    });
    return values;
  }

  Future<void> _addStep() async {
    await ref.read(templateControllerProvider).load();
    if (!mounted) return;
    final values =
        await _stepDialog(null, ref.read(templateControllerProvider).items);
    if (values != null) {
      await ref
          .read(promptChainControllerProvider)
          .addStep(widget.chainId, values);
    }
  }

  Future<void> _editStep(PromptChainStep step) async {
    final values = await _stepDialog(step);
    if (values != null) {
      await ref
          .read(promptChainControllerProvider)
          .updateStep(widget.chainId, step.id, values);
    }
  }

  Future<void> _complete(PromptChainStep step) async {
    final result = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Concluir etapa ${step.position}'),
        content: TextField(
          key: const Key('step_result'),
          controller: result,
          minLines: 5,
          maxLines: 12,
          maxLength: 10000,
          decoration: const InputDecoration(
            labelText: 'Resultado desta etapa *',
            hintText: 'Cole ou escreva aqui o resultado obtido.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.icon(
            key: const Key('confirm_step_completion'),
            onPressed: () =>
                Navigator.pop(context, result.text.trim().isNotEmpty),
            icon: const Icon(Icons.check),
            label: const Text('Concluir e avançar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(promptChainControllerProvider)
          .completeStep(widget.chainId, step.id, result.text.trim());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => result.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptChainControllerProvider);
    final chain = state.selected;
    if (state.loading && chain == null) {
      return const Scaffold(
        appBar: AppPageAppBar(title: 'Fluxo'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (chain == null) {
      return Scaffold(
          appBar: const AppPageAppBar(title: 'Fluxo'),
          body: Center(child: Text(state.error ?? 'Fluxo não encontrado.')));
    }
    return Scaffold(
      appBar: AppPageAppBar(title: chain.name),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: _Progress(
            chain: chain,
            loading: state.loading,
            onStart: () => ref
                .read(promptChainControllerProvider)
                .startExecution(widget.chainId),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('add_step'),
              onPressed: chain.steps.length < 20 ? _addStep : null,
              icon: const Icon(Icons.add),
              label: Text(chain.steps.length < 20
                  ? '+ Adicionar etapa'
                  : 'Limite de 20 etapas atingido'),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            itemCount: chain.steps.length,
            itemBuilder: (context, index) {
              final step = chain.steps[index];
              return _StepCard(
                step: step,
                index: index,
                total: chain.steps.length,
                current: chain.currentStepId == step.id,
                onUp: index == 0
                    ? null
                    : () => ref
                        .read(promptChainControllerProvider)
                        .move(widget.chainId, index, index - 1),
                onDown: index == chain.steps.length - 1
                    ? null
                    : () => ref
                        .read(promptChainControllerProvider)
                        .move(widget.chainId, index, index + 1),
                onUse: () => context
                    .go('/prompts/new?chain=${widget.chainId}&step=${step.id}'),
                onComplete: () => _complete(step),
                onEdit: () => _editStep(step),
                onDelete: () => ref
                    .read(promptChainControllerProvider)
                    .deleteStep(widget.chainId, step.id),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(
      {required this.chain, required this.loading, required this.onStart});
  final PromptChainRecord chain;
  final bool loading;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final total = chain.steps.length;
    final started = chain.steps
        .any((step) => step.executionStatus != PromptChainStepStatus.pending);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Progresso do fluxo',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${chain.completedStepCount} de $total etapas concluídas'),
          const SizedBox(height: 10),
          LinearProgressIndicator(
              value: total == 0 ? 0 : chain.completedStepCount / total,
              minHeight: 9,
              borderRadius: BorderRadius.circular(10)),
          const SizedBox(height: 14),
          if (chain.executionCompleted)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.verified_outlined),
                  SizedBox(width: 8),
                  Text('Fluxo concluído'),
                ]),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('completed_chains_button'),
                      onPressed: () => context.go('/chains'),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Ver meus fluxos'),
                    ),
                    FilledButton.icon(
                      key: const Key('completed_home_button'),
                      onPressed: () => context.go('/dashboard'),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Ir para o início'),
                    ),
                  ],
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('start_chain_execution'),
                onPressed: total == 0 || loading ? null : onStart,
                icon: Icon(
                    started ? Icons.play_arrow : Icons.rocket_launch_outlined),
                label:
                    Text(started ? 'Retomar etapa atual' : 'Iniciar execução'),
              ),
            ),
        ]),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.index,
    required this.total,
    required this.current,
    required this.onUp,
    required this.onDown,
    required this.onUse,
    required this.onComplete,
    required this.onEdit,
    required this.onDelete,
  });
  final PromptChainStep step;
  final int index;
  final int total;
  final bool current;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onUse;
  final VoidCallback onComplete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        key: Key('chain_step_${step.id}'),
        color: current ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
                child: step.executionStatus == PromptChainStepStatus.completed
                    ? const Icon(Icons.check)
                    : Text('${index + 1}')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                        '${step.targetAi.label} • ${step.mode.name.toUpperCase()}'),
                    const SizedBox(height: 8),
                    _Status(status: step.executionStatus),
                    if (step.result != null) const Text('Resultado registrado'),
                    const SizedBox(height: 6),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      IconButton(
                          tooltip: 'Mover para cima',
                          onPressed: onUp,
                          icon: const Icon(Icons.arrow_upward)),
                      IconButton(
                          tooltip: 'Mover para baixo',
                          onPressed: onDown,
                          icon: const Icon(Icons.arrow_downward)),
                      TextButton(
                          key: Key('use_step_${step.id}'),
                          onPressed: onUse,
                          child: const Text('Usar etapa')),
                      if (current &&
                          step.executionStatus ==
                              PromptChainStepStatus.inProgress)
                        FilledButton.icon(
                          key: Key('complete_step_${step.id}'),
                          onPressed: onComplete,
                          icon: const Icon(Icons.check),
                          label: const Text('Registrar e concluir'),
                        ),
                      IconButton(
                          tooltip: 'Editar etapa',
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined)),
                      IconButton(
                          tooltip: 'Excluir etapa',
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline)),
                    ]),
                  ]),
            ),
          ]),
        ),
      );
}

class _Status extends StatelessWidget {
  const _Status({required this.status});
  final PromptChainStepStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      PromptChainStepStatus.pending => (
          'Pendente',
          Icons.schedule_outlined,
          Colors.grey
        ),
      PromptChainStepStatus.inProgress => (
          'Etapa atual',
          Icons.play_circle_outline,
          Colors.blue
        ),
      PromptChainStepStatus.completed => (
          'Concluída',
          Icons.check_circle_outline,
          Colors.green
        ),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    ]);
  }
}
