import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/prompt_models.dart';
import '../prompt_providers.dart';
import 'prompt_scaffold.dart';

class PromptCreatePage extends ConsumerStatefulWidget {
  const PromptCreatePage({super.key});

  @override
  ConsumerState<PromptCreatePage> createState() => _PromptCreatePageState();
}

class _PromptCreatePageState extends ConsumerState<PromptCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _input = TextEditingController();
  final _title = TextEditingController();
  final _language = TextEditingController(text: 'pt-BR');
  final _tone = TextEditingController();
  final _context = TextEditingController();
  final _audience = TextEditingController();
  final _role = TextEditingController();
  final _instructions = TextEditingController();
  final _constraints = TextEditingController();
  final _outputFormat = TextEditingController();
  final _additionalInformation = TextEditingController();
  final _provider = TextEditingController(text: 'openai');
  final _model = TextEditingController();
  PromptMode _mode = PromptMode.basic;
  PromptCategory _category = PromptCategory.general;
  bool _optimize = false;
  bool _advanced = false;

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  List<String> _lines(TextEditingController controller) => controller.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final result = await ref.read(promptControllerProvider).generate(
          PromptGenerateInput(
            input: _input.text.trim(),
            category: _category,
            language: _language.text.trim(),
            tone: _optional(_tone),
            mode: _mode,
            optimizeWithAi: _optimize,
            title: _optional(_title),
            context: _optional(_context),
            audience: _optional(_audience),
            role: _optional(_role),
            instructions: _lines(_instructions),
            constraints: _lines(_constraints),
            outputFormat: _optional(_outputFormat),
            additionalInformation: _optional(_additionalInformation),
            provider: _provider.text.trim(),
            model: _optional(_model),
          ),
        );
    if (mounted && result != null) context.go('/prompts/${result.id}');
  }

  String? _validateRequired(String? value, int min, int max) {
    final text = value?.trim() ?? '';
    if (text.length < min) return 'Use pelo menos $min caracteres.';
    if (text.length > max) return 'Use no máximo $max caracteres.';
    return null;
  }

  String? _validateOptional(String? value, int min, int max) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return _validateRequired(text, min, max);
  }

  @override
  void dispose() {
    for (final controller in [
      _input,
      _title,
      _language,
      _tone,
      _context,
      _audience,
      _role,
      _instructions,
      _constraints,
      _outputFormat,
      _additionalInformation,
      _provider,
      _model,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptControllerProvider);
    return PromptScaffold(
      title: 'Criar prompt',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Transforme sua ideia em um prompt profissional',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                    'A geração padrão é determinística. A otimização com IA pode consumir créditos conforme o backend.'),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('prompt_input'),
                  controller: _input,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                      labelText: 'O que você precisa?',
                      alignLabelWithHint: true),
                  validator: (value) => _validateRequired(value, 3, 10000),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<PromptCategory>(
                        initialValue: _category,
                        decoration:
                            const InputDecoration(labelText: 'Categoria'),
                        items: PromptCategory.values
                            .map((item) => DropdownMenuItem(
                                value: item, child: Text(item.label)))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _category = value!),
                      )),
                  SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<PromptMode>(
                        key: const Key('prompt_mode'),
                        initialValue: _mode,
                        decoration: const InputDecoration(labelText: 'Modo'),
                        items: PromptMode.values
                            .map((item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.name.toUpperCase())))
                            .toList(),
                        onChanged: (value) => setState(() => _mode = value!),
                      )),
                ]),
                SwitchListTile(
                  key: const Key('optimize_with_ai'),
                  value: _optimize,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Otimizar com IA'),
                  subtitle: const Text(
                      'Opcional; custo e disponibilidade são determinados pelo servidor.'),
                  onChanged: (value) => setState(() => _optimize = value),
                ),
                ExpansionTile(
                  title: const Text('Configurações avançadas'),
                  initiallyExpanded: _advanced,
                  onExpansionChanged: (value) => _advanced = value,
                  children: [
                    _field(_title, 'Título',
                        validator: (v) => _validateOptional(v, 3, 160)),
                    _field(_language, 'Idioma', validator: (v) {
                      final value = v?.trim() ?? '';
                      return RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?$')
                              .hasMatch(value)
                          ? null
                          : 'Informe um idioma válido, como pt-BR.';
                    }),
                    _field(_tone, 'Tom',
                        validator: (v) => _validateOptional(v, 2, 80)),
                    _field(_context, 'Contexto', max: 4000),
                    _field(_audience, 'Público', max: 1000),
                    _field(_role, 'Papel', max: 500),
                    _field(_instructions, 'Instruções (uma por linha)',
                        max: 15000, lines: 3),
                    _field(_constraints, 'Restrições (uma por linha)',
                        max: 15000, lines: 3),
                    _field(_outputFormat, 'Formato de saída', max: 1000),
                    _field(_additionalInformation, 'Informações adicionais',
                        max: 2000),
                    if (_optimize) ...[
                      _field(_provider, 'Provider',
                          validator: (v) => _validateRequired(v, 1, 50)),
                      _field(_model, 'Modelo (opcional)',
                          validator: (v) => _validateOptional(v, 1, 200)),
                    ],
                  ],
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 16),
                  Text(state.error!,
                      key: const Key('prompt_error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('prompt_submit'),
                  onPressed: state.isSubmitting ? null : _submit,
                  icon: state.isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label:
                      Text(state.isSubmitting ? 'Gerando...' : 'Gerar prompt'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
      {int? max, int lines = 1, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
        maxLength: max,
        validator: validator,
      ),
    );
  }
}
