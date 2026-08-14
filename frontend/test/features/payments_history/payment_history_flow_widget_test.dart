import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/payments_history/domain/payment_history_models.dart';
import 'package:gupmax_ai/features/payments_history/payments_history_providers.dart';
import 'package:gupmax_ai/features/payments_history/presentation/payment_detail_page.dart';
import 'package:gupmax_ai/features/payments_history/presentation/payment_history_page.dart';

import '../../support/fake_payment_history_repository.dart';

void main() {
  testWidgets('mostra assinatura, trial, créditos e histórico vazio',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentHistoryRepositoryProvider
              .overrideWithValue(FakePaymentHistoryRepository()),
        ],
        child: const MaterialApp(home: PaymentHistoryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Minha assinatura'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    expect(find.text('Trial: Ativo'), findsOneWidget);
    expect(find.byKey(const Key('empty_payments')), findsOneWidget);
  });

  testWidgets('histórico preenchido traduz todos os status reais',
      (tester) async {
    final repository = FakePaymentHistoryRepository()
      ..pageValue = PaymentHistoryPageData(
        items: [
          paymentFixture(status: 'pending'),
          paymentFixture(status: 'paid'),
          paymentFixture(status: 'failed'),
          paymentFixture(status: 'canceled'),
        ],
        total: 4,
        offset: 0,
        limit: 20,
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentHistoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: PaymentHistoryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pendente'), findsOneWidget);
    expect(find.text('Pago'), findsOneWidget);
    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('Cancelado'), findsOneWidget);
    expect(find.text('500 créditos'), findsNWidgets(4));
  });

  testWidgets('detalhe mostra dados permitidos e produto amigável',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentHistoryRepositoryProvider
              .overrideWithValue(FakePaymentHistoryRepository()),
        ],
        child: const MaterialApp(
          home: PaymentDetailPage(paymentId: 'payment-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pendente'), findsOneWidget);
    expect(find.text('500 créditos'), findsOneWidget);
    expect(find.text('Stripe'), findsOneWidget);
    expect(find.text('BRL 19.90'), findsOneWidget);
    expect(
        find.textContaining('Nenhum status pode ser alterado'), findsOneWidget);
  });

  testWidgets('layout não apresenta overflow em viewport mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentHistoryRepositoryProvider
              .overrideWithValue(FakePaymentHistoryRepository()),
        ],
        child: const MaterialApp(home: PaymentHistoryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('erro oferece retry e recupera o conteúdo', (tester) async {
    final repository = FakePaymentHistoryRepository()
      ..error = const AppException('Falha temporária');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentHistoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: PaymentHistoryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Falha temporária'), findsOneWidget);
    repository.error = null;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Minha assinatura'), findsOneWidget);
  });
}
