import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../../prompt_chains/prompt_chain_providers.dart';
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
  String? _removingKey;
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

  Future<void> _removeOverview(ProjectOverview item) async {
    final linked = item.project != null && item.chain != null;
    final itemKind = linked
        ? 'o projeto e o fluxo associados'
        : item.project != null
            ? 'o projeto'
            : 'o fluxo';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(linked ? 'Arquivar trabalho?' : 'Excluir trabalho?'),
        content: Text(
          linked
              ? '"${item.name}" reúne um projeto e um fluxo. Para preservar etapas, resultados e relações, os dois serão arquivados, não excluídos.'
              : 'Deseja excluir $itemKind "${item.name}"? ${item.project != null ? 'Prompts e templates serão preservados sem associação.' : 'As etapas e os resultados deste fluxo também serão removidos.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm_project_remove'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(linked ? 'Arquivar' : 'Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingKey = item.key);
    var success = true;
    if (linked) {
      final projectOk = await ref
          .read(projectControllerProvider)
          .update(item.project!.id, {'status': 'archived'});
      final chainOk = projectOk &&
          await ref
              .read(promptChainControllerProvider)
              .update(item.chain!.id, {'status': 'archived'});
      success = projectOk && chainOk;
      if (projectOk && !chainOk) {
        await ref.read(projectControllerProvider).update(item.project!.id, {
          'status': item.project!.status.name,
        });
      }
    } else if (item.project case final project?) {
      success = await ref.read(projectControllerProvider).remove(project.id);
    } else {
      success =
          await ref.read(promptChainControllerProvider).remove(item.chain!.id);
    }
    if (!mounted) return;
    setState(() => _removingKey = null);
    if (success) _refresh();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? linked
              ? '"${item.name}" foi arquivado com segurança.'
              : '"${item.name}" foi excluído.'
          : 'Não foi possível ${linked ? 'arquivar' : 'excluir'} "${item.name}".'),
    ));
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
                                          FilledButton.icon(
                                            key:
                                                Key('open_project_${item.key}'),
                                            onPressed: () =>
                                                context.go(item.route),
                                            icon: Icon(item.canContinue
                                                ? Icons.play_arrow_rounded
                                                : Icons.folder_open_outlined),
                                            label: Text(item.canContinue
                                                ? 'Continuar'
                                                : 'Abrir'),
                                          ),
                                          if (item.project
                                              case final project?) ...[
                                            TextButton.icon(
                                              onPressed: () => _form(project),
                                              icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18),
                                              label: const Text('Editar'),
                                            ),
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _toggleArchive(project),
                                              icon: Icon(
                                                project.status ==
                                                        ProjectStatus.active
                                                    ? Icons.archive_outlined
                                                    : Icons.unarchive_outlined,
                                                size: 18,
                                              ),
                                              label: Text(project.status ==
                                                      ProjectStatus.active
                                                  ? 'Arquivar'
                                                  : 'Reativar'),
                                            ),
                                          ],
                                          IconButton(
                                            key: Key(
                                                'remove_project_${item.key}'),
                                            tooltip: item.project != null &&
                                                    item.chain != null
                                                ? 'Arquivar trabalho'
                                                : 'Excluir',
                                            onPressed: _removingKey == null
                                                ? () => _removeOverview(item)
                                                : null,
                                            icon: _removingKey == item.key
                                                ? const SizedBox.square(
                                                    dimension: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.delete_outline,
                                                    size: 20,
                                                  ),
                                          ),
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
