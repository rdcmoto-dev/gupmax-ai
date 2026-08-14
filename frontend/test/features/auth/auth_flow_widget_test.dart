import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/app/app.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    FakeAuthRepository repository,
  ) async {
    final bus = SessionExpiryBus();
    final controller = AuthController(
        repository: repository, expiryBus: bus, restoreOnCreate: false);
    repository.error =
        const AppException('Sessão não encontrada.', statusCode: 401);
    await controller.restoreSession();
    repository.error = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((ref) => controller)],
        child: const GupmaxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'login válido navega ao dashboard com GET users/me representado pelo usuário',
      (tester) async {
    final repository = FakeAuthRepository();
    await pumpApp(tester, repository);
    await tester.enterText(
        find.byKey(const Key('login_email')), 'teste@example.com');
    await tester.enterText(
        find.byKey(const Key('login_password')), 'valid-password');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Olá, Usuário Teste'), findsOneWidget);
    expect(find.text('teste@example.com'), findsOneWidget);
    expect(repository.loginCalls, 1);
  });

  testWidgets('login inválido exibe erro amigável sem detalhes internos',
      (tester) async {
    final repository = FakeAuthRepository();
    await pumpApp(tester, repository);
    repository.error =
        const AppException('E-mail ou senha inválidos.', statusCode: 401);
    await tester.enterText(
        find.byKey(const Key('login_email')), 'teste@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'wrong');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth_error')), findsOneWidget);
    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
  });

  testWidgets('formulário bloqueia campos inválidos antes da API',
      (tester) async {
    final repository = FakeAuthRepository();
    await pumpApp(tester, repository);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();

    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(find.text('Informe sua senha.'), findsOneWidget);
    expect(repository.loginCalls, 0);
  });

  testWidgets('logout remove acesso ao dashboard e retorna ao login',
      (tester) async {
    final repository = FakeAuthRepository();
    await pumpApp(tester, repository);
    await tester.enterText(
        find.byKey(const Key('login_email')), 'teste@example.com');
    await tester.enterText(
        find.byKey(const Key('login_password')), 'valid-password');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();

    expect(find.text('Bem-vindo ao GUPMAX AI'), findsOneWidget);
    expect(repository.logoutCalls, 1);
  });
}
