import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/core/widgets/app_navigation_menu.dart';

void main() {
  testWidgets('menu global apresenta todas as áreas principais do MVP',
      (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.byKey(const Key('app_navigation_menu')));
    await tester.pumpAndSettle();

    for (final destination in AppNavigationMenu.destinations) {
      expect(find.text(destination.label), findsAtLeastNWidgets(1));
    }
  });

  testWidgets('menu navega e não apresenta overflow em larguras principais',
      (tester) async {
    final router = _router();
    addTearDown(router.dispose);

    for (final width in [320.0, 768.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app_navigation_menu')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byKey(const Key('app_navigation_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minha conta'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/account');
    expect(find.text('route:/account'), findsOneWidget);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

GoRouter _router() => GoRouter(
      initialLocation: '/dashboard',
      routes: AppNavigationMenu.destinations
          .map(
            (destination) => GoRoute(
              path: destination.path,
              builder: (_, __) => Scaffold(
                appBar: AppBar(
                  title: Text(destination.label),
                  actions: const [AppNavigationMenu()],
                ),
                body: Text('route:${destination.path}'),
              ),
            ),
          )
          .toList(),
    );
