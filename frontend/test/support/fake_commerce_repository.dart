import 'dart:async';

import 'package:gupmax_ai/features/commerce/data/checkout_navigation.dart';
import 'package:gupmax_ai/features/commerce/data/commerce_repository.dart';
import 'package:gupmax_ai/features/commerce/domain/commerce_models.dart';

class FakeCommerceRepository implements CommerceRepositoryContract {
  CommerceCatalog catalogValue = const CommerceCatalog(packages: [], plans: []);
  CheckoutResult checkoutValue = const CheckoutResult(
    paymentId: 'payment-1',
    provider: 'mercado_pago',
    checkoutUrl: 'https://sandbox.example/checkout',
    status: 'pending',
  );
  PaymentInfo paymentValue = PaymentInfo(
    id: 'payment-1',
    provider: 'mercado_pago',
    purpose: 'credit_purchase',
    status: 'pending',
    amount: '19.90',
    currency: 'BRL',
    createdAt: DateTime.utc(2026, 8, 14),
  );
  int walletValue = 600;
  int checkoutCalls = 0;
  int walletCalls = 0;
  String? selectedId;
  CheckoutProvider? selectedProvider;
  String? idempotencyKey;
  Completer<CheckoutResult>? checkoutCompleter;

  @override
  Future<CommerceCatalog> catalog() async => catalogValue;

  @override
  Future<CheckoutResult> createCreditCheckout({
    required String packageId,
    required CheckoutProvider provider,
    required String idempotencyKey,
  }) =>
      _checkout(packageId, provider, idempotencyKey);

  @override
  Future<CheckoutResult> createSubscriptionCheckout({
    required String planId,
    required CheckoutProvider provider,
    required String idempotencyKey,
  }) =>
      _checkout(planId, provider, idempotencyKey);

  Future<CheckoutResult> _checkout(
      String id, CheckoutProvider provider, String key) {
    checkoutCalls++;
    selectedId = id;
    selectedProvider = provider;
    idempotencyKey = key;
    return checkoutCompleter?.future ?? Future.value(checkoutValue);
  }

  @override
  Future<PaymentInfo> payment(String id) async => paymentValue;

  @override
  Future<int> walletBalance() async {
    walletCalls++;
    return walletValue;
  }
}

class FakeCheckoutNavigation implements CheckoutNavigation {
  bool opens = true;
  String? pendingId = 'payment-1';
  String? openedUrl;
  String? storedId;
  int clearCalls = 0;

  @override
  Future<bool> open(String url, String paymentId) async {
    openedUrl = url;
    storedId = paymentId;
    return opens;
  }

  @override
  Future<String?> pendingPaymentId() async => pendingId;

  @override
  Future<void> clearPendingPayment() async {
    clearCalls++;
    pendingId = null;
  }
}
