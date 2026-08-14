import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/usage/domain/usage_models.dart';

void main() {
  test('faz parsing do contrato real de wallet', () {
    final wallet = CreditWallet.fromJson({
      'id': 'wallet-id',
      'available_balance': 100,
      'reserved_balance': 4,
      'lifetime_credited': 150,
      'lifetime_spent': 46,
      'created_at': '2026-08-01T00:00:00Z',
      'updated_at': '2026-08-14T00:00:00Z',
    });
    expect(wallet.availableBalance, 100);
    expect(wallet.reservedBalance, 4);
    expect(wallet.lifetimeSpent, 46);
  });

  test('faz parsing de limits, usage, subscription e ledger', () {
    final limits = AccountLimits.fromJson({
      'plan': 'STARTER',
      'generations': {'used': 1, 'limit': 100, 'remaining': 99},
      'input_tokens': {'used': 12, 'limit': 10000, 'remaining': 9988},
      'output_tokens': {'used': 5, 'limit': 5000, 'remaining': 4995},
      'period_start': '2026-08-01T00:00:00Z',
      'period_end': '2026-09-01T00:00:00Z',
      'trial': 'active',
    });
    final usage = UsagePageData.fromJson({
      'items': [
        {
          'id': 'usage-id',
          'prompt_id': null,
          'provider': 'openai',
          'model': null,
          'input_tokens': 12,
          'output_tokens': 5,
          'total_tokens': 17,
          'generation_count': 1,
          'occurred_at': '2026-08-14T00:00:00Z',
        }
      ],
      'total': 1,
      'offset': 0,
      'limit': 20,
    });
    final movement = CreditMovementPage.fromJson({
      'items': [
        {
          'id': 'transaction-id',
          'type': 'ai_usage',
          'amount': -3,
          'balance_after': 97,
          'reference_type': 'prompt',
          'reference_id': 'prompt-id',
          'description': 'AI usage',
          'expires_at': null,
          'created_at': '2026-08-14T00:00:00Z',
        }
      ],
      'total': 1,
      'offset': 0,
      'limit': 20,
    });
    expect(limits.generations.remaining, 99);
    expect(usage.items.single.totalTokens, 17);
    expect(movement.items.single.amount, -3);
  });
}
