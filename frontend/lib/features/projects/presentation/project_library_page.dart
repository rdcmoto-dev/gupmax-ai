import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../../prompt_chains/prompt_chain_providers.dart';
import '../project_library.dart';
import '../project_providers.dart';

class ProjectLibraryPage extends ConsumerWidget {
  const ProjectLibraryPage({required this.projectId, super.key});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(projectLibraryProvider(projectId));
    return Scaffold(
      appBar: AppPageAppBar(
          title: 'Conteúdo do projeto',
          fallbackLocation: '/projects/$projectId'),
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(projectLibraryProvider(projectId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'))),
        data: (data) => RefreshIndicator(
          onRefresh: () =>
              ref.refresh(projectLibraryProvider(projectId).future),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Summary(data),
                          const SizedBox(height: 18),
                          _Prompts(data.prompts),
                          const SizedBox(height: 18),
                          _Flows(data.chains),
                          if (data.activity.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _Activity(data.activity),
                          ],
                        ]))),
          ]),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.data);
  final ProjectLibraryData data;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(spacing: 12, runSpacing: 10, children: [
            Chip(
                avatar: const Icon(Icons.auto_awesome_outlined),
                label: Text('${data.promptTotal} prompts')),
            Chip(
                avatar: const Icon(Icons.task_alt),
                label: Text('${data.completedStepCount} etapas concluídas')),
            Chip(
                avatar: const Icon(Icons.update),
                label: Text('Última atividade: ${_date(data.lastActivityAt)}')),
          ])));
}

class _Prompts extends StatelessWidget {
  const _Prompts(this.items);
  final List<ProjectLibraryPrompt> items;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Prompts', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('Nenhum prompt foi criado neste projeto.')
            else
              for (final prompt in items)
                ListTile(
                  key: Key('library_prompt_${prompt.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                      child: Icon(Icons.auto_awesome_outlined)),
                  title: Text(prompt.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${prompt.category.label} • ${prompt.mode.name.toUpperCase()} • '
                      '${prompt.targetAi.label}${prompt.versionCount > 1 ? ' • ${prompt.versionCount} versões' : ''}'),
                  trailing: FilledButton.tonalIcon(
                      onPressed: () => context.push('/prompts/${prompt.id}'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir')),
                ),
          ])));
}

class _Flows extends ConsumerWidget {
  const _Flows(this.chains);
  final List<ProjectLibraryChain> chains;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Fluxo e resultados',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (chains.isEmpty)
              const Text('Este projeto ainda não possui um fluxo associado.')
            else
              for (final chain in chains) ...[
                Text(
                    '${chain.name} • ${chain.completedCount} de ${chain.stepCount} etapas',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final step in chain.steps)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(step.status == 'completed'
                        ? Icons.check_circle
                        : step.status == 'in_progress'
                            ? Icons.play_circle
                            : Icons.radio_button_unchecked),
                    title: Text('${step.position}. ${step.title}'),
                    subtitle: Text(step.status == 'completed'
                        ? 'Concluída'
                        : step.status == 'in_progress'
                            ? 'Etapa atual'
                            : 'Pendente'),
                    trailing: step.hasResult
                        ? TextButton.icon(
                            onPressed: () async {
                              final detail = await ref
                                  .read(promptChainRepositoryProvider)
                                  .get(chain.id);
                              final result = detail.steps
                                  .where((item) => item.id == step.id)
                                  .firstOrNull
                                  ?.result;
                              if (!context.mounted) return;
                              await showDialog<void>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: Text(step.title),
                                  content: SingleChildScrollView(
                                      child: SelectableText(result ?? '')),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text('Fechar'))
                                  ],
                                ),
                              );
                            },
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Ver resultado'))
                        : null,
                  ),
                Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                        onPressed: () => context.push('/chains/${chain.id}'),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(chain.currentStepId == null
                            ? 'Abrir fluxo'
                            : 'Continuar projeto'))),
              ],
          ])));
}

class _Activity extends StatelessWidget {
  const _Activity(this.items);
  final List<ProjectActivity> items;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Atividade recente',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final item in items.take(8))
              ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(item.label),
                  subtitle: Text(_date(item.occurredAt))),
          ])));
}

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
