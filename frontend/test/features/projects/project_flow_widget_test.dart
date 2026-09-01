import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/presentation/project_detail_page.dart';
import 'package:gupmax_ai/features/projects/presentation/project_list_page.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/prompt_chains/prompt_chain_providers.dart';
import 'package:gupmax_ai/features/account/account_providers.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_create_page.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';

import '../../support/fake_account_repository.dart';
import '../../support/fake_interview_repository.dart';
import '../../support/fake_prompt_repository.dart';
import '../../support/fake_project_repository.dart';
import '../../support/fake_prompt_chain_repository.dart';

void main() {
  testWidgets('lista mostra loading e estado vazio', (tester) async {
    final repository = FakeProjectRepository()
      ..listCompleter = Completer<ProjectPageData>();
    await _pumpList(tester, repository);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.listCompleter!.complete(const ProjectPageData([], 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects_empty')), findsOneWidget);
  });

  testWidgets('cria edita arquiva reativa e exclui com confirmação',
      (tester) async {
    final repository = FakeProjectRepository()..items = [projectSample()];
    await _pumpList(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Pizzaria Donatello'), findsOneWidget);
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project_name')), 'Donatello');
    await tester.tap(find.byKey(const Key('save_project')));
    await tester.pumpAndSettle();
    expect(find.text('Donatello'), findsOneWidget);
    await tester.tap(find.text('Arquivar'));
    await tester.pumpAndSettle();
    expect(find.text('Reativar'), findsOneWidget);
    await tester.tap(find.text('Reativar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove_project_project-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_project_remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects_empty')), findsOneWidget);
  });

  testWidgets('detalhe exibe contexto listas e criação associada',
      (tester) async {
    final repository = FakeProjectRepository()..items = [projectSample()];
    await tester.pumpWidget(ProviderScope(
      overrides: [projectRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: ProjectDetailPage(projectId: 'project-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pizzaria com delivery'), findsOneWidget);
    expect(find.text('Prompts do projeto'), findsOneWidget);
    expect(find.text('Templates do projeto'), findsOneWidget);
    expect(find.byKey(const Key('create_prompt_in_project')), findsOneWidget);
  });

  testWidgets('grid funciona em mobile e desktop sem overflow', (tester) async {
    final repository = FakeProjectRepository()..items = [projectSample()];
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

  testWidgets('criar prompt no projeto envia associação sem gerar sozinho',
      (tester) async {
    final projects = FakeProjectRepository()..items = [projectSample()];
    final prompts = FakePromptRepository()..generateCompleter = Completer();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(projects),
        promptRepositoryProvider.overrideWithValue(prompts),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        interviewRepositoryProvider
            .overrideWithValue(FakeInterviewRepository()),
      ],
      child: const MaterialApp(home: PromptCreatePage(projectId: 'project-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Projeto: Pizzaria Donatello'), findsOneWidget);
    expect(prompts.generatedInput, isNull);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha');
    final submit = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(prompts.generatedInput!.projectId, 'project-1');
    expect(prompts.generatedInput!.optimizeWithAi, isFalse);
  });
}

Future<void> _pumpList(
    WidgetTester tester, FakeProjectRepository repository) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      projectRepositoryProvider.overrideWithValue(repository),
      promptChainRepositoryProvider
          .overrideWithValue(FakePromptChainRepository()),
    ],
    child: const MaterialApp(home: ProjectListPage()),
  ));
}
