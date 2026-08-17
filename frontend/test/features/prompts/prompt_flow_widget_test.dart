import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/app/app.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_interview_repository.dart';
import '../../support/fake_prompt_repository.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, FakePromptRepository prompts,
      [FakeInterviewRepository? interviews]) async {
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
          promptRepositoryProvider.overrideWithValue(prompts),
          interviewRepositoryProvider
              .overrideWithValue(interviews ?? FakeInterviewRepository()),
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

  testWidgets('valida formulário antes de criar', (tester) async {
    final repository = FakePromptRepository();
    await pumpApp(tester, repository);
    await openCreate(tester);
    await submitPrompt(tester);
    await tester.pump();
    expect(find.text('Use pelo menos 3 caracteres.'), findsOneWidget);
    expect(repository.generatedInput, isNull);
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
