import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../auth_providers.dart';
import 'auth_scaffold.dart';
import 'auth_validators.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authControllerProvider).login(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return AuthScaffold(
      title: 'Bem-vindo ao GUPMAX AI',
      subtitle: 'Entre para acessar sua conta.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('login_email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: 'E-mail', prefixIcon: Icon(Icons.email_outlined)),
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('login_password'),
              controller: _passwordController,
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => auth.isSubmitting ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility),
                ),
              ),
              validator: AuthValidators.password,
            ),
            if (auth.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                auth.errorMessage!,
                key: const Key('auth_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('login_submit'),
              onPressed: auth.isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.electricBlue,
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.gold, width: 1.5),
                elevation: 5,
                shadowColor: AppColors.cyanGlow,
                minimumSize: const Size.fromHeight(54),
              ),
              icon: auth.isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login_rounded),
              label: Text(auth.isSubmitting ? 'Entrando...' : 'Entrar'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed:
                  auth.isSubmitting ? null : () => context.go('/register'),
              child: const Text('Criar uma conta'),
            ),
          ],
        ),
      ),
    );
  }
}
