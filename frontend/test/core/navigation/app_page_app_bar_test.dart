import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/core/widgets/app_page_app_bar.dart';

Widget _page(String title) => Scaffold(
      appBar: AppPageAppBar(title: title),
      body: Center(child: Text('Página $title')),
    );

GoRouter _router(String initialLocation) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
            path: '/dashboard', builder: (_, __) => _page('Dashboard teste')),
        GoRoute(path: '/origem', builder: (_, __) => _page('Origem')),
        GoRoute(path: '/destino', builder: (_, __) => _page('Destino')),
      ],
    );

void main() {
  testWidgets('Voltar retorna para rota anterior válida', (tester) async {
    final router = _router('/origem');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.push('/destino');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app_back_button')));
    await tester.pumpAndSettle();
    expect(find.text('Página Origem'), findsOneWidget);
  });

  testWidgets('Voltar sem histórico usa Dashboard como fallback',
      (tester) async {
    final router = _router('/destino');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app_back_button')));
    await tester.pumpAndSettle();
    expect(find.text('Página Dashboard teste'), findsOneWidget);
  });

  testWidgets('Início é acessível e cabeçalho não transborda no mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = _router('/destino');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app_home_button')));
    await tester.pumpAndSettle();
    expect(find.text('Página Dashboard teste'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
