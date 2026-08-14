import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/app/app.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';
import 'package:gupmax_ai/features/usage/usage_providers.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_usage_repository.dart';

void main() {
  Future<void> pumpApp(
      WidgetTester tester, FakeUsageRepository repository) async {
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
          usageRepositoryProvider.overrideWithValue(repository),
        ],
        child: const GupmaxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openUsage(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('my_usage_button')));
    await tester.pump();
  }

  testWidgets('mostra loading, saldo, plano, limites e estados vazios',
      (tester) async {
    final repository = FakeUsageRepository()..summaryCompleter = Completer();
    await pumpApp(tester, repository);
    await openUsage(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.summaryCompleter!.complete(repository.sampleSummary());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wallet_card')), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    expect(find.textContaining('2 de 100'), findsOneWidget);
    expect(find.byKey(const Key('empty_usage')), findsOneWidget);
    expect(find.byKey(const Key('empty_movements')), findsOneWidget);
  });

  testWidgets('exibe uso e ledger reais preservando sinal', (tester) async {
    final repository = FakeUsageRepository();
    repository.usageItems = [repository.sampleUsage()];
    repository.movementItems = [repository.sampleMovement()];
    await pumpApp(tester, repository);
    await openUsage(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('17 tokens'), findsOneWidget);
    expect(find.text('Uso de IA'), findsWidgets);
    expect(find.text('-3'), findsOneWidget);
    expect(find.text('Saldo 97'), findsOneWidget);
  });

  testWidgets('erro oferece retry e sessão expirada é amigável',
      (tester) async {
    final repository = FakeUsageRepository()
      ..error = const AppException('Sua sessão expirou. Entre novamente.',
          statusCode: 401);
    await pumpApp(tester, repository);
    await openUsage(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('usage_error')), findsOneWidget);
    expect(find.textContaining('sessão expirou'), findsOneWidget);
    repository.error = null;
    await tester.tap(find.byKey(const Key('usage_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wallet_card')), findsOneWidget);
  });

  testWidgets('pagina usage e ledger pelo contrato offset/limit',
      (tester) async {
    final repository = FakeUsageRepository()
      ..usageItems = [FakeUsageRepository().sampleUsage()]
      ..movementItems = [FakeUsageRepository().sampleMovement()]
      ..usageTotal = 25
      ..movementTotal = 25;
    await pumpApp(tester, repository);
    await openUsage(tester);
    await tester.pumpAndSettle();
    final nextButtons = find.ancestor(
      of: find.byIcon(Icons.chevron_right),
      matching: find.byType(IconButton),
    );
    expect(nextButtons, findsNWidgets(2));
    tester.widget<IconButton>(nextButtons.at(0)).onPressed!();
    tester.widget<IconButton>(nextButtons.at(1)).onPressed!();
    await tester.pumpAndSettle();
    expect(repository.usageOffset, 20);
    expect(repository.movementOffset, 20);
  });

  testWidgets('Meu uso não apresenta overflow em largura reduzida',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpApp(tester, FakeUsageRepository());
    await openUsage(tester);
    await tester.pumpAndSettle();
    expect(find.text('Acompanhe sua conta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
