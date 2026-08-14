import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/commerce/domain/commerce_models.dart';
import 'package:gupmax_ai/features/commerce/presentation/commerce_controller.dart';

import '../../support/fake_commerce_repository.dart';

void main() {
  test('cria checkout com provider selecionado e abre URL do backend',
      () async {
    final repository = FakeCommerceRepository();
    final navigation = FakeCheckoutNavigation();
    final controller = CommerceController(repository, navigation);
    controller.selectProvider(CheckoutProvider.stripe);

    await controller.buyCredits('package-1');

    expect(repository.selectedId, 'package-1');
    expect(repository.selectedProvider, CheckoutProvider.stripe);
    expect(repository.idempotencyKey, startsWith('flutter-'));
    expect(navigation.openedUrl, repository.checkoutValue.checkoutUrl);
    expect(navigation.storedId, repository.checkoutValue.paymentId);
  });

  test('bloqueia submit duplo enquanto checkout está sendo criado', () async {
    final repository = FakeCommerceRepository();
    final navigation = FakeCheckoutNavigation();
    final completer = Completer<CheckoutResult>();
    repository.checkoutCompleter = completer;
    final controller = CommerceController(repository, navigation);

    final first = controller.buyCredits('package-1');
    await controller.buyCredits('package-1');
    expect(repository.checkoutCalls, 1);
    completer.complete(repository.checkoutValue);
    await first;
  });

  test('não prossegue quando a navegação rejeita URL de checkout', () async {
    final repository = FakeCommerceRepository();
    final navigation = FakeCheckoutNavigation()..opens = false;
    final controller = CommerceController(repository, navigation);

    await controller.buyCredits('package-1');

    expect(controller.error, contains('URL segura'));
    expect(controller.isSubmitting, isFalse);
  });

  for (final status in ['pending', 'failed', 'canceled']) {
    test('$status não atualiza nem concede wallet localmente', () async {
      final repository = FakeCommerceRepository();
      repository.paymentValue = PaymentInfo(
        id: 'payment-1',
        provider: 'stripe',
        purpose: 'credit_purchase',
        status: status,
        amount: '19.90',
        currency: 'BRL',
        createdAt: DateTime.utc(2026, 8, 14),
      );
      final controller =
          CommerceController(repository, FakeCheckoutNavigation());

      await controller.checkReturnedPayment();

      expect(controller.payment?.status, status);
      expect(controller.walletBalance, isNull);
      expect(repository.walletCalls, 0);
    });
  }

  test('paid atualiza wallet somente consultando backend', () async {
    final repository = FakeCommerceRepository();
    repository.paymentValue = PaymentInfo(
      id: 'payment-1',
      provider: 'mercado_pago',
      purpose: 'credit_purchase',
      status: 'paid',
      amount: '19.90',
      currency: 'BRL',
      createdAt: DateTime.utc(2026, 8, 14),
    );
    final navigation = FakeCheckoutNavigation();
    final controller = CommerceController(repository, navigation);

    await controller.checkReturnedPayment();

    expect(controller.walletBalance, repository.walletValue);
    expect(repository.walletCalls, 1);
    expect(navigation.clearCalls, 1);
  });

  test('retorno sem sessão pendente informa erro sem consultar wallet',
      () async {
    final repository = FakeCommerceRepository();
    final navigation = FakeCheckoutNavigation()..pendingId = null;
    final controller = CommerceController(repository, navigation);

    await controller.checkReturnedPayment();

    expect(controller.error, contains('sessão de pagamento'));
    expect(repository.walletCalls, 0);
  });
}
