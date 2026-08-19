import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_navigation_menu.dart';
import '../../prompts/domain/prompt_models.dart';
import '../domain/prompt_template.dart';
import '../template_providers.dart';

class TemplateListPage extends ConsumerStatefulWidget {
  const TemplateListPage({super.key});

  @override
  ConsumerState<TemplateListPage> createState() => _TemplateListPageState();
}

class _TemplateListPageState extends ConsumerState<TemplateListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(ref.read(templateControllerProvider).load);
  }

  Future<void> _edit(PromptTemplateRecord template) async {
    final name = TextEditingController(text: template.name);
    final description = TextEditingController(text: template.description);
    final content = TextEditingController(text: template.templateContent);
    var category = template.category;
    var mode = template.mode;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Editar template'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    key: const Key('template_edit_name'),
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome')),
                TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Descrição')),
                TextField(
                    key: const Key('template_edit_content'),
                    controller: content,
                    minLines: 4,
                    maxLines: 10,
                    decoration:
                        const InputDecoration(labelText: 'Conteúdo/base')),
                DropdownButtonFormField<PromptCategory>(
                  initialValue: category,
                  items: PromptCategory.values
                      .map((item) => DropdownMenuItem(
                          value: item, child: Text(item.label)))
                      .toList(),
                  onChanged: (value) => setState(() => category = value!),
                  decoration: const InputDecoration(labelText: 'Categoria'),
                ),
                DropdownButtonFormField<PromptMode>(
                  initialValue: mode,
                  items: PromptMode.values
                      .map((item) => DropdownMenuItem(
                          value: item, child: Text(item.name.toUpperCase())))
                      .toList(),
                  onChanged: (value) => setState(() => mode = value!),
                  decoration: const InputDecoration(labelText: 'Modo'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                key: const Key('template_edit_save'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (save == true) {
      await ref.read(templateControllerProvider).updateTemplate(template.id, {
        'name': name.text.trim(),
        'description':
            description.text.trim().isEmpty ? null : description.text.trim(),
        'template_content': content.text.trim(),
        'base_input': content.text.trim(),
        'category': category.value,
        'mode': mode.name,
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      description.dispose();
      content.dispose();
    });
  }

  Future<void> _delete(PromptTemplateRecord template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir template?'),
        content: const Text(
            'O Prompt de origem e os Prompts derivados serão preservados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              key: const Key('confirm_template_delete'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(templateControllerProvider).remove(template.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(templateControllerProvider);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Meus templates'),
          actions: const [AppNavigationMenu(), SizedBox(width: 8)]),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.items.isEmpty
                ? Center(child: Text(state.error!))
                : state.items.isEmpty
                    ? const Center(
                        key: Key('templates_empty'),
                        child: Text('Você ainda não possui templates.'))
                    : LayoutBuilder(builder: (context, constraints) {
                        final width = constraints.maxWidth >= 900
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth;
                        return SingleChildScrollView(
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: state.items
                                .map((template) => SizedBox(
                                      width: width,
                                      child: Card(
                                        key: Key('template_${template.id}'),
                                        child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(template.name,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleLarge),
                                                if (template.description !=
                                                    null)
                                                  Text(template.description!),
                                                const SizedBox(height: 8),
                                                Text(
                                                    '${template.category.label} • ${template.mode.name.toUpperCase()}'),
                                                Text(
                                                    'Atualizado em ${_date(template.updatedAt)}'),
                                                const SizedBox(height: 12),
                                                Wrap(spacing: 8, children: [
                                                  FilledButton(
                                                      key: Key(
                                                          'use_template_${template.id}'),
                                                      onPressed: () => context.go(
                                                          '/prompts/new?template=${template.id}'),
                                                      child:
                                                          const Text('Usar')),
                                                  TextButton(
                                                      onPressed: () =>
                                                          _edit(template),
                                                      child:
                                                          const Text('Editar')),
                                                  TextButton(
                                                      onPressed: () =>
                                                          _delete(template),
                                                      child: const Text(
                                                          'Excluir')),
                                                ]),
                                              ]),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        );
                      }),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
