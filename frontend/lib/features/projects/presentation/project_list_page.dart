import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_page_app_bar.dart';
import '../../prompt_chains/prompt_chain_providers.dart';
import '../../project_blueprints/blueprint_dialog.dart';
import '../domain/project.dart';
import '../project_overview.dart';
import '../project_organization.dart';
import '../project_providers.dart';

const _allProjectsQuery = ProjectOverviewQuery(includeArchived: true);

class ProjectListPage extends ConsumerStatefulWidget {
  const ProjectListPage({super.key});
  @override
  ConsumerState<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends ConsumerState<ProjectListPage> {
  String? _removingKey;
  final _favoriting = <String>{};
  final _pinning = <String>{};
  final _search = TextEditingController();
  ProjectListFilter _filter = ProjectListFilter.all;
  ProjectListOrder _order = ProjectListOrder.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() =>
      ref.invalidate(projectOverviewsProvider(_allProjectsQuery));

  Future<void> _toggleFavorite(ProjectRecord project) async {
    if (!_favoriting.add(project.id)) return;
    setState(() {});
    try {
      await ref
          .read(projectRepositoryProvider)
          .setFavorite(project.id, !project.isFavorite);
      if (!mounted) return;
      _refresh();
      await ref.read(projectOverviewsProvider(_allProjectsQuery).future);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Não foi possível atualizar o favorito. Tente novamente.'),
      ));
    } finally {
      if (mounted) setState(() => _favoriting.remove(project.id));
    }
  }

  Future<void> _togglePin(ProjectRecord project) async {
    if (!_pinning.add(project.id)) return;
    setState(() {});
    try {
      await ref.read(projectRepositoryProvider).setPinned(project.id, !project.isPinned);
      if (!mounted) return;
      _refresh();
      await ref.read(projectOverviewsProvider(_allProjectsQuery).future);
    } on AppException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.code == 'project_pin_limit_reached'
            ? 'Você pode fixar até 3 projetos. Desafixe um projeto para continuar.'
            : 'Não foi possível atualizar o projeto fixado. Tente novamente.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível atualizar o projeto fixado. Tente novamente.'),
      ));
    } finally {
      if (mounted) setState(() => _pinning.remove(project.id));
    }
  }

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: ProjectReviewActionButton(
                  actionKey: const Key('project_blueprints'),
                  onPressed: () => context.push('/project-blueprints'),
                  icon: Icons.library_books_outlined,
                  label: 'Modelos de projeto',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
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
                          final pinned = items
                              .where((item) => item.project?.isPinned == true)
                              .take(3)
                              .toList();
                          final visible = organizeProjects(
                            items,
                            search: _search.text,
                            filter: _filter,
                            order: _order,
                          );
                          final width = constraints.maxWidth >= 900
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (pinned.isNotEmpty) ...[
                                Text('Projetos fixados', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final item in pinned)
                                      _PinnedProjectShortcut(
                                        item: item,
                                        pinning: _pinning.contains(item.project!.id),
                                        onOpen: () => context.go(item.route),
                                        onUnpin: () => _togglePin(item.project!),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                              ],
                              TextField(
                                key: const Key('project_search'),
                                controller: _search,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Buscar projetos',
                                  hintText: 'Buscar projetos...',
                                  prefixIcon: Icon(Icons.search),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final filter
                                        in ProjectListFilter.values)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: ChoiceChip(
                                          key: Key(
                                              'project_filter_${filter.name}'),
                                          label: Text(filter.label),
                                          selected: _filter == filter,
                                          onSelected: (_) =>
                                              setState(() => _filter = filter),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: SizedBox(
                                  width: constraints.maxWidth < 520
                                      ? constraints.maxWidth
                                      : 240,
                                  child:
                                      DropdownButtonFormField<ProjectListOrder>(
                                    key: const Key('project_order'),
                                    initialValue: _order,
                                    decoration: const InputDecoration(
                                        labelText: 'Ordenar'),
                                    items: [
                                      for (final order
                                          in ProjectListOrder.values)
                                        DropdownMenuItem(
                                          value: order,
                                          child: Text(order.label),
                                        ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _order = value);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: visible.isEmpty
                                    ? const Center(
                                        key: Key('projects_no_results'),
                                        child:
                                            Text('Nenhum projeto encontrado.'),
                                      )
                                    : SingleChildScrollView(
                                        child: Wrap(
                                          spacing: 16,
                                          runSpacing: 16,
                                          children: [
                                            for (final item in visible)
                                              SizedBox(
                                                width: width,
                                                child: Card(
                                                  key: Key(
                                                      'project_${item.key}'),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            20),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Expanded(
                                                                child: Text(
                                                                    item.name,
                                                                    style: Theme.of(
                                                                            context)
                                                                        .textTheme
                                                                        .titleLarge)),
                                                            if (item.project
                                                                case final project?)
                                                              IconButton(
                                                                key: Key('pin_${project.id}'),
                                                                tooltip: project.isPinned ? 'Desafixar projeto' : 'Fixar projeto',
                                                                onPressed: _pinning.contains(project.id)
                                                                    ? null
                                                                    : () => _togglePin(project),
                                                                icon: _pinning.contains(project.id)
                                                                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                                                    : Icon(project.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                                                              ),
                                                            if (item.project
                                                                case final project?)
                                                              IconButton(
                                                                key: Key(
                                                                    'favorite_${project.id}'),
                                                                tooltip: project
                                                                        .isFavorite
                                                                    ? 'Remover dos favoritos'
                                                                    : 'Marcar como favorito',
                                                                isSelected: project
                                                                    .isFavorite,
                                                                onPressed: _favoriting
                                                                        .contains(project
                                                                            .id)
                                                                    ? null
                                                                    : () => _toggleFavorite(
                                                                        project),
                                                                icon: _favoriting
                                                                        .contains(project
                                                                            .id)
                                                                    ? const SizedBox
                                                                        .square(
                                                                        dimension:
                                                                            20,
                                                                        child: CircularProgressIndicator(
                                                                            strokeWidth:
                                                                                2))
                                                                    : Icon(project
                                                                            .isFavorite
                                                                        ? Icons
                                                                            .star
                                                                        : Icons
                                                                            .star_border),
                                                              ),
                                                          ],
                                                        ),
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
                                                              key: Key(
                                                                  'open_project_${item.key}'),
                                                              onPressed: () =>
                                                                  context.go(item
                                                                      .route),
                                                              icon: Icon(item
                                                                      .canContinue
                                                                  ? Icons
                                                                      .play_arrow_rounded
                                                                  : Icons
                                                                      .folder_open_outlined),
                                                              label: Text(item
                                                                      .canContinue
                                                                  ? 'Continuar'
                                                                  : 'Abrir'),
                                                            ),
                                                            if (item.project
                                                                case final project?) ...[
                                                              TextButton.icon(
                                                                onPressed: () =>
                                                                    _form(
                                                                        project),
                                                                icon: const Icon(
                                                                    Icons
                                                                        .edit_outlined,
                                                                    size: 18),
                                                                label: const Text(
                                                                    'Editar'),
                                                              ),
                                                              TextButton.icon(
                                                                onPressed: () =>
                                                                    _toggleArchive(
                                                                        project),
                                                                icon: Icon(
                                                                  project.status ==
                                                                          ProjectStatus
                                                                              .active
                                                                      ? Icons
                                                                          .archive_outlined
                                                                      : Icons
                                                                          .unarchive_outlined,
                                                                  size: 18,
                                                                ),
                                                                label: Text(project
                                                                            .status ==
                                                                        ProjectStatus
                                                                            .active
                                                                    ? 'Arquivar'
                                                                    : 'Reativar'),
                                                              ),
                                                            ],
                                                            IconButton(
                                                              key: Key(
                                                                  'remove_project_${item.key}'),
                                                              tooltip: item.project !=
                                                                          null &&
                                                                      item.chain !=
                                                                          null
                                                                  ? 'Arquivar trabalho'
                                                                  : 'Excluir',
                                                              onPressed: _removingKey ==
                                                                      null
                                                                  ? () =>
                                                                      _removeOverview(
                                                                          item)
                                                                  : null,
                                                              icon: _removingKey ==
                                                                      item.key
                                                                  ? const SizedBox
                                                                      .square(
                                                                      dimension:
                                                                          18,
                                                                      child:
                                                                          CircularProgressIndicator(
                                                                        strokeWidth:
                                                                            2,
                                                                      ),
                                                                    )
                                                                  : const Icon(
                                                                      Icons
                                                                          .delete_outline,
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
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedProjectShortcut extends StatelessWidget {
  const _PinnedProjectShortcut({required this.item, required this.pinning, required this.onOpen, required this.onUnpin});
  final ProjectOverview item;
  final bool pinning;
  final VoidCallback onOpen;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.lightBlue.shade200),
            gradient: LinearGradient(colors: [Colors.white, Colors.lightBlue.shade50]),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              const Icon(Icons.push_pin, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
              IconButton(key: Key('open_pinned_${item.project!.id}'), tooltip: item.canContinue ? 'Continuar' : 'Abrir', onPressed: onOpen, icon: Icon(item.canContinue ? Icons.play_arrow_rounded : Icons.folder_open_outlined)),
              IconButton(key: Key('unpin_pinned_${item.project!.id}'), tooltip: 'Desafixar projeto', onPressed: pinning ? null : onUnpin, icon: pinning ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.push_pin_outlined)),
            ]),
          ),
        ),
      );
}
