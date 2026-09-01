import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_page_app_bar.dart';
import '../../usage/domain/usage_models.dart';
import '../domain/payment_history_models.dart';
import '../payments_history_providers.dart';
import 'payment_history_controller.dart';

class PaymentHistoryPage extends ConsumerStatefulWidget {
  const PaymentHistoryPage({super.key});

  @override
  ConsumerState<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends ConsumerState<PaymentHistoryPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(paymentHistoryControllerProvider).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentHistoryControllerProvider);
    return Scaffold(
      appBar: const AppPageAppBar(title: 'Pagamentos'),
      body: SafeArea(
        child: state.isLoading || (state.summary == null && state.error == null)
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.summary == null
                ? _Error(message: state.error!, retry: state.load)
                : RefreshIndicator(
                    onRefresh: state.load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: _Content(state: state),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.state});
  final PaymentHistoryController state;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Situação comercial da conta',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text(
              'Assinatura, créditos e pagamentos informados pelo servidor.'),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            MaterialBanner(
              content: Text(state.error!),
              actions: [
                TextButton(
                    onPressed: state.load,
                    child: const Text('Tentar novamente'))
              ],
            ),
          ],
          const SizedBox(height: 24),
          _SummaryCards(summary: state.summary!),
          const SizedBox(height: 30),
          Text('Histórico financeiro',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          _Filters(state: state),
          const SizedBox(height: 12),
          if (state.items.isEmpty)
            const Card(
              key: Key('empty_payments'),
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text('Nenhum pagamento encontrado.'),
              ),
            )
          else
            ...state.items.map((payment) => _PaymentCard(
                  payment: payment,
                  productName: _productName(state.summary!, payment),
                  onTap: () => context.go('/payments/${payment.id}'),
                )),
          if (state.total > PaymentHistoryController.pageSize) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Página anterior',
                  onPressed: state.offset == 0
                      ? null
                      : () => state.loadPage(
                          (state.offset - PaymentHistoryController.pageSize)
                              .clamp(0, state.total)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                    '${state.offset + 1}–${(state.offset + state.items.length).clamp(0, state.total)} de ${state.total}'),
                IconButton(
                  tooltip: 'Próxima página',
                  onPressed: state.offset + state.items.length >= state.total
                      ? null
                      : () => state.loadPage(
                          state.offset + PaymentHistoryController.pageSize),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ],
      );
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary});
  final CommercialSummary summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 700
              ? constraints.maxWidth
              : (constraints.maxWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                  width: width, child: _SubscriptionCard(summary.subscription)),
              SizedBox(width: width, child: _WalletCard(summary.wallet)),
            ],
          );
        },
      );
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard(this.subscription);
  final AccountSubscription subscription;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('commercial_subscription'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Minha assinatura'),
            Text(subscription.plan.name,
                style: Theme.of(context).textTheme.headlineSmall),
            Text(
                '${statusLabel(subscription.status)} • ${providerLabel(subscription.provider)}'),
            Text(
                'Período: ${date(subscription.currentPeriodStart)} a ${date(subscription.currentPeriodEnd)}'),
            Text('Trial: ${trialLabel(subscription.trialStatus)}'),
            if (subscription.cancelAtPeriodEnd)
              const Text('Cancelamento agendado para o fim do período.'),
          ]),
        ),
      );
}

class _WalletCard extends StatelessWidget {
  const _WalletCard(this.wallet);
  final CreditWallet wallet;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('commercial_wallet'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Créditos disponíveis'),
            Text('${wallet.availableBalance}',
                style: Theme.of(context).textTheme.headlineSmall),
            Text('${wallet.reservedBalance} reservados'),
            Text(
                '${wallet.lifetimeCredited} recebidos • ${wallet.lifetimeSpent} utilizados'),
          ]),
        ),
      );
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state});
  final PaymentHistoryController state;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _Dropdown(
            label: 'Status',
            value: state.statusFilter,
            entries: const {
              'pending': 'Pendente',
              'processing': 'Processando',
              'paid': 'Pago',
              'failed': 'Falhou',
              'canceled': 'Cancelado',
              'refunded': 'Reembolsado'
            },
            changed: (value) => state.setFilters(
                status: value,
                provider: state.providerFilter,
                purpose: state.purposeFilter),
          ),
          _Dropdown(
            label: 'Provedor',
            value: state.providerFilter,
            entries: const {'stripe': 'Stripe', 'mercado_pago': 'Mercado Pago'},
            changed: (value) => state.setFilters(
                status: state.statusFilter,
                provider: value,
                purpose: state.purposeFilter),
          ),
          _Dropdown(
            label: 'Finalidade',
            value: state.purposeFilter,
            entries: const {
              'credit_purchase': 'Compra de créditos',
              'subscription': 'Assinatura'
            },
            changed: (value) => state.setFilters(
                status: state.statusFilter,
                provider: state.providerFilter,
                purpose: value),
          ),
        ],
      );
}

class _Dropdown extends StatelessWidget {
  const _Dropdown(
      {required this.label,
      required this.value,
      required this.entries,
      required this.changed});
  final String label;
  final String? value;
  final Map<String, String> entries;
  final ValueChanged<String?> changed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        child: Theme(
          data: Theme.of(context).copyWith(
            canvasColor: AppColors.surface,
            disabledColor: AppColors.textSecondary,
          ),
          child: DropdownButtonFormField<String?>(
            key: Key('payment_filter_${label.toLowerCase()}'),
            isExpanded: true,
            initialValue: value,
            dropdownColor: AppColors.surface,
            iconEnabledColor: AppColors.oceanBlue,
            iconDisabledColor: AppColors.textSecondary,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: label,
              filled: true,
              fillColor: AppColors.raisedSurface,
              border: const OutlineInputBorder(),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.oceanBlue),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.lightGold, width: 2),
              ),
              disabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              ...entries.entries.map((entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value))),
            ],
            onChanged: changed,
          ),
        ),
      );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard(
      {required this.payment, required this.productName, required this.onTap});
  final PaymentRecord payment;
  final String? productName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(child: Icon(statusIcon(payment.status))),
          title: Text(productName ?? purposeLabel(payment.purpose)),
          subtitle: Text(
              '${providerLabel(payment.provider)} • ${dateTime(payment.createdAt)}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${payment.currency} ${payment.amount}'),
              Text(statusLabel(payment.status)),
            ],
          ),
        ),
      );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('Tentar novamente')),
      ]));
}

String? _productName(CommercialSummary summary, PaymentRecord payment) =>
    summary.productNames[payment.creditPackageId ?? payment.planId];
String statusLabel(String value) => switch (value) {
      'pending' => 'Pendente',
      'processing' => 'Processando',
      'paid' => 'Pago',
      'failed' => 'Falhou',
      'canceled' => 'Cancelado',
      'refunded' => 'Reembolsado',
      _ => value,
    };
String providerLabel(String value) => value == 'mercado_pago'
    ? 'Mercado Pago'
    : value == 'stripe'
        ? 'Stripe'
        : 'Interno';
String purposeLabel(String value) =>
    value == 'subscription' ? 'Assinatura' : 'Compra de créditos';
String trialLabel(String value) => value == 'active'
    ? 'Ativo'
    : value == 'expired'
        ? 'Expirado'
        : 'Não elegível';
IconData statusIcon(String value) => value == 'paid'
    ? Icons.check
    : value == 'failed' || value == 'canceled'
        ? Icons.close
        : Icons.schedule;
String date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String dateTime(DateTime value) =>
    '${date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
