import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/payment_history_models.dart';
import '../payments_history_providers.dart';
import 'payment_history_page.dart';

class PaymentDetailPage extends ConsumerStatefulWidget {
  const PaymentDetailPage({required this.paymentId, super.key});
  final String paymentId;

  @override
  ConsumerState<PaymentDetailPage> createState() => _PaymentDetailPageState();
}

class _PaymentDetailPageState extends ConsumerState<PaymentDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref
        .read(paymentHistoryControllerProvider)
        .loadDetail(widget.paymentId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentHistoryControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhe do pagamento'),
        leading: IconButton(
          tooltip: 'Voltar para pagamentos',
          onPressed: () => context.go('/payments'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Center(
        child: state.isLoadingDetail
            ? const CircularProgressIndicator()
            : state.error != null || state.selectedPayment == null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.error ?? 'Pagamento não encontrado.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => state.loadDetail(widget.paymentId),
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _PaymentDetails(
                        payment: state.selectedPayment!,
                        productName: state.summary?.productNames[
                            state.selectedPayment!.creditPackageId ??
                                state.selectedPayment!.planId],
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _PaymentDetails extends StatelessWidget {
  const _PaymentDetails({required this.payment, required this.productName});
  final PaymentRecord payment;
  final String? productName;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(statusIcon(payment.status), size: 52),
              const SizedBox(height: 12),
              Text(statusLabel(payment.status),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),
              _row('Finalidade', purposeLabel(payment.purpose)),
              if (productName != null) _row('Produto', productName!),
              _row('Provedor', providerLabel(payment.provider)),
              _row('Valor', '${payment.currency} ${payment.amount}'),
              _row('Criado em', dateTime(payment.createdAt)),
              _row('Atualizado em', dateTime(payment.updatedAt)),
              if (payment.paidAt != null)
                _row('Pago em', dateTime(payment.paidAt!)),
              if (payment.canceledAt != null)
                _row('Cancelado em', dateTime(payment.canceledAt!)),
              if (payment.failedAt != null)
                _row('Falhou em', dateTime(payment.failedAt!)),
              const SizedBox(height: 12),
              const Text(
                'Os dados financeiros são informados pelo backend. Nenhum status pode ser alterado nesta tela.',
              ),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label)),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
