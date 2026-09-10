import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../projects/domain/project.dart';
import '../prompts/domain/prompt_models.dart';
import 'project_blueprints.dart';

class BlueprintDialog extends StatefulWidget {
  const BlueprintDialog(
      {required this.title,
      required this.name,
      required this.confirmLabel,
      required this.onSave,
      this.description,
      this.category,
      this.preview,
      this.delete = false,
      super.key});
  final String title;
  final String name;
  final String confirmLabel;
  final String? description;
  final PromptCategory? category;
  final Map<String, dynamic>? preview;
  final bool delete;
  final Future<String> Function(Map<String, dynamic>) onSave;
  @override
  State<BlueprintDialog> createState() => _BlueprintDialogState();
}

class _BlueprintDialogState extends State<BlueprintDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  late final _description = TextEditingController(text: widget.description);
  late PromptCategory? _category = widget.category;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || (!widget.delete && !_form.currentState!.validate())) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSave({
        'name': _name.text.trim(),
        if (widget.preview == null)
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        if (_category != null) 'category': _category!.value,
      });
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Não foi possível salvar a alteração. Tente novamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.delete)
                              Text(
                                  'Excluir “${widget.name}”? Os projetos já criados serão preservados.')
                            else ...[
                              TextFormField(
                                  key: const Key('blueprint_name'),
                                  controller: _name,
                                  enabled: !_busy,
                                  maxLength: 160,
                                  decoration:
                                      const InputDecoration(labelText: 'Nome'),
                                  validator: (value) =>
                                      (value?.trim().length ?? 0) < 3
                                          ? 'Informe pelo menos 3 caracteres.'
                                          : null),
                              if (widget.preview == null)
                                TextFormField(
                                    key: const Key('blueprint_description'),
                                    controller: _description,
                                    enabled: !_busy,
                                    maxLength: 1000,
                                    minLines: 1,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                        labelText: 'Descrição (opcional)')),
                              if (_category != null)
                                DropdownButtonFormField<PromptCategory>(
                                    initialValue: _category,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Categoria'),
                                    items: [
                                      for (final value in PromptCategory.values)
                                        DropdownMenuItem(
                                            value: value,
                                            child: Text(value.label))
                                    ],
                                    onChanged: _busy
                                        ? null
                                        : (value) =>
                                            setState(() => _category = value)),
                              if (widget.preview case final preview?) ...[
                                const Text(
                                    'Revise a estrutura. O novo projeto começará sem progresso ou resultados.'),
                                if (preview['description'] != null)
                                  Text('Descrição: ${preview['description']}'),
                                if (preview['objective'] != null)
                                  Text('Objetivo: ${preview['objective']}'),
                                for (final value
                                    in (preview['success_criteria'] as List? ??
                                        []))
                                  Text('Critério: $value'),
                                for (final value
                                    in (preview['milestones'] as List? ?? []))
                                  Text('Marco: $value'),
                                if (preview['context'] != null)
                                  Text('Contexto: ${preview['context']}'),
                                for (final chain
                                    in (preview['chains'] as List? ?? []))
                                  ExpansionTile(
                                    title: Text(chain['name'] as String),
                                    children: [
                                      for (final step
                                          in (chain['steps'] as List))
                                        Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(step['title'] as String),
                                                  Text(step['base_input']
                                                      as String),
                                                  Text(
                                                      '${step['mode']} · ${step['category']} · ${step['target_ai']}'),
                                                ]))
                                    ],
                                  ),
                              ] else
                                const Text(
                                    'O modelo guardará apenas a estrutura reutilizável, sem histórico de execução.'),
                            ],
                            if (_error != null)
                              Text(_error!, key: const Key('blueprint_error')),
                          ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                key: const Key('confirm_blueprint'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.confirmLabel)),
          ],
        ),
      );
}

class SaveBlueprintButton extends ConsumerStatefulWidget {
  const SaveBlueprintButton({required this.project, super.key});
  final ProjectRecord project;
  @override
  ConsumerState<SaveBlueprintButton> createState() =>
      _SaveBlueprintButtonState();
}

class _SaveBlueprintButtonState extends ConsumerState<SaveBlueprintButton> {
  bool _opening = false;
  Future<void> _save() async {
    if (_opening) return;
    setState(() => _opening = true);
    final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BlueprintDialog(
            title: 'Salvar como modelo',
            name: widget.project.name,
            confirmLabel: 'Salvar modelo',
            onSave: (values) async => (await ref
                    .read(blueprintRepositoryProvider)
                    .create(widget.project.id, values))
                .id));
    if (!mounted) return;
    setState(() => _opening = false);
    if (result != null) {
      ref.invalidate(blueprintListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modelo de projeto salvo.')));
    }
  }

  @override
  Widget build(BuildContext context) => ProjectReviewActionButton(
      actionKey: const Key('save_project_blueprint'),
      onPressed: _opening ? null : _save,
      icon: Icons.library_add_outlined,
      label: 'Salvar como modelo');
}

class ProjectReviewActionButton extends StatelessWidget {
  const ProjectReviewActionButton({
    required this.actionKey,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.loading = false,
    super.key,
  });

  final Key actionKey;
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final brightness = Theme.of(context).brightness;
    final foreground =
        enabled ? const Color(0xFF1558A6) : Theme.of(context).disabledColor;
    final surface = enabled
        ? const Color(0xFFF1F8FF)
        : (brightness == Brightness.dark
            ? Colors.white.withValues(alpha: .06)
            : Colors.black.withValues(alpha: .04));
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white.withValues(alpha: .92), surface],
              )
            : null,
        color: enabled ? null : surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
              ? const Color(0xFFB8D8F6)
              : Theme.of(context).disabledColor.withValues(alpha: .25),
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: const Color(0xFF4389C9).withValues(alpha: .12),
                  blurRadius: 7,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: actionKey,
          borderRadius: BorderRadius.circular(12),
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onTap: onPressed,
          hoverColor: const Color(0xFFBFE3FF).withValues(alpha: .22),
          splashColor: const Color(0xFF76B7EB).withValues(alpha: .28),
          highlightColor: const Color(0xFF76B7EB).withValues(alpha: .14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, color: foreground, size: 20),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
