import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../../prompt_chains/domain/prompt_chain.dart';
import '../../prompt_chains/prompt_chain_providers.dart';
import '../../prompts/prompt_providers.dart';
import '../../templates/template_providers.dart';
import '../domain/project.dart';
import '../project_goals.dart';
import '../project_export.dart';
import '../project_health.dart';
import '../project_memory.dart';
import '../project_milestones.dart';
import '../project_insight.dart';
import '../project_review.dart';
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
  bool _savingGoals = false;
  bool _savingMilestones = false;
  bool _savingCompletion = false;
  bool _savingReview = false;
  bool _savingProject = false;
  bool _exporting = false;

  Future<void> _exportProject(ProjectRecord project) async {
    final format = await showDialog<ProjectExportFormat>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exportar projeto'),
        content: const Text(
          'Baixe uma cópia organizada dos dados deste projeto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          OutlinedButton.icon(
            key: const Key('export_project_markdown'),
            onPressed: () =>
                Navigator.pop(dialogContext, ProjectExportFormat.markdown),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Markdown'),
          ),
          FilledButton.icon(
            key: const Key('export_project_json'),
            onPressed: () =>
                Navigator.pop(dialogContext, ProjectExportFormat.json),
            icon: const Icon(Icons.data_object),
            label: const Text('JSON'),
          ),
        ],
      ),
    );
    if (format == null || !mounted || _exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await ref
          .read(projectRepositoryProvider)
          .export(project.id, project.name, format);
      ref.read(fileDownloadProvider).download(
            bytes: file.bytes,
            filename: file.filename,
            mimeType: file.mimeType,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.filename} baixado.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível exportar o projeto.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveCompletion(ProjectRecord project, String? context) async {
    setState(() => _savingCompletion = true);
    final success = await ref
        .read(projectControllerProvider)
        .update(project.id, {'context': context});
    if (!mounted) return;
    setState(() => _savingCompletion = false);
    if (success) ref.invalidate(projectWorkspaceProvider(widget.target));
    final messenger = ScaffoldMessenger.of(this.context)..hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(success
          ? 'Status manual atualizado.'
          : 'Não foi possível atualizar o status manual.'),
    ));
  }

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
    final allEntries = ProjectMemory.parse(project.context);
    final structuredEntries = allEntries
        .where((entry) =>
            ProjectGoals.isGoalEntry(entry) ||
            ProjectMilestones.isMilestoneEntry(entry) ||
            ProjectReview.isReviewEntry(entry))
        .toList(growable: false);
    final drafts = allEntries
        .where((entry) =>
            !ProjectGoals.isGoalEntry(entry) &&
            !ProjectMilestones.isMilestoneEntry(entry) &&
            !ProjectReview.isReviewEntry(entry))
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
                        onPressed: drafts.length + structuredEntries.length <
                                ProjectMemory.maxEntries
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
                  ProjectMemory.serialize([
                    ...structuredEntries,
                    ...drafts.map((draft) => draft.entry),
                  ]);
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
      final contextValue = ProjectMemory.serialize([
        ...structuredEntries,
        ...drafts.map((draft) => draft.entry),
      ]);
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

  Future<void> _editGoals(ProjectRecord project) async {
    final current = ProjectGoals.parse(project.context);
    final objective = TextEditingController(text: current.objective);
    final criteria = current.criteria
        .map((value) => TextEditingController(text: value))
        .toList(growable: true);
    final retired = <TextEditingController>[];
    final formKey = GlobalKey<FormState>();
    String? dialogError;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar objetivos'),
          content: SizedBox(
            width: 640,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('project_goal_objective'),
                      controller: objective,
                      maxLength: ProjectMemory.maxValueLength,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Objetivo principal',
                        hintText: 'O que você quer alcançar?',
                      ),
                      onChanged: (_) => setDialogState(() {
                        dialogError = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Text('Critérios de sucesso',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text(
                      'Os itens abaixo são critérios definidos, não uma confirmação de que foram alcançados.',
                    ),
                    const SizedBox(height: 10),
                    for (var index = 0; index < criteria.length; index++)
                      Padding(
                        key: ValueKey(criteria[index]),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: Key('project_goal_criterion_$index'),
                                controller: criteria[index],
                                maxLength: ProjectMemory.maxValueLength,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: 'Critério ${index + 1}',
                                ),
                              ),
                            ),
                            IconButton(
                              key: Key('remove_project_goal_criterion_$index'),
                              onPressed: () => setDialogState(() {
                                retired.add(criteria.removeAt(index));
                                dialogError = null;
                              }),
                              tooltip: 'Remover critério',
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('add_project_goal_criterion'),
                        onPressed: criteria.length <
                                ProjectGoals.availableCriteria(
                                  project.context,
                                  hasObjective:
                                      objective.text.trim().isNotEmpty,
                                )
                            ? () => setDialogState(() {
                                  criteria.add(TextEditingController());
                                  dialogError = null;
                                })
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar critério'),
                      ),
                    ),
                    if (dialogError != null)
                      Text(
                        dialogError!,
                        key: const Key('project_goals_error'),
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
              key: const Key('save_project_goals'),
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  ProjectGoals.merge(
                    context: project.context,
                    objective: objective.text,
                    criteria: criteria.map((item) => item.text),
                  );
                  Navigator.pop(dialogContext, true);
                } on FormatException catch (error) {
                  setDialogState(() => dialogError = error.message);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar objetivos'),
            ),
          ],
        ),
      ),
    );
    if (save == true && mounted) {
      final merged = ProjectGoals.merge(
        context: project.context,
        objective: objective.text,
        criteria: criteria.map((item) => item.text),
      );
      setState(() => _savingGoals = true);
      final success = await ref
          .read(projectControllerProvider)
          .update(project.id, {'context': merged});
      if (mounted) {
        setState(() => _savingGoals = false);
        if (success) ref.invalidate(projectWorkspaceProvider(widget.target));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Objetivos do projeto salvos.'
              : 'Não foi possível salvar os objetivos do projeto.'),
        ));
      }
    }
    await Future<void>.delayed(kThemeAnimationDuration);
    objective.dispose();
    for (final controller in [...criteria, ...retired]) {
      controller.dispose();
    }
  }

  Future<void> _editMilestones(ProjectRecord project) async {
    final milestones = ProjectMilestones.parse(project.context)
        .items
        .map((value) => TextEditingController(text: value))
        .toList(growable: true);
    final retired = <TextEditingController>[];
    final formKey = GlobalKey<FormState>();
    String? dialogError;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar marcos'),
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
                      'Registre pontos importantes planejados para o caminho do projeto.',
                    ),
                    const SizedBox(height: 12),
                    for (var index = 0; index < milestones.length; index++)
                      Padding(
                        key: ValueKey(milestones[index]),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: Key('project_milestone_$index'),
                                controller: milestones[index],
                                maxLength: ProjectMilestones.maxItemLength,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: 'Marco ${index + 1}',
                                ),
                                onChanged: (_) =>
                                    setDialogState(() => dialogError = null),
                              ),
                            ),
                            IconButton(
                              key: Key('remove_project_milestone_$index'),
                              onPressed: () => setDialogState(() {
                                retired.add(milestones.removeAt(index));
                                dialogError = null;
                              }),
                              tooltip: 'Remover marco',
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('add_project_milestone'),
                        onPressed: ProjectMilestones.canAdd(
                          context: project.context,
                          milestones: milestones.map((item) => item.text),
                        )
                            ? () => setDialogState(() {
                                  milestones.add(TextEditingController());
                                  dialogError = null;
                                })
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar marco'),
                      ),
                    ),
                    if (!ProjectMilestones.canAdd(
                      context: project.context,
                      milestones: milestones.map((item) => item.text),
                    ))
                      Text(
                        ProjectMilestones.addUnavailableReason(
                          context: project.context,
                          milestones: milestones.map((item) => item.text),
                        )!,
                        key: const Key('project_milestones_add_reason'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (dialogError != null)
                      Text(
                        dialogError!,
                        key: const Key('project_milestones_error'),
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
              key: const Key('save_project_milestones'),
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  ProjectMilestones.merge(
                    context: project.context,
                    milestones: milestones.map((item) => item.text),
                  );
                  Navigator.pop(dialogContext, true);
                } on FormatException catch (error) {
                  setDialogState(() => dialogError = error.message);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar marcos'),
            ),
          ],
        ),
      ),
    );
    if (save == true && mounted) {
      final merged = ProjectMilestones.merge(
        context: project.context,
        milestones: milestones.map((item) => item.text),
      );
      setState(() => _savingMilestones = true);
      final success = await ref
          .read(projectControllerProvider)
          .update(project.id, {'context': merged});
      if (mounted) {
        setState(() => _savingMilestones = false);
        if (success) ref.invalidate(projectWorkspaceProvider(widget.target));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Marcos do projeto salvos.'
              : 'Não foi possível salvar os marcos do projeto.'),
        ));
      }
    }
    await Future<void>.delayed(kThemeAnimationDuration);
    for (final controller in [...milestones, ...retired]) {
      controller.dispose();
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

  Future<void> _reviewProject(
    ProjectRecord project,
    PromptChainRecord? chain,
  ) async {
    final current = ProjectReview.parse(project.context);
    final summary = projectReviewSummaryFor(project: project, chain: chain);
    final conclusion = TextEditingController(text: current.conclusion);
    String? dialogError;
    final action = await showDialog<_ReviewAction>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Revisão final'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReviewSummary(summary: summary),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('project_final_conclusion'),
                    controller: conclusion,
                    maxLength: ProjectReview.maxConclusionLength,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Conclusão do projeto (opcional)',
                      hintText: 'Registre observações finais confirmadas.',
                    ),
                    onChanged: (_) => setDialogState(() => dialogError = null),
                  ),
                  if (summary.hasPendingItems && !current.isClosed)
                    const Text(
                      'Há itens pendentes. O projeto pode ser encerrado sem concluir a Chain, critérios ou marcos.',
                      key: Key('project_review_pending_warning'),
                    ),
                  if (dialogError != null)
                    Text(
                      dialogError!,
                      key: const Key('project_review_error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              key: const Key('save_project_review'),
              onPressed: () {
                try {
                  ProjectReview.merge(
                    context: project.context,
                    conclusion: conclusion.text,
                    isClosed: current.isClosed,
                  );
                  Navigator.pop(dialogContext, _ReviewAction.save);
                } on FormatException catch (error) {
                  setDialogState(() => dialogError = error.message);
                }
              },
              child: const Text('Salvar revisão'),
            ),
            FilledButton(
              key: Key(current.isClosed ? 'reopen_project' : 'close_project'),
              onPressed: () => Navigator.pop(
                dialogContext,
                current.isClosed ? _ReviewAction.reopen : _ReviewAction.close,
              ),
              child: Text(
                  current.isClosed ? 'Reabrir projeto' : 'Encerrar projeto'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      await Future<void>.delayed(kThemeAnimationDuration);
      conclusion.dispose();
      return;
    }
    if (action == _ReviewAction.close) {
      final confirmed = await _confirmClosure(project.name);
      if (!confirmed || !mounted) {
        await Future<void>.delayed(kThemeAnimationDuration);
        conclusion.dispose();
        return;
      }
    }
    final closed = switch (action) {
      _ReviewAction.close => true,
      _ReviewAction.reopen => false,
      _ReviewAction.save => current.isClosed,
    };
    String? merged;
    try {
      merged = ProjectReview.merge(
        context: project.context,
        conclusion: conclusion.text,
        isClosed: closed,
      );
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      await Future<void>.delayed(kThemeAnimationDuration);
      conclusion.dispose();
      return;
    }
    setState(() => _savingReview = true);
    final success = await ref
        .read(projectControllerProvider)
        .update(project.id, {'context': merged});
    if (!mounted) return;
    setState(() => _savingReview = false);
    if (success) ref.invalidate(projectWorkspaceProvider(widget.target));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? closed
              ? 'Projeto encerrado.'
              : action == _ReviewAction.reopen
                  ? 'Projeto reaberto.'
                  : 'Revisão do projeto salva.'
          : 'Não foi possível atualizar a revisão do projeto.'),
    ));
    await Future<void>.delayed(kThemeAnimationDuration);
    conclusion.dispose();
  }

  Future<bool> _confirmClosure(String projectName) async {
    final controller = TextEditingController();
    var matches = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirmar encerramento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Digite “$projectName” para confirmar.'),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('confirm_project_name'),
                  controller: controller,
                  onChanged: (value) => setDialogState(
                    () => matches = value.trim() == projectName,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('confirm_close_project'),
              onPressed:
                  matches ? () => Navigator.pop(dialogContext, true) : null,
              child: const Text('Confirmar encerramento'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(kThemeAnimationDuration);
    controller.dispose();
    return confirmed == true;
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
                      _ProjectHealthCard(
                        health: projectHealthFor(
                          project: data.project,
                          chain: data.chain,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ProjectGoalsCard(
                        project: data.project,
                        saving: _savingGoals,
                        savingCompletion: _savingCompletion,
                        onEdit: data.project == null
                            ? null
                            : () => _editGoals(data.project!),
                        onToggleCriterion: data.project == null
                            ? null
                            : (criterion, completed) => _saveCompletion(
                                  data.project!,
                                  ProjectGoals.toggleCriterion(
                                    context: data.project!.context,
                                    criterion: criterion,
                                    completed: completed,
                                  ),
                                ),
                      ),
                      const SizedBox(height: 18),
                      _ProjectMilestonesCard(
                        project: data.project,
                        saving: _savingMilestones,
                        savingCompletion: _savingCompletion,
                        onEdit: data.project == null
                            ? null
                            : () => _editMilestones(data.project!),
                        onToggleMilestone: data.project == null
                            ? null
                            : (milestone, completed) => _saveCompletion(
                                  data.project!,
                                  ProjectMilestones.toggle(
                                    context: data.project!.context,
                                    milestone: milestone,
                                    completed: completed,
                                  ),
                                ),
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
                      const SizedBox(height: 18),
                      _ProjectReviewCard(
                        project: data.project,
                        review: data.project == null
                            ? null
                            : ProjectReview.parse(data.project!.context),
                        saving: _savingReview,
                        exporting: _exporting,
                        onExport: data.project == null
                            ? null
                            : () => _exportProject(data.project!),
                        onReview: data.project == null
                            ? null
                            : () => _reviewProject(data.project!, data.chain),
                      ),
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

enum _ReviewAction { save, close, reopen }

class _ProjectReviewCard extends StatelessWidget {
  const _ProjectReviewCard({
    required this.project,
    required this.review,
    required this.saving,
    required this.exporting,
    required this.onExport,
    required this.onReview,
  });

  final ProjectRecord? project;
  final ProjectReview? review;
  final bool saving;
  final bool exporting;
  final VoidCallback? onExport;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('project_review_card'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Revisão do projeto',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (project != null)
                    OutlinedButton.icon(
                      key: const Key('export_project'),
                      onPressed: saving || exporting ? null : onExport,
                      icon: exporting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(
                          exporting ? 'Exportando...' : 'Exportar projeto'),
                    ),
                  if (project != null)
                    OutlinedButton.icon(
                      key: const Key('review_project'),
                      onPressed: saving ? null : onReview,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(review?.isClosed ?? false
                              ? Icons.lock_open_outlined
                              : Icons.fact_check_outlined),
                      label: Text(review?.isClosed ?? false
                          ? 'Revisão final'
                          : 'Revisar projeto'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (project == null)
                const Text(
                  'Salve este fluxo como projeto para registrar uma revisão final.',
                )
              else ...[
                Text(review!.isClosed ? 'Projeto encerrado' : 'Projeto ativo'),
                const SizedBox(height: 6),
                Text(
                  review!.conclusion ?? 'Conclusão final ainda não registrada.',
                  key: const Key('project_conclusion_text'),
                ),
              ],
            ],
          ),
        ),
      );
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.summary});

  final ProjectReviewSummary summary;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Resumo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Objetivo: ${summary.objective ?? 'Não definido'}'),
          Text(
            'Critérios: ${summary.criteriaCount} definidos, ${summary.confirmedCriteriaCount} confirmados',
          ),
          Text(
            'Marcos: ${summary.milestoneCount} definidos, ${summary.confirmedMilestoneCount} confirmados',
          ),
          Text(
            summary.totalSteps == 0
                ? 'Chain: não associada'
                : 'Chain: ${summary.completedSteps} de ${summary.totalSteps} etapas concluídas',
          ),
          Text('Conteúdo: ${summary.promptCount} prompts'),
          Text('Saúde do projeto: ${summary.health.label}'),
        ],
      );
}

class _ProjectGoalsCard extends StatelessWidget {
  const _ProjectGoalsCard({
    required this.project,
    required this.saving,
    required this.savingCompletion,
    required this.onEdit,
    required this.onToggleCriterion,
  });

  final ProjectRecord? project;
  final bool saving;
  final bool savingCompletion;
  final VoidCallback? onEdit;
  final void Function(String, bool)? onToggleCriterion;

  @override
  Widget build(BuildContext context) {
    final goals = ProjectGoals.parse(project?.context);
    return Card(
      key: const Key('project_goals'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final title = Text('Objetivo do projeto',
                  style: Theme.of(context).textTheme.titleLarge);
              final action = onEdit == null
                  ? null
                  : TextButton.icon(
                      key: const Key('edit_project_goals'),
                      onPressed: saving ? null : onEdit,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_outlined, size: 18),
                      label: Text(goals.isEmpty
                          ? 'Definir objetivo'
                          : 'Editar objetivos'),
                    );
              if (constraints.maxWidth < 360 && action != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    Align(alignment: Alignment.centerLeft, child: action),
                  ],
                );
              }
              return Row(children: [
                Expanded(child: title),
                if (action != null) action,
              ]);
            }),
            const SizedBox(height: 10),
            if (project == null)
              const Text(
                'Salve este fluxo como projeto para definir objetivos persistentes.',
                key: Key('chain_without_project_goals'),
              )
            else if (goals.isEmpty)
              const Text(
                'Objetivo ainda não definido.',
                key: Key('empty_project_goals'),
              )
            else ...[
              if (goals.objective case final objective?) ...[
                Text('Objetivo', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(objective, key: const Key('project_goal_value')),
              ],
              if (goals.criteria.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Critérios de sucesso definidos',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 5),
                for (var index = 0; index < goals.criteria.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          key: Key('project_criterion_completion_$index'),
                          value:
                              goals.isCriterionCompleted(goals.criteria[index]),
                          onChanged:
                              savingCompletion || onToggleCriterion == null
                                  ? null
                                  : (value) => onToggleCriterion!(
                                      goals.criteria[index], value ?? false),
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: Text(
                            goals.criteria[index],
                            key: Key('project_goal_criterion_value_$index'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  'Status confirmado manualmente por você.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProjectMilestonesCard extends StatelessWidget {
  const _ProjectMilestonesCard({
    required this.project,
    required this.saving,
    required this.savingCompletion,
    required this.onEdit,
    required this.onToggleMilestone,
  });

  final ProjectRecord? project;
  final bool saving;
  final bool savingCompletion;
  final VoidCallback? onEdit;
  final void Function(String, bool)? onToggleMilestone;

  @override
  Widget build(BuildContext context) {
    final milestones = ProjectMilestones.parse(project?.context);
    return Card(
      key: const Key('project_milestones'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final title = Text(
                'Marcos do projeto',
                style: Theme.of(context).textTheme.titleLarge,
              );
              final action = onEdit == null
                  ? null
                  : TextButton.icon(
                      key: const Key('edit_project_milestones'),
                      onPressed: saving ? null : onEdit,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_outlined, size: 18),
                      label: Text(milestones.isEmpty
                          ? 'Definir marcos'
                          : 'Editar marcos'),
                    );
              if (constraints.maxWidth < 360 && action != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    Align(alignment: Alignment.centerLeft, child: action),
                  ],
                );
              }
              return Row(children: [
                Expanded(child: title),
                if (action != null) action,
              ]);
            }),
            const SizedBox(height: 10),
            if (project == null)
              const Text(
                'Salve este fluxo como projeto para definir marcos persistentes.',
                key: Key('chain_without_project_milestones'),
              )
            else if (milestones.isEmpty)
              const Text(
                'Nenhum marco definido.',
                key: Key('empty_project_milestones'),
              )
            else
              for (var index = 0; index < milestones.items.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        key: Key('project_milestone_completion_$index'),
                        value: milestones.isCompleted(milestones.items[index]),
                        onChanged: savingCompletion || onToggleMilestone == null
                            ? null
                            : (value) => onToggleMilestone!(
                                milestones.items[index], value ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                      Expanded(
                        child: Text(
                          milestones.items[index],
                          key: Key('project_milestone_value_$index'),
                        ),
                      ),
                    ],
                  ),
                ),
            if (project != null && milestones.items.isNotEmpty)
              Text('Status confirmado manualmente por você.',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ProjectHealthCard extends StatelessWidget {
  const _ProjectHealthCard({required this.health});

  final ProjectHealth health;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('project_health'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Saúde do projeto',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                health.label,
                key: const Key('project_health_state'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _healthColor(context, health.state),
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < health.signals.length; index++)
                Padding(
                  key: Key('project_health_signal_$index'),
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        health.signals[index].kind ==
                                ProjectHealthSignalKind.positive
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 18,
                        color: health.signals[index].kind ==
                                ProjectHealthSignalKind.positive
                            ? Colors.green.shade700
                            : Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(health.signals[index].label)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

Color _healthColor(BuildContext context, ProjectHealthState state) =>
    switch (state) {
      ProjectHealthState.good => Colors.green.shade800,
      ProjectHealthState.attention => Theme.of(context).colorScheme.secondary,
      ProjectHealthState.needsSetup =>
        Theme.of(context).colorScheme.onSurfaceVariant,
      ProjectHealthState.completed => Colors.green.shade800,
    };

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
              if (_visibleProjectContext(data.context)
                  case final projectContext?) ...[
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
    final entries = ProjectMemory.parse(project?.context)
        .where((entry) =>
            !ProjectGoals.isGoalEntry(entry) &&
            !ProjectMilestones.isMilestoneEntry(entry) &&
            !ProjectReview.isReviewEntry(entry))
        .toList(growable: false);
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
                'O GUPMAX ainda não possui outras informações salvas sobre este projeto.',
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

String? _visibleProjectContext(String? context) {
  if (context == null) return null;
  final lines = context
      .split('\n')
      .where((rawLine) {
        final line = rawLine.trim();
        final separator = line.indexOf(':');
        if (separator <= 0) return line.isNotEmpty;
        return !ProjectReview.isReviewEntry(ProjectMemoryEntry(
          label: line.substring(0, separator).trim(),
          value: line.substring(separator + 1).trim(),
        ));
      })
      .map((line) => line.trim())
      .toList(growable: false);
  return lines.isEmpty ? null : lines.join('\n');
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
