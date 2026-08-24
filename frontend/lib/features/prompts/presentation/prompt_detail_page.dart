import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/prompt_models.dart';
import '../prompt_providers.dart';
import '../../templates/template_providers.dart';
import '../../projects/project_providers.dart';
import 'prompt_refinement_panel.dart';
import 'prompt_scaffold.dart';
import 'prompt_score_card.dart';

class PromptDetailPage extends ConsumerStatefulWidget {
  const PromptDetailPage({required this.promptId, super.key});
  final String promptId;

  @override
  ConsumerState<PromptDetailPage> createState() => _PromptDetailPageState();
}

class _PromptDetailPageState extends ConsumerState<PromptDetailPage> {
  String? _scoreInstruction;
  String? _projectName;
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final controller = ref.read(promptControllerProvider);
      await controller.load(widget.promptId);
      final projectId = controller.selected?.projectId;
      if (projectId != null) {
        final project =
            await ref.read(projectRepositoryProvider).get(projectId);
        if (mounted) setState(() => _projectName = project.name);
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

  Future<void> _saveTemplate(PromptRecord prompt) async {
    final name = TextEditingController(text: prompt.title);
    final description = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salvar como template'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('template_name'),
            controller: name,
            decoration: const InputDecoration(labelText: 'Nome do template'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('template_description'),
            controller: description,
            decoration: const InputDecoration(labelText: 'Descrição opcional'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            key: const Key('confirm_save_template'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (save == true && name.text.trim().length >= 3) {
      final saved = await ref.read(templateControllerProvider).savePrompt(
            prompt.id,
            name.text.trim(),
            description.text.trim().isEmpty ? null : description.text.trim(),
          );
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template salvo com sucesso.')),
        );
      } else if (mounted) {
        final error = ref.read(templateControllerProvider).error;
        if (error != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      description.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptControllerProvider);
    final selected = state.selected;
    final routeBelongsToLoadedVersions =
        state.versions.any((version) => version.id == widget.promptId);
    final selectedBelongsToLoadedVersions = selected != null &&
        state.versions.any((version) => version.id == selected.id);
    final prompt = selected != null &&
            (selected.id == widget.promptId ||
                (routeBelongsToLoadedVersions &&
                    selectedBelongsToLoadedVersions))
        ? selected
        : null;
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
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        Chip(
                            key: const Key('result_version'),
                            label: Text('Versão ${prompt.versionNumber}')),
                        Chip(
                            key: const Key('result_mode'),
                            avatar: const Icon(Icons.tune, size: 18),
                            label: Text(_modeLabel(prompt.mode))),
                        Chip(label: Text(prompt.category.label)),
                        Chip(
                            key: const Key('result_ai_status'),
                            avatar: Icon(
                                prompt.status == 'optimized'
                                    ? Icons.psychology
                                    : Icons.offline_bolt_outlined,
                                size: 18),
                            label: Text(prompt.status == 'optimized'
                                ? 'IA utilizada'
                                : 'IA não utilizada')),
                        if (prompt.provider != null)
                          Chip(label: Text('Provider: ${prompt.provider}')),
                        if (prompt.model != null)
                          Chip(label: Text('Modelo: ${prompt.model}')),
                        if (prompt.totalTokens != null)
                          Chip(label: Text('${prompt.totalTokens} tokens')),
                        if (_projectName != null)
                          Chip(
                            key: const Key('result_project'),
                            avatar: const Icon(Icons.folder_outlined, size: 18),
                            label: Text('Projeto: $_projectName'),
                          ),
                      ]),
                      if (state.error != null)
                        Text(state.error!,
                            key: const Key('prompt_error'),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16),
                      PromptScoreCard(
                        score: state.scores[prompt.id],
                        loading: state.isLoadingScores,
                        error: state.scoreError,
                        onImprove: (instruction) =>
                            setState(() => _scoreInstruction = instruction),
                      ),
                      const SizedBox(height: 16),
                      PromptRefinementPanel(
                        key:
                            ValueKey('${prompt.id}-${_scoreInstruction ?? ''}'),
                        prompt: prompt,
                        initialInstruction: _scoreInstruction,
                      ),
                      const SizedBox(height: 16),
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text('Seu prompt final',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 16),
                                    SelectableText(prompt.generatedPrompt,
                                        key: const Key('generated_prompt')),
                                  ]))),
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
                        OutlinedButton.icon(
                          key: const Key('save_as_template'),
                          onPressed: () => _saveTemplate(prompt),
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Salvar como template'),
                        ),
                      ]),
                    ]),
    );
  }

  static String _modeLabel(PromptMode mode) => switch (mode) {
        PromptMode.basic => 'GUPMAX Rápido',
        PromptMode.pro => 'GUPMAX Pro',
        PromptMode.expert => 'GUPMAX Expert',
      };
}
