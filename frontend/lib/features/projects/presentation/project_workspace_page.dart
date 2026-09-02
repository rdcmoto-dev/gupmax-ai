import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../../prompt_chains/domain/prompt_chain.dart';
import '../../prompt_chains/prompt_chain_providers.dart';
import '../../prompts/prompt_providers.dart';
import '../../templates/template_providers.dart';
import '../domain/project.dart';
import '../project_memory.dart';
import '../project_insight.dart';
import '../project_providers.dart';
import '../project_workspace.dart';

class ProjectWorkspacePage extends ConsumerStatefulWidget {
  const ProjectWorkspacePage({required this.target, super.key});

  final ProjectWorkspaceTarget target;

  @override
  ConsumerState<ProjectWorkspacePage> createState() =>
      _ProjectWorkspacePageState();
}

class _ProjectWorkspacePageState extends ConsumerState<ProjectWorkspacePage> {
  bool _starting = false;
  bool _savingMemory = false;
  bool _savingProject = false;

  Future<void> _saveAsProject(PromptChainRecord chain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salvar como projeto?'),
        content: Text(
          'O fluxo “${chain.name}” será associado a um projeto real. O progresso atual será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const Key('confirm_save_chain_as_project'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar como projeto'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingProject = true);
    try {
      await ref.read(projectRepositoryProvider).createFromChain(chain.id);
      ref.invalidate(projectWorkspaceProvider(widget.target));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Projeto criado e associado ao fluxo.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar este fluxo como projeto.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingProject = false);
    }
  }

  Future<void> _editMemory(ProjectRecord project) async {
    final drafts = ProjectMemory.parse(project.context)
        .map((entry) => _MemoryDraft(entry.label, entry.value))
        .toList();
    final retiredDrafts = <_MemoryDraft>[];
    if (drafts.isEmpty) drafts.add(_MemoryDraft('', ''));
    final formKey = GlobalKey<FormState>();
    String? dialogError;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar contexto do projeto'),
          content: SizedBox(
            width: 640,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Registre somente informações confirmadas. Campos vazios não serão salvos.',
                    ),
                    const SizedBox(height: 16),
                    for (var index = 0; index < drafts.length; index++)
                      _MemoryEditorRow(
                        key: ValueKey(drafts[index]),
                        index: index,
                        draft: drafts[index],
                        onRemove: () => setDialogState(() {
                          retiredDrafts.add(drafts.removeAt(index));
                          if (drafts.isEmpty) drafts.add(_MemoryDraft('', ''));
                          dialogError = null;
                        }),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('add_project_memory'),
                        onPressed: drafts.length < ProjectMemory.maxEntries
                            ? () => setDialogState(() {
                                  drafts.add(_MemoryDraft('', ''));
                                  dialogError = null;
                                })
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar informação'),
                      ),
                    ),
                    if (dialogError != null)
                      Text(
                        dialogError!,
                        key: const Key('project_memory_error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              key: const Key('save_project_memory'),
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  ProjectMemory.serialize(drafts.map((draft) => draft.entry));
                  Navigator.pop(dialogContext, true);
                } on FormatException catch (error) {
                  setDialogState(() => dialogError = error.message);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar contexto'),
            ),
          ],
        ),
      ),
    );
    if (save == true && mounted) {
      setState(() => _savingMemory = true);
      final contextValue =
          ProjectMemory.serialize(drafts.map((draft) => draft.entry));
      final success = await ref
          .read(projectControllerProvider)
          .update(project.id, {'context': contextValue});
      if (mounted) {
        setState(() => _savingMemory = false);
        if (success) {
          ref.invalidate(projectWorkspaceProvider(widget.target));
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Contexto do projeto salvo.'
              : 'Não foi possível salvar o contexto do projeto.'),
        ));
      }
    }
    await Future<void>.delayed(kThemeAnimationDuration);
    for (final draft in [...drafts, ...retiredDrafts]) {
      draft.dispose();
    }
  }

  Future<void> _addPrompt(String projectId) async {
    final prompts = ref.read(promptControllerProvider);
    await prompts.loadPage();
    if (!mounted) return;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Adicionar prompt existente'),
        children: prompts.items
            .where((item) => item.projectId == null)
            .map((item) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, item.id),
                  child: Text(item.title),
                ))
            .toList(),
      ),
    );
    if (id == null) return;
    await ref.read(projectRepositoryProvider).assignPrompt(projectId, id);
    ref.invalidate(projectWorkspaceProvider(widget.target));
  }

  Future<void> _addTemplate(String projectId) async {
    final templates = ref.read(templateControllerProvider);
    await templates.load();
    if (!mounted) return;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Adicionar template existente'),
        children: templates.items
            .where((item) => item.projectId == null)
            .map((item) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, item.id),
                  child: Text(item.name),
                ))
            .toList(),
      ),
    );
    if (id == null) return;
    await ref.read(projectRepositoryProvider).assignTemplate(projectId, id);
    ref.invalidate(projectWorkspaceProvider(widget.target));
  }

  Future<void> _removePrompt(String projectId, String promptId) async {
    await ref.read(projectRepositoryProvider).removePrompt(projectId, promptId);
    ref.invalidate(projectWorkspaceProvider(widget.target));
  }

  Future<void> _removeTemplate(String projectId, String templateId) async {
    await ref
        .read(projectRepositoryProvider)
        .removeTemplate(projectId, templateId);
    ref.invalidate(projectWorkspaceProvider(widget.target));
  }

  Future<void> _openChain(PromptChainRecord chain) async {
    final pending = !chain.executionCompleted &&
        chain.completedStepCount == 0 &&
        chain.currentStepId == null;
    if (pending) {
      setState(() => _starting = true);
      try {
        await ref.read(promptChainRepositoryProvider).startExecution(chain.id);
        ref.invalidate(projectWorkspaceProvider(widget.target));
      } finally {
        if (mounted) setState(() => _starting = false);
      }
    }
    if (mounted) await context.push('/chains/${chain.id}');
    if (mounted) ref.invalidate(projectWorkspaceProvider(widget.target));
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(projectWorkspaceProvider(widget.target));
    return Scaffold(
      appBar: const AppPageAppBar(
        title: 'Central do projeto',
        fallbackLocation: '/projects',
      ),
      body: workspace.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _WorkspaceError(
          onRetry: () =>
              ref.invalidate(projectWorkspaceProvider(widget.target)),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async =>
              ref.refresh(projectWorkspaceProvider(widget.target).future),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProjectHeader(data: data),
                      const SizedBox(height: 18),
                      _ProjectInsightCard(
                        insight: projectInsightFor(
                          project: data.project,
                          chain: data.chain,
                        ),
                        starting: _starting,
                        onAction: (action) => _handleInsight(action, data),
                      ),
                      const SizedBox(height: 18),
                      _ProjectMemoryCard(
                        project: data.project,
                        chain: data.chain,
                        saving: _savingMemory,
                        savingProject: _savingProject,
                        onEdit: data.project == null
                            ? null
                            : () => _editMemory(data.project!),
                        onSaveAsProject:
                            data.project == null && data.chain != null
                                ? () => _saveAsProject(data.chain!)
                                : null,
                      ),
                      if (data.project case final project?) ...[
                        const SizedBox(height: 18),
                        _ProjectContentCard(projectId: project.id),
                      ],
                      if (data.chain case final chain?) ...[
                        const SizedBox(height: 18),
                        _ProgressCard(
                          chain: chain,
                        ),
                        const SizedBox(height: 18),
                        _StepsCard(chain: chain),
                      ] else if (data.project case final project?) ...[
                        const SizedBox(height: 18),
                        _ProjectActions(
                          project: project,
                          onAddPrompt: () => _addPrompt(project.id),
                          onAddTemplate: () => _addTemplate(project.id),
                        ),
                      ],
                      if (data.project case final project?) ...[
                        const SizedBox(height: 18),
                        _ProjectPrompts(
                          project: project,
                          onRemove: (promptId) =>
                              _removePrompt(project.id, promptId),
                        ),
                        const SizedBox(height: 18),
                        _ProjectTemplates(
                          project: project,
                          onRemove: (templateId) =>
                              _removeTemplate(project.id, templateId),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleInsight(
    ProjectInsightAction action,
    ProjectWorkspaceData data,
  ) async {
    switch (action) {
      case ProjectInsightAction.continueChain:
      case ProjectInsightAction.startChain:
      case ProjectInsightAction.viewCompletedChain:
        await _openChain(data.chain!);
        return;
      case ProjectInsightAction.editContext:
        await _editMemory(data.project!);
        return;
      case ProjectInsightAction.createPrompt:
        await context.push('/prompts/new?project=${data.project!.id}');
        return;
      case ProjectInsightAction.viewContent:
        await context.push('/projects/${data.project!.id}/content');
        return;
      case ProjectInsightAction.none:
        return;
    }
  }
}

class _ProjectInsightCard extends StatelessWidget {
  const _ProjectInsightCard({
    required this.insight,
    required this.starting,
    required this.onAction,
  });

  final ProjectInsight insight;
  final bool starting;
  final ValueChanged<ProjectInsightAction> onAction;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('project_next_step'),
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Próximo passo',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                insight.recommendation,
                key: const Key('project_next_step_recommendation'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(insight.explanation),
              if (insight.actionLabel case final label?) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const Key('workspace_primary_action'),
                    onPressed: starting ? null : () => onAction(insight.action),
                    icon: Icon(_insightIcon(insight.action)),
                    label: Text(starting ? 'Iniciando...' : label),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

IconData _insightIcon(ProjectInsightAction action) => switch (action) {
      ProjectInsightAction.continueChain => Icons.play_arrow_rounded,
      ProjectInsightAction.startChain => Icons.rocket_launch_outlined,
      ProjectInsightAction.editContext => Icons.edit_outlined,
      ProjectInsightAction.createPrompt => Icons.auto_awesome,
      ProjectInsightAction.viewContent => Icons.folder_open_outlined,
      ProjectInsightAction.viewCompletedChain => Icons.visibility_outlined,
      ProjectInsightAction.none => Icons.check_circle_outline,
    };

class _ProjectContentCard extends ConsumerWidget {
  const _ProjectContentCard({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(projectLibraryProvider(projectId));
    return Card(
      key: const Key('project_content_summary'),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Conteúdo do projeto',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          library.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) =>
                const Text('Não foi possível carregar o resumo agora.'),
            data: (data) => Text(
              '${data.promptTotal} prompts • ${data.completedStepCount} etapas concluídas',
              key: const Key('project_content_summary_label'),
            ),
          ),
          const SizedBox(height: 14),
          Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const Key('open_project_content'),
                onPressed: () => context.push('/projects/$projectId/content'),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Ver conteúdo'),
              )),
        ]),
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.data});
  final ProjectWorkspaceData data;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.name,
                  style: Theme.of(context).textTheme.headlineMedium),
              if (data.description case final description?) ...[
                const SizedBox(height: 6),
                Text(description),
              ],
              if (data.context case final projectContext?) ...[
                const SizedBox(height: 12),
                Text('Contexto do projeto',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(projectContext),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (data.categoryLabel case final category?)
                    Chip(
                      avatar: const Icon(Icons.category_outlined, size: 18),
                      label: Text(category),
                    ),
                  Chip(
                    avatar: const Icon(Icons.flag_outlined, size: 18),
                    label: Text(data.statusLabel),
                  ),
                  if (data.recentAt case final date?)
                    Chip(
                      avatar: const Icon(Icons.update, size: 18),
                      label: Text('Atualizado em ${_date(date)}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _ProjectMemoryCard extends StatelessWidget {
  const _ProjectMemoryCard({
    required this.project,
    required this.chain,
    required this.saving,
    required this.savingProject,
    required this.onEdit,
    required this.onSaveAsProject,
  });

  final ProjectRecord? project;
  final PromptChainRecord? chain;
  final bool saving;
  final bool savingProject;
  final VoidCallback? onEdit;
  final VoidCallback? onSaveAsProject;

  @override
  Widget build(BuildContext context) {
    final entries = ProjectMemory.parse(project?.context);
    return Card(
      key: const Key('project_memory_card'),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final heading = Row(
                  children: [
                    const Icon(Icons.psychology_alt_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Contexto do projeto',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                );
                final edit = onEdit == null
                    ? null
                    : TextButton.icon(
                        key: const Key('edit_project_memory'),
                        onPressed: saving ? null : onEdit,
                        icon: saving
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.edit_outlined, size: 18),
                        label: Text(saving ? 'Salvando...' : 'Editar contexto'),
                      );
                if (constraints.maxWidth < 360 && edit != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      Align(alignment: Alignment.centerLeft, child: edit),
                    ],
                  );
                }
                return Row(children: [
                  Expanded(child: heading),
                  if (edit != null) edit
                ]);
              },
            ),
            const SizedBox(height: 10),
            if (project == null) ...[
              Text(
                chain == null
                    ? 'Nenhum contexto disponível.'
                    : 'Este fluxo ainda não está associado a um projeto. O contexto do fluxo continua disponível, mas nenhuma memória será criada automaticamente.',
                key: const Key('chain_without_project_memory'),
              ),
              if (onSaveAsProject != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const Key('save_chain_as_project'),
                    onPressed: savingProject ? null : onSaveAsProject,
                    icon: savingProject
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_business_outlined),
                    label: Text(savingProject
                        ? 'Salvando projeto...'
                        : 'Salvar como projeto'),
                  ),
                ),
              ],
            ] else if (entries.isEmpty)
              const Text(
                'O GUPMAX ainda não possui informações salvas sobre este projeto.',
                key: Key('empty_project_memory'),
              )
            else ...[
              for (final entry in entries.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${entry.label}: ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: entry.value),
                      ],
                    ),
                  ),
                ),
              if (entries.length > 4)
                Text('+ ${entries.length - 4} informações salvas'),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemoryEditorRow extends StatelessWidget {
  const _MemoryEditorRow({
    required this.index,
    required this.draft,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _MemoryDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final fields = [
              SizedBox(
                width: compact ? constraints.maxWidth : 180,
                child: TextFormField(
                  key: Key('project_memory_label_$index'),
                  controller: draft.label,
                  maxLength: ProjectMemory.maxLabelLength,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de informação',
                    hintText: 'Ex.: Público',
                    counterText: '',
                  ),
                  validator: (_) => draft.isPartiallyFilled
                      ? 'Preencha o tipo e a informação.'
                      : null,
                ),
              ),
              if (!compact) const SizedBox(width: 10),
              SizedBox(
                width:
                    compact ? constraints.maxWidth : constraints.maxWidth - 238,
                child: TextFormField(
                  key: Key('project_memory_value_$index'),
                  controller: draft.value,
                  maxLength: ProjectMemory.maxValueLength,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Informação',
                    counterText: '',
                  ),
                  validator: (_) => draft.isPartiallyFilled
                      ? 'Preencha o tipo e a informação.'
                      : null,
                ),
              ),
              IconButton(
                key: Key('remove_project_memory_$index'),
                tooltip: 'Remover informação',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ];
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      fields[0],
                      const SizedBox(height: 8),
                      fields[1],
                      Align(alignment: Alignment.centerRight, child: fields[2])
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: fields);
          },
        ),
      );
}

class _MemoryDraft {
  _MemoryDraft(String initialLabel, String initialValue)
      : label = TextEditingController(text: initialLabel),
        value = TextEditingController(text: initialValue);

  final TextEditingController label;
  final TextEditingController value;

  bool get isPartiallyFilled =>
      label.text.trim().isEmpty != value.text.trim().isEmpty;

  ProjectMemoryEntry get entry =>
      ProjectMemoryEntry(label: label.text, value: value.text);

  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.chain});

  final PromptChainRecord chain;

  @override
  Widget build(BuildContext context) {
    final total = chain.steps.isEmpty ? chain.stepCount : chain.steps.length;
    return Card(
      key: const Key('workspace_progress'),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Progresso', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${chain.completedStepCount} de $total etapas concluídas',
              key: const Key('workspace_progress_label'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: total == 0 ? 0 : chain.completedStepCount / total,
              minHeight: 10,
              borderRadius: BorderRadius.circular(10),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.chain});
  final PromptChainRecord chain;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Etapas do projeto',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (chain.steps.isEmpty)
                const Text('Este projeto ainda não possui etapas.')
              else
                for (final step in chain.steps)
                  _CompactStep(
                    step: step,
                    current: chain.currentStepId == step.id,
                  ),
            ],
          ),
        ),
      );
}

class _CompactStep extends StatelessWidget {
  const _CompactStep({required this.step, required this.current});
  final PromptChainStep step;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final completed = step.executionStatus == PromptChainStepStatus.completed;
    return Container(
      key: Key('workspace_step_${step.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: current
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: current
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            completed
                ? Icons.check_circle
                : current
                    ? Icons.arrow_circle_right
                    : Icons.radio_button_unchecked,
            color: completed
                ? Colors.green.shade700
                : current
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${step.position}. ${step.title}',
              style: TextStyle(fontWeight: current ? FontWeight.w800 : null),
            ),
          ),
          Text(completed
              ? 'Concluída'
              : current
                  ? 'Atual'
                  : 'Pendente'),
        ],
      ),
    );
  }
}

class _ProjectActions extends StatelessWidget {
  const _ProjectActions({
    required this.project,
    required this.onAddPrompt,
    required this.onAddTemplate,
  });
  final ProjectRecord project;
  final VoidCallback onAddPrompt;
  final VoidCallback onAddTemplate;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('create_prompt_in_project'),
                onPressed: project.status == ProjectStatus.active
                    ? () => context.push('/prompts/new?project=${project.id}')
                    : null,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Criar prompt neste projeto'),
              ),
              OutlinedButton.icon(
                onPressed:
                    project.status == ProjectStatus.active ? onAddPrompt : null,
                icon: const Icon(Icons.add_link),
                label: const Text('Adicionar prompt'),
              ),
              OutlinedButton.icon(
                onPressed: project.status == ProjectStatus.active
                    ? onAddTemplate
                    : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Adicionar template'),
              ),
            ],
          ),
        ),
      );
}

class _ProjectPrompts extends StatelessWidget {
  const _ProjectPrompts({required this.project, required this.onRemove});
  final ProjectRecord project;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Prompts do projeto',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (project.prompts.isEmpty)
                const Text('Nenhum prompt associado.')
              else
                for (final prompt in project.prompts.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(prompt.title),
                    trailing: IconButton(
                      tooltip: 'Remover do projeto',
                      icon: const Icon(Icons.link_off),
                      onPressed: () => onRemove(prompt.id),
                    ),
                    onTap: () => context.push('/prompts/${prompt.id}'),
                  ),
            ],
          ),
        ),
      );
}

class _ProjectTemplates extends StatelessWidget {
  const _ProjectTemplates({required this.project, required this.onRemove});
  final ProjectRecord project;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Templates do projeto',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (project.templates.isEmpty)
                const Text('Nenhum template associado.')
              else
                for (final template in project.templates.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: Text(template.name),
                    trailing: IconButton(
                      tooltip: 'Remover do projeto',
                      icon: const Icon(Icons.link_off),
                      onPressed: () => onRemove(template.id),
                    ),
                    onTap: () => context.push(
                      '/prompts/new?project=${project.id}&template=${template.id}',
                    ),
                  ),
            ],
          ),
        ),
      );
}

class _WorkspaceError extends StatelessWidget {
  const _WorkspaceError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Projeto não encontrado ou indisponível.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
}

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
