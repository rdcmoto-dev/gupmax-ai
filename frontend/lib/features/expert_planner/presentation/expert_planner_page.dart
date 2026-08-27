import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../prompts/domain/prompt_models.dart';
import '../domain/expert_plan.dart';
import '../expert_planner_providers.dart';
import 'expert_planner_controller.dart';

class ExpertPlannerPage extends ConsumerStatefulWidget {
  const ExpertPlannerPage({required this.input, super.key});
  final PromptGenerateInput? input;

  @override
  ConsumerState<ExpertPlannerPage> createState() => _ExpertPlannerPageState();
}

class _ExpertPlannerPageState extends ConsumerState<ExpertPlannerPage> {
  final _name = TextEditingController();
  List<ExpertPlanStep> _steps = [];

  @override
  void initState() {
    super.initState();
    if (widget.input != null) {
      Future<void>.microtask(() async {
        final controller = ref.read(expertPlannerControllerProvider);
        await controller.load(widget.input!);
        if (mounted && controller.plan != null) {
          setState(() {
            _name.text = controller.plan!.suggestedName;
            _steps = [...controller.plan!.steps];
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _renumber() {
    _steps = [
      for (var index = 0; index < _steps.length; index++)
        _steps[index].copyWith(position: index + 1),
    ];
  }

  Future<void> _edit(int index) async {
    var title = _steps[index].title;
    var base = _steps[index].baseInput;
    var target = _steps[index].targetAi;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Editar etapa ${index + 1}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  key: const Key('planner_edit_title'),
                  initialValue: title,
                  onChanged: (value) => title = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                    key: const Key('planner_edit_base'),
                    initialValue: base,
                    onChanged: (value) => base = value,
                    minLines: 3,
                    maxLines: 7),
                const SizedBox(height: 12),
                DropdownButtonFormField<TargetAI>(
                  key: const Key('planner_edit_target'),
                  initialValue: target,
                  items: TargetAI.values
                      .map((item) => DropdownMenuItem(
                          value: item, child: Text(item.label)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => target = value ?? target),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (accepted == true &&
        title.trim().length >= 3 &&
        base.trim().length >= 3) {
      setState(() => _steps[index] = _steps[index].copyWith(
          title: title.trim(),
          objective: base.trim(),
          baseInput: base.trim(),
          targetAi: target));
    }
  }

  void _move(int from, int to) => setState(() {
        final item = _steps.removeAt(from);
        _steps.insert(to, item);
        _renumber();
      });

  void _add() => setState(() {
        if (_steps.length >= 20) return;
        _steps.add(ExpertPlanStep(
          position: _steps.length + 1,
          title: 'Nova etapa',
          objective: 'Descreva o objetivo desta etapa',
          baseInput: 'Descreva o objetivo desta etapa',
          category: widget.input?.category ?? PromptCategory.general,
          mode: PromptMode.expert,
          targetAi: widget.input?.targetAi ?? TargetAI.generic,
          requiresPreviousResult: false,
        ));
      });

  Future<void> _save() async {
    if (_name.text.trim().length < 3 || _steps.isEmpty) return;
    final id = await ref.read(expertPlannerControllerProvider).createChain(
        name: _name.text.trim(),
        projectId: widget.input?.projectId,
        steps: _steps);
    if (mounted && id != null) context.go('/chains/$id');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(expertPlannerControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Plano de execução')),
      body: widget.input == null
          ? const Center(child: Text('Volte à criação e informe uma ideia.'))
          : state.loading
              ? const Center(
                  child: CircularProgressIndicator(key: Key('planner_loading')))
              : state.error != null && state.plan == null
                  ? Center(
                      child:
                          Text(state.error!, key: const Key('planner_error')))
                  : _content(state),
    );
  }

  Widget _content(ExpertPlannerController state) =>
      LayoutBuilder(builder: (context, constraints) {
        final plan = state.plan;
        return ListView(
          key: const Key('expert_plan'),
          padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 28),
          children: [
            Text('Plano sugerido',
                style: Theme.of(context).textTheme.headlineMedium),
            if (plan != null) ...[
              const SizedBox(height: 8),
              Text(
                  plan.planningRecommended
                      ? 'Este projeto se beneficia de várias etapas.'
                      : 'Planejamento opcional: ajuste as etapas como preferir.',
                  key: const Key('planning_recommendation')),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('planner_chain_name'),
              controller: _name,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Nome do fluxo'),
            ),
            for (var index = 0; index < _steps.length; index++)
              Card(
                key: Key('planner_step_$index'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${index + 1}. ${_steps[index].title}',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(_steps[index].baseInput),
                        const SizedBox(height: 8),
                        Text('Destino: ${_steps[index].targetAi.label}'),
                        Wrap(spacing: 4, children: [
                          IconButton(
                              key: Key('planner_edit_$index'),
                              tooltip: 'Editar',
                              onPressed: () => _edit(index),
                              icon: const Icon(Icons.edit_outlined)),
                          IconButton(
                              key: Key('planner_up_$index'),
                              tooltip: 'Mover para cima',
                              onPressed: index == 0
                                  ? null
                                  : () => _move(index, index - 1),
                              icon: const Icon(Icons.arrow_upward)),
                          IconButton(
                              key: Key('planner_down_$index'),
                              tooltip: 'Mover para baixo',
                              onPressed: index == _steps.length - 1
                                  ? null
                                  : () => _move(index, index + 1),
                              icon: const Icon(Icons.arrow_downward)),
                          IconButton(
                              key: Key('planner_remove_$index'),
                              tooltip: 'Remover',
                              onPressed: _steps.length <= 1
                                  ? null
                                  : () => setState(() {
                                        _steps.removeAt(index);
                                        _renumber();
                                      }),
                              icon: const Icon(Icons.delete_outline)),
                        ]),
                      ]),
                ),
              ),
            OutlinedButton.icon(
                key: const Key('planner_add_step'),
                onPressed: _steps.length >= 20 ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar etapa')),
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.end, spacing: 12, children: [
              TextButton(
                  key: const Key('planner_cancel'),
                  onPressed: () => context.pop(),
                  child: const Text('Cancelar')),
              FilledButton.icon(
                  key: const Key('planner_create_chain'),
                  onPressed: state.saving ? null : _save,
                  icon: const Icon(Icons.account_tree_outlined),
                  label:
                      Text(state.saving ? 'Criando fluxo...' : 'Criar fluxo')),
            ]),
          ],
        );
      });
}
