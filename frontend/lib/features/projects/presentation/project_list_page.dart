import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../domain/project.dart';
import '../project_providers.dart';

class ProjectListPage extends ConsumerStatefulWidget {
  const ProjectListPage({super.key});
  @override
  ConsumerState<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends ConsumerState<ProjectListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(ref.read(projectControllerProvider).load);
  }

  Future<void> _form([ProjectRecord? project]) async {
    final name = TextEditingController(text: project?.name);
    final description = TextEditingController(text: project?.description);
    final context = TextEditingController(text: project?.context);
    final save = await showDialog<bool>(
      context: this.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(project == null ? 'Criar projeto' : 'Editar projeto'),
        content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    key: const Key('project_name'),
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome')),
                TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Descrição')),
                TextField(
                    controller: context,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                        labelText: 'Contexto do projeto')),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
              key: const Key('save_project'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salvar projeto')),
        ],
      ),
    );
    if (save == true && name.text.trim().length >= 3) {
      final values = {
        'name': name.text.trim(),
        'description':
            description.text.trim().isEmpty ? null : description.text.trim(),
        'context': context.text.trim().isEmpty ? null : context.text.trim(),
      };
      if (project == null) {
        await ref.read(projectControllerProvider).create(values);
      } else {
        await ref.read(projectControllerProvider).update(project.id, values);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      description.dispose();
      context.dispose();
    });
  }

  Future<void> _delete(ProjectRecord project) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Excluir projeto?'),
              content: const Text(
                  'Prompts e templates serão preservados sem associação.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    key: const Key('confirm_project_delete'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Excluir')),
              ],
            ));
    if (confirmed == true) {
      await ref.read(projectControllerProvider).remove(project.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectControllerProvider);
    return Scaffold(
      appBar: const AppPageAppBar(title: 'Meus projetos'),
      floatingActionButton: FloatingActionButton.extended(
          key: const Key('create_project'),
          onPressed: _form,
          icon: const Icon(Icons.add),
          label: const Text('Novo projeto')),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: state.loading && state.items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null && state.items.isEmpty
                  ? Center(child: Text(state.error!))
                  : state.items.isEmpty
                      ? const Center(
                          key: Key('projects_empty'),
                          child: Text('Você ainda não possui projetos.'))
                      : LayoutBuilder(builder: (context, constraints) {
                          final width = constraints.maxWidth >= 900
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth;
                          return SingleChildScrollView(
                              child: Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: state.items
                                .map((project) => SizedBox(
                                      width: width,
                                      child: Card(
                                          key: Key('project_${project.id}'),
                                          child: Padding(
                                              padding: const EdgeInsets.all(20),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(project.name,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleLarge),
                                                  if (project.description !=
                                                      null)
                                                    Text(project.description!),
                                                  Text(
                                                      '${project.promptCount} prompts • ${project.templateCount} templates'),
                                                  Text(project.status ==
                                                          ProjectStatus.active
                                                      ? 'Ativo'
                                                      : 'Arquivado'),
                                                  Wrap(spacing: 6, children: [
                                                    FilledButton(
                                                        onPressed: () => context.go(
                                                            '/projects/${project.id}'),
                                                        child: const Text(
                                                            'Abrir')),
                                                    TextButton(
                                                        onPressed: () =>
                                                            _form(project),
                                                        child: const Text(
                                                            'Editar')),
                                                    TextButton(
                                                        onPressed: () => ref
                                                                .read(
                                                                    projectControllerProvider)
                                                                .update(
                                                                    project.id,
                                                                    {
                                                                  'status': project
                                                                              .status ==
                                                                          ProjectStatus
                                                                              .active
                                                                      ? 'archived'
                                                                      : 'active'
                                                                }),
                                                        child: Text(project
                                                                    .status ==
                                                                ProjectStatus
                                                                    .active
                                                            ? 'Arquivar'
                                                            : 'Reativar')),
                                                    TextButton(
                                                        onPressed: () =>
                                                            _delete(project),
                                                        child: const Text(
                                                            'Excluir')),
                                                  ]),
                                                ],
                                              ))),
                                    ))
                                .toList(),
                          ));
                        })),
    );
  }
}
