import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/commerce/commerce_providers.dart';
import 'package:gupmax_ai/features/commerce/domain/commerce_models.dart';
import 'package:gupmax_ai/features/commerce/presentation/commerce_page.dart';
import 'package:gupmax_ai/features/commerce/presentation/payment_return_page.dart';

import '../../support/fake_commerce_repository.dart';

void main() {
  testWidgets('exibe catálogos reais e escolha de provider sem overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeCommerceRepository()
      ..catalogValue = const CommerceCatalog(
        packages: [
          CreditPackage(
            id: 'package-1',
            code: 'CREDITS_500',
            name: '500 créditos',
            credits: 500,
            price: '19.90',
            currency: 'BRL',
            bonusCredits: 0,
          ),
        ],
        plans: [
          CommercePlan(
            id: 'plan-1',
            code: 'PRO',
            name: 'Pro',
            description: 'Plano profissional',
            price: '79.90',
            currency: 'BRL',
            billingInterval: 'month',
            trialDays: 5,
            monthlyGenerationLimit: 1000,
            monthlyInputTokenLimit: 500000,
            monthlyOutputTokenLimit: 200000,
            monthlyCreditGrant: 2000,
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [commerceRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: CommercePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mercado Pago'), findsOneWidget);
    expect(find.text('Stripe'), findsOneWidget);
    expect(find.text('500 créditos'), findsAtLeastNWidgets(1));
    expect(find.text('Pro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retorno de pagamento permanece responsivo em mobile',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeCommerceRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commerceRepositoryProvider.overrideWithValue(repository),
          checkoutNavigationProvider
              .overrideWithValue(FakeCheckoutNavigation()),
        ],
        child: const MaterialApp(home: PaymentReturnPage(canceled: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pagamento pendente'), findsOneWidget);
    expect(find.byKey(const Key('app_navigation_menu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
