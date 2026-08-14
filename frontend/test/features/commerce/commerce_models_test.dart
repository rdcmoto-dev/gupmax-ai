import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/commerce/domain/commerce_models.dart';

void main() {
  test('faz parsing do pacote exclusivamente com campos do backend', () {
    final package = CreditPackage.fromJson({
      'id': 'package-1',
      'code': 'CREDITS_500',
      'name': '500 créditos',
      'credits': 500,
      'price': '19.90',
      'currency': 'BRL',
      'bonus_credits': 50,
    });
    expect(package.credits, 500);
    expect(package.bonusCredits, 50);
    expect(package.price, '19.90');
  });

  test('faz parsing do plano e de seus limites reais', () {
    final plan = CommercePlan.fromJson({
      'id': 'plan-1',
      'code': 'PRO',
      'name': 'Pro',
      'description': 'Profissional',
      'price': '79.90',
      'currency': 'BRL',
      'billing_interval': 'month',
      'trial_days': 5,
      'monthly_generation_limit': 1000,
      'monthly_input_token_limit': 500000,
      'monthly_output_token_limit': 200000,
      'monthly_credit_grant': 2000,
    });
    expect(plan.name, 'Pro');
    expect(plan.monthlyCreditGrant, 2000);
    expect(plan.billingInterval, 'month');
  });

  test('faz parsing de checkout e status de pagamento', () {
    final checkout = CheckoutResult.fromJson({
      'payment_id': 'payment-1',
      'provider': 'stripe',
      'checkout_url': 'https://checkout.stripe.test/session',
      'status': 'pending',
    });
    final payment = PaymentInfo.fromJson({
      'id': 'payment-1',
      'provider': 'stripe',
      'purpose': 'credit_purchase',
      'status': 'paid',
      'amount': '19.90',
      'currency': 'BRL',
      'created_at': '2026-08-14T12:00:00Z',
    });
    expect(checkout.checkoutUrl, startsWith('https://'));
    expect(payment.status, 'paid');
  });
}
