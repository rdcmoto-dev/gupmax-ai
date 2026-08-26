import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/account/account_providers.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';
import 'package:gupmax_ai/features/prompt_chains/presentation/prompt_chain_list_page.dart';
import 'package:gupmax_ai/features/prompt_chains/presentation/prompt_chain_detail_page.dart';
import 'package:gupmax_ai/features/prompt_chains/prompt_chain_providers.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_create_page.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';
import 'package:gupmax_ai/features/templates/template_providers.dart';
import 'package:gupmax_ai/features/templates/domain/prompt_template.dart';

import '../../support/fake_account_repository.dart';
import '../../support/fake_interview_repository.dart';
import '../../support/fake_project_repository.dart';
import '../../support/fake_prompt_chain_repository.dart';
import '../../support/fake_prompt_repository.dart';
import '../../support/fake_template_repository.dart';

void main() {
  Future<void> verifyTwoSteps(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final chains = FakePromptChainRepository();
    await chains.create({'name': 'Lançamento Pizzaria Donatello'});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        promptChainRepositoryProvider.overrideWithValue(chains),
        templateRepositoryProvider.overrideWithValue(FakeTemplateRepository()),
      ],
      child: const MaterialApp(home: PromptChainDetailPage(chainId: 'chain-1')),
    ));
    await tester.pumpAndSettle();

    Future<void> add(String title, String input) async {
      expect(find.text('+ Adicionar etapa'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('add_step')));
      await tester.tap(find.byKey(const Key('add_step')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('step_title')), title);
      await tester.enterText(find.byKey(const Key('step_input')), input);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save_step')));
      await tester.tap(find.byKey(const Key('save_step')));
      await tester.pumpAndSettle();
    }

    await add('Posicionamento', 'Crie posicionamento para Donatello');
    await add('Campanha', 'Crie uma campanha para Instagram');
    expect(chains.addStepCalls, 2);
    await tester.scrollUntilVisible(find.text('Campanha'), 100);
    expect(find.text('Posicionamento'), findsOneWidget);
    expect(find.text('Campanha'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets('cria fluxo e adiciona duas etapas ordenadas no desktop',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await verifyTwoSteps(tester, const Size(1280, 900));
  });

  testWidgets(
      'cria fluxo e adiciona duas etapas ordenadas no mobile sem overflow',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await verifyTwoSteps(tester, const Size(390, 844));
  });

  testWidgets('Meus fluxos mostra vazio e cria fluxo sem overflow',
      (tester) async {
    final repository = FakePromptChainRepository();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        promptChainRepositoryProvider.overrideWithValue(repository),
        projectRepositoryProvider.overrideWithValue(FakeProjectRepository()),
      ],
      child: const MaterialApp(home: PromptChainListPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chains_empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('new_chain')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('chain_name')), 'Fluxo de lançamento');
    await tester.tap(find.byKey(const Key('save_chain')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
    expect(find.text('Fluxo de lançamento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resultado anterior reaparece ao reabrir e reconstruir a etapa',
      (tester) async {
    final chains = FakePromptChainRepository()
      ..items = [
        chainSample(steps: [
          PromptChainStep(
            id: 'step-2',
            chainId: 'chain-1',
            position: 2,
            title: 'Campanha',
            baseInput: 'Use {resultado_anterior} para {empresa}',
            mode: PromptMode.basic,
            category: PromptCategory.marketing,
            targetAi: TargetAI.claude,
            variables: const [
              TemplateVariable(name: 'empresa', label: 'Empresa')
            ],
            // Reproduz metadata ausente/desatualizada recebida pelo frontend.
            requiresPreviousResult: false,
          ),
        ])
      ];
    final prompts = FakePromptRepository()..generateCompleter = Completer();
    Future<void> openStep(String key) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            promptChainRepositoryProvider.overrideWithValue(chains),
            promptRepositoryProvider.overrideWithValue(prompts),
            accountRepositoryProvider
                .overrideWithValue(FakeAccountRepository()),
            projectRepositoryProvider
                .overrideWithValue(FakeProjectRepository()),
            interviewRepositoryProvider
                .overrideWithValue(FakeInterviewRepository()),
            templateRepositoryProvider
                .overrideWithValue(FakeTemplateRepository()),
          ],
          child: MaterialApp(
              home: PromptCreatePage(
                  key: ValueKey(key),
                  chainId: 'chain-1',
                  chainStepId: 'step-2'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('previous_result')), findsOneWidget);
      expect(
          find.byKey(const Key('template_variable_empresa')), findsOneWidget);
    }

    await openStep('first-open');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await openStep('reopen');
    await openStep('browser-refresh-reconstruction');

    expect(find.byKey(const Key('selected_chain')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('previous_result')), 'Marca familiar premium');
    await tester.enterText(
        find.byKey(const Key('template_variable_empresa')), 'Donatello');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(submit);
    tester.widget<FilledButton>(submit).onPressed!();
    await tester.pump();
    expect(prompts.generatedInput?.chainId, 'chain-1');
    expect(prompts.generatedInput?.chainStepId, 'step-2');
    expect(prompts.generatedInput?.previousResult, 'Marca familiar premium');
    expect(prompts.generatedInput?.variableValues, {'empresa': 'Donatello'});
    expect(tester.takeException(), isNull);
  });
}
