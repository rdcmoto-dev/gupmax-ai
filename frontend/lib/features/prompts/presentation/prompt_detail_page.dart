import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/prompt_models.dart';
import '../prompt_providers.dart';
import 'prompt_scaffold.dart';

class PromptDetailPage extends ConsumerStatefulWidget {
  const PromptDetailPage({required this.promptId, super.key});
  final String promptId;

  @override
  ConsumerState<PromptDetailPage> createState() => _PromptDetailPageState();
}

class _PromptDetailPageState extends ConsumerState<PromptDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final state = ref.read(promptControllerProvider);
      if (state.selected?.id != widget.promptId) {
        state.load(widget.promptId);
      }
    });
  }

  Future<void> _edit(PromptRecord prompt) async {
    final title = TextEditingController(text: prompt.title);
    final generated = TextEditingController(text: prompt.generatedPrompt);
    final language = TextEditingController(text: prompt.language);
    final tone = TextEditingController(text: prompt.tone);
    var category = prompt.category;
    var mode = prompt.mode;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar prompt'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    key: const Key('edit_title'),
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Título')),
                const SizedBox(height: 12),
                TextField(
                    key: const Key('edit_generated'),
                    controller: generated,
                    minLines: 5,
                    maxLines: 12,
                    decoration:
                        const InputDecoration(labelText: 'Prompt gerado')),
                const SizedBox(height: 12),
                DropdownButtonFormField<PromptCategory>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: PromptCategory.values
                        .map((item) => DropdownMenuItem(
                            value: item, child: Text(item.label)))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => category = value!)),
                const SizedBox(height: 12),
                TextField(
                    controller: language,
                    decoration: const InputDecoration(labelText: 'Idioma')),
                const SizedBox(height: 12),
                TextField(
                    controller: tone,
                    decoration: const InputDecoration(labelText: 'Tom')),
                const SizedBox(height: 12),
                DropdownButtonFormField<PromptMode>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'Modo'),
                    items: PromptMode.values
                        .map((item) => DropdownMenuItem(
                            value: item, child: Text(item.name.toUpperCase())))
                        .toList(),
                    onChanged: (value) => setDialogState(() => mode = value!)),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                key: const Key('save_prompt'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await ref.read(promptControllerProvider).update(
            prompt.id,
            PromptUpdateInput(
              title: title.text.trim(),
              generatedPrompt: generated.text.trim(),
              category: category,
              language: language.text.trim(),
              tone: tone.text.trim().isEmpty ? null : tone.text.trim(),
              mode: mode,
            ),
          );
    }
  }

  Future<void> _delete(PromptRecord prompt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir prompt?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              key: const Key('confirm_delete'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed == true &&
        await ref.read(promptControllerProvider).remove(prompt.id) &&
        mounted) {
      context.go('/prompts');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptControllerProvider);
    final prompt =
        state.selected?.id == widget.promptId ? state.selected : null;
    return PromptScaffold(
      title: 'Resultado',
      child: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : prompt == null
              ? Center(child: Text(state.error ?? 'Prompt não encontrado.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      Row(children: [
                        Expanded(
                            child: Text(prompt.title,
                                style:
                                    Theme.of(context).textTheme.headlineSmall)),
                        IconButton(
                            key: const Key('edit_prompt'),
                            tooltip: 'Editar',
                            onPressed:
                                state.isSubmitting ? null : () => _edit(prompt),
                            icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                            key: const Key('delete_prompt'),
                            tooltip: 'Excluir',
                            onPressed: state.isSubmitting
                                ? null
                                : () => _delete(prompt),
                            icon: const Icon(Icons.delete_outline)),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        Chip(label: Text(prompt.mode.name.toUpperCase())),
                        Chip(label: Text(prompt.category.label)),
                        Chip(
                            label: Text(prompt.status == 'optimized'
                                ? 'Otimizado com IA'
                                : 'Gerado')),
                        if (prompt.totalTokens != null)
                          Chip(label: Text('${prompt.totalTokens} tokens')),
                      ]),
                      if (state.error != null)
                        Text(state.error!,
                            key: const Key('prompt_error'),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16),
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: SelectableText(prompt.generatedPrompt,
                                  key: const Key('generated_prompt')))),
                      const SizedBox(height: 16),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        FilledButton.icon(
                          key: const Key('copy_prompt'),
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: prompt.generatedPrompt));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Prompt copiado.')));
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar prompt'),
                        ),
                        OutlinedButton(
                            onPressed: () => context.go('/prompts/new'),
                            child: const Text('Criar outro')),
                        OutlinedButton(
                            onPressed: () => context.go('/prompts'),
                            child: const Text('Ver histórico')),
                      ]),
                    ]),
    );
  }
}
