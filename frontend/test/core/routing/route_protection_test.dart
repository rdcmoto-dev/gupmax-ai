import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/core/routing/app_router.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  for (final path in ['/prompts', '/prompts/new', '/prompts/prompt-id']) {
    testWidgets('não autenticado é redirecionado de $path para login',
        (tester) async {
      final repository = FakeAuthRepository()
        ..error = const AppException('Sem sessão', statusCode: 401);
      final bus = SessionExpiryBus();
      final controller = AuthController(
          repository: repository, expiryBus: bus, restoreOnCreate: false);
      await controller.restoreSession();
      final router = createAppRouter(controller);
      router.go(path);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith((ref) => controller)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bem-vindo ao GUPMAX AI'), findsOneWidget);
      router.dispose();
      bus.dispose();
    });
  }

  testWidgets('não autenticado é redirecionado de dashboard para login',
      (tester) async {
    final repository = FakeAuthRepository()
      ..error = const AppException('Sem sessão', statusCode: 401);
    final bus = SessionExpiryBus();
    final controller = AuthController(
        repository: repository, expiryBus: bus, restoreOnCreate: false);
    await controller.restoreSession();
    final router = createAppRouter(controller);
    router.go('/dashboard');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((ref) => controller)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bem-vindo ao GUPMAX AI'), findsOneWidget);
    router.dispose();
    bus.dispose();
  });

  testWidgets('autenticado não permanece em login', (tester) async {
    final repository = FakeAuthRepository();
    final bus = SessionExpiryBus();
    final controller = AuthController(
        repository: repository, expiryBus: bus, restoreOnCreate: false);
    await controller.login(
        email: 'teste@example.com', password: 'valid-password');
    final router = createAppRouter(controller);
    router.go('/login');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((ref) => controller)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Olá, Usuário Teste'), findsOneWidget);
    router.dispose();
    bus.dispose();
  });
}
