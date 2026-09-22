import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/app/app.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/auth/presentation/register_page.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  Future<FakeAuthRepository> pumpRegistration(WidgetTester tester) async {
    final repository = FakeAuthRepository();
    final bus = SessionExpiryBus();
    final controller = AuthController(
        repository: repository, expiryBus: bus, restoreOnCreate: false);
    addTearDown(bus.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: RegisterPage()),
    ));
    await tester.enterText(
        find.byKey(const Key('register_name')), 'Pilot User');
    await tester.enterText(
        find.byKey(const Key('register_email')), 'invited@example.com');
    await tester.enterText(
        find.byKey(const Key('register_password')), 'ValidPassword123!');
    return repository;
  }

  testWidgets('cadastro exige convite antes de chamar a API', (tester) async {
    final repository = await pumpRegistration(tester);
    await tester.ensureVisible(find.byKey(const Key('register_submit')));
    await tester.tap(find.byKey(const Key('register_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Informe o convite recebido do administrador.'),
        findsOneWidget);
    expect(repository.registerCalls, 0);
  });

  testWidgets('cadastro envia convite e exibe recusa segura', (tester) async {
    final repository = await pumpRegistration(tester);
    repository.error = const AppException(
        'Convite inválido, vencido ou já utilizado. Confira o e-mail convidado ou solicite um novo convite ao administrador.',
        statusCode: 403);
    await tester.enterText(find.byKey(const Key('register_invitation')),
        '  invitation-test-only  ');
    final field = tester
        .widget<TextFormField>(find.byKey(const Key('register_invitation')));
    final editable = find.descendant(
        of: find.byKey(const Key('register_invitation')),
        matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).obscureText, isTrue);
    expect(field.controller, isNotNull);
    await tester.ensureVisible(find.byKey(const Key('register_submit')));
    await tester.tap(find.byKey(const Key('register_submit')));
    await tester.pumpAndSettle();
    expect(repository.registeredInvitation, 'invitation-test-only');
    expect(repository.registerCalls, 1);
    expect(find.byKey(const Key('auth_error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('dashboard preserva navegação e logout em largura mobile',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeAuthRepository();
    await pumpApp(tester, repository);
    await tester.enterText(
        find.byKey(const Key('login_email')), 'teste@example.com');
    await tester.enterText(
        find.byKey(const Key('login_password')), 'valid-password');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_navigation_menu')), findsOneWidget);
    expect(find.byKey(const Key('logout_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
