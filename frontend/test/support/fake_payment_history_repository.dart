import 'package:gupmax_ai/features/payments_history/data/payment_history_repository.dart';
import 'package:gupmax_ai/features/payments_history/domain/payment_history_models.dart';
import 'package:gupmax_ai/features/usage/domain/usage_models.dart';

class FakePaymentHistoryRepository implements PaymentHistoryRepositoryContract {
  CommercialSummary summaryValue = CommercialSummary(
    wallet: const CreditWallet(
      availableBalance: 1100,
      reservedBalance: 0,
      lifetimeCredited: 1100,
      lifetimeSpent: 0,
    ),
    subscription: AccountSubscription(
      plan: const AccountPlan(
        code: 'STARTER',
        name: 'Starter',
        description: 'Inicial',
        billingInterval: 'month',
        monthlyCreditGrant: 500,
      ),
      status: 'trialing',
      provider: 'internal',
      currentPeriodStart: DateTime.utc(2026, 8, 1),
      currentPeriodEnd: DateTime.utc(2026, 9, 1),
      cancelAtPeriodEnd: false,
      trialStatus: 'active',
      trialEndsAt: DateTime.utc(2026, 8, 16),
    ),
    productNames: const {'package-1': '500 créditos', 'plan-1': 'Pro'},
  );
  PaymentHistoryPageData pageValue = const PaymentHistoryPageData(
    items: [],
    total: 0,
    offset: 0,
    limit: 20,
  );
  PaymentRecord detailValue = paymentFixture();
  Object? error;
  int paymentCalls = 0;
  int lastOffset = 0;
  PaymentFilters lastFilters = const PaymentFilters();

  @override
  Future<CommercialSummary> summary() async {
    if (error case final value?) throw value;
    return summaryValue;
  }

  @override
  Future<PaymentHistoryPageData> payments({
    required int offset,
    int limit = 20,
    PaymentFilters filters = const PaymentFilters(),
  }) async {
    if (error case final value?) throw value;
    paymentCalls++;
    lastOffset = offset;
    lastFilters = filters;
    return PaymentHistoryPageData(
      items: pageValue.items,
      total: pageValue.total,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<PaymentRecord> payment(String id) async {
    if (error case final value?) throw value;
    return detailValue;
  }
}

PaymentRecord paymentFixture({String status = 'pending'}) => PaymentRecord(
      id: 'payment-1',
      provider: 'stripe',
      purpose: 'credit_purchase',
      status: status,
      amount: '19.90',
      currency: 'BRL',
      creditPackageId: 'package-1',
      createdAt: DateTime.utc(2026, 8, 14, 12),
      updatedAt: DateTime.utc(2026, 8, 14, 12),
      paidAt: status == 'paid' ? DateTime.utc(2026, 8, 14, 12, 5) : null,
      failedAt: status == 'failed' ? DateTime.utc(2026, 8, 14, 12, 5) : null,
      canceledAt:
          status == 'canceled' ? DateTime.utc(2026, 8, 14, 12, 5) : null,
    );
