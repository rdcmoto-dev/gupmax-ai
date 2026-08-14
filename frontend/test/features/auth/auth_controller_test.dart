import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late SessionExpiryBus expiryBus;
  late AuthController controller;

  setUp(() {
    repository = FakeAuthRepository();
    expiryBus = SessionExpiryBus();
    controller = AuthController(
        repository: repository, expiryBus: expiryBus, restoreOnCreate: false);
  });

  tearDown(() {
    controller.dispose();
    expiryBus.dispose();
  });

  test('login válido autentica com usuário real retornado pelo repositório',
      () async {
    final success = await controller.login(
        email: 'teste@example.com', password: 'valid-password');
    expect(success, isTrue);
    expect(controller.status, AuthStatus.authenticated);
    expect(controller.user?.email, 'teste@example.com');
    expect(repository.loginCalls, 1);
  });

  test('login inválido mantém sessão local não autenticada', () async {
    repository.error =
        const AppException('E-mail ou senha inválidos.', statusCode: 401);
    final success =
        await controller.login(email: 'teste@example.com', password: 'invalid');
    expect(success, isFalse);
    expect(controller.isAuthenticated, isFalse);
    expect(controller.errorMessage, 'E-mail ou senha inválidos.');
  });

  test('logout limpa estado autenticado', () async {
    await controller.login(
        email: 'teste@example.com', password: 'valid-password');
    await controller.logout();
    expect(controller.status, AuthStatus.unauthenticated);
    expect(controller.user, isNull);
    expect(repository.logoutCalls, 1);
  });

  test('restauração de sessão recupera usuário', () async {
    await controller.restoreSession();
    expect(controller.status, AuthStatus.authenticated);
    expect(controller.user, FakeAuthRepository.user);
    expect(repository.restoreCalls, 1);
  });

  test('restauração falha encerra sessão local', () async {
    repository.error =
        const AppException('Sessão não encontrada.', statusCode: 401);
    await controller.restoreSession();
    expect(controller.status, AuthStatus.unauthenticated);
    expect(controller.user, isNull);
  });

  test('expiração global causada por refresh falho encerra sessão', () async {
    await controller.login(
        email: 'teste@example.com', password: 'valid-password');
    expiryBus.expire();
    expect(controller.status, AuthStatus.unauthenticated);
  });
}
