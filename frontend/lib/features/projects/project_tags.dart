import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import '../auth/auth_providers.dart';
import 'domain/project.dart';
import 'data/project_repository.dart';
import 'project_overview.dart';
import 'project_workspace.dart';

final tagRepositoryProvider =
    Provider((ref) => TagRepository(ref.watch(apiClientProvider)));
final projectTagsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(tagRepositoryProvider).list());

class TagRepository {
  const TagRepository(this.client);
  final ApiClient client;

  Future<dynamic> request(String method, String path, [String? name]) async {
    try {
      return (await client.dio.request<dynamic>('/project-tags$path',
              data: name == null ? null : {'name': name.trim()},
              options: Options(method: method)))
          .data;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final detail = data is Map ? data['detail'] : null;
      throw AppException(
          status == 409 && detail is String
              ? detail
              : status == 404
                  ? 'Tag ou projeto não encontrado.'
                  : 'Não foi possível salvar as Tags. Tente novamente.',
          statusCode: status);
    }
  }

  Future<List<ProjectTag>> list() async => (await request('GET', '') as List)
      .map((item) => ProjectTag.fromJson(item as Map<String, dynamic>))
      .toList();
  Future<ProjectTag> save(String name, {String? id}) async =>
      ProjectTag.fromJson(await request(
              id == null ? 'POST' : 'PUT', id == null ? '' : '/$id', name)
          as Map<String, dynamic>);
  Future<void> delete(String id) async {
    await request('DELETE', '/$id');
  }

  Future<void> associate(String projectId, String tagId, bool selected) async {
    await request(selected ? 'PUT' : 'DELETE', '/projects/$projectId/$tagId');
  }

  Future<List<ProjectTag>> associations(String projectId) async =>
      (await ProjectRepository(client).get(projectId)).tags;
}

class ProjectTagsPanel extends ConsumerWidget {
  const ProjectTagsPanel({required this.project, super.key});
  final ProjectRecord project;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tags'),
                if (project.tags.isEmpty) const Text('Nenhuma Tag associada.'),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final tag in project.tags) Chip(label: Text(tag.name)),
                ]),
                TextButton.icon(
                    key: const Key('manage_project_tags'),
                    icon: const Icon(Icons.label_outline),
                    label: const Text('Gerenciar Tags'),
                    onPressed: () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _TagDialog(project: project))),
              ],
            )),
      );
}

class _TagDialog extends ConsumerStatefulWidget {
  const _TagDialog({required this.project});
  final ProjectRecord project;
  @override
  ConsumerState<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends ConsumerState<_TagDialog> {
  final _name = TextEditingController();
  final _selected = <String>{};
  bool _loaded = false;
  String? _editing;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _readAssociations() async {
    final saved =
        await ref.read(tagRepositoryProvider).associations(widget.project.id);
    if (!mounted) return;
    _selected
      ..clear()
      ..addAll(saved.map((tag) => tag.id));
    _loaded = true;
  }

  Future<void> _reload() => _run(() async {}, refreshCatalog: false);
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation,
      {bool refreshCatalog = true, String? tagId, bool? selected}) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      await _readAssociations();
      if (!mounted) return;
      if (tagId != null && _selected.contains(tagId) != selected) {
        throw const AppException(
            'A associação não foi confirmada. Tente novamente.');
      }
      if (refreshCatalog) ref.invalidate(projectTagsProvider);
      ref.invalidate(projectOverviewsProvider);
      ref.invalidate(projectWorkspaceProvider);
    } catch (error) {
      if (mounted) {
        _loaded = false;
        setState(() => _error = error is AppException
            ? error.message
            : 'Não foi possível concluir. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(projectTagsProvider);
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('Gerenciar Tags'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Até 50 Tags e 10 por projeto. Selecione para associar ou remover. Editar e excluir afeta todos os seus projetos.'),
                  TextField(
                      key: const Key('tag_name'),
                      controller: _name,
                      enabled: !_busy,
                      maxLength: 60,
                      decoration: InputDecoration(
                          labelText:
                              _editing == null ? 'Nova Tag' : 'Editar Tag')),
                  Wrap(children: [
                    FilledButton(
                        key: const Key('save_tag'),
                        onPressed: _busy
                            ? null
                            : () {
                                final name = _name.text.trim();
                                if (name.isEmpty || name.length > 60) {
                                  setState(() => _error =
                                      'Informe um nome de 1 a 60 caracteres.');
                                  return;
                                }
                                _run(() async {
                                  await ref
                                      .read(tagRepositoryProvider)
                                      .save(name, id: _editing);
                                  _name.clear();
                                  _editing = null;
                                });
                              },
                        child: Text(
                            _editing == null ? 'Criar Tag' : 'Salvar nome')),
                    if (_editing != null)
                      TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _editing = null;
                                    _name.clear();
                                  }),
                          child: const Text('Cancelar edição')),
                  ]),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(_error!, key: const Key('tag_error')),
                  if (!_loaded && !_busy)
                    TextButton(
                        onPressed: _reload,
                        child: const Text('Recarregar associações')),
                  tags.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => TextButton(
                          onPressed: () => ref.invalidate(projectTagsProvider),
                          child: const Text(
                              'Falha ao carregar Tags. Tentar novamente')),
                      data: (items) =>
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            if (items.isEmpty)
                              const Text('Nenhuma Tag criada.'),
                            for (final tag in items)
                              Row(children: [
                                Expanded(
                                    child: FilterChip(
                                        key: Key('tag_select_${tag.id}'),
                                        label: Text(tag.name),
                                        selected: _loaded &&
                                            _selected.contains(tag.id),
                                        onSelected: _busy || !_loaded
                                            ? null
                                            : (selected) => _run(() async {
                                                  await ref
                                                      .read(
                                                          tagRepositoryProvider)
                                                      .associate(
                                                          widget.project.id,
                                                          tag.id,
                                                          selected);
                                                },
                                                    tagId: tag.id,
                                                    selected: selected))),
                                IconButton(
                                    tooltip: 'Editar ${tag.name}',
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                              _editing = tag.id;
                                              _name.text = tag.name;
                                            }),
                                    icon: const Icon(Icons.edit_outlined)),
                                IconButton(
                                    tooltip: 'Excluir ${tag.name}',
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            final confirmed = await showDialog<
                                                    bool>(
                                                context: context,
                                                builder: (context) =>
                                                    AlertDialog(
                                                        title: const Text(
                                                            'Excluir Tag?'),
                                                        content: Text(
                                                            'Excluir “${tag.name}” de todos os projetos? Os projetos serão preservados.'),
                                                        actions: [
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      context,
                                                                      false),
                                                              child: const Text(
                                                                  'Cancelar')),
                                                          FilledButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      context,
                                                                      true),
                                                              child: const Text(
                                                                  'Excluir'))
                                                        ]));
                                            if (confirmed == true && mounted) {
                                              await _run(() async {
                                                await ref
                                                    .read(tagRepositoryProvider)
                                                    .delete(tag.id);
                                                _selected.remove(tag.id);
                                                if (_editing == tag.id) {
                                                  _editing = null;
                                                  _name.clear();
                                                }
                                              });
                                            }
                                          },
                                    icon: const Icon(Icons.delete_outline)),
                              ]),
                          ])),
                ],
              ))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Concluir'))
          ],
        ));
  }
}
