import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../../prompts/prompt_providers.dart';
import '../../templates/template_providers.dart';
import '../project_providers.dart';

class ProjectDetailPage extends ConsumerStatefulWidget {
  const ProjectDetailPage({required this.projectId, super.key});
  final String projectId;
  @override
  ConsumerState<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends ConsumerState<ProjectDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(projectControllerProvider).loadDetail(widget.projectId));
  }

  Future<void> _addPrompt() async {
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
                      child: Text(item.title)))
                  .toList(),
            ));
    if (id != null) {
      await ref
          .read(projectControllerProvider)
          .assignPrompt(widget.projectId, id);
    }
  }

  Future<void> _addTemplate() async {
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
                      child: Text(item.name)))
                  .toList(),
            ));
    if (id != null) {
      await ref
          .read(projectControllerProvider)
          .assignTemplate(widget.projectId, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectControllerProvider);
    final project =
        state.selected?.id == widget.projectId ? state.selected : null;
    return Scaffold(
      appBar: const AppPageAppBar(title: 'Projeto'),
      body: project == null
          ? Center(
              child: state.error == null
                  ? const CircularProgressIndicator()
                  : Text(state.error!))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(project.name,
                      style: Theme.of(context).textTheme.headlineMedium),
                  if (project.description != null) Text(project.description!),
                  if (project.context != null)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(project.context!))),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                        key: const Key('create_prompt_in_project'),
                        onPressed: project.status.name == 'active'
                            ? () =>
                                context.go('/prompts/new?project=${project.id}')
                            : null,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Criar prompt neste projeto')),
                    OutlinedButton(
                        onPressed: _addPrompt,
                        child: const Text('Adicionar prompt existente')),
                    OutlinedButton(
                        onPressed: _addTemplate,
                        child: const Text('Adicionar template existente')),
                  ]),
                  const SizedBox(height: 24),
                  Text('Prompts do projeto',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (project.prompts.isEmpty)
                    const Text('Nenhum prompt associado.'),
                  ...project.prompts.map((prompt) => ListTile(
                      title: Text(prompt.title),
                      onTap: () => context.go('/prompts/${prompt.id}'),
                      trailing: IconButton(
                          tooltip: 'Remover do projeto',
                          icon: const Icon(Icons.link_off),
                          onPressed: () => ref
                              .read(projectControllerProvider)
                              .removePrompt(project.id, prompt.id)))),
                  const SizedBox(height: 16),
                  Text('Templates do projeto',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (project.templates.isEmpty)
                    const Text('Nenhum template associado.'),
                  ...project.templates.map((template) => ListTile(
                      title: Text(template.name),
                      onTap: () => context.go(
                          '/prompts/new?project=${project.id}&template=${template.id}'),
                      trailing: IconButton(
                          tooltip: 'Remover do projeto',
                          icon: const Icon(Icons.link_off),
                          onPressed: () => ref
                              .read(projectControllerProvider)
                              .removeTemplate(project.id, template.id)))),
                ],
              )),
    );
  }
}
