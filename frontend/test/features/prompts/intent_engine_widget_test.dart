import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/account/account_providers.dart';
import 'package:gupmax_ai/features/intent_engine/domain/intent_analysis.dart';
import 'package:gupmax_ai/features/intent_engine/intent_providers.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_create_page.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';
import 'package:gupmax_ai/features/templates/template_providers.dart';

import '../../support/fake_account_repository.dart';
import '../../support/fake_intent_repository.dart';
import '../../support/fake_interview_repository.dart';
import '../../support/fake_project_repository.dart';
import '../../support/fake_prompt_repository.dart';
import '../../support/fake_template_repository.dart';

void main() {
  testWidgets('analisa ideia sem repetir entidade e preserva categoria manual',
      (tester) async {
    final intents = FakeIntentRepository();
    final prompts = FakePromptRepository()..generateCompleter = Completer();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        intentRepositoryProvider.overrideWithValue(intents),
        promptRepositoryProvider.overrideWithValue(prompts),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        projectRepositoryProvider.overrideWithValue(FakeProjectRepository()),
        interviewRepositoryProvider
            .overrideWithValue(FakeInterviewRepository()),
        templateRepositoryProvider.overrideWithValue(FakeTemplateRepository()),
      ],
      child: const MaterialApp(home: PromptCreatePage()),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('prompt_input')),
        'Quero criar um anúncio para vender tênis feminino no Instagram.');
    await tester.ensureVisible(find.byKey(const Key('analyze_intent')));
    await tester.tap(find.byKey(const Key('analyze_intent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('intent_analysis')), findsOneWidget);
    expect(find.byKey(const Key('intent_entity_platform')), findsOneWidget);
    expect(find.byKey(const Key('intent_question_platform')), findsNothing);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('category_marketing')))
            .selected,
        isTrue);

    await tester.ensureVisible(find.byKey(const Key('category_programacao')));
    await tester.tap(find.byKey(const Key('category_programacao')));
    intents.result = const IntentAnalysis(
      summary: 'Vídeo sugerido',
      intent: 'video_creation',
      suggestedCategory: PromptCategory.video,
      detectedEntities: {},
      missingInformation: [],
      suggestedQuestions: [],
      confidence: 0.8,
    );
    await tester.ensureVisible(find.byKey(const Key('analyze_intent')));
    await tester.tap(find.byKey(const Key('analyze_intent')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('category_programacao')))
            .selected,
        isTrue);

    final submit = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(submit);
    tester.widget<FilledButton>(submit).onPressed!();
    await tester.pump();
    expect(prompts.generatedInput?.mode, PromptMode.basic);
    expect(prompts.generatedInput?.category, PromptCategory.programming);
    expect(prompts.generatedInput?.targetAi, TargetAI.generic);
    expect(intents.calls, 2);
    expect(tester.takeException(), isNull);
  });
}
