import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_page_app_bar.dart';
import 'blueprint_dialog.dart';
import 'project_blueprints.dart';

class BlueprintListPage extends ConsumerStatefulWidget {
  const BlueprintListPage({super.key});
  @override
  ConsumerState<BlueprintListPage> createState() => _BlueprintListPageState();
}

class _BlueprintListPageState extends ConsumerState<BlueprintListPage> {
  int _offset = 0;
  String? _busy;
  bool _loadingDetail = false;
  Future<void> _action(ProjectBlueprint item, String action) async {
    if (_busy != null) return;
    setState(() {
      _busy = item.id;
      _loadingDetail = action == 'use';
    });
    try {
      final repository = ref.read(blueprintRepositoryProvider);
      final detail = action == 'use' ? await repository.get(item.id) : item;
      if (!mounted) return;
      setState(() => _loadingDetail = false);
      final result = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => BlueprintDialog(
                title: action == 'use'
                    ? 'Usar modelo'
                    : action == 'edit'
                        ? 'Editar modelo'
                        : 'Excluir modelo',
                name: action == 'use'
                    ? (detail.structure!['project_name'] as String)
                    : item.name,
                description: item.description,
                category: action == 'edit' ? item.category : null,
                preview: action == 'use' ? detail.structure : null,
                delete: action == 'delete',
                confirmLabel: action == 'use'
                    ? 'Criar projeto'
                    : action == 'edit'
                        ? 'Salvar alterações'
                        : 'Excluir modelo',
                onSave: (values) async {
                  if (action == 'use') {
                    return (await repository.use(
                            item.id, values['name'] as String))
                        .id;
                  }
                  if (action == 'edit') {
                    return (await repository.update(item.id, values)).id;
                  }
                  await repository.delete(item.id);
                  return item.id;
                },
              ));
      if (!mounted || result == null) return;
      if (action == 'use') {
        context.go('/projects/$result');
        return;
      }
      ref.invalidate(blueprintListProvider);
      if (action == 'delete') setState(() => _offset = 0);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Não foi possível abrir o modelo. Tente novamente.')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _loadingDetail = false;
        });
      }
    }
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppPageAppBar(
            title: 'Modelos de projeto', fallbackLocation: '/projects'),
        body: ref.watch(blueprintListProvider(_offset)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Não foi possível carregar os modelos.'),
                TextButton(
                    onPressed: () =>
                        ref.invalidate(blueprintListProvider(_offset)),
                    child: const Text('Tentar novamente')),
              ])),
              data: (page) => page.items.isEmpty
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Você ainda não possui modelos de projeto. Use “Salvar como modelo” na Central de um projeto.')))
                  : ListView(padding: const EdgeInsets.all(24), children: [
                      for (final item in page.items)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      if (item.description?.isNotEmpty ?? false)
                                        Text(item.description!),
                                      Text(item.category.label),
                                      Text(
                                          'Criado: ${_date(item.createdAt)} · Atualizado: ${_date(item.updatedAt)}'),
                                      if (_busy == item.id && _loadingDetail)
                                        const LinearProgressIndicator(),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton(
                                                key: Key(
                                                    'use_blueprint_${item.id}'),
                                                onPressed: _busy != null
                                                    ? null
                                                    : () =>
                                                        _action(item, 'use'),
                                                child:
                                                    const Text('Usar modelo')),
                                            TextButton(
                                                key: Key(
                                                    'edit_blueprint_${item.id}'),
                                                onPressed: _busy != null
                                                    ? null
                                                    : () =>
                                                        _action(item, 'edit'),
                                                child: const Text('Editar')),
                                            TextButton(
                                                key: Key(
                                                    'delete_blueprint_${item.id}'),
                                                onPressed: _busy != null
                                                    ? null
                                                    : () =>
                                                        _action(item, 'delete'),
                                                child: const Text('Excluir')),
                                          ]),
                                    ]))),
                      Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton(
                                onPressed: _offset > 0 && _busy == null
                                    ? () => setState(() => _offset -= 20)
                                    : null,
                                child: const Text('Anterior')),
                            Text(
                                '${_offset + 1}–${_offset + page.items.length} de ${page.total}'),
                            TextButton(
                                onPressed:
                                    _offset + page.items.length < page.total &&
                                            _busy == null
                                        ? () => setState(() => _offset += 20)
                                        : null,
                                child: const Text('Próxima')),
                          ]),
                    ]),
            ),
      );
}
