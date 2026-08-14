import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../data/checkout_navigation.dart';
import '../data/commerce_repository.dart';
import '../domain/commerce_models.dart';

class CommerceController extends ChangeNotifier {
  CommerceController(this._repository, this._navigation);
  final CommerceRepositoryContract _repository;
  final CheckoutNavigation _navigation;

  bool isLoading = false;
  bool isSubmitting = false;
  bool isCheckingPayment = false;
  String? error;
  List<CreditPackage> packages = [];
  List<CommercePlan> plans = [];
  CheckoutProvider provider = CheckoutProvider.mercadoPago;
  PaymentInfo? payment;
  int? walletBalance;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final catalog = await _repository.catalog();
      packages = catalog.packages;
      plans = catalog.plans;
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void selectProvider(CheckoutProvider value) {
    provider = value;
    notifyListeners();
  }

  Future<void> buyCredits(String packageId) => _startCheckout(
        (key) => _repository.createCreditCheckout(
          packageId: packageId,
          provider: provider,
          idempotencyKey: key,
        ),
      );

  Future<void> subscribe(String planId) => _startCheckout(
        (key) => _repository.createSubscriptionCheckout(
          planId: planId,
          provider: provider,
          idempotencyKey: key,
        ),
      );

  Future<void> _startCheckout(
      Future<CheckoutResult> Function(String key) create) async {
    if (isSubmitting) return;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      final key = 'flutter-${DateTime.now().microsecondsSinceEpoch}';
      final checkout = await create(key);
      final opened = await _navigation.open(
        checkout.checkoutUrl,
        checkout.paymentId,
      );
      if (!opened) {
        throw const AppException(
            'A URL segura de checkout retornada não pôde ser aberta.');
      }
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> checkReturnedPayment() async {
    if (isCheckingPayment) return;
    isCheckingPayment = true;
    error = null;
    notifyListeners();
    try {
      final id = await _navigation.pendingPaymentId();
      if (id == null) {
        throw const AppException(
            'Não foi encontrada uma sessão de pagamento para consultar.');
      }
      payment = await _repository.payment(id);
      if (payment!.status == 'paid') {
        walletBalance = await _repository.walletBalance();
        await _navigation.clearPendingPayment();
      }
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isCheckingPayment = false;
      notifyListeners();
    }
  }
}
