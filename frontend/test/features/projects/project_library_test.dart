import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/presentation/project_library_page.dart';
import 'package:gupmax_ai/features/projects/project_library.dart';
import 'package:gupmax_ai/features/projects/project_providers.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';
import 'package:gupmax_ai/features/prompt_chains/prompt_chain_providers.dart';

import '../../support/fake_project_repository.dart';
import '../../support/fake_prompt_chain_repository.dart';

void main() {
  ProjectLibraryData sample() => ProjectLibraryData(
      projectId: 'project-1',
      prompts: [
        ProjectLibraryPrompt(
            id: 'prompt-2',
            title: 'Campanha Instagram',
            category: PromptCategory.marketing,
            mode: PromptMode.basic,
            targetAi: TargetAI.chatgpt,
            versionCount: 3,
            updatedAt: DateTime.utc(2026, 9, 2))
      ],
      promptTotal: 1,
      offset: 0,
      limit: 20,
      chains: [
        ProjectLibraryChain(
            id: 'chain-1',
            name: 'Lançamento',
            completedCount: 1,
            stepCount: 2,
            currentStepId: 'step-2',
            steps: const [
              ProjectLibraryStep(
                  id: 'step-1',
                  position: 1,
                  title: 'Estratégia',
                  status: 'completed',
                  hasResult: true,
                  resultPreview: 'Estratégia aprovada.'),
              ProjectLibraryStep(
                  id: 'step-2',
                  position: 2,
                  title: 'Campanha',
                  status: 'in_progress',
                  hasResult: false),
            ])
      ],
      completedStepCount: 1,
      activity: [
        ProjectActivity('Etapa concluída: Estratégia', DateTime.utc(2026, 9, 2))
      ],
      lastActivityAt: DateTime.utc(2026, 9, 2));

  Future<void> pump(WidgetTester tester, Size size,
      {ProjectLibraryData? data}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeProjectRepository()..libraryData = data ?? sample();
    final chains = FakePromptChainRepository()
      ..items = [
        const PromptChainRecord(
          id: 'chain-1',
          name: 'Lançamento',
          status: PromptChainStatus.active,
          stepCount: 2,
          steps: [
            PromptChainStep(
                id: 'step-1',
                chainId: 'chain-1',
                position: 1,
                title: 'Estratégia',
                baseInput: 'Crie estratégia',
                mode: PromptMode.basic,
                category: PromptCategory.marketing,
                targetAi: TargetAI.chatgpt,
                executionStatus: PromptChainStepStatus.completed,
                result: 'Estratégia aprovada.'),
          ],
        ),
      ];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          projectRepositoryProvider.overrideWithValue(repository),
          promptChainRepositoryProvider.overrideWithValue(chains),
        ],
        child: const MaterialApp(
            home: ProjectLibraryPage(projectId: 'project-1'))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'biblioteca mostra prompts agrupados, etapas e resultado sem alterar estado',
      (tester) async {
    await pump(tester, const Size(1280, 900));
    expect(find.text('Campanha Instagram'), findsOneWidget);
    expect(find.textContaining('3 versões'), findsOneWidget);
    expect(find.text('1 prompts'), findsOneWidget);
    expect(find.text('1 etapas concluídas'), findsOneWidget);
    expect(find.text('Etapa atual'), findsOneWidget);
    await tester.tap(find.text('Ver resultado'));
    await tester.pumpAndSettle();
    expect(find.text('Estratégia aprovada.'), findsOneWidget);
  });

  testWidgets('estado vazio é claro e mobile não apresenta overflow',
      (tester) async {
    final empty = ProjectLibraryData(
        projectId: 'project-1',
        prompts: const [],
        promptTotal: 0,
        offset: 0,
        limit: 20,
        chains: const [],
        completedStepCount: 0,
        activity: const [],
        lastActivityAt: DateTime.utc(2026, 9, 2));
    await pump(tester, const Size(390, 844), data: empty);
    expect(
        find.text('Nenhum prompt foi criado neste projeto.'), findsOneWidget);
    expect(find.text('Este projeto ainda não possui um fluxo associado.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
