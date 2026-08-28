import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_app_bar.dart';
import '../commerce_providers.dart';
import 'commerce_controller.dart';

class PaymentReturnPage extends ConsumerStatefulWidget {
  const PaymentReturnPage({required this.canceled, super.key});
  final bool canceled;

  @override
  ConsumerState<PaymentReturnPage> createState() => _PaymentReturnPageState();
}

class _PaymentReturnPageState extends ConsumerState<PaymentReturnPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(commerceControllerProvider).checkReturnedPayment());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commerceControllerProvider);
    return Scaffold(
      appBar: const AppPageAppBar(title: 'Status do pagamento'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _StatusContent(state: state, canceled: widget.canceled),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({required this.state, required this.canceled});
  final CommerceController state;
  final bool canceled;

  @override
  Widget build(BuildContext context) {
    if (state.isCheckingPayment) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Consultando confirmação no GUPMAX...'),
        ],
      );
    }
    final payment = state.payment;
    final status = payment?.status;
    final title = switch (status) {
      'paid' => 'Pagamento confirmado',
      'failed' => 'Pagamento não aprovado',
      'canceled' => 'Pagamento cancelado',
      'refunded' => 'Pagamento reembolsado',
      'processing' => 'Pagamento em processamento',
      'pending' => 'Pagamento pendente',
      _ => canceled ? 'Checkout cancelado' : 'Confirmação indisponível',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(status == 'paid' ? Icons.check_circle_outline : Icons.schedule,
            size: 56,
            color: status == 'paid'
                ? Theme.of(context).colorScheme.primary
                : null),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        if (payment != null) ...[
          Text('Valor: ${payment.currency} ${payment.amount}'),
          Text('Provedor: ${_provider(payment.provider)}'),
          Text('Finalidade: ${_purpose(payment.purpose)}'),
        ],
        if (status == 'paid' && state.walletBalance != null)
          Text('Saldo atual: ${state.walletBalance} créditos'),
        if (status != 'paid')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'Nenhum crédito é concedido pelo retorno do checkout. A confirmação depende do backend.'),
          ),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Text(state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed:
              state.isCheckingPayment ? null : state.checkReturnedPayment,
          child: const Text('Atualizar status'),
        ),
        TextButton(
          onPressed: () => context.go('/usage'),
          child: const Text('Ir para Meu uso'),
        ),
      ],
    );
  }

  static String _provider(String value) =>
      value == 'mercado_pago' ? 'Mercado Pago' : 'Stripe';
  static String _purpose(String value) =>
      value == 'subscription' ? 'Assinatura' : 'Compra de créditos';
}
