import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/core/routing/app_router.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/interviews/domain/interview_models.dart';
import 'package:gupmax_ai/features/interviews/interview_providers.dart';
import 'package:gupmax_ai/features/interviews/presentation/interview_page.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';

import '../../support/fake_interview_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_prompt_repository.dart';

void main() {
  Future<void> pumpInterview(
    WidgetTester tester,
    FakeInterviewRepository interviews, {
    FakePromptRepository? prompts,
    Size size = const Size(800, 900),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          interviewRepositoryProvider.overrideWithValue(interviews),
          promptRepositoryProvider
              .overrideWithValue(prompts ?? FakePromptRepository()),
        ],
        child: const MaterialApp(
          home: InterviewPage(interviewId: 'interview-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final typeCases = <InterviewQuestionType, Key>{
    InterviewQuestionType.text: const Key('answer_text'),
    InterviewQuestionType.multiline: const Key('answer_multiline'),
    InterviewQuestionType.singleChoice: const Key('choice_Opção A'),
    InterviewQuestionType.multiChoice: const Key('choice_Opção A'),
    InterviewQuestionType.boolean: const Key('answer_boolean'),
  };

  for (final entry in typeCases.entries) {
    testWidgets('renderiza pergunta ${entry.key.name} pelo contrato',
        (tester) async {
      final repository = FakeInterviewRepository();
      repository.current = repository.sample(questions: [
        InterviewQuestion(
          key: 'dynamic_question',
          text: 'Pergunta dinâmica',
          type: entry.key,
          required: true,
          options: entry.key == InterviewQuestionType.singleChoice ||
                  entry.key == InterviewQuestionType.multiChoice
              ? const ['Opção A', 'Opção B']
              : const [],
        ),
      ]);
      await pumpInterview(tester, repository);
      expect(find.text('Pergunta dinâmica'), findsOneWidget);
      expect(find.byKey(entry.value), findsOneWidget);
    });
  }

  testWidgets('envia resposta e usa o progresso retornado pelo backend',
      (tester) async {
    final repository = FakeInterviewRepository();
    repository.current = repository.sample(questions: const [
      InterviewQuestion(
        key: 'channel',
        text: 'Canal?',
        type: InterviewQuestionType.singleChoice,
        required: true,
        options: ['Site', 'Rede social'],
      ),
      InterviewQuestion(
        key: 'audience',
        text: 'Público?',
        type: InterviewQuestionType.multiline,
        required: true,
        options: [],
      ),
    ]);
    await pumpInterview(tester, repository);
    await tester.tap(find.byKey(const Key('choice_Site')));
    await tester.tap(find.byKey(const Key('interview_continue')));
    await tester.pumpAndSettle();
    expect(repository.answerCalls, 1);
    expect(find.text('1 de 2 respondidas'), findsOneWidget);
    expect(find.byKey(const Key('answer_multiline')), findsOneWidget);
  });

  testWidgets('permite pular opcional sem enviar resposta artificial',
      (tester) async {
    final repository = FakeInterviewRepository();
    repository.current = repository.sample(questions: const [
      InterviewQuestion(
        key: 'optional_context',
        text: 'Contexto opcional?',
        type: InterviewQuestionType.text,
        required: false,
        options: [],
      ),
      InterviewQuestion(
        key: 'required_goal',
        text: 'Objetivo obrigatório?',
        type: InterviewQuestionType.text,
        required: true,
        options: [],
      ),
    ]);
    await pumpInterview(tester, repository);
    await tester.tap(find.byKey(const Key('interview_skip')));
    await tester.pump();
    expect(repository.answerCalls, 0);
    expect(find.text('Objetivo obrigatório?'), findsOneWidget);
    expect(find.text('0 de 2 respondidas'), findsOneWidget);
  });

  testWidgets('erro de carregamento oferece retry', (tester) async {
    final repository = FakeInterviewRepository()
      ..error = const AppException('Falha temporária.');
    await pumpInterview(tester, repository);
    expect(find.text('Falha temporária.'), findsOneWidget);
    repository.error = null;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(repository.getCalls, 2);
    expect(find.text('Vamos melhorar seu prompt'), findsOneWidget);
  });

  testWidgets('ready conclui e encaminha payload ao gerador existente',
      (tester) async {
    final interviews = FakeInterviewRepository();
    interviews.current = interviews.sample(status: InterviewStatus.ready);
    final prompts = FakePromptRepository();
    prompts.error = const AppException('Geração simulada.');
    await pumpInterview(tester, interviews, prompts: prompts);
    expect(find.byKey(const Key('interview_ready')), findsOneWidget);
    await tester.tap(find.byKey(const Key('interview_generate')));
    await tester.pumpAndSettle();
    expect(interviews.completeCalls, 1);
    expect(prompts.generatedInput?.mode, PromptMode.pro);
  });

  testWidgets('bloqueia complete concorrente por clique duplo', (tester) async {
    final repository = FakeInterviewRepository();
    repository.current = repository.sample(status: InterviewStatus.ready);
    final completer = Completer<InterviewCompleteResult>();
    repository.completeCompleter = completer;
    await pumpInterview(
      tester,
      repository,
      prompts: FakePromptRepository()
        ..error = const AppException('Geração simulada.'),
    );
    final button = tester
        .widget<FilledButton>(find.byKey(const Key('interview_generate')));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(repository.completeCalls, 1);
    final input = const PromptGenerateInput(
      input: 'Crie uma campanha',
      category: PromptCategory.marketing,
      mode: PromptMode.pro,
    );
    final completed = repository.sample(
      status: InterviewStatus.completed,
      structuredPrompt: input,
    );
    completer.complete(
        InterviewCompleteResult(interview: completed, promptInput: input));
    await tester.pumpAndSettle();
  });

  testWidgets('completed reutiliza structured prompt sem novo complete',
      (tester) async {
    const input = PromptGenerateInput(
      input: 'Crie uma campanha',
      category: PromptCategory.marketing,
      mode: PromptMode.pro,
    );
    final interviews = FakeInterviewRepository();
    interviews.current = interviews.sample(
      status: InterviewStatus.completed,
      structuredPrompt: input,
    );
    final prompts = FakePromptRepository();
    prompts.error = const AppException('Geração simulada.');
    await pumpInterview(tester, interviews, prompts: prompts);
    expect(find.byKey(const Key('interview_completed')), findsOneWidget);
    await tester.tap(find.byKey(const Key('interview_generate')));
    await tester.pumpAndSettle();
    expect(interviews.completeCalls, 0);
    expect(prompts.generatedInput?.input, input.input);
  });

  testWidgets('expired orienta iniciar nova criação', (tester) async {
    final repository = FakeInterviewRepository()
      ..error = const AppException('Esta entrevista expirou.', statusCode: 409);
    await pumpInterview(tester, repository);
    expect(find.byKey(const Key('interview_expired')), findsOneWidget);
    expect(find.text('Criar novo prompt'), findsOneWidget);
  });

  testWidgets('deep link autenticado consulta entrevista pelo id',
      (tester) async {
    final bus = SessionExpiryBus();
    final auth = AuthController(
      repository: FakeAuthRepository(),
      expiryBus: bus,
      restoreOnCreate: false,
    );
    await auth.login(email: 'teste@example.com', password: 'valid-password');
    final interviews = FakeInterviewRepository();
    final router = createAppRouter(
      auth,
      initialLocation: '/interviews/interview-1',
    );
    addTearDown(router.dispose);
    addTearDown(bus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          interviewRepositoryProvider.overrideWithValue(interviews),
          promptRepositoryProvider.overrideWithValue(FakePromptRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path,
        '/interviews/interview-1');
    expect(interviews.getCalls, 1);
    expect(find.text('Vamos melhorar seu prompt'), findsOneWidget);
  });

  for (final width in [320.0, 768.0, 1280.0]) {
    testWidgets('entrevista não apresenta overflow em ${width.toInt()} px',
        (tester) async {
      await pumpInterview(
        tester,
        FakeInterviewRepository(),
        size: Size(width, 900),
      );
      expect(find.text('Vamos melhorar seu prompt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
