import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/project_review.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';

import '../../support/fake_project_repository.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';

void main() {
  test('conclusão pode ser criada editada removida sem afetar memória', () {
    final created = ProjectReview.merge(
      context: 'Público: Restaurantes',
      conclusion: 'Entrega aprovada.',
      isClosed: false,
    );
    expect(created, contains('Público: Restaurantes'));
    expect(ProjectReview.parse(created).conclusion, 'Entrega aprovada.');

    final edited = ProjectReview.merge(
      context: created,
      conclusion: 'Entrega revisada.',
      isClosed: false,
    );
    expect(ProjectReview.parse(edited).conclusion, 'Entrega revisada.');

    final removed = ProjectReview.merge(
      context: edited,
      conclusion: '',
      isClosed: false,
    );
    expect(ProjectReview.parse(removed).conclusion, isNull);
    expect(removed, 'Público: Restaurantes');
  });

  test('encerrar e reabrir preserva conclusão e demais dados', () {
    const source =
        'Objetivo: Lançar campanha\nCritério de sucesso: [x] Aprovada\nMarco: Publicar';
    final closed = ProjectReview.merge(
      context: source,
      conclusion: 'Finalizado pelo cliente.',
      isClosed: true,
    );
    expect(ProjectReview.parse(closed).isClosed, isTrue);
    expect(closed, contains('Critério de sucesso: [x] Aprovada'));
    expect(closed, contains('Marco: Publicar'));

    final reopened = ProjectReview.merge(
      context: closed,
      conclusion: ProjectReview.parse(closed).conclusion,
      isClosed: false,
    );
    expect(ProjectReview.parse(reopened).isClosed, isFalse);
    expect(
        ProjectReview.parse(reopened).conclusion, 'Finalizado pelo cliente.');
  });

  test('resumo usa somente dados reais carregados', () {
    final project = projectSample(
      context:
          'Objetivo: Publicar\nCritério de sucesso: [x] Aprovado\nCritério de sucesso: Entregue\nMarco: [x] Planejar',
      promptCount: 2,
    );
    final steps = [
      _step(1, PromptChainStepStatus.completed),
      _step(2, PromptChainStepStatus.pending),
    ];
    final chain = PromptChainRecord(
      id: 'chain-1',
      name: 'Fluxo',
      status: PromptChainStatus.active,
      projectId: project.id,
      stepCount: 2,
      completedStepCount: 1,
      steps: steps,
    );
    final summary = projectReviewSummaryFor(project: project, chain: chain);
    expect(summary.objective, 'Publicar');
    expect(summary.criteriaCount, 2);
    expect(summary.confirmedCriteriaCount, 1);
    expect(summary.milestoneCount, 1);
    expect(summary.confirmedMilestoneCount, 1);
    expect(summary.completedSteps, 1);
    expect(summary.totalSteps, 2);
    expect(summary.promptCount, 2);
    expect(summary.hasPendingItems, isTrue);
  });

  test('limites de conclusão, entradas e contexto são locais e determinísticos',
      () {
    expect(
      () => ProjectReview.merge(
        context: null,
        conclusion: 'a' * 1001,
        isClosed: false,
      ),
      throwsFormatException,
    );
    final twenty =
        List.generate(20, (index) => 'Campo $index: valor').join('\n');
    expect(
      () => ProjectReview.merge(
        context: twenty,
        conclusion: 'final',
        isClosed: false,
      ),
      throwsFormatException,
    );
  });
}

PromptChainStep _step(int position, PromptChainStepStatus status) =>
    PromptChainStep(
      id: 'step-$position',
      chainId: 'chain-1',
      position: position,
      title: 'Etapa $position',
      baseInput: 'Executar',
      mode: PromptMode.basic,
      category: PromptCategory.marketing,
      targetAi: TargetAI.chatgpt,
      executionStatus: status,
    );
