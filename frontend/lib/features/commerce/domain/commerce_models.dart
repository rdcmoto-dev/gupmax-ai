class CreditPackage {
  const CreditPackage({
    required this.id,
    required this.code,
    required this.name,
    required this.credits,
    required this.price,
    required this.currency,
    required this.bonusCredits,
  });

  factory CreditPackage.fromJson(Map<String, dynamic> json) => CreditPackage(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        credits: json['credits'] as int,
        price: json['price'] as String,
        currency: json['currency'] as String,
        bonusCredits: json['bonus_credits'] as int,
      );

  final String id;
  final String code;
  final String name;
  final int credits;
  final String price;
  final String currency;
  final int bonusCredits;
}

class CommercePlan {
  const CommercePlan({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.billingInterval,
    required this.trialDays,
    required this.monthlyGenerationLimit,
    required this.monthlyInputTokenLimit,
    required this.monthlyOutputTokenLimit,
    required this.monthlyCreditGrant,
  });

  factory CommercePlan.fromJson(Map<String, dynamic> json) => CommercePlan(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        price: json['price'] as String,
        currency: json['currency'] as String,
        billingInterval: json['billing_interval'] as String,
        trialDays: json['trial_days'] as int,
        monthlyGenerationLimit: json['monthly_generation_limit'] as int,
        monthlyInputTokenLimit: json['monthly_input_token_limit'] as int,
        monthlyOutputTokenLimit: json['monthly_output_token_limit'] as int,
        monthlyCreditGrant: json['monthly_credit_grant'] as int,
      );

  final String id;
  final String code;
  final String name;
  final String description;
  final String price;
  final String currency;
  final String billingInterval;
  final int trialDays;
  final int monthlyGenerationLimit;
  final int monthlyInputTokenLimit;
  final int monthlyOutputTokenLimit;
  final int monthlyCreditGrant;
}

enum CheckoutProvider {
  mercadoPago('mercado_pago', 'Mercado Pago'),
  stripe('stripe', 'Stripe');

  const CheckoutProvider(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class CheckoutResult {
  const CheckoutResult({
    required this.paymentId,
    required this.provider,
    required this.checkoutUrl,
    required this.status,
  });

  factory CheckoutResult.fromJson(Map<String, dynamic> json) => CheckoutResult(
        paymentId: json['payment_id'] as String,
        provider: json['provider'] as String,
        checkoutUrl: json['checkout_url'] as String,
        status: json['status'] as String,
      );

  final String paymentId;
  final String provider;
  final String checkoutUrl;
  final String status;
}

class PaymentInfo {
  const PaymentInfo({
    required this.id,
    required this.provider,
    required this.purpose,
    required this.status,
    required this.amount,
    required this.currency,
    required this.createdAt,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) => PaymentInfo(
        id: json['id'] as String,
        provider: json['provider'] as String,
        purpose: json['purpose'] as String,
        status: json['status'] as String,
        amount: json['amount'] as String,
        currency: json['currency'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String provider;
  final String purpose;
  final String status;
  final String amount;
  final String currency;
  final DateTime createdAt;
}

class CommerceCatalog {
  const CommerceCatalog({required this.packages, required this.plans});
  final List<CreditPackage> packages;
  final List<CommercePlan> plans;
}
