import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../domain/usage_models.dart';
import '../usage_providers.dart';
import 'usage_controller.dart';

class UsagePage extends ConsumerStatefulWidget {
  const UsagePage({super.key});

  @override
  ConsumerState<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends ConsumerState<UsagePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(usageControllerProvider).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(usageControllerProvider);
    return Scaffold(
      appBar: const AppPageAppBar(title: 'Meu uso'),
      body: SafeArea(
        child: state.isLoading || (state.summary == null && state.error == null)
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.summary == null
                ? _LoadError(message: state.error!, onRetry: state.load)
                : RefreshIndicator(
                    onRefresh: state.load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: _UsageContent(state: state),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _UsageContent extends StatelessWidget {
  const _UsageContent({required this.state});
  final UsageController state;

  @override
  Widget build(BuildContext context) {
    final summary = state.summary!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Acompanhe sua conta',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text(
            'Saldo, plano, limites e movimentações informados pelo servidor.'),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          MaterialBanner(
            content: Text(state.error!),
            actions: [
              TextButton(
                  onPressed: state.load, child: const Text('Tentar novamente'))
            ],
          ),
        ],
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth < 720
              ? constraints.maxWidth
              : (constraints.maxWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                  width: width, child: _WalletCard(wallet: summary.wallet)),
              SizedBox(
                  width: width,
                  child: _SubscriptionCard(subscription: summary.subscription)),
            ],
          );
        }),
        const SizedBox(height: 28),
        Text('Limites do período',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
            '${_date(summary.limits.periodStart)} a ${_date(summary.limits.periodEnd)}'),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth < 720
              ? constraints.maxWidth
              : (constraints.maxWidth - 24) / 3;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                  width: width,
                  child: _MetricCard(
                      title: 'Gerações com IA',
                      metric: summary.limits.generations)),
              SizedBox(
                  width: width,
                  child: _MetricCard(
                      title: 'Tokens de entrada',
                      metric: summary.limits.inputTokens)),
              SizedBox(
                  width: width,
                  child: _MetricCard(
                      title: 'Tokens de saída',
                      metric: summary.limits.outputTokens)),
            ],
          );
        }),
        const SizedBox(height: 28),
        _PagedSection<AiUsageRecord>(
          title: 'Uso de IA',
          emptyKey: const Key('empty_usage'),
          emptyText: 'Nenhum uso de IA registrado neste período.',
          items: state.usageItems,
          total: state.usageTotal,
          offset: state.usageOffset,
          itemBuilder: (item) => ListTile(
            leading: const CircleAvatar(child: Icon(Icons.psychology_outlined)),
            title: Text(
                '${item.generationCount} geração • ${item.totalTokens} tokens'),
            subtitle: Text(
                '${item.provider}${item.model == null ? '' : ' • ${item.model}'} • ${_dateTime(item.occurredAt)}'),
          ),
          onPage: state.loadUsage,
        ),
        const SizedBox(height: 28),
        _PagedSection<CreditMovement>(
          title: 'Movimentações de créditos',
          emptyKey: const Key('empty_movements'),
          emptyText: 'Nenhuma movimentação de créditos encontrada.',
          items: state.movements,
          total: state.movementTotal,
          offset: state.movementOffset,
          itemBuilder: (item) => ListTile(
            leading: CircleAvatar(
              backgroundColor: item.amount >= 0
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.errorContainer,
              child: Icon(item.amount >= 0 ? Icons.add : Icons.remove),
            ),
            title: Text(_movementLabel(item.type)),
            subtitle:
                Text('${item.description} • ${_dateTime(item.createdAt)}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${item.amount >= 0 ? '+' : ''}${item.amount}',
                    style: Theme.of(context).textTheme.titleMedium),
                Text('Saldo ${item.balanceAfter}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          onPage: state.loadMovements,
        ),
      ],
    );
  }

  static String _movementLabel(String type) => switch (type) {
        'plan_grant' => 'Créditos do plano',
        'purchase' => 'Compra',
        'trial_grant' => 'Créditos de teste',
        'promotion' => 'Promoção',
        'ai_usage' => 'Uso de IA',
        'reservation' => 'Reserva',
        'reservation_release' => 'Liberação de reserva',
        'refund' => 'Reembolso',
        'adjustment' => 'Ajuste',
        'expiration' => 'Expiração',
        _ => 'Movimentação',
      };

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  static String _dateTime(DateTime value) =>
      '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet});
  final CreditWallet wallet;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('wallet_card'),
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.toll_outlined, size: 34),
            const SizedBox(height: 12),
            const Text('Seus créditos'),
            Text('${wallet.availableBalance}',
                style: Theme.of(context).textTheme.displaySmall),
            Text('${wallet.reservedBalance} reservados'),
            const Divider(height: 24),
            Text(
                '${wallet.lifetimeCredited} recebidos • ${wallet.lifetimeSpent} utilizados'),
          ]),
        ),
      );
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.subscription});
  final AccountSubscription subscription;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('subscription_card'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.workspace_premium_outlined, size: 34),
            const SizedBox(height: 12),
            const Text('Plano atual'),
            Text(subscription.plan.name,
                style: Theme.of(context).textTheme.headlineSmall),
            Text(_statusLabel(subscription.status, subscription.trialStatus)),
            const SizedBox(height: 8),
            Text(
                'Período até ${_UsageContent._date(subscription.currentPeriodEnd)}'),
            if (subscription.cancelAtPeriodEnd)
              const Text('Cancelamento agendado para o fim do período.'),
          ]),
        ),
      );

  static String _statusLabel(String status, String trial) {
    if (status == 'trialing' && trial == 'active') {
      return 'Período de teste ativo';
    }
    if (status == 'trialing' && trial == 'expired') {
      return 'Período de teste expirado';
    }
    return switch (status) {
      'active' => 'Ativo',
      'past_due' => 'Pagamento pendente',
      'canceled' => 'Cancelado',
      'expired' => 'Expirado',
      _ => 'Em teste',
    };
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.metric});
  final String title;
  final UsageMetric metric;

  @override
  Widget build(BuildContext context) {
    final progress =
        metric.limit == 0 ? 0.0 : (metric.used / metric.limit).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(metric.limit == 0
              ? 'Sem capacidade neste período'
              : '${metric.used} de ${metric.limit} • ${metric.remaining} restantes'),
        ]),
      ),
    );
  }
}

class _PagedSection<T> extends StatelessWidget {
  const _PagedSection({
    required this.title,
    required this.emptyKey,
    required this.emptyText,
    required this.items,
    required this.total,
    required this.offset,
    required this.itemBuilder,
    required this.onPage,
  });
  final String title;
  final Key emptyKey;
  final String emptyText;
  final List<T> items;
  final int total;
  final int offset;
  final Widget Function(T) itemBuilder;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Card(
            child: items.isEmpty
                ? Padding(
                    key: emptyKey,
                    padding: const EdgeInsets.all(28),
                    child: Center(child: Text(emptyText)))
                : Column(children: items.map(itemBuilder).toList()),
          ),
          if (total > UsageController.pageSize)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                tooltip: 'Página anterior',
                onPressed: offset > 0
                    ? () => onPage(
                        (offset - UsageController.pageSize).clamp(0, total))
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                  '${offset + 1}–${(offset + items.length).clamp(0, total)} de $total'),
              IconButton(
                tooltip: 'Próxima página',
                onPressed: offset + items.length < total
                    ? () => onPage(offset + UsageController.pageSize)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
        ],
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message,
                key: const Key('usage_error'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
                key: const Key('usage_retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente')),
          ]),
        ),
      );
}
