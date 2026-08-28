import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../domain/project.dart';
import '../project_overview.dart';
import '../project_providers.dart';

const _allProjectsQuery = ProjectOverviewQuery(includeArchived: true);

class ProjectListPage extends ConsumerStatefulWidget {
  const ProjectListPage({super.key});
  @override
  ConsumerState<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends ConsumerState<ProjectListPage> {
  void _refresh() =>
      ref.invalidate(projectOverviewsProvider(_allProjectsQuery));

  Future<void> _form([ProjectRecord? project]) async {
    final name = TextEditingController(text: project?.name);
    final description = TextEditingController(text: project?.description);
    final projectContext = TextEditingController(text: project?.context);
    final save = await showDialog<bool>(
      context: context,
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
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                TextField(
                  controller: projectContext,
                  minLines: 3,
                  maxLines: 6,
                  decoration:
                      const InputDecoration(labelText: 'Contexto do projeto'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('save_project'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salvar projeto'),
          ),
        ],
      ),
    );
    if (save == true && name.text.trim().length >= 3) {
      final values = {
        'name': name.text.trim(),
        'description':
            description.text.trim().isEmpty ? null : description.text.trim(),
        'context': projectContext.text.trim().isEmpty
            ? null
            : projectContext.text.trim(),
      };
      if (project == null) {
        await ref.read(projectControllerProvider).create(values);
      } else {
        await ref.read(projectControllerProvider).update(project.id, values);
      }
      _refresh();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      description.dispose();
      projectContext.dispose();
    });
  }

  Future<void> _toggleArchive(ProjectRecord project) async {
    await ref.read(projectControllerProvider).update(project.id, {
      'status': project.status == ProjectStatus.active ? 'archived' : 'active',
    });
    _refresh();
  }

  Future<void> _delete(ProjectRecord project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir projeto?'),
        content: const Text(
          'Prompts e templates serão preservados sem associação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm_project_delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(projectControllerProvider).remove(project.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final overviews = ref.watch(projectOverviewsProvider(_allProjectsQuery));
    return Scaffold(
      appBar: const AppPageAppBar(title: 'Meus projetos'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_project'),
        onPressed: _form,
        icon: const Icon(Icons.add),
        label: const Text('Novo projeto'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: overviews.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
            child: Text('Não foi possível carregar seus projetos.'),
          ),
          data: (items) => items.isEmpty
              ? const Center(
                  key: Key('projects_empty'),
                  child: Text('Você ainda não possui projetos.'),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth >= 900
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final item in items)
                            SizedBox(
                              width: width,
                              child: Card(
                                key: Key('project_${item.key}'),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      if (item.categoryLabel
                                          case final category?)
                                        Text(category),
                                      if (item.progressLabel
                                          case final progress?)
                                        Text(progress),
                                      Text(item.statusLabel),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          FilledButton(
                                            key:
                                                Key('open_project_${item.key}'),
                                            onPressed: () =>
                                                context.go(item.route),
                                            child: Text(item.canContinue
                                                ? 'Continuar'
                                                : 'Abrir'),
                                          ),
                                          if (item.project
                                              case final project?) ...[
                                            TextButton(
                                              onPressed: () => _form(project),
                                              child: const Text('Editar'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  _toggleArchive(project),
                                              child: Text(project.status ==
                                                      ProjectStatus.active
                                                  ? 'Arquivar'
                                                  : 'Reativar'),
                                            ),
                                            TextButton(
                                              onPressed: () => _delete(project),
                                              child: const Text('Excluir'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
