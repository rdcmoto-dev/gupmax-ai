import 'dart:async';

import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/usage/data/usage_repository.dart';
import 'package:gupmax_ai/features/usage/domain/usage_models.dart';

class FakeUsageRepository implements UsageRepositoryContract {
  AppException? error;
  Completer<UsageSummary>? summaryCompleter;
  UsageSummary? summaryOverride;
  int usageOffset = 0;
  int movementOffset = 0;
  int usageTotal = 0;
  int movementTotal = 0;
  List<AiUsageRecord> usageItems = [];
  List<CreditMovement> movementItems = [];

  UsageSummary sampleSummary() {
    final start = DateTime.utc(2026, 8, 1);
    final end = DateTime.utc(2026, 9, 1);
    return UsageSummary(
      wallet: const CreditWallet(
        availableBalance: 100,
        reservedBalance: 5,
        lifetimeCredited: 150,
        lifetimeSpent: 45,
      ),
      subscription: AccountSubscription(
        plan: const AccountPlan(
          code: 'STARTER',
          name: 'Starter',
          description: 'Plano inicial',
          billingInterval: 'month',
          monthlyCreditGrant: 100,
        ),
        status: 'trialing',
        provider: 'internal',
        currentPeriodStart: start,
        currentPeriodEnd: end,
        cancelAtPeriodEnd: false,
        trialStatus: 'active',
        trialEndsAt: end,
      ),
      limits: AccountLimits(
        plan: 'STARTER',
        generations: const UsageMetric(used: 2, limit: 100, remaining: 98),
        inputTokens:
            const UsageMetric(used: 120, limit: 10000, remaining: 9880),
        outputTokens: const UsageMetric(used: 80, limit: 5000, remaining: 4920),
        periodStart: start,
        periodEnd: end,
        trial: 'active',
      ),
    );
  }

  AiUsageRecord sampleUsage() => AiUsageRecord(
        id: 'usage-1',
        promptId: 'prompt-1',
        provider: 'openai',
        model: 'model',
        inputTokens: 12,
        outputTokens: 5,
        totalTokens: 17,
        generationCount: 1,
        occurredAt: DateTime.utc(2026, 8, 14),
      );

  CreditMovement sampleMovement() => CreditMovement(
        id: 'movement-1',
        type: 'ai_usage',
        amount: -3,
        balanceAfter: 97,
        description: 'AI usage: prompt_optimization',
        createdAt: DateTime.utc(2026, 8, 14),
      );

  Never _throw() => throw error!;

  @override
  Future<UsageSummary> summary() async {
    if (error != null) _throw();
    return summaryCompleter?.future ?? summaryOverride ?? sampleSummary();
  }

  @override
  Future<UsagePageData> usage({required int offset, int limit = 20}) async {
    if (error != null) _throw();
    usageOffset = offset;
    return UsagePageData(
      items: usageItems,
      total: usageTotal == 0 ? usageItems.length : usageTotal,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<CreditMovementPage> movements(
      {required int offset, int limit = 20}) async {
    if (error != null) _throw();
    movementOffset = offset;
    return CreditMovementPage(
      items: movementItems,
      total: movementTotal == 0 ? movementItems.length : movementTotal,
      offset: offset,
      limit: limit,
    );
  }
}
