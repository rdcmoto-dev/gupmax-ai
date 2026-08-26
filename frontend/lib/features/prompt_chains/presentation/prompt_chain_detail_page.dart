import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../prompts/domain/prompt_models.dart';
import '../../templates/template_providers.dart';
import '../domain/prompt_chain.dart';
import '../prompt_chain_providers.dart';

class PromptChainDetailPage extends ConsumerStatefulWidget {
  const PromptChainDetailPage({required this.chainId, super.key});
  final String chainId;
  @override
  ConsumerState<PromptChainDetailPage> createState() =>
      _PromptChainDetailPageState();
}

class _PromptChainDetailPageState extends ConsumerState<PromptChainDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(promptChainControllerProvider).open(widget.chainId));
  }

  Future<void> _addStep() async {
    await ref.read(templateControllerProvider).load();
    if (!mounted) return;
    final templates = ref.read(templateControllerProvider).items;
    final title = TextEditingController();
    final input = TextEditingController();
    var mode = PromptMode.basic;
    var category = PromptCategory.general;
    var target = TargetAI.generic;
    String? templateId;
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('Adicionar etapa'),
                content: SizedBox(
                    width: 620,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String?>(
                          key: const Key('step_template'),
                          isExpanded: true,
                          initialValue: templateId,
                          items: [
                            const DropdownMenuItem<String?>(
                                value: null, child: Text('Sem template')),
                            ...templates.map((template) =>
                                DropdownMenuItem<String?>(
                                    value: template.id,
                                    child: Text(template.name))),
                          ],
                          onChanged: (value) {
                            setState(() => templateId = value);
                            if (value == null) return;
                            final selected = templates
                                .firstWhere((item) => item.id == value);
                            input.text = selected.baseInput;
                            mode = selected.mode;
                            category = selected.category;
                            target = selected.targetAi;
                          },
                          decoration: const InputDecoration(
                              labelText: 'Template (opcional)')),
                      TextField(
                          key: const Key('step_title'),
                          controller: title,
                          decoration:
                              const InputDecoration(labelText: 'Título *')),
                      TextField(
                          key: const Key('step_input'),
                          controller: input,
                          minLines: 4,
                          maxLines: 10,
                          decoration: const InputDecoration(
                              labelText: 'Prompt/base *')),
                      DropdownButtonFormField(
                          isExpanded: true,
                          initialValue: mode,
                          items: PromptMode.values
                              .map((v) => DropdownMenuItem(
                                  value: v, child: Text(v.name.toUpperCase())))
                              .toList(),
                          onChanged: (v) => setState(() => mode = v!),
                          decoration: const InputDecoration(labelText: 'Modo')),
                      DropdownButtonFormField(
                          isExpanded: true,
                          initialValue: category,
                          items: PromptCategory.values
                              .map((v) => DropdownMenuItem(
                                  value: v, child: Text(v.label)))
                              .toList(),
                          onChanged: (v) => setState(() => category = v!),
                          decoration:
                              const InputDecoration(labelText: 'Categoria')),
                      DropdownButtonFormField(
                          isExpanded: true,
                          initialValue: target,
                          items: TargetAI.values
                              .map((v) => DropdownMenuItem(
                                  value: v, child: Text(v.label)))
                              .toList(),
                          onChanged: (v) => setState(() => target = v!),
                          decoration:
                              const InputDecoration(labelText: 'Target AI')),
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      key: const Key('save_step'),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Adicionar')),
                ],
              ),
            ));
    if (save == true &&
        title.text.trim().length >= 3 &&
        input.text.trim().length >= 3) {
      await ref.read(promptChainControllerProvider).addStep(widget.chainId, {
        'title': title.text.trim(),
        'base_input': input.text.trim(),
        'template_id': templateId,
        'mode': mode.name,
        'category': category.value,
        'target_ai': target.value,
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      title.dispose();
      input.dispose();
    });
  }

  Future<void> _editStep(PromptChainStep step) async {
    final title = TextEditingController(text: step.title);
    final input = TextEditingController(text: step.baseInput);
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Editar etapa'),
              content: SizedBox(
                  width: 620,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        key: const Key('edit_step_title'),
                        controller: title,
                        decoration:
                            const InputDecoration(labelText: 'Título *')),
                    TextField(
                        key: const Key('edit_step_input'),
                        controller: input,
                        minLines: 4,
                        maxLines: 10,
                        decoration:
                            const InputDecoration(labelText: 'Prompt/base *')),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    key: const Key('save_step_edit'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Salvar')),
              ],
            ));
    if (save == true) {
      await ref
          .read(promptChainControllerProvider)
          .updateStep(widget.chainId, step.id, {
        'title': title.text.trim(),
        'base_input': input.text.trim(),
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      title.dispose();
      input.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptChainControllerProvider);
    final chain = state.selected;
    final canAddStep = chain != null && chain.steps.length < 20;
    return Scaffold(
      appBar: AppBar(title: Text(chain?.name ?? 'Fluxo')),
      body: state.loading && chain == null
          ? const Center(child: CircularProgressIndicator())
          : chain == null
              ? Center(child: Text(state.error ?? 'Fluxo não encontrado.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: const Key('add_step'),
                          onPressed: canAddStep ? _addStep : null,
                          child: Text(canAddStep
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
                          return Card(
                              key: Key('chain_step_${step.id}'),
                              child: ListTile(
                                leading:
                                    CircleAvatar(child: Text('${index + 1}')),
                                title: Text(step.title),
                                subtitle: Text(
                                    '${step.targetAi.label} • ${step.mode.name.toUpperCase()}${step.requiresPreviousResult ? ' • usa resultado anterior' : ''}'),
                                trailing: Wrap(children: [
                                  IconButton(
                                      tooltip: 'Mover para cima',
                                      onPressed: index == 0
                                          ? null
                                          : () => ref
                                              .read(
                                                  promptChainControllerProvider)
                                              .move(widget.chainId, index,
                                                  index - 1),
                                      icon: const Icon(Icons.arrow_upward)),
                                  IconButton(
                                      tooltip: 'Mover para baixo',
                                      onPressed: index == chain.steps.length - 1
                                          ? null
                                          : () => ref
                                              .read(
                                                  promptChainControllerProvider)
                                              .move(widget.chainId, index,
                                                  index + 1),
                                      icon: const Icon(Icons.arrow_downward)),
                                  TextButton(
                                      key: Key('use_step_${step.id}'),
                                      onPressed: () => context.go(
                                          '/prompts/new?chain=${widget.chainId}&step=${step.id}'),
                                      child: const Text('Usar etapa')),
                                  IconButton(
                                      tooltip: 'Editar etapa',
                                      onPressed: () => _editStep(step),
                                      icon: const Icon(Icons.edit_outlined)),
                                  IconButton(
                                      tooltip: 'Excluir etapa',
                                      onPressed: () => ref
                                          .read(promptChainControllerProvider)
                                          .deleteStep(widget.chainId, step.id),
                                      icon: const Icon(Icons.delete_outline)),
                                ]),
                              ));
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
