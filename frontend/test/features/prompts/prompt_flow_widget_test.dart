import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/app/app.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_prompt_repository.dart';

void main() {
  Future<void> pumpApp(
      WidgetTester tester, FakePromptRepository prompts) async {
    final auth = AuthController(
      repository: FakeAuthRepository(),
      expiryBus: SessionExpiryBus(),
      restoreOnCreate: false,
    );
    await auth.login(email: 'teste@example.com', password: 'valid-password');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          promptRepositoryProvider.overrideWithValue(prompts),
        ],
        child: const GupmaxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreate(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('create_prompt_button')));
    await tester.pumpAndSettle();
  }

  Future<void> submitPrompt(WidgetTester tester) async {
    final button = find.byKey(const Key('prompt_submit'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
  }

  testWidgets('valida formulário antes de criar', (tester) async {
    final repository = FakePromptRepository();
    await pumpApp(tester, repository);
    await openCreate(tester);
    await submitPrompt(tester);
    await tester.pump();
    expect(find.text('Use pelo menos 3 caracteres.'), findsOneWidget);
    expect(repository.generatedInput, isNull);
  });

  testWidgets('cria, mostra loading, resultado e copia prompt', (tester) async {
    final repository = FakePromptRepository()..generateCompleter = Completer();
    await pumpApp(tester, repository);
    await openCreate(tester);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha');
    await tester.tap(find.byKey(const Key('optimize_with_ai')));
    await submitPrompt(tester);
    await tester.pump();
    expect(find.text('Gerando...'), findsOneWidget);
    expect(repository.generatedInput?.optimizeWithAi, isTrue);
    repository.generateCompleter!.complete(repository.sample());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('generated_prompt')), findsOneWidget);
    final copyButton = find.byKey(const Key('copy_prompt'));
    await tester.ensureVisible(copyButton);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(copyButton).onPressed, isNotNull);
  });

  testWidgets('apresenta erro amigável do backend', (tester) async {
    final repository = FakePromptRepository()
      ..error = const AppException('Limite de uso atingido.');
    await pumpApp(tester, repository);
    await openCreate(tester);
    await tester.enterText(
        find.byKey(const Key('prompt_input')), 'Crie uma campanha');
    await submitPrompt(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt_error')), findsOneWidget);
    expect(find.text('Limite de uso atingido.'), findsOneWidget);
  });

  testWidgets('histórico vazio exibe estado dedicado', (tester) async {
    await pumpApp(tester, FakePromptRepository());
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty_prompts')), findsOneWidget);
  });

  testWidgets('histórico preenchido abre detalhes e pagina', (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample())
      ..totalOverride = 25;
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt_prompt-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('next_page')));
    await tester.pumpAndSettle();
    expect(repository.requestedOffset, 20);
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('generated_prompt')), findsOneWidget);
  });

  testWidgets('edita e exclui prompt com confirmação', (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample());
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('my_prompts_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prompt_prompt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_prompt')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('edit_title')), 'Título atualizado');
    await tester.tap(find.byKey(const Key('save_prompt')));
    await tester.pumpAndSettle();
    expect(find.text('Título atualizado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete_prompt')));
    await tester.pumpAndSettle();
    expect(find.text('Esta ação não pode ser desfeita.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_delete')));
    await tester.pumpAndSettle();
    expect(repository.deleted, isTrue);
    expect(find.byKey(const Key('empty_prompts')), findsOneWidget);
  });
}
