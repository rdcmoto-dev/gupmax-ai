import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/app/app.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/account/account_providers.dart';
import 'package:gupmax_ai/features/account/domain/smart_profile.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';
import 'package:gupmax_ai/features/templates/template_providers.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_account_repository.dart';
import '../../support/fake_interview_repository.dart';
import '../../support/fake_prompt_repository.dart';
import '../../support/fake_template_repository.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, FakePromptRepository prompts,
      [FakeInterviewRepository? interviews,
      FakeAccountRepository? accountRepository,
      FakeTemplateRepository? templateRepository]) async {
    final auth = AuthController(
      repository: FakeAuthRepository(),
      expiryBus: SessionExpiryBus(),
      restoreOnCreate: false,
    );
    await auth.login(email: 'teste@example.com', password: 'valid-password');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          accountRepositoryProvider
              .overrideWithValue(accountRepository ?? FakeAccountRepository()),
          promptRepositoryProvider.overrideWithValue(prompts),
          interviewRepositoryProvider
              .overrideWithValue(interviews ?? FakeInterviewRepository()),
          templateRepositoryProvider.overrideWithValue(
              templateRepository ?? FakeTemplateRepository()),
        ],
        child: const GupmaxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreate(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('create_prompt_button')));
    await tester.pumpAndSettle();
  }

  Future<void> submitPrompt(WidgetTester tester) async {
    final button = find.byKey(const Key('prompt_submit'));
    tester.widget<FilledButton>(button).onPressed!();
  }

  testWidgets(
      'seleciona e envia Target AI com default generico e layout mobile',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakePromptRepository();
    await pumpApp(tester, repository);
    await openCreate(tester);
    for (final target in TargetAI.values) {
      expect(find.byKey(Key('target_ai_${target.value}')), findsOneWidget);
    }
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('target_ai_generic')))
            .selected,
        isTrue);
    await tester.ensureVisible(find.byKey(const Key('target_ai_chatgpt')));
    await tester.tap(find.byKey(const Key('target_ai_chatgpt')));
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha');
    await submitPrompt(tester);
    await tester.pumpAndSettle();
    expect(repository.generatedInput?.targetAi, TargetAI.chatgpt);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valida formulário antes de criar', (tester) async {
    final repository = FakePromptRepository();
    await pumpApp(tester, repository);
    await openCreate(tester);
    await submitPrompt(tester);
    await tester.pump();
    expect(find.text('Use pelo menos 3 caracteres.'), findsOneWidget);
    expect(repository.generatedInput, isNull);
  });

  testWidgets('indica Smart Profile ativo sem sobrescrever override local',
      (tester) async {
    final prompts = FakePromptRepository();
    final account = FakeAccountRepository()
      ..smartProfileValue = const SmartProfile(
        isEnabled: true,
        defaultTone: 'profissional',
        defaultAudience: 'Empresários',
      );
    await pumpApp(tester, prompts, null, account);
    await openCreate(tester);
    expect(account.smartProfileCalls, 1);
    expect(find.byKey(const Key('smart_profile_active')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie um anúncio casual');
    final complementary = find.byKey(const Key('complementary_information'));
    await tester.ensureVisible(complementary);
    await tester.tap(complementary);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('prompt_tone')), 'casual');
    await submitPrompt(tester);
    await tester.pumpAndSettle();
    expect(prompts.generatedInput?.tone, 'casual');
    expect(account.smartProfileValue.defaultTone, 'profissional');
    expect(account.smartProfileSaveCalls, 0);
  });

  testWidgets('cria, mostra loading, resultado e copia prompt', (tester) async {
    final repository = FakePromptRepository()..generateCompleter = Completer();
    await pumpApp(tester, repository);
    await openCreate(tester);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha');
    tester
        .widget<SwitchListTile>(find.byKey(const Key('optimize_with_ai')))
        .onChanged!(true);
    await submitPrompt(tester);
    await tester.pump();
    expect(find.text('Construindo seu prompt...'), findsOneWidget);
    expect(repository.generatedInput?.optimizeWithAi, isTrue);
    repository.generateCompleter!.complete(repository.sample());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('generated_prompt')), findsOneWidget);
    expect(find.text('GUPMAX Pro'), findsOneWidget);
    expect(find.text('IA não utilizada'), findsOneWidget);
    final copyButton = find.byKey(const Key('copy_prompt'));
    await tester.ensureVisible(copyButton);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(copyButton).onPressed, isNotNull);
  });

  testWidgets('apresenta erro amigável do backend', (tester) async {
    final repository = FakePromptRepository()
      ..error = const AppException('Limite de uso atingido.');
    await pumpApp(tester, repository);
    await openCreate(tester);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha');
    await submitPrompt(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt_error')), findsOneWidget);
    expect(find.text('Limite de uso atingido.'), findsOneWidget);
  });

  testWidgets('toggle de IA mostra estimativa fornecida pelo backend',
      (tester) async {
    final repository = FakePromptRepository();
    await pumpApp(tester, repository);
    await openCreate(tester);
    tester
        .widget<SwitchListTile>(find.byKey(const Key('optimize_with_ai')))
        .onChanged!(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai_credit_estimate')), findsOneWidget);
    expect(find.byKey(const Key('ai_credit_estimate_summary')), findsOneWidget);
    expect(find.text('Custo estimado: 8 créditos'), findsOneWidget);
    expect(find.text('Saldo disponível: 100 créditos'), findsOneWidget);
    expect(
        find.text(
          'Custo estimado: 8 créditos. Saldo disponível: 100 créditos.',
        ),
        findsOneWidget);
  });

  testWidgets('estimativa sem saldo oferece Créditos e planos', (tester) async {
    final repository = FakePromptRepository()
      ..estimateResult = const AiCreditEstimate(
          estimatedCredits: 8, availableCredits: 2, canExecute: false);
    await pumpApp(tester, repository);
    await openCreate(tester);
    tester
        .widget<SwitchListTile>(find.byKey(const Key('optimize_with_ai')))
        .onChanged!(true);
    await tester.pumpAndSettle();
    expect(find.text('Créditos e planos'), findsOneWidget);
  });

  testWidgets('resultado otimizado identifica uso real de IA', (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample(
          status: 'optimized', provider: 'openai', model: 'test-model'));
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    expect(find.text('IA utilizada'), findsOneWidget);
    expect(find.text('Provider: openai'), findsOneWidget);
  });

  testWidgets('salva versão exibida como template e apresenta confirmação',
      (tester) async {
    final prompts = FakePromptRepository()
      ..records.add(FakePromptRepository().sample());
    final templates = FakeTemplateRepository();
    await pumpApp(tester, prompts, null, null, templates);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('save_as_template'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Salvar como template'), findsAtLeastNWidgets(1));
    await tester.enterText(
        find.byKey(const Key('template_name')), 'Campanha para pizzaria');
    await tester.tap(find.byKey(const Key('confirm_save_template')));
    await tester.pumpAndSettle();
    expect(templates.saveCalls, 1);
    expect(find.text('Template salvo com sucesso.'), findsOneWidget);
  });

  testWidgets('GUPMAX Score abre análise e prepara refinamento sem executar',
      (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample());
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gupmax_score_card')), findsOneWidget);
    expect(find.text('72 / 100'), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle_score_analysis')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('improve_prompt_from_score')));
    await tester.tap(find.byKey(const Key('improve_prompt_from_score')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('refinement_form')), findsOneWidget);
    expect(
        find.text('Defina para quem a resposta será criada.'), findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('refine_with_ai')))
            .value,
        isFalse);
    expect(find.byKey(const Key('gupmax_score_card')), findsOneWidget);
    expect(repository.refineCalls, 0);
    expect(repository.estimateRefinementCalls, 0);
  });

  testWidgets('scores de V1 V2 V3 acompanham a versão selecionada',
      (tester) async {
    final repository = FakePromptRepository();
    repository.records.addAll([
      repository.sample(id: 'v1'),
      repository.sample(
          id: 'v2', versionNumber: 2, parentPromptId: 'v1', rootPromptId: 'v1'),
      repository.sample(
          id: 'v3', versionNumber: 3, parentPromptId: 'v2', rootPromptId: 'v1'),
    ]);
    repository.scoreResults.addAll({
      'v1': const PromptQualityScore(
          promptId: 'v1',
          score: 50,
          rating: 'needs_improvement',
          criteria: [],
          strengths: [],
          improvements: [],
          suggestions: []),
      'v2': const PromptQualityScore(
          promptId: 'v2',
          score: 70,
          rating: 'good',
          criteria: [],
          strengths: [],
          improvements: [],
          suggestions: []),
      'v3': const PromptQualityScore(
          promptId: 'v3',
          score: 90,
          rating: 'excellent',
          criteria: [],
          strengths: [],
          improvements: [],
          suggestions: []),
    });
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_v3')));
    await tester.pumpAndSettle();

    expect(repository.scoreCalls, 3);
    expect(find.text('90 / 100'), findsOneWidget);
    final useV1 = find
        .descendant(
          of: find.byKey(const Key('prompt_versions')),
          matching: find.widgetWithText(TextButton, 'Usar esta'),
        )
        .first;
    await tester.ensureVisible(useV1);
    await tester.pumpAndSettle();
    await tester.tap(useV1);
    await tester.pumpAndSettle();
    expect(find.text('50 / 100'), findsOneWidget);
    expect(find.byKey(const Key('gupmax_score_card')), findsOneWidget);
  });

  testWidgets('404 de versions preserva prompt antigo como versão 1',
      (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample(
        mode: PromptMode.basic,
        status: 'optimized',
        provider: 'openai',
        model: 'gpt-5.6-luna',
        totalTokens: 439,
      ))
      ..versionsError =
          const AppException('Prompt não encontrado.', statusCode: 404);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('generated_prompt')), findsOneWidget);
    expect(find.byKey(const Key('result_version')), findsOneWidget);
    expect(find.byKey(const Key('prompt_error')), findsNothing);
    expect(find.text('Prompt não encontrado.'), findsNothing);
    expect(find.byKey(const Key('refine_prompt')), findsOneWidget);
    expect(find.byKey(const Key('prompt_versions')), findsOneWidget);
    final estimatesBeforeOpen = repository.estimateRefinementCalls;
    final refinementsBeforeOpen = repository.refineCalls;
    await tester.tap(find.byKey(const Key('refine_prompt')));
    await tester.pumpAndSettle();
    const instruction = 'Deixe mais persuasivo e mantenha curto.';
    await tester.enterText(
        find.byKey(const Key('refinement_instruction')), instruction);
    await tester.pump();

    expect(find.text(instruction), findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('refine_with_ai')))
            .value,
        isFalse);
    expect(repository.estimateRefinementCalls, 0);
    expect(repository.estimateRefinementCalls, estimatesBeforeOpen);
    expect(repository.refineCalls, refinementsBeforeOpen);
    expect(find.text('Prompt não encontrado.'), findsNothing);
    expect(find.byKey(const Key('prompt_error')), findsNothing);
    expect(find.byKey(const Key('refinement_error')), findsNothing);
  });

  testWidgets('nova interação limpa refinementError histórico sem requests',
      (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample())
      ..estimateRefinementError =
          const AppException('Prompt não encontrado.', statusCode: 404);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refine_prompt')));
    await tester.pumpAndSettle();
    const instruction = 'Deixe mais persuasivo e mantenha curto.';
    await tester.enterText(
        find.byKey(const Key('refinement_instruction')), instruction);
    tester
        .widget<SwitchListTile>(find.byKey(const Key('refine_with_ai')))
        .onChanged!(true);
    await tester.pumpAndSettle();
    expect(find.text('Prompt não encontrado.'), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('refine_prompt'))));
    final controller = container.read(promptControllerProvider);
    expect(controller.refinementError, isNull);
    expect(controller.refinementEstimateError, 'Prompt não encontrado.');
    final getCallsBeforeReopen = repository.getCalls;
    final versionsCallsBeforeReopen = repository.versionsCalls;

    tester
        .widget<SwitchListTile>(find.byKey(const Key('refine_with_ai')))
        .onChanged!(false);
    await tester.pumpAndSettle();
    expect(controller.refinementEstimateError, isNull);
    expect(find.text('Prompt não encontrado.'), findsNothing);
    await tester.tap(find.byKey(const Key('refine_prompt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refine_prompt')));
    await tester.pumpAndSettle();

    expect(identical(controller, container.read(promptControllerProvider)),
        isTrue);
    expect(controller.refinementError, isNull);
    expect(controller.error, isNull);
    expect(find.text('Prompt não encontrado.'), findsNothing);
    expect(find.text(instruction), findsOneWidget);
    expect(repository.estimateRefinementCalls, 1);
    expect(repository.refineCalls, 0);
    expect(repository.getCalls, getCallsBeforeReopen);
    expect(repository.versionsCalls, versionsCallsBeforeReopen);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit_refinement')))
            .onPressed,
        isNotNull);
  });

  testWidgets('ação Refinar prompt fica visível ao abrir resultado persistido',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample(
        status: 'optimized',
        provider: 'openai',
        model: 'gpt-5.6-luna',
        generatedPrompt:
            List.filled(25, 'Crie uma campanha persuasiva para Instagram.')
                .join('\n'),
      ));
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();

    final action = find.byKey(const Key('refine_prompt'));
    expect(action, findsOneWidget);
    expect(tester.getRect(action).top, lessThan(720));
  });

  for (final testCase
      in <({String name, PromptMode mode, String status, String text})>[
    (
      name: 'Rápido sem IA',
      mode: PromptMode.basic,
      status: 'generated',
      text: '## OBJECTIVE\nCrie uma campanha',
    ),
    (
      name: 'Pro com IA',
      mode: PromptMode.pro,
      status: 'optimized',
      text: '## OBJECTIVE\nCrie uma campanha',
    ),
    (
      name: 'Expert sem IA',
      mode: PromptMode.expert,
      status: 'generated',
      text: '## OBJECTIVE\nCrie uma campanha',
    ),
    (
      name: 'originado de entrevista',
      mode: PromptMode.expert,
      status: 'generated',
      text:
          '## CONTEXT\nInstagram\n\n## AUDIENCE\nJovens\n\n## CONSTRAINTS\nCurto',
    ),
  ]) {
    testWidgets('Refinar prompt acessível para ${testCase.name}',
        (tester) async {
      final repository = FakePromptRepository()
        ..records.add(FakePromptRepository().sample(
          mode: testCase.mode,
          status: testCase.status,
          provider: testCase.status == 'optimized' ? 'openai' : null,
          model: testCase.status == 'optimized' ? 'gpt-5.6-luna' : null,
          generatedPrompt: testCase.text,
        ));
      await pumpApp(tester, repository);
      await tester.tap(find.byKey(const Key('my_prompts_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prompt_prompt-1')));
      await tester.pumpAndSettle();

      final action = find.byKey(const Key('refine_prompt'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('refinement_instruction')), findsOneWidget);
      expect(find.byKey(const Key('refine_with_ai')), findsOneWidget);
    });
  }

  testWidgets('refino determinístico cria versão e preserva anterior',
      (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample());
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refine_prompt')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('refinement_instruction')),
        'Deixe mais persuasivo e mantenha curto.');
    final submit = find.byKey(const Key('submit_refinement'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.refinedInput?.optimizeWithAi, isFalse);
    expect(find.text('Versão 2'), findsWidgets);
    expect(find.textContaining('Versão 1'), findsWidgets);
    expect(find.text('Comparar versões'), findsOneWidget);
    expect(find.textContaining('ANTERIOR'), findsOneWidget);
    expect(find.textContaining('NOVA'), findsOneWidget);
  });

  testWidgets('refino com IA mostra estimate e bloqueia sem saldo',
      (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample())
      ..estimateResult = const AiCreditEstimate(
          estimatedCredits: 8, availableCredits: 2, canExecute: false);
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refine_prompt')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('refinement_instruction')), 'Deixe mais curto.');
    tester
        .widget<SwitchListTile>(find.byKey(const Key('refine_with_ai')))
        .onChanged!(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('refinement_estimate')), findsOneWidget);
    expect(find.text('Estimativa: 8 créditos'), findsOneWidget);
    expect(find.text('Créditos e planos'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit_refinement')))
            .onPressed,
        isNull);
    expect(repository.refinedInput, isNull);
  });

  testWidgets('histórico vazio exibe estado dedicado', (tester) async {
    await pumpApp(tester, FakePromptRepository());
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty_prompts')), findsOneWidget);
  });

  testWidgets('histórico preenchido abre detalhes e pagina', (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample())
      ..totalOverride = 25;
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt_prompt-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('next_page')));
    await tester.pumpAndSettle();
    expect(repository.requestedOffset, 20);
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('generated_prompt')), findsOneWidget);
  });

  testWidgets('edita e exclui prompt com confirmação', (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample());
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_prompt')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('edit_title')), 'Título atualizado');
    await tester.tap(find.byKey(const Key('save_prompt')));
    await tester.pumpAndSettle();
    expect(find.text('Título atualizado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete_prompt')));
    await tester.pumpAndSettle();
    expect(find.text('Esta ação não pode ser desfeita.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_delete')));
    await tester.pumpAndSettle();
    expect(repository.deleted, isTrue);
    expect(find.byKey(const Key('empty_prompts')), findsOneWidget);
  });

  for (final mapping in {PromptMode.basic: 'GUPMAX Rápido'}.entries) {
    testWidgets('${mapping.value} envia ${mapping.key.name}', (tester) async {
      final repository = FakePromptRepository();
      await pumpApp(tester, repository);
      await openCreate(tester);
      expect(find.text(mapping.value), findsOneWidget);
      final modeCard = find.byKey(Key('mode_${mapping.key.name}'));
      tester
          .widget<InkWell>(
              find.descendant(of: modeCard, matching: find.byType(InkWell)))
          .onTap!();
      await tester.enterText(
          find.byKey(const Key('prompt_input')), 'Crie algo profissional');
      await submitPrompt(tester);
      await tester.pumpAndSettle();
      expect(repository.generatedInput?.mode, mapping.key);
    });
  }

  for (final mapping in {
    PromptMode.pro: 'GUPMAX Pro',
    PromptMode.expert: 'GUPMAX Expert',
  }.entries) {
    testWidgets('${mapping.value} inicia entrevista ${mapping.key.name}',
        (tester) async {
      final interviews = FakeInterviewRepository();
      await pumpApp(tester, FakePromptRepository(), interviews);
      await openCreate(tester);
      final modeCard = find.byKey(Key('mode_${mapping.key.name}'));
      tester
          .widget<InkWell>(
              find.descendant(of: modeCard, matching: find.byType(InkWell)))
          .onTap!();
      await tester.enterText(
          find.byKey(const Key('prompt_input')), 'Crie algo profissional');
      await submitPrompt(tester);
      await tester.pumpAndSettle();
      expect(interviews.createdMode, mapping.key);
      expect(interviews.createdRequest, 'Crie algo profissional');
      expect(interviews.createdKnownFields?.language, 'pt-BR');
      expect(interviews.createdKnownFields?.mode, mapping.key);
      expect(find.text('Vamos melhorar seu prompt'), findsOneWidget);
    });
  }

  testWidgets('entrevista preserva a opção de otimização com IA',
      (tester) async {
    final interviews = FakeInterviewRepository();
    await pumpApp(tester, FakePromptRepository(), interviews);
    await openCreate(tester);
    final pro = find.byKey(const Key('mode_pro'));
    tester
        .widget<InkWell>(
            find.descendant(of: pro, matching: find.byType(InkWell)))
        .onTap!();
    tester
        .widget<SwitchListTile>(find.byKey(const Key('optimize_with_ai')))
        .onChanged!(true);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha completa');
    await submitPrompt(tester);
    await tester.pumpAndSettle();
    expect(interviews.createdKnownFields?.optimizeWithAi, isTrue);
  });

  testWidgets('exibe categorias reais e envia campos complementares',
      (tester) async {
    final repository = FakePromptRepository();
    await pumpApp(tester, repository);
    await openCreate(tester);
    for (final category in PromptCategory.values) {
      expect(find.byKey(Key('category_${category.value}')), findsOneWidget);
    }
    final programming = find.byKey(const Key('category_programacao'));
    await tester.ensureVisible(programming);
    await tester.tap(programming);
    final complementary = find.byKey(const Key('complementary_information'));
    await tester.ensureVisible(complementary);
    await tester.tap(complementary);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Criar uma API segura');
    await tester.enterText(
        find.byKey(const Key('prompt_context')), 'Projeto Flutter e FastAPI');
    await tester.enterText(
        find.byKey(const Key('prompt_audience')), 'Desenvolvedores');
    await tester.enterText(
        find.byKey(const Key('prompt_output_format')), 'Passos numerados');
    await submitPrompt(tester);
    await tester.pumpAndSettle();
    expect(repository.generatedInput?.category, PromptCategory.programming);
    expect(repository.generatedInput?.context, 'Projeto Flutter e FastAPI');
    expect(repository.generatedInput?.audience, 'Desenvolvedores');
    expect(repository.generatedInput?.outputFormat, 'Passos numerados');
  });

  testWidgets('experiência de criação funciona em largura reduzida',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpApp(tester, FakePromptRepository());
    expect(tester.takeException(), isNull);
    await openCreate(tester);
    expect(find.text('O que você quer criar?'), findsOneWidget);
    expect(find.byKey(const Key('mode_basic')), findsOneWidget);
    expect(find.byTooltip('Navegação principal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
