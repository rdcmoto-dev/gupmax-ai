import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_navigation_menu.dart';
import '../commerce_providers.dart';
import '../domain/commerce_models.dart';
import 'commerce_controller.dart';

class CommercePage extends ConsumerStatefulWidget {
  const CommercePage({super.key});

  @override
  ConsumerState<CommercePage> createState() => _CommercePageState();
}

class _CommercePageState extends ConsumerState<CommercePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(commerceControllerProvider).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commerceControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créditos e planos'),
        actions: const [AppNavigationMenu(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.packages.isEmpty
                ? _LoadError(message: state.error!, onRetry: state.load)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: _Content(state: state),
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.state});
  final CommerceController state;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Escolha o que faz sentido para você',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text(
              'O pagamento é processado em ambiente seguro pelo provedor escolhido.'),
          if (state.error != null) ...[
            const SizedBox(height: 16),
            MaterialBanner(
              content: Text(state.error!),
              actions: [
                TextButton(
                    onPressed: state.load, child: const Text('Recarregar'))
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text('Forma de pagamento',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SegmentedButton<CheckoutProvider>(
            segments: CheckoutProvider.values
                .map((item) => ButtonSegment(
                      value: item,
                      label: Text(item.label),
                    ))
                .toList(),
            selected: {state.provider},
            onSelectionChanged: state.isSubmitting
                ? null
                : (values) => state.selectProvider(values.first),
          ),
          const SizedBox(height: 28),
          Text('Comprar créditos',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (state.packages.isEmpty)
            const _EmptyCard('Nenhum pacote disponível no momento.')
          else
            _ResponsiveCards(
              children: state.packages
                  .map((item) => _PackageCard(
                        item: item,
                        disabled: state.isSubmitting,
                        onBuy: () => state.buyCredits(item.id),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 32),
          Text('Planos', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (state.plans.isEmpty)
            const _EmptyCard('Nenhum plano disponível no momento.')
          else
            _ResponsiveCards(
              children: state.plans
                  .map((item) => _PlanCard(
                        item: item,
                        disabled: state.isSubmitting,
                        onSubscribe: () => state.subscribe(item.id),
                      ))
                  .toList(),
            ),
          if (state.isSubmitting) ...[
            const SizedBox(height: 20),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Criando checkout seguro...'),
              ],
            ),
          ],
        ],
      );
}

class _ResponsiveCards extends StatelessWidget {
  const _ResponsiveCards({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 680
              ? constraints.maxWidth
              : (constraints.maxWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: children
                .map((child) => SizedBox(width: width, child: child))
                .toList(),
          );
        },
      );
}

class _PackageCard extends StatelessWidget {
  const _PackageCard(
      {required this.item, required this.disabled, required this.onBuy});
  final CreditPackage item;
  final bool disabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('${item.currency} ${item.price}',
                  style: Theme.of(context).textTheme.headlineSmall),
              Text('${item.credits} créditos'),
              if (item.bonusCredits > 0)
                Text('+ ${item.bonusCredits} créditos de bônus'),
              const SizedBox(height: 18),
              FilledButton(
                key: Key('buy_${item.id}'),
                onPressed: disabled ? null : onBuy,
                child: const Text('Continuar para pagamento seguro'),
              ),
            ],
          ),
        ),
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard(
      {required this.item, required this.disabled, required this.onSubscribe});
  final CommercePlan item;
  final bool disabled;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.name, style: Theme.of(context).textTheme.titleLarge),
              Text(item.description),
              const SizedBox(height: 8),
              Text(
                  '${item.currency} ${item.price} / ${_interval(item.billingInterval)}',
                  style: Theme.of(context).textTheme.headlineSmall),
              Text('${item.monthlyGenerationLimit} gerações com IA'),
              Text('${item.monthlyInputTokenLimit} tokens de entrada'),
              Text('${item.monthlyOutputTokenLimit} tokens de saída'),
              Text('${item.monthlyCreditGrant} créditos incluídos'),
              if (item.trialDays > 0)
                Text('${item.trialDays} dias de teste previstos pelo plano'),
              const SizedBox(height: 18),
              FilledButton.tonal(
                key: Key('subscribe_${item.id}'),
                onPressed: disabled ? null : onSubscribe,
                child: const Text('Assinar com checkout seguro'),
              ),
            ],
          ),
        ),
      );

  static String _interval(String value) => value == 'year' ? 'ano' : 'mês';
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message),
        ),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: onRetry, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
}
