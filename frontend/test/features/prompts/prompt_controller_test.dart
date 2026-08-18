import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/prompts/data/prompt_repository.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_controller.dart';

import '../../support/fake_prompt_repository.dart';

void main() {
  test('distingue erro do provider de validação do formulário', () {
    expect(promptGenerateErrorMessage(400), contains('provider/model'));
    expect(
        promptGenerateErrorMessage(400), isNot('Confira os dados informados.'));
    expect(promptGenerateErrorMessage(422), 'Confira os dados informados.');
    expect(promptEstimateErrorMessage(404),
        'Não foi possível calcular a estimativa.');
  });

  test('cria prompt determinístico e encaminha optimize_with_ai', () async {
    final repository = FakePromptRepository();
    final controller = PromptController(repository);
    final result = await controller.generate(const PromptGenerateInput(
      input: 'Crie uma campanha',
      mode: PromptMode.expert,
      optimizeWithAi: true,
    ));
    expect(result?.generatedPrompt, contains('OBJECTIVE'));
    expect(repository.generatedInput?.optimizeWithAi, isTrue);
    expect(repository.generatedInput?.mode, PromptMode.expert);
  });

  test('expõe erro amigável e encerra loading', () async {
    final repository = FakePromptRepository()
      ..error = const AppException('Créditos insuficientes.', statusCode: 402);
    final controller = PromptController(repository);
    expect(
        await controller
            .generate(const PromptGenerateInput(input: 'Entrada válida')),
        isNull);
    expect(controller.error, 'Créditos insuficientes.');
    expect(controller.isSubmitting, isFalse);
  });

  test('carrega paginação, detalhes, edita e exclui', () async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample());
    repository.totalOverride = 25;
    final controller = PromptController(repository);
    await controller.loadPage(newOffset: 20);
    expect(repository.requestedOffset, 20);
    expect(controller.total, 25);
    expect((await controller.load('prompt-1'))?.id, 'prompt-1');
    expect(
        await controller.update(
            'prompt-1', const PromptUpdateInput(title: 'Novo título')),
        isTrue);
    expect(controller.selected?.title, 'Novo título');
    expect(await controller.remove('prompt-1'), isTrue);
    expect(repository.deleted, isTrue);
  });

  test('sessão expirada durante operação é tratada', () async {
    final repository = FakePromptRepository()
      ..error = const AppException('Sua sessão expirou. Entre novamente.',
          statusCode: 401);
    final controller = PromptController(repository);
    await controller.loadPage();
    expect(controller.error, contains('sessão expirou'));
  });

  test('refina prompt e preserva histórico de versões', () async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample());
    final controller = PromptController(repository);
    final source = await controller.load('prompt-1');
    final refined = await controller.refine(
      source!,
      const PromptRefineInput(
          instruction: 'Deixe mais persuasivo e mantenha curto.'),
    );
    expect(refined?.versionNumber, 2);
    expect(refined?.parentPromptId, source.id);
    expect(repository.refinedInput?.optimizeWithAi, isFalse);
    expect(controller.versions.map((item) => item.versionNumber), [1, 2]);
  });

  test('mantém prompt antigo como versão 1 quando versions retorna 404',
      () async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample())
      ..versionsError =
          const AppException('Prompt não encontrado.', statusCode: 404);
    final controller = PromptController(repository);

    final prompt = await controller.load('prompt-1');

    expect(prompt?.id, 'prompt-1');
    expect(controller.selected?.id, 'prompt-1');
    expect(controller.versions, [prompt]);
    expect(controller.error, isNull);
  });

  test('não mantém prompt residual quando o detalhe atual retorna 404',
      () async {
    final repository = FakePromptRepository();
    final controller = PromptController(repository);
    await controller
        .generate(const PromptGenerateInput(input: 'Prompt antigo'));
    repository.getError =
        const AppException('Prompt não encontrado.', statusCode: 404);

    expect(await controller.load('outro-prompt'), isNull);
    expect(controller.selected, isNull);
    expect(controller.versions, isEmpty);
    expect(controller.error, 'Prompt não encontrado.');
  });

  test('estima refino com IA sem executar geração', () async {
    final repository = FakePromptRepository();
    final controller = PromptController(repository);
    final source = repository.sample();
    await controller.estimateRefinement(
      source,
      const PromptRefineInput(
          instruction: 'Deixe mais curto.', optimizeWithAi: true),
    );
    expect(controller.estimate?.estimatedCredits, 8);
    expect(repository.refinedInput, isNull);
  });
}
