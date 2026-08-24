import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/app/app.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/account/account_providers.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';
import 'package:gupmax_ai/features/templates/template_providers.dart';

import '../../support/fake_account_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_interview_repository.dart';
import '../../support/fake_prompt_repository.dart';
import '../../support/fake_template_repository.dart';

void main() {
  Future<void> pumpApp(
      WidgetTester tester, FakePromptRepository prompts) async {
    final auth = AuthController(
      repository: FakeAuthRepository(),
      expiryBus: SessionExpiryBus(),
      restoreOnCreate: false,
    );
    await auth.login(email: 'teste@example.com', password: 'valid-password');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        promptRepositoryProvider.overrideWithValue(prompts),
        interviewRepositoryProvider
            .overrideWithValue(FakeInterviewRepository()),
        templateRepositoryProvider.overrideWithValue(FakeTemplateRepository()),
      ],
      child: const GupmaxApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_prompt_button')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'controle real inicia desligado, seleciona 2 a 4 e volta ao single-target',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, FakePromptRepository());
    final toggle = find.byKey(const Key('multi_target_toggle'));
    await tester.ensureVisible(toggle);
    expect(toggle, findsOneWidget);
    expect(find.text('Comparar em várias IAs'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.byKey(const Key('target_ai_chatgpt')), findsOneWidget);

    tester.widget<SwitchListTile>(toggle).onChanged!(true);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text('2 de 4 IAs selecionadas'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('compare_target_chatgpt')))
            .selected,
        isTrue);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('compare_target_claude')))
            .selected,
        isTrue);
    expect(find.byKey(const Key('multi_target_deterministic_message')),
        findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('optimize_with_ai')))
            .onChanged,
        isNull);
    for (final key in ['gemini', 'midjourney']) {
      await tester
          .tap(find.byKey(Key('compare_target_$key'), skipOffstage: false));
      await tester.pump();
    }
    expect(find.text('4 de 4 IAs selecionadas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('compare_target_image_generator'),
        skipOffstage: false));
    await tester.pump();
    expect(find.text('Escolha no máximo 4 IAs para comparar.'), findsOneWidget);
    expect(find.text('4 de 4 IAs selecionadas'), findsOneWidget);

    tester.widget<SwitchListTile>(toggle).onChanged!(false);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.byKey(const Key('target_ai_chatgpt')), findsOneWidget);
    expect(find.byKey(const Key('compare_target_chatgpt')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controle Multi-Target aparece no mobile sem overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, FakePromptRepository());
    final toggle = find.byKey(const Key('multi_target_toggle'));
    await tester.ensureVisible(toggle);
    expect(find.text('Comparar em várias IAs'), findsOneWidget);
    tester.widget<SwitchListTile>(toggle).onChanged!(true);
    await tester.pumpAndSettle();
    expect(find.text('2 de 4 IAs selecionadas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fluxo single-target permanece funcional', (tester) async {
    final repository = FakePromptRepository();
    await pumpApp(tester, repository);
    final target = find.byKey(const Key('target_ai_gemini'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha completa');
    tester
        .widget<FilledButton>(find.byKey(const Key('prompt_submit')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(repository.compareCalls, 0);
    expect(repository.generatedInput?.targetAi, TargetAI.gemini);
    expect(repository.generatedInput?.comparisonTargetAis, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compara sem salvar e persiste somente a versao escolhida',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakePromptRepository();
    await pumpApp(tester, repository);
    final toggle = find.byKey(const Key('multi_target_toggle'));
    await tester.ensureVisible(toggle);
    tester.widget<SwitchListTile>(toggle).onChanged!(true);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha completa');
    tester
        .widget<FilledButton>(find.byKey(const Key('prompt_submit')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(repository.compareCalls, 1);
    expect(repository.records, isEmpty);
    expect(repository.generatedInput, isNull);
    expect(repository.comparedInput?.comparisonTargetAis,
        [TargetAI.chatgpt, TargetAI.claude]);
    expect(find.byKey(const Key('comparison_card_chatgpt')), findsOneWidget);
    expect(find.byKey(const Key('comparison_card_claude')), findsOneWidget);
    expect(find.byKey(const Key('comparison_score_chatgpt')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('copy_comparison_chatgpt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_comparison_chatgpt')));
    await tester.pumpAndSettle();
    expect(repository.records, hasLength(1));
    expect(repository.generatedInput?.targetAi, TargetAI.chatgpt);
    expect(repository.generatedInput?.optimizeWithAi, isFalse);
    expect(find.byKey(const Key('open_comparison_chatgpt')), findsOneWidget);
  });
}
