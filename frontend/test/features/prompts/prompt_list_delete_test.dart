import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/theme/app_theme.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_list_page.dart';
import 'package:gupmax_ai/features/prompts/prompt_providers.dart';

import '../../support/fake_prompt_repository.dart';

void main() {
  Future<void> pumpList(
    WidgetTester tester,
    FakePromptRepository repository, {
    Size size = const Size(1000, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/prompts',
      routes: [
        GoRoute(path: '/prompts', builder: (_, __) => const PromptListPage()),
        GoRoute(
          path: '/prompts/new',
          builder: (_, __) => const Scaffold(body: Text('Novo')),
        ),
        GoRoute(
          path: '/prompts/:id',
          builder: (_, __) => const Scaffold(body: Text('Detalhe')),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [promptRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lixeira identifica prompt e cancelar preserva o registro',
      (tester) async {
    final repository = FakePromptRepository()
      ..records.add(
        FakePromptRepository().sample(title: 'Campanha Donatello'),
      );
    await pumpList(tester, repository);

    await tester.tap(find.byKey(const Key('delete_prompt_prompt-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Campanha Donatello'), findsWidgets);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repository.deleted, isFalse);
    expect(find.text('Campanha Donatello'), findsOneWidget);
  });

  testWidgets('confirmar exclui e atualiza a lista imediatamente',
      (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample(title: 'Excluir agora'));
    await pumpList(tester, repository);

    await tester.tap(find.byKey(const Key('delete_prompt_prompt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_prompt_delete')));
    await tester.pumpAndSettle();

    expect(repository.deleted, isTrue);
    expect(repository.records, isEmpty);
    expect(find.text('Excluir agora'), findsNothing);
    expect(find.textContaining('excluído'), findsOneWidget);
  });

  testWidgets('erro de API preserva prompt e mostra feedback', (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample(title: 'Preservado'));
    await pumpList(tester, repository);
    repository.error = const AppException('Acesso negado.');

    await tester.tap(find.byKey(const Key('delete_prompt_prompt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_prompt_delete')));
    await tester.pumpAndSettle();

    expect(repository.records, hasLength(1));
    expect(find.text('Acesso negado.'), findsWidgets);
  });

  testWidgets('ação destrutiva não causa overflow no mobile', (tester) async {
    final repository = FakePromptRepository()
      ..records.add(FakePromptRepository().sample(title: 'Prompt mobile'));
    await pumpList(tester, repository, size: const Size(390, 844));
    expect(find.byTooltip('Excluir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
