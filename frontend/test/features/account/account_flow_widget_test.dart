import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/session_expiry_bus.dart';
import 'package:gupmax_ai/core/routing/app_router.dart';
import 'package:gupmax_ai/features/account/account_providers.dart';
import 'package:gupmax_ai/features/account/domain/smart_profile.dart';
import 'package:gupmax_ai/features/account/presentation/account_page.dart';
import 'package:gupmax_ai/features/auth/auth_providers.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_controller.dart';

import '../../support/fake_account_repository.dart';
import '../../support/fake_auth_repository.dart';

void main() {
  testWidgets('carrega e exibe os campos reais da conta', (tester) async {
    await _pumpAccount(tester, FakeAccountRepository());
    await tester.pumpAndSettle();

    expect(find.text('Dados pessoais'), findsOneWidget);
    expect(find.text('Usuário Teste'), findsOneWidget);
    expect(find.text('usuario@example.com'), findsOneWidget);
    expect(find.text('Perfil: Usuário'), findsOneWidget);
    expect(find.text('Status: Ativo'), findsOneWidget);
    expect(find.text('Criada em: 01/08/2026'), findsOneWidget);
  });

  testWidgets('mostra loading enquanto o perfil está sendo carregado',
      (tester) async {
    final repository = FakeAccountRepository()..profileCompleter = Completer();
    await _pumpAccount(tester, repository);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.profileCompleter!.complete(repository.profileValue);
    await tester.pumpAndSettle();
  });

  testWidgets('erro oferece retry e recupera o perfil', (tester) async {
    final repository = FakeAccountRepository()
      ..error = const AppException('Falha temporária');
    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Falha temporária'), findsOneWidget);
    repository.error = null;
    await tester.tap(find.byKey(const Key('retry_account_button')));
    await tester.pumpAndSettle();
    expect(find.text('Dados pessoais'), findsOneWidget);
    expect(repository.profileCalls, 2);
  });

  testWidgets('edita somente nome e e-mail usando o contrato existente',
      (tester) async {
    final repository = FakeAccountRepository();
    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('account_name_field')), 'Nome Atualizado');
    await tester.enterText(
        find.byKey(const Key('account_email_field')), 'novo@example.com');
    await tester.tap(find.byKey(const Key('save_profile_button')));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(repository.updatedName, 'Nome Atualizado');
    expect(repository.updatedEmail, 'novo@example.com');
    expect(find.text('Perfil atualizado com sucesso.'), findsOneWidget);
  });

  testWidgets('valida edição e apresenta erro amigável do backend',
      (tester) async {
    final repository = FakeAccountRepository();
    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('account_name_field')), 'A');
    await tester.enterText(
        find.byKey(const Key('account_email_field')), 'invalido');
    await tester.tap(find.byKey(const Key('save_profile_button')));
    await tester.pump();
    expect(repository.updateCalls, 0);
    expect(find.textContaining('pelo menos 2 caracteres'), findsOneWidget);
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);

    repository.error = const AppException('E-mail indisponível');
    await tester.enterText(
        find.byKey(const Key('account_name_field')), 'Nome Válido');
    await tester.enterText(
        find.byKey(const Key('account_email_field')), 'valido@example.com');
    await tester.tap(find.byKey(const Key('save_profile_button')));
    await tester.pumpAndSettle();
    expect(find.text('E-mail indisponível'), findsOneWidget);
  });

  testWidgets('campos de senha permanecem obscurecidos', (tester) async {
    await _pumpAccount(tester, FakeAccountRepository());
    await tester.pumpAndSettle();

    for (final key in [
      const Key('current_password_field'),
      const Key('new_password_field'),
      const Key('confirm_password_field'),
    ]) {
      final editable = tester.widget<EditableText>(
        find.descendant(
            of: find.byKey(key), matching: find.byType(EditableText)),
      );
      expect(editable.obscureText, isTrue);
    }
  });

  testWidgets('valida confirmação antes de alterar a senha', (tester) async {
    final repository = FakeAccountRepository();
    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('current_password_field')), 'senha-atual');
    await tester.enterText(
        find.byKey(const Key('new_password_field')), 'nova-senha-123');
    await tester.enterText(
        find.byKey(const Key('confirm_password_field')), 'outra-senha');
    await tester.ensureVisible(find.byKey(const Key('change_password_button')));
    await tester.tap(find.byKey(const Key('change_password_button')));
    await tester.pump();

    expect(find.text('As senhas não coincidem.'), findsOneWidget);
    expect(repository.passwordCalls, 0);
  });

  testWidgets('altera senha com sucesso e limpa os campos', (tester) async {
    final repository = FakeAccountRepository();
    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();

    await _fillPasswords(tester);
    await tester.ensureVisible(find.byKey(const Key('change_password_button')));
    await tester.tap(find.byKey(const Key('change_password_button')));
    await tester.pumpAndSettle();

    expect(repository.passwordCalls, 1);
    expect(find.text('Senha alterada com sucesso.'), findsOneWidget);
    for (final key in [
      const Key('current_password_field'),
      const Key('new_password_field'),
      const Key('confirm_password_field'),
    ]) {
      final field = tester.widget<TextFormField>(find.byKey(key));
      expect(field.controller!.text, isEmpty);
    }
  });

  testWidgets('apresenta erro do backend ao alterar senha', (tester) async {
    final repository = FakeAccountRepository();
    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();
    repository.error = const AppException('Senha atual incorreta');

    await _fillPasswords(tester);
    await tester.ensureVisible(find.byKey(const Key('change_password_button')));
    await tester.tap(find.byKey(const Key('change_password_button')));
    await tester.pumpAndSettle();

    expect(repository.passwordCalls, 1);
    expect(find.text('Senha atual incorreta'), findsOneWidget);
  });

  testWidgets('logout limpa a sessão e redireciona para login', (tester) async {
    final accountRepository = FakeAccountRepository();
    final authRepository = FakeAuthRepository();
    final bus = SessionExpiryBus();
    final auth = AuthController(
      repository: authRepository,
      expiryBus: bus,
      restoreOnCreate: false,
    );
    await auth.login(email: 'usuario@example.com', password: 'senha-valida');
    final router = createAppRouter(auth, initialLocation: '/account');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          accountRepositoryProvider.overrideWithValue(accountRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('account_logout_button')));
    expect(find.text('Sessão'), findsOneWidget);
    expect(
      find.text('Encerre sua sessão neste dispositivo.'),
      findsOneWidget,
    );
    expect(find.text('Sair da conta'), findsOneWidget);
    await tester.tap(find.byKey(const Key('account_logout_button')));
    await tester.pumpAndSettle();

    expect(authRepository.logoutCalls, 1);
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.text('Bem-vindo ao GUPMAX AI'), findsOneWidget);

    router.go('/account');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.text('Minha conta'), findsNothing);
    router.dispose();
    bus.dispose();
  });

  testWidgets('layout não apresenta overflow em viewport mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAccount(tester, FakeAccountRepository());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('carrega edita salva desativa e exclui Smart Profile',
      (tester) async {
    final repository = FakeAccountRepository()
      ..smartProfileValue = const SmartProfile(
        isEnabled: true,
        defaultLanguage: 'pt-BR',
        defaultTone: 'profissional',
        defaultAudience: 'Pequenos negócios',
      );
    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('smart_profile_card'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(find.text('pt-BR'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('smart_profile_field_1')), 'casual');
    tester
        .widget<SwitchListTile>(find.byKey(const Key('smart_profile_enabled')))
        .onChanged!(false);
    final save = find.byKey(const Key('save_smart_profile'));
    tester.widget<FilledButton>(save).onPressed!();
    await tester.pumpAndSettle();
    expect(repository.smartProfileSaveCalls, 1);
    expect(repository.smartProfileValue.defaultTone, 'casual');
    expect(repository.smartProfileValue.isEnabled, isFalse);
    final delete = find.byKey(const Key('delete_smart_profile'));
    tester.widget<OutlinedButton>(delete).onPressed!();
    await tester.pumpAndSettle();
    expect(repository.smartProfileDeleteCalls, 1);
    expect(repository.smartProfileValue.hasData, isFalse);
  });

  testWidgets('perfil vazio ainda exibe Smart Profile e carrega preferências',
      (tester) async {
    final repository = FakeAccountRepository();

    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('smart_profile_card'));
    await tester.ensureVisible(card);
    expect(card, findsOneWidget);
    expect(find.text('Smart Profile'), findsOneWidget);
    expect(repository.smartProfileCalls, 1);
  });

  testWidgets('ativa Smart Profile pela UI e preserva toggle após recarregar',
      (tester) async {
    final repository = FakeAccountRepository()
      ..smartProfileValue = const SmartProfile(
        isEnabled: false,
        defaultAudience: 'Pequenos negócios',
      );

    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('smart_profile_enabled'));
    await tester.ensureVisible(toggle);
    expect(
      find.text('Usar minhas preferências em novos prompts'),
      findsOneWidget,
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    final save = find.byKey(const Key('save_smart_profile'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.smartProfileValue.isEnabled, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpAccount(tester, repository);
    await tester.pumpAndSettle();
    final reloadedToggle = find.byKey(const Key('smart_profile_enabled'));
    await tester.ensureVisible(reloadedToggle);
    expect(tester.widget<SwitchListTile>(reloadedToggle).value, isTrue);
  });
}

Future<void> _fillPasswords(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('current_password_field')), 'senha-atual');
  await tester.enterText(
      find.byKey(const Key('new_password_field')), 'nova-senha-123');
  await tester.enterText(
      find.byKey(const Key('confirm_password_field')), 'nova-senha-123');
}

Future<void> _pumpAccount(
  WidgetTester tester,
  FakeAccountRepository accountRepository,
) async {
  final bus = SessionExpiryBus();
  final auth = AuthController(
    repository: FakeAuthRepository(),
    expiryBus: bus,
    restoreOnCreate: false,
  );
  await auth.login(email: 'usuario@example.com', password: 'senha-valida');
  addTearDown(bus.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        accountRepositoryProvider.overrideWithValue(accountRepository),
      ],
      child: const MaterialApp(home: AccountPage()),
    ),
  );
}
