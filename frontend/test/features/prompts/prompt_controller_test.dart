import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_controller.dart';

import '../../support/fake_prompt_repository.dart';

void main() {
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
}
