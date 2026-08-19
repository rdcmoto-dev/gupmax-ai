import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/account/account_providers.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_create_page.dart';
import 'package:gupmax_ai/features/templates/presentation/template_list_page.dart';
import 'package:gupmax_ai/features/templates/template_providers.dart';
import 'package:gupmax_ai/features/templates/domain/prompt_template.dart';

import '../../support/fake_account_repository.dart';
import '../../support/fake_interview_repository.dart';
import '../../support/fake_prompt_repository.dart';
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
    await tester.tap(submit);
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
