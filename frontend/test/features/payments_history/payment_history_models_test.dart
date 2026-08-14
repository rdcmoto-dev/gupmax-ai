import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/payments_history/domain/payment_history_models.dart';

void main() {
  test('faz parsing do pagamento sem referências secretas', () {
    final payment = PaymentRecord.fromJson({
      'id': 'payment-1',
      'provider': 'stripe',
      'purpose': 'credit_purchase',
      'status': 'paid',
      'amount': '19.90',
      'currency': 'BRL',
      'credit_package_id': 'package-1',
      'plan_id': null,
      'created_at': '2026-08-14T12:00:00Z',
      'updated_at': '2026-08-14T12:05:00Z',
      'paid_at': '2026-08-14T12:05:00Z',
      'canceled_at': null,
      'failed_at': null,
    });
    expect(payment.status, 'paid');
    expect(payment.amount, '19.90');
    expect(payment.paidAt, isNotNull);
    expect(payment.creditPackageId, 'package-1');
  });

  test('faz parsing da página e preserva paginação do backend', () {
    final page = PaymentHistoryPageData.fromJson({
      'items': <dynamic>[],
      'total': 42,
      'offset': 20,
      'limit': 20,
    });
    expect(page.total, 42);
    expect(page.offset, 20);
    expect(page.limit, 20);
  });

  test('filtros geram somente query suportada pelo contrato', () {
    const filters = PaymentFilters(
      status: 'pending',
      provider: 'stripe',
      purpose: 'credit_purchase',
    );
    expect(filters.query(20, 20), {
      'offset': 20,
      'limit': 20,
      'status': 'pending',
      'provider': 'stripe',
      'purpose': 'credit_purchase',
    });
  });
}
