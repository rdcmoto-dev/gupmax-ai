import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../../prompt_chains/domain/prompt_chain.dart';
import '../../prompt_chains/prompt_chain_providers.dart';
import '../../prompts/prompt_providers.dart';
import '../../templates/template_providers.dart';
import '../domain/project.dart';
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
                      if (data.chain case final chain?) ...[
                        const SizedBox(height: 18),
                        _ProgressCard(
                          chain: chain,
                          starting: _starting,
                          onOpen: () => _openChain(chain),
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

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.chain,
    required this.starting,
    required this.onOpen,
  });

  final PromptChainRecord chain;
  final bool starting;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final total = chain.steps.isEmpty ? chain.stepCount : chain.steps.length;
    final pending = chain.completedStepCount == 0 &&
        chain.currentStepId == null &&
        !chain.executionCompleted;
    final label = chain.executionCompleted
        ? 'Ver projeto concluído'
        : pending
            ? 'Iniciar projeto'
            : 'Continuar projeto';
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
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('workspace_primary_action'),
                onPressed: total == 0 || starting ? null : onOpen,
                icon: Icon(chain.executionCompleted
                    ? Icons.visibility_outlined
                    : pending
                        ? Icons.rocket_launch_outlined
                        : Icons.play_arrow_rounded),
                label: Text(starting ? 'Iniciando...' : label),
              ),
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
