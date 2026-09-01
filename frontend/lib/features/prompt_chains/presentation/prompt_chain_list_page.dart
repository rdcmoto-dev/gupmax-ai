import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../../projects/project_providers.dart';
import '../domain/prompt_chain.dart';
import '../prompt_chain_providers.dart';

class PromptChainListPage extends ConsumerStatefulWidget {
  const PromptChainListPage({super.key});
  @override
  ConsumerState<PromptChainListPage> createState() =>
      _PromptChainListPageState();
}

class _PromptChainListPageState extends ConsumerState<PromptChainListPage> {
  String? _deletingId;
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await Future.wait([
        ref.read(promptChainControllerProvider).load(),
        ref.read(projectControllerProvider).load(),
      ]);
    });
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final description = TextEditingController();
    String? projectId;
    final projects = ref.read(projectControllerProvider).items;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Novo fluxo'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const Key('chain_name'),
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome *')),
            TextField(
                key: const Key('chain_description'),
                controller: description,
                decoration: const InputDecoration(labelText: 'Descrição')),
            DropdownButtonFormField<String?>(
              key: const Key('chain_project'),
              initialValue: projectId,
              decoration:
                  const InputDecoration(labelText: 'Projeto (opcional)'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Sem projeto')),
                ...projects.map((project) => DropdownMenuItem<String?>(
                    value: project.id, child: Text(project.name))),
              ],
              onChanged: (value) => setState(() => projectId = value),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                key: const Key('save_chain'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Criar')),
          ],
        ),
      ),
    );
    if (save == true && name.text.trim().length >= 3) {
      await ref.read(promptChainControllerProvider).create({
        'name': name.text.trim(),
        'description':
            description.text.trim().isEmpty ? null : description.text.trim(),
        'project_id': projectId,
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      description.dispose();
    });
  }

  Future<void> _edit(PromptChainRecord chain) async {
    final name = TextEditingController(text: chain.name);
    final description = TextEditingController(text: chain.description);
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Editar fluxo'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    key: const Key('edit_chain_name'),
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome *')),
                TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Descrição')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    key: const Key('save_chain_edit'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Salvar')),
              ],
            ));
    if (save == true && name.text.trim().length >= 3) {
      await ref.read(promptChainControllerProvider).update(chain.id, {
        'name': name.text.trim(),
        'description':
            description.text.trim().isEmpty ? null : description.text.trim(),
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      description.dispose();
    });
  }

  Future<void> _delete(PromptChainRecord chain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir fluxo?'),
        content: Text(
          'O fluxo "${chain.name}", suas etapas e resultados serão excluídos. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const Key('confirm_chain_delete'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = chain.id);
    final success =
        await ref.read(promptChainControllerProvider).remove(chain.id);
    if (!mounted) return;
    setState(() => _deletingId = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? 'Fluxo "${chain.name}" excluído.'
          : 'Não foi possível excluir o fluxo "${chain.name}".'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptChainControllerProvider);
    return Scaffold(
      appBar: AppPageAppBar(title: 'Meus fluxos', actions: [
        IconButton(
            key: const Key('new_chain'),
            onPressed: _create,
            tooltip: 'Novo fluxo',
            icon: const Icon(Icons.add)),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: state.loading && state.items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.items.isEmpty
                ? Center(child: Text(state.error!))
                : state.items.isEmpty
                    ? const Center(
                        key: Key('chains_empty'),
                        child: Text('Você ainda não possui fluxos.'))
                    : LayoutBuilder(builder: (context, constraints) {
                        final width = constraints.maxWidth >= 900
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth;
                        return SingleChildScrollView(
                            child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: state.items
                              .map((chain) => SizedBox(
                                    width: width,
                                    child: Card(
                                        child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(chain.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge),
                                            if (chain.description != null)
                                              Text(chain.description!),
                                            Text(
                                                '${chain.stepCount} etapas • ${chain.status == PromptChainStatus.active ? 'Ativo' : 'Arquivado'}'),
                                            if (chain.projectId != null)
                                              const Text('Projeto associado'),
                                            Wrap(spacing: 8, children: [
                                              FilledButton(
                                                  key: Key(
                                                      'open_chain_${chain.id}'),
                                                  onPressed: () => context.go(
                                                      '/chains/${chain.id}'),
                                                  child: const Text('Abrir')),
                                              TextButton(
                                                  onPressed: () => _edit(chain),
                                                  child: const Text('Editar')),
                                              TextButton(
                                                  onPressed: () => ref
                                                          .read(
                                                              promptChainControllerProvider)
                                                          .update(chain.id, {
                                                        'status': chain
                                                                    .status ==
                                                                PromptChainStatus
                                                                    .active
                                                            ? 'archived'
                                                            : 'active'
                                                      }),
                                                  child: Text(chain.status ==
                                                          PromptChainStatus
                                                              .active
                                                      ? 'Arquivar'
                                                      : 'Reativar')),
                                              IconButton(
                                                key: Key(
                                                    'delete_chain_${chain.id}'),
                                                tooltip: 'Excluir',
                                                onPressed: _deletingId == null
                                                    ? () => _delete(chain)
                                                    : null,
                                                icon: _deletingId == chain.id
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
                                            ]),
                                          ]),
                                    )),
                                  ))
                              .toList(),
                        ));
                      }),
      ),
    );
  }
}
