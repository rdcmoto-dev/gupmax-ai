import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/payments_history/domain/payment_history_models.dart';
import 'package:gupmax_ai/features/payments_history/presentation/payment_history_controller.dart';

import '../../support/fake_payment_history_repository.dart';

void main() {
  test('expõe loading enquanto carrega', () async {
    final controller = PaymentHistoryController(FakePaymentHistoryRepository());
    final loading = controller.load();
    expect(controller.isLoading, isTrue);
    await loading;
    expect(controller.isLoading, isFalse);
  });

  test('carrega resumo comercial e histórico vazio', () async {
    final controller = PaymentHistoryController(FakePaymentHistoryRepository());
    await controller.load();
    expect(controller.summary?.subscription.plan.name, 'Starter');
    expect(controller.summary?.subscription.trialStatus, 'active');
    expect(controller.summary?.wallet.availableBalance, 1100);
    expect(controller.items, isEmpty);
  });

  test('pagina e envia filtros reais ao backend', () async {
    final repository = FakePaymentHistoryRepository()
      ..pageValue = PaymentHistoryPageData(
        items: [paymentFixture()],
        total: 45,
        offset: 0,
        limit: 20,
      );
    final controller = PaymentHistoryController(repository);
    await controller.setFilters(
      status: 'pending',
      provider: 'stripe',
      purpose: 'credit_purchase',
    );
    await controller.loadPage(20);
    expect(repository.lastOffset, 20);
    expect(repository.lastFilters.status, 'pending');
    expect(repository.lastFilters.provider, 'stripe');
    expect(repository.lastFilters.purpose, 'credit_purchase');
  });

  for (final status in ['pending', 'paid', 'failed', 'canceled']) {
    test('detalhe preserva status $status retornado pelo backend', () async {
      final repository = FakePaymentHistoryRepository()
        ..detailValue = paymentFixture(status: status);
      final controller = PaymentHistoryController(repository);
      await controller.loadDetail('payment-1');
      expect(controller.selectedPayment?.status, status);
    });
  }

  test('erro oferece estado recuperável', () async {
    final repository = FakePaymentHistoryRepository()
      ..error = const AppException('Falha temporária');
    final controller = PaymentHistoryController(repository);
    await controller.load();
    expect(controller.error, 'Falha temporária');
    expect(controller.isLoading, isFalse);
  });
}
