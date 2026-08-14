class CreditWallet {
  const CreditWallet({
    required this.availableBalance,
    required this.reservedBalance,
    required this.lifetimeCredited,
    required this.lifetimeSpent,
  });

  factory CreditWallet.fromJson(Map<String, dynamic> json) => CreditWallet(
        availableBalance: json['available_balance'] as int,
        reservedBalance: json['reserved_balance'] as int,
        lifetimeCredited: json['lifetime_credited'] as int,
        lifetimeSpent: json['lifetime_spent'] as int,
      );

  final int availableBalance;
  final int reservedBalance;
  final int lifetimeCredited;
  final int lifetimeSpent;
}

class AccountPlan {
  const AccountPlan({
    required this.code,
    required this.name,
    required this.description,
    required this.billingInterval,
    required this.monthlyCreditGrant,
  });

  factory AccountPlan.fromJson(Map<String, dynamic> json) => AccountPlan(
        code: json['code'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        billingInterval: json['billing_interval'] as String,
        monthlyCreditGrant: json['monthly_credit_grant'] as int,
      );

  final String code;
  final String name;
  final String description;
  final String billingInterval;
  final int monthlyCreditGrant;
}

class AccountSubscription {
  const AccountSubscription({
    required this.plan,
    required this.status,
    required this.provider,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.trialStatus,
    this.trialEndsAt,
  });

  factory AccountSubscription.fromJson(Map<String, dynamic> json) =>
      AccountSubscription(
        plan: AccountPlan.fromJson(json['plan'] as Map<String, dynamic>),
        status: json['status'] as String,
        provider: json['provider'] as String,
        currentPeriodStart:
            DateTime.parse(json['current_period_start'] as String),
        currentPeriodEnd: DateTime.parse(json['current_period_end'] as String),
        cancelAtPeriodEnd: json['cancel_at_period_end'] as bool,
        trialStatus: json['trial_status'] as String,
        trialEndsAt: json['trial_ends_at'] == null
            ? null
            : DateTime.parse(json['trial_ends_at'] as String),
      );

  final AccountPlan plan;
  final String status;
  final String provider;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String trialStatus;
  final DateTime? trialEndsAt;
}

class UsageMetric {
  const UsageMetric(
      {required this.used, required this.limit, required this.remaining});

  factory UsageMetric.fromJson(Map<String, dynamic> json) => UsageMetric(
        used: json['used'] as int,
        limit: json['limit'] as int,
        remaining: json['remaining'] as int,
      );

  final int used;
  final int limit;
  final int remaining;
}

class AccountLimits {
  const AccountLimits({
    required this.plan,
    required this.generations,
    required this.inputTokens,
    required this.outputTokens,
    required this.periodStart,
    required this.periodEnd,
    required this.trial,
  });

  factory AccountLimits.fromJson(Map<String, dynamic> json) => AccountLimits(
        plan: json['plan'] as String,
        generations:
            UsageMetric.fromJson(json['generations'] as Map<String, dynamic>),
        inputTokens:
            UsageMetric.fromJson(json['input_tokens'] as Map<String, dynamic>),
        outputTokens:
            UsageMetric.fromJson(json['output_tokens'] as Map<String, dynamic>),
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        trial: json['trial'] as String,
      );

  final String plan;
  final UsageMetric generations;
  final UsageMetric inputTokens;
  final UsageMetric outputTokens;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String trial;
}

class AiUsageRecord {
  const AiUsageRecord({
    required this.id,
    required this.provider,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.generationCount,
    required this.occurredAt,
    this.promptId,
    this.model,
  });

  factory AiUsageRecord.fromJson(Map<String, dynamic> json) => AiUsageRecord(
        id: json['id'] as String,
        promptId: json['prompt_id'] as String?,
        provider: json['provider'] as String,
        model: json['model'] as String?,
        inputTokens: json['input_tokens'] as int,
        outputTokens: json['output_tokens'] as int,
        totalTokens: json['total_tokens'] as int,
        generationCount: json['generation_count'] as int,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
      );

  final String id;
  final String? promptId;
  final String provider;
  final String? model;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int generationCount;
  final DateTime occurredAt;
}

class CreditMovement {
  const CreditMovement({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    required this.createdAt,
    this.expiresAt,
  });

  factory CreditMovement.fromJson(Map<String, dynamic> json) => CreditMovement(
        id: json['id'] as String,
        type: json['type'] as String,
        amount: json['amount'] as int,
        balanceAfter: json['balance_after'] as int,
        description: json['description'] as String,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String type;
  final int amount;
  final int balanceAfter;
  final String description;
  final DateTime? expiresAt;
  final DateTime createdAt;
}

class UsagePageData {
  const UsagePageData(
      {required this.items,
      required this.total,
      required this.offset,
      required this.limit});

  factory UsagePageData.fromJson(Map<String, dynamic> json) => UsagePageData(
        items: (json['items'] as List<dynamic>)
            .map((item) => AiUsageRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        offset: json['offset'] as int,
        limit: json['limit'] as int,
      );

  final List<AiUsageRecord> items;
  final int total;
  final int offset;
  final int limit;
}

class CreditMovementPage {
  const CreditMovementPage(
      {required this.items,
      required this.total,
      required this.offset,
      required this.limit});

  factory CreditMovementPage.fromJson(Map<String, dynamic> json) =>
      CreditMovementPage(
        items: (json['items'] as List<dynamic>)
            .map(
                (item) => CreditMovement.fromJson(item as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        offset: json['offset'] as int,
        limit: json['limit'] as int,
      );

  final List<CreditMovement> items;
  final int total;
  final int offset;
  final int limit;
}

class UsageSummary {
  const UsageSummary(
      {required this.wallet, required this.subscription, required this.limits});
  final CreditWallet wallet;
  final AccountSubscription subscription;
  final AccountLimits limits;
}
