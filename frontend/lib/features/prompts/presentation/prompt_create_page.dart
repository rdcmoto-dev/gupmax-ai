import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/account_providers.dart';
import '../../interviews/interview_providers.dart';
import '../../templates/domain/prompt_template.dart';
import '../../templates/template_providers.dart';
import '../domain/prompt_models.dart';
import '../prompt_providers.dart';
import 'prompt_scaffold.dart';

class PromptCreatePage extends ConsumerStatefulWidget {
  const PromptCreatePage({this.templateId, super.key});
  final String? templateId;

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
  String? _templateName;

  static const _examples = [
    'Criar anúncio para um produto',
    'Criar um site',
    'Criar um vídeo',
    'Criar uma imagem',
    'Melhorar um texto',
    'Criar código',
  ];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await ref.read(accountControllerProvider).loadSmartProfile();
      if (widget.templateId != null) {
        final template =
            await ref.read(templateControllerProvider).get(widget.templateId!);
        if (template != null && mounted) _applyTemplate(template);
      }
    });
  }

  void _applyTemplate(PromptTemplateRecord template) {
    setState(() {
      _templateName = template.name;
      _input.text = template.baseInput;
      _language.text = template.language;
      _tone.text = template.tone ?? '';
      _context.text = template.context ?? '';
      _audience.text = template.audience ?? '';
      _instructions.text = template.instructions.join('\n');
      _constraints.text = template.constraints.join('\n');
      _outputFormat.text = template.outputFormat ?? '';
      _additionalInformation.text = template.additionalInformation ?? '';
      _mode = template.mode;
      _category = template.category;
      _optimize = false;
    });
  }

  Future<void> _chooseTemplate() async {
    final controller = ref.read(templateControllerProvider);
    await controller.load();
    if (!mounted) return;
    final selected = await showDialog<PromptTemplateRecord>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Começar com um template'),
        content: SizedBox(
          width: 520,
          child: controller.items.isEmpty
              ? const Text('Você ainda não possui templates.')
              : ListView(
                  shrinkWrap: true,
                  children: controller.items
                      .where((item) => item.isActive)
                      .map((item) => ListTile(
                            key: Key('choose_template_${item.id}'),
                            title: Text(item.name),
                            subtitle: Text(
                                '${item.category.label} • ${item.mode.name.toUpperCase()}'),
                            onTap: () => Navigator.pop(context, item),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
        ],
      ),
    );
    if (selected != null) _applyTemplate(selected);
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  List<String> _lines(TextEditingController controller) => controller.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  PromptGenerateInput _currentInput({required bool optimize}) =>
      PromptGenerateInput(
        input: _input.text.trim().isEmpty
            ? 'Estimativa de prompt'
            : _input.text.trim(),
        category: _category,
        language: _language.text.trim(),
        tone: _optional(_tone),
        mode: _mode,
        optimizeWithAi: optimize,
        context: _optional(_context),
        audience: _optional(_audience),
        role: _optional(_role),
        instructions: _lines(_instructions),
        constraints: _lines(_constraints),
        outputFormat: _optional(_outputFormat),
        additionalInformation: _optional(_additionalInformation),
        provider: _provider.text.trim(),
        model: _optional(_model),
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final input = PromptGenerateInput(
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
    );
    if (_mode != PromptMode.basic) {
      final interview = await ref.read(interviewControllerProvider).start(
            initialRequest: _input.text.trim(),
            mode: _mode,
            category: _category,
            knownFields: input,
          );
      if (mounted && interview != null) {
        context.go('/interviews/${interview.id}');
      }
      return;
    }
    final result = await ref.read(promptControllerProvider).generate(input);
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
    final interviewState = ref.watch(interviewControllerProvider);
    final smartProfile = ref.watch(accountControllerProvider).smartProfile;
    final isSubmitting = state.isSubmitting || interviewState.isSubmitting;
    return PromptScaffold(
      title: 'Criar prompt',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                key: const Key('choose_template_button'),
                leading: const Icon(Icons.bookmarks_outlined),
                title: Text(_templateName == null
                    ? 'Começar com um template'
                    : 'Template: $_templateName'),
                subtitle: const Text(
                    'Use como ponto de partida e revise tudo antes de construir.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _chooseTemplate,
              ),
            ),
            const SizedBox(height: 16),
            if (smartProfile.isEnabled && smartProfile.hasData) ...[
              Card(
                key: const Key('smart_profile_active'),
                color: AppColors.paleGold,
                child: ListTile(
                  leading:
                      const Icon(Icons.auto_awesome, color: AppColors.gold),
                  title: const Text('Smart Profile ativo'),
                  subtitle: const Text(
                      'Preferências serão aplicadas apenas onde você não informar um valor.'),
                  trailing: TextButton(
                    onPressed: () => context.go('/account'),
                    child: const Text('Ver preferências'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _HeroCard(input: _input, validate: _validateRequired),
            const SizedBox(height: 20),
            _SectionCard(
              number: '1',
              title: 'Escolha como o GUPMAX vai construir',
              subtitle:
                  'O valor enviado ao servidor continua sendo basic, pro ou expert.',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cards = PromptMode.values
                      .map((mode) => _ModeCard(
                            key: Key('mode_${mode.name}'),
                            mode: mode,
                            selected: _mode == mode,
                            onTap: () => setState(() => _mode = mode),
                          ))
                      .toList();
                  if (constraints.maxWidth < 680) {
                    return Column(children: cards);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        cards.map((card) => Expanded(child: card)).toList(),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            _SectionCard(
              number: '2',
              title: 'Qual é o tipo da sua criação?',
              subtitle:
                  'Escolha uma das categorias aceitas pelo Prompt Engine.',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: PromptCategory.values
                    .map((category) => ChoiceChip(
                          key: Key('category_${category.value}'),
                          avatar: Icon(_categoryIcon(category), size: 18),
                          label: Text(category.label),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: const Key('complementary_information'),
                leading: const CircleAvatar(child: Text('3')),
                title: const Text('Conte mais para o GUPMAX'),
                subtitle: const Text(
                    'Opcional: contexto, público, tom, formato e outras orientações.'),
                childrenPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _responsiveFields([
                    _field(_title, 'Título do projeto',
                        key: const Key('prompt_title'),
                        hint: 'Ex.: Campanha de primavera',
                        validator: (v) => _validateOptional(v, 3, 160)),
                    _field(_language, 'Idioma',
                        key: const Key('prompt_language'), validator: (v) {
                      final value = v?.trim() ?? '';
                      return RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?$')
                              .hasMatch(value)
                          ? null
                          : 'Informe um idioma válido, como pt-BR.';
                    }),
                    _field(_tone, 'Tom de voz',
                        key: const Key('prompt_tone'),
                        hint: 'Ex.: persuasivo, didático',
                        validator: (v) => _validateOptional(v, 2, 80)),
                    _field(_audience, 'Público',
                        key: const Key('prompt_audience'),
                        hint: 'Para quem é esta criação?',
                        max: 1000),
                  ]),
                  _field(_context, 'Contexto',
                      key: const Key('prompt_context'),
                      hint: 'Cenário, produto ou situação relevante',
                      max: 4000,
                      lines: 3),
                  _field(_role, 'Especialista desejado',
                      key: const Key('prompt_role'),
                      hint: 'Ex.: estrategista de marketing',
                      max: 500),
                  _field(_instructions, 'Orientações (uma por linha)',
                      key: const Key('prompt_instructions'),
                      max: 15000,
                      lines: 3),
                  _field(_constraints, 'Restrições (uma por linha)',
                      key: const Key('prompt_constraints'),
                      max: 15000,
                      lines: 3),
                  _field(_outputFormat, 'Formato da resposta',
                      key: const Key('prompt_output_format'),
                      hint: 'Ex.: título e texto de até 100 palavras',
                      max: 1000),
                  _field(_additionalInformation, 'Outras informações',
                      key: const Key('prompt_additional_information'),
                      max: 2000,
                      lines: 2),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: AppColors.paleBlue,
              child: SwitchListTile(
                key: const Key('optimize_with_ai'),
                value: _optimize,
                secondary: const Icon(Icons.psychology_outlined,
                    color: AppColors.gold),
                title: const Text('Otimizar com IA (opcional)'),
                subtitle: state.isEstimating
                    ? const Text('Calculando estimativa de créditos...')
                    : state.estimate != null
                        ? Text(
                            'Custo estimado: ${state.estimate!.estimatedCredits} créditos. '
                            'Saldo disponível: ${state.estimate!.availableCredits} créditos.',
                            key: const Key('ai_credit_estimate_summary'),
                          )
                        : const Text(
                            'O servidor decide disponibilidade e consumo de créditos. O GUPMAX nunca chama IA diretamente do navegador.'),
                onChanged: isSubmitting
                    ? null
                    : (value) {
                        setState(() => _optimize = value);
                        final controller = ref.read(promptControllerProvider);
                        if (value) {
                          controller.estimateOptimization(
                              _currentInput(optimize: true));
                        } else {
                          controller.clearEstimate();
                        }
                      },
              ),
            ),
            if (_optimize) ...[
              const SizedBox(height: 12),
              if (state.isEstimating)
                const LinearProgressIndicator(key: Key('ai_estimate_loading'))
              else if (state.estimate case final estimate?)
                Card(
                  key: const Key('ai_credit_estimate'),
                  child: ListTile(
                    leading: Icon(estimate.canExecute
                        ? Icons.toll_outlined
                        : Icons.account_balance_wallet_outlined),
                    title: Text(
                        'Custo estimado: ${estimate.estimatedCredits} créditos'),
                    subtitle: Text(
                        'Saldo disponível: ${estimate.availableCredits} créditos'),
                    trailing: estimate.canExecute
                        ? null
                        : TextButton(
                            onPressed: () => context.go('/credits'),
                            child: const Text('Créditos e planos'),
                          ),
                  ),
                ),
              _responsiveFields([
                _field(_provider, 'Provider',
                    key: const Key('prompt_provider'),
                    validator: (v) => _validateRequired(v, 1, 50)),
                _field(_model, 'Modelo (opcional)',
                    key: const Key('prompt_model'),
                    validator: (v) => _validateOptional(v, 1, 200)),
              ]),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 16),
              Text(state.error!,
                  key: const Key('prompt_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (interviewState.error != null) ...[
              const SizedBox(height: 16),
              Text(interviewState.error!,
                  key: const Key('interview_start_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('prompt_submit'),
              onPressed: isSubmitting ? null : _submit,
              icon: isSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(isSubmitting
                  ? _mode == PromptMode.basic
                      ? 'Construindo seu prompt...'
                      : 'Preparando sua criação...'
                  : _mode == PromptMode.basic
                      ? 'Construir meu prompt'
                      : 'Iniciar entrevista'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _responsiveFields(List<Widget> fields) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) return Column(children: fields);
          return Wrap(
            spacing: 12,
            children: fields
                .map((field) => SizedBox(
                    width: (constraints.maxWidth - 12) / 2, child: field))
                .toList(),
          );
        },
      );

  Widget _field(TextEditingController controller, String label,
      {Key? key,
      String? hint,
      int? max,
      int lines = 1,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: key,
        controller: controller,
        maxLines: lines,
        decoration: InputDecoration(labelText: label, hintText: hint),
        maxLength: max,
        validator: validator,
      ),
    );
  }

  static IconData _categoryIcon(PromptCategory category) => switch (category) {
        PromptCategory.marketing => Icons.campaign_outlined,
        PromptCategory.sales => Icons.sell_outlined,
        PromptCategory.socialMedia => Icons.share_outlined,
        PromptCategory.ecommerce => Icons.shopping_bag_outlined,
        PromptCategory.programming => Icons.code,
        PromptCategory.business => Icons.business_center_outlined,
        PromptCategory.education => Icons.school_outlined,
        PromptCategory.writing => Icons.edit_note,
        PromptCategory.image => Icons.image_outlined,
        PromptCategory.video => Icons.videocam_outlined,
        PromptCategory.productivity => Icons.task_alt,
        PromptCategory.general => Icons.auto_awesome,
      };
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.input, required this.validate});
  final TextEditingController input;
  final String? Function(String?, int, int) validate;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.auto_awesome,
                  size: 38, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('O que você quer criar?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text(
                'Conte sua ideia com suas palavras. O GUPMAX organiza os detalhes em uma instrução profissional.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('prompt_input'),
                controller: input,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Descreva sua ideia',
                  hintText:
                      'Ex.: Quero criar um anúncio para vender um tênis feminino...',
                  alignLabelWithHint: true,
                ),
                validator: (value) => validate(value, 3, 10000),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: _PromptCreatePageState._examples
                    .map((example) => ActionChip(
                          label: Text(example),
                          onPressed: () {
                            input.text = example;
                            input.selection = TextSelection.collapsed(
                                offset: input.text.length);
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String number;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(child: Text(number)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(subtitle),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              child,
            ],
          ),
        ),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final PromptMode mode;
  final bool selected;
  final VoidCallback onTap;

  String get title => switch (mode) {
        PromptMode.basic => 'GUPMAX Rápido',
        PromptMode.pro => 'GUPMAX Pro',
        PromptMode.expert => 'GUPMAX Expert',
      };

  String get description => switch (mode) {
        PromptMode.basic => 'Uma experiência direta para criar rapidamente.',
        PromptMode.pro => 'Mais contexto, público e organização da resposta.',
        PromptMode.expert =>
          'Mais profundidade, restrições e revisão estrutural.',
      };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(6),
        child: Semantics(
          button: true,
          selected: selected,
          label: '$title, $description',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected ? _selectedColor : AppColors.surface,
                border: Border.all(
                  width: selected ? 2 : 1,
                  color: selected ? _accentColor : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _accentColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(title,
                            style: Theme.of(context).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 8),
                  Text(description),
                ],
              ),
            ),
          ),
        ),
      );

  Color get _accentColor => switch (mode) {
        PromptMode.basic => AppColors.brightBlue,
        PromptMode.pro => AppColors.gold,
        PromptMode.expert => AppColors.deepBlue,
      };

  Color get _selectedColor => switch (mode) {
        PromptMode.basic => AppColors.paleBlue,
        PromptMode.pro => AppColors.paleGold,
        PromptMode.expert => const Color(0xFFDDECF8),
      };
}
