import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/prompt_models.dart';
import '../prompt_providers.dart';
import 'prompt_controller.dart';
import 'prompt_scaffold.dart';

class PromptListPage extends ConsumerStatefulWidget {
  const PromptListPage({super.key});

  @override
  ConsumerState<PromptListPage> createState() => _PromptListPageState();
}

class _PromptListPageState extends ConsumerState<PromptListPage> {
  String? _deletingId;
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(promptControllerProvider).loadPage());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptControllerProvider);
    return PromptScaffold(
      title: 'Meus prompts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Histórico',
                      style: Theme.of(context).textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: () => context.go('/prompts/new'),
                icon: const Icon(Icons.add),
                label: const Text('Novo prompt'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (state.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (state.error != null)
            _Message(
              icon: Icons.error_outline,
              text: state.error!,
              action: TextButton(
                  onPressed: () => state.loadPage(newOffset: state.offset),
                  child: const Text('Tentar novamente')),
            )
          else if (state.items.isEmpty)
            _Message(
              key: const Key('empty_prompts'),
              icon: Icons.description_outlined,
              text: 'Você ainda não criou prompts.',
              action: TextButton(
                  onPressed: () => context.go('/prompts/new'),
                  child: const Text('Criar primeiro prompt')),
            )
          else ...[
            ...state.items.map((prompt) => Card(
                  child: ListTile(
                    key: Key('prompt_${prompt.id}'),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    leading:
                        const CircleAvatar(child: Icon(Icons.auto_awesome)),
                    title: Text(prompt.title),
                    subtitle: Text(
                        '${prompt.category.label} • ${prompt.mode.name.toUpperCase()} • ${prompt.targetAi.label} • ${_date(prompt.createdAt)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('delete_prompt_${prompt.id}'),
                          tooltip: 'Excluir',
                          onPressed: _deletingId == null
                              ? () => _confirmDelete(prompt)
                              : null,
                          icon: _deletingId == prompt.id
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => context.go('/prompts/${prompt.id}'),
                  ),
                )),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  key: const Key('previous_page'),
                  tooltip: 'Página anterior',
                  onPressed: state.offset > 0
                      ? () => state.loadPage(
                          newOffset: (state.offset - PromptController.pageSize)
                              .clamp(0, state.total))
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                    '${state.offset + 1}–${(state.offset + state.items.length).clamp(0, state.total)} de ${state.total}'),
                IconButton(
                  key: const Key('next_page'),
                  tooltip: 'Próxima página',
                  onPressed: state.offset + state.items.length < state.total
                      ? () => state.loadPage(
                          newOffset: state.offset + PromptController.pageSize)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _confirmDelete(PromptRecord prompt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir prompt?'),
        content: Text(
          'O prompt "${prompt.title}" será excluído. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const Key('confirm_prompt_delete'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = prompt.id);
    final removed = await ref.read(promptControllerProvider).remove(prompt.id);
    if (!mounted) return;
    setState(() => _deletingId = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(removed
          ? 'Prompt "${prompt.title}" excluído.'
          : (ref.read(promptControllerProvider).deletionError ??
              'Não foi possível excluir o prompt.')),
    ));
  }
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon,
      required this.text,
      required this.action,
      super.key});
  final IconData icon;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(icon, size: 42),
            const SizedBox(height: 12),
            Text(text),
            action
          ]),
        ),
      );
}
