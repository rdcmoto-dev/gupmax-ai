import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/app/app.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/core/routing/app_router.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/commerce/commerce_providers.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_commerce_repository.dart';

void main() {
  for (final path in [
    '/prompts',
    '/prompts/new',
    '/prompts/prompt-id',
    '/usage',
    '/credits',
    '/payments/success',
    '/payments/cancel',
    '/payments',
    '/payments/payment-id',
    '/account',
  ]) {
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

  for (final path in ['/payments/cancel', '/payments/success']) {
    testWidgets(
        'retorno autenticado preserva $path durante restauração da sessão',
        (tester) async {
      final repository = FakeAuthRepository();
      final bus = SessionExpiryBus();
      final controller = AuthController(
        repository: repository,
        expiryBus: bus,
        restoreOnCreate: false,
      );
      final router = createAppRouter(controller, initialLocation: path);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((ref) => controller),
            commerceRepositoryProvider
                .overrideWithValue(FakeCommerceRepository()),
            checkoutNavigationProvider
                .overrideWithValue(FakeCheckoutNavigation()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['redirect'],
        path,
      );

      await controller.restoreSession();
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, path);
      expect(find.text('Status do pagamento'), findsOneWidget);
      expect(find.text('Olá, Usuário Teste'), findsNothing);
      router.dispose();
      bus.dispose();
    });

    testWidgets('boot completo preserva o deep link Web $path', (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = path;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final bus = SessionExpiryBus();
      final controller = AuthController(
        repository: FakeAuthRepository(),
        expiryBus: bus,
        restoreOnCreate: false,
      );
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith((ref) => controller),
        commerceRepositoryProvider.overrideWithValue(FakeCommerceRepository()),
        checkoutNavigationProvider.overrideWithValue(FakeCheckoutNavigation()),
      ]);
      addTearDown(container.dispose);
      addTearDown(bus.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const GupmaxApp(),
        ),
      );
      await tester.pump();
      final routerBeforeRestore = container.read(appRouterProvider);

      await controller.restoreSession();
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider), same(routerBeforeRestore));
      expect(
        routerBeforeRestore.routeInformationProvider.value.uri.path,
        path,
      );
      expect(find.text('Status do pagamento'), findsOneWidget);
      expect(find.text('Olá, Usuário Teste'), findsNothing);
    });
  }

  testWidgets('login preserva destino original do retorno de pagamento',
      (tester) async {
    final repository = FakeAuthRepository()
      ..error = const AppException('Sem sessão', statusCode: 401);
    final bus = SessionExpiryBus();
    final controller = AuthController(
      repository: repository,
      expiryBus: bus,
      restoreOnCreate: false,
    );
    await controller.restoreSession();
    final router =
        createAppRouter(controller, initialLocation: '/payments/cancel');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
          commerceRepositoryProvider
              .overrideWithValue(FakeCommerceRepository()),
          checkoutNavigationProvider
              .overrideWithValue(FakeCheckoutNavigation()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['redirect'],
      '/payments/cancel',
    );

    repository.error = null;
    await controller.login(
      email: 'teste@example.com',
      password: 'valid-password',
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/payments/cancel',
    );
    router.dispose();
    bus.dispose();
  });
}
