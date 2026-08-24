import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/account/account_providers.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/core/routing/app_router.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_create_page.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/templates/presentation/template_list_page.dart';
import 'package:gupmax_ai/features/templates/template_providers.dart';
import 'package:gupmax_ai/features/templates/domain/prompt_template.dart';

import '../../support/fake_account_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_interview_repository.dart';
import '../../support/fake_prompt_repository.dart';
import '../../support/fake_project_repository.dart';
import '../../support/fake_template_repository.dart';

void main() {
  testWidgets('lista mostra loading e empty state', (tester) async {
    final repository = FakeTemplateRepository()..listCompleter = Completer();
    await _pumpList(tester, repository);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.listCompleter!.complete(const TemplatePageData([], 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('templates_empty')), findsOneWidget);
  });

  testWidgets('cria template dinâmico e detecta variáveis no editor',
      (tester) async {
    final repository = FakeTemplateRepository();
    await _pumpList(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_template_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('template_create_name')), 'Campanha dinâmica');
    await tester.enterText(find.byKey(const Key('template_create_content')),
        'Crie campanha para {produto} no {canal}');
    await tester.pumpAndSettle();
    expect(find.text('Variáveis encontradas:'), findsOneWidget);
    expect(find.text('Produto'), findsOneWidget);
    expect(find.text('Canal'), findsOneWidget);
    await tester.tap(find.byKey(const Key('template_create_save')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
    expect(find.text('2 variáveis'), findsOneWidget);
  });

  testWidgets('fluxo real cria, lista, usa pela rota e envia variáveis',
      (tester) async {
    final templates = FakeTemplateRepository();
    final prompts = FakePromptRepository()..generateCompleter = Completer();
    final authRepository = FakeAuthRepository();
    final bus = SessionExpiryBus();
    final auth = AuthController(
      repository: authRepository,
      expiryBus: bus,
      restoreOnCreate: false,
    );
    await auth.login(email: 'usuario@example.com', password: 'senha-valida');
    final router = createAppRouter(auth, initialLocation: '/templates');
    addTearDown(router.dispose);
    addTearDown(bus.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        templateRepositoryProvider.overrideWithValue(templates),
        promptRepositoryProvider.overrideWithValue(prompts),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        projectRepositoryProvider.overrideWithValue(FakeProjectRepository()),
        interviewRepositoryProvider
            .overrideWithValue(FakeInterviewRepository()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create_template_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('template_create_name')), 'Campanha dinâmica');
    const original =
        'Crie uma campanha para {produto} voltada para {publico} no {canal}.';
    await tester.enterText(
        find.byKey(const Key('template_create_content')), original);
    await tester.pump();
    await tester.tap(find.byKey(const Key('template_create_save')));
    await tester.pumpAndSettle();
    expect(templates.createCalls, 1);
    expect(find.text('Campanha dinâmica'), findsOneWidget);
    expect(
        find.byKey(const Key('use_template_created-template')), findsOneWidget);

    // Reproduz o payload real que disparou o smoke: conteúdo presente e
    // metadata variables ausente. A desserialização deve recalcular os campos.
    templates.items = [
      PromptTemplateRecord.fromJson({
        'id': 'created-template',
        'name': 'Campanha dinâmica',
        'category': 'geral',
        'mode': 'basic',
        'target_ai': 'generic',
        'template_content': original,
        'base_input': original,
        'language': 'pt-BR',
        'constraints': <String>[],
        'instructions': <String>[],
        'is_active': true,
        'project_id': null,
        'source_prompt_id': null,
        'created_at': '2026-08-24T12:00:00Z',
        'updated_at': '2026-08-24T12:00:00Z',
      }),
    ];
    await tester.tap(find.byKey(const Key('use_template_created-template')));
    await tester.pumpAndSettle();

    expect(
        router.routeInformationProvider.value.uri.queryParameters['template'],
        'created-template');
    expect(find.byKey(const Key('template_variables_form')), findsOneWidget);
    expect(find.text('Produto *'), findsOneWidget);
    expect(find.text('Público *'), findsOneWidget);
    expect(find.text('Canal *'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('template_variable_produto')), 'Pizza artesanal');
    await tester.enterText(find.byKey(const Key('template_variable_publico')),
        'Famílias da região');
    await tester.enterText(
        find.byKey(const Key('template_variable_canal')), 'Instagram');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(submit);
    tester.widget<FilledButton>(submit).onPressed!();
    await tester.pump();

    expect(prompts.generatedInput?.templateId, 'created-template');
    expect(prompts.generatedInput?.variableValues, {
      'produto': 'Pizza artesanal',
      'publico': 'Famílias da região',
      'canal': 'Instagram',
    });
    expect(templates.items.single.baseInput, original);
    prompts.generateCompleter!.complete(prompts.sample());
    await tester.pumpAndSettle();

    router.go('/templates');
    await tester.pumpAndSettle();
    router.go('/prompts/new?template=created-template');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template_variables_form')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lista permite usar editar e excluir com confirmação',
      (tester) async {
    final repository = FakeTemplateRepository()..items = [sample()];
    await _pumpList(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Campanha para pizzaria'), findsOneWidget);
    expect(find.text('Usar'), findsOneWidget);

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('template_edit_name')), 'Campanha editada');
    await tester.tap(find.byKey(const Key('template_edit_save')));
    await tester.pumpAndSettle();
    expect(repository.updateCalls, 1);
    expect(find.text('Campanha editada'), findsOneWidget);

    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_template_delete')));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 1);
    expect(find.byKey(const Key('templates_empty')), findsOneWidget);
  });

  testWidgets('template preenche criação e permite override local sem gerar',
      (tester) async {
    final repository = FakeTemplateRepository()
      ..items = [
        sample(
          tone: 'profissional',
          additionalInformation: 'Canal/plataforma: Instagram',
        ),
      ];
    final prompts = FakePromptRepository()..generateCompleter = Completer();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        templateRepositoryProvider.overrideWithValue(repository),
        promptRepositoryProvider.overrideWithValue(prompts),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        interviewRepositoryProvider
            .overrideWithValue(FakeInterviewRepository()),
      ],
      child:
          const MaterialApp(home: PromptCreatePage(templateId: 'template-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Template: Campanha para pizzaria'), findsOneWidget);
    final complementary = find.byKey(const Key('complementary_information'));
    await tester.ensureVisible(complementary);
    await tester.tap(complementary);
    await tester.pumpAndSettle();
    final tone = find.byKey(const Key('prompt_tone'));
    await tester.ensureVisible(tone);
    await tester.enterText(tone, 'casual');
    final additional = find.byKey(const Key('prompt_additional_information'));
    await tester.ensureVisible(additional);
    await tester.enterText(
      additional,
      'Canal/plataforma: TikTok',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(submit);
    tester.widget<FilledButton>(submit).onPressed!();
    await tester.pump();
    expect(prompts.generatedInput!.tone, 'casual');
    expect(prompts.generatedInput!.additionalInformation,
        'Canal/plataforma: TikTok');
    expect(prompts.generatedInput!.optimizeWithAi, isFalse);
    expect(repository.items.single.baseInput, 'Criar campanha para pizzaria');
    expect(repository.items.single.tone, 'profissional');
    expect(repository.items.single.additionalInformation,
        'Canal/plataforma: Instagram');
  });

  testWidgets('template dinâmico mostra campos, valida e envia valores',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const content =
        'Crie uma campanha para {produto} voltada para {publico} no {canal}.';
    final variables = detectTemplateVariables(content);
    final templates = FakeTemplateRepository()
      ..items = [
        sample(
          name: 'Campanha dinâmica',
          templateContent: content,
          baseInput: content,
          variables: variables,
        ),
      ];
    final prompts = FakePromptRepository()..generateCompleter = Completer();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        templateRepositoryProvider.overrideWithValue(templates),
        promptRepositoryProvider.overrideWithValue(prompts),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        interviewRepositoryProvider
            .overrideWithValue(FakeInterviewRepository()),
      ],
      child:
          const MaterialApp(home: PromptCreatePage(templateId: 'template-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template_variables_form')), findsOneWidget);
    expect(find.text('Produto *'), findsOneWidget);
    expect(find.text('Público *'), findsOneWidget);
    expect(find.text('Canal *'), findsOneWidget);

    final submit = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Preencha Produto.'), findsOneWidget);
    expect(prompts.generatedInput, isNull);

    await tester.enterText(
        find.byKey(const Key('template_variable_produto')), 'Pizza artesanal');
    await tester.enterText(find.byKey(const Key('template_variable_publico')),
        'Famílias da região');
    await tester.enterText(
        find.byKey(const Key('template_variable_canal')), 'Instagram');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(submit);
    tester.widget<FilledButton>(submit).onPressed!();
    await tester.pump();
    expect(prompts.generatedInput?.templateId, 'template-1');
    expect(prompts.generatedInput?.variableValues, {
      'produto': 'Pizza artesanal',
      'publico': 'Famílias da região',
      'canal': 'Instagram',
    });
    expect(templates.items.single.baseInput, content);
    expect(tester.takeException(), isNull);
  });

  testWidgets('template dinâmico preenche uma vez no Multi-Target desktop',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const content = 'Crie campanha para {produto} no {canal}';
    final templates = FakeTemplateRepository()
      ..items = [
        sample(
          templateContent: content,
          baseInput: content,
          variables: detectTemplateVariables(content),
        ),
      ];
    final prompts = FakePromptRepository()
      ..error = const AppException('Comparação interrompida no teste.');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        templateRepositoryProvider.overrideWithValue(templates),
        promptRepositoryProvider.overrideWithValue(prompts),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        interviewRepositoryProvider
            .overrideWithValue(FakeInterviewRepository()),
      ],
      child:
          const MaterialApp(home: PromptCreatePage(templateId: 'template-1')),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('template_variable_produto')), 'Pizza artesanal');
    await tester.enterText(
        find.byKey(const Key('template_variable_canal')), 'Instagram');
    final toggle = find.byKey(const Key('multi_target_toggle'));
    await tester.ensureVisible(toggle);
    tester.widget<SwitchListTile>(toggle).onChanged!(true);
    await tester.pump();
    final submit = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(prompts.compareCalls, 1);
    expect(prompts.comparedInput?.variableValues,
        {'produto': 'Pizza artesanal', 'canal': 'Instagram'});
    expect(prompts.comparedInput?.comparisonTargetAis,
        [TargetAI.chatgpt, TargetAI.claude]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lista indica variáveis e edição detecta em tempo real',
      (tester) async {
    const content = 'Crie anúncio para {produto} no {canal}';
    final repository = FakeTemplateRepository()
      ..items = [
        sample(
          templateContent: content,
          baseInput: content,
          variables: detectTemplateVariables(content),
        ),
      ];
    await _pumpList(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('2 variáveis'), findsOneWidget);
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Variáveis encontradas:'), findsOneWidget);
    expect(find.text('Produto'), findsOneWidget);
    expect(find.text('Canal'), findsOneWidget);
  });

  testWidgets('template estruturado com projeto envia somente o objetivo',
      (tester) async {
    const structured = '''## ROLE
Especialista em marketing e comunicação persuasiva

## OBJECTIVE
Criar uma campanha para divulgar uma pizzaria

## CONTEXT
Pizzaria premium especializada em pizzas artesanais para eventos corporativos.
## AUDIENCE
donos de pequenos negócios

## INSTRUCTIONS
- Priorize recomendações aplicáveis e objetivas.

## CONSTRAINTS
- Use linguagem clara e prática.

## OUTPUT FORMAT
lista objetiva

## LANGUAGE
pt-BR

## TONE
profissional

## ADDITIONAL INFORMATION
Canal/plataforma: Instagram''';
    final template = PromptTemplateRecord.fromJson({
      'id': 'template-1',
      'name': 'Criar uma campanha para divulgar uma pizzaria',
      'project_id': null,
      'source_prompt_id': 'prompt-1',
      'category': 'marketing',
      'mode': 'basic',
      'base_input': structured,
      'template_content': structured,
      'context':
          'Pequena empresa brasileira que vende produtos e serviços pela internet.',
      'audience': 'donos de pequenos negócios',
      'instructions': ['Priorize recomendações aplicáveis e objetivas.'],
      'constraints': ['Use linguagem clara e prática.'],
      'output_format': 'lista objetiva',
      'language': 'pt-BR',
      'tone': 'profissional',
      'additional_information': 'Canal/plataforma: Instagram',
      'is_active': true,
      'created_at': '2026-08-21T16:25:58.207087Z',
      'updated_at': '2026-08-21T16:25:58.207087Z',
    });
    final templates = FakeTemplateRepository()..items = [template];
    final projects = FakeProjectRepository()..items = [projectSample()];
    final prompts = FakePromptRepository()..generateCompleter = Completer();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        templateRepositoryProvider.overrideWithValue(templates),
        projectRepositoryProvider.overrideWithValue(projects),
        promptRepositoryProvider.overrideWithValue(prompts),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        interviewRepositoryProvider
            .overrideWithValue(FakeInterviewRepository()),
      ],
      child: const MaterialApp(
        home: PromptCreatePage(
          templateId: 'template-1',
          projectId: 'project-1',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(prompts.generatedInput!.input,
        'Criar uma campanha para divulgar uma pizzaria');
    expect(prompts.generatedInput!.input, isNot(contains('## ROLE')));
    expect(prompts.generatedInput!.title, isNull);
    expect(prompts.generatedInput!.projectId, 'project-1');
    expect(prompts.generatedInput!.context,
        'Pizzaria premium especializada em pizzas artesanais para eventos corporativos.');
    expect(prompts.generatedInput!.role,
        'Especialista em marketing e comunicação persuasiva');
    expect(prompts.generatedInput!.audience, 'donos de pequenos negócios');
    expect(prompts.generatedInput!.instructions,
        ['Priorize recomendações aplicáveis e objetivas.']);
    expect(prompts.generatedInput!.constraints,
        ['Use linguagem clara e prática.']);
    for (final value in prompts.generatedInput!.toJson().values) {
      expect(value.toString(), isNot(contains('## ')));
    }
    expect(templates.items.single.baseInput, structured);
    expect(templates.items.single.context,
        'Pequena empresa brasileira que vende produtos e serviços pela internet.');
  });

  testWidgets('grid responsivo não apresenta overflow', (tester) async {
    final repository = FakeTemplateRepository()..items = [sample()];
    for (final width in [390.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await _pumpList(tester, repository);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpList(
    WidgetTester tester, FakeTemplateRepository repository) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [templateRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: TemplateListPage()),
  ));
}
