import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../account_providers.dart';
import 'account_controller.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _profileKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmationController = TextEditingController();
  String? _loadedUserId;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(ref.read(accountControllerProvider).load);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _fillProfile(AuthUser user) {
    if (_loadedUserId == user.id) return;
    _loadedUserId = user.id;
    _nameController.text = user.fullName;
    _emailController.text = user.email;
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final user = account.user;
    if (user != null) _fillProfile(user);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha conta'),
        leading: IconButton(
          tooltip: 'Voltar ao dashboard',
          onPressed: () => context.go('/dashboard'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: account.isLoading && user == null
          ? const Center(child: CircularProgressIndicator())
          : account.error != null && user == null
              ? _LoadError(message: account.error!, onRetry: account.load)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Perfil e segurança',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Gerencie seus dados pessoais e sua senha.',
                          ),
                          if (account.error != null) ...[
                            const SizedBox(height: 16),
                            _MessageBanner(
                              message: account.error!,
                              isError: true,
                            ),
                          ],
                          if (account.successMessage != null) ...[
                            const SizedBox(height: 16),
                            _MessageBanner(message: account.successMessage!),
                          ],
                          const SizedBox(height: 24),
                          if (user != null) ...[
                            _buildProfileCard(context, account, user),
                            const SizedBox(height: 20),
                            _buildPasswordCard(context, account),
                            const SizedBox(height: 20),
                            _buildAccountStatusCard(context, user),
                            const SizedBox(height: 20),
                            _buildSessionCard(context, auth),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildProfileCard(
    BuildContext context,
    AccountController account,
    AuthUser user,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _profileKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Dados pessoais',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('account_name_field'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome'),
                textInputAction: TextInputAction.next,
                validator: (value) => (value ?? '').trim().length < 2
                    ? 'Informe um nome com pelo menos 2 caracteres.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('account_email_field'),
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'E-mail'),
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('save_profile_button'),
                  onPressed: account.isSavingProfile
                      ? null
                      : () async {
                          if (!_profileKey.currentState!.validate()) return;
                          final updated = await account.updateProfile(
                            fullName: _nameController.text,
                            email: _emailController.text,
                          );
                          if (updated != null) {
                            ref.read(authControllerProvider).syncUser(updated);
                          }
                        },
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    account.isSavingProfile ? 'Salvando...' : 'Salvar perfil',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordCard(BuildContext context, AccountController account) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _passwordKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Alterar senha',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('current_password_field'),
                controller: _currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha atual'),
                validator: (value) =>
                    (value ?? '').isEmpty ? 'Informe sua senha atual.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('new_password_field'),
                controller: _newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nova senha'),
                validator: (value) => (value ?? '').length < 8
                    ? 'A nova senha deve ter pelo menos 8 caracteres.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('confirm_password_field'),
                controller: _confirmationController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirmar nova senha'),
                validator: (value) => value != _newPasswordController.text
                    ? 'As senhas não coincidem.'
                    : null,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('change_password_button'),
                  onPressed: account.isChangingPassword
                      ? null
                      : () async {
                          if (!_passwordKey.currentState!.validate()) return;
                          final changed = await account.changePassword(
                            currentPassword: _currentPasswordController.text,
                            newPassword: _newPasswordController.text,
                          );
                          if (changed) {
                            _currentPasswordController.clear();
                            _newPasswordController.clear();
                            _confirmationController.clear();
                          }
                        },
                  icon: const Icon(Icons.lock_reset),
                  label: Text(account.isChangingPassword
                      ? 'Alterando...'
                      : 'Alterar senha'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountStatusCard(BuildContext context, AuthUser user) {
    final role = user.role == 'admin' ? 'Administrador' : 'Usuário';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Conta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Perfil: $role'),
            const SizedBox(height: 8),
            Text('Status: ${user.isActive ? 'Ativo' : 'Inativo'}'),
            const SizedBox(height: 8),
            Text('Criada em: ${_formatDate(user.createdAt)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context, AuthController auth) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sessão', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Encerre sua sessão neste dispositivo.'),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const Key('account_logout_button'),
                onPressed: auth.isSubmitting ? null : auth.logout,
                icon: const Icon(Icons.logout),
                label: const Text('Sair da conta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  final email = (value ?? '').trim();
  final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  return valid ? null : 'Informe um e-mail válido.';
}

String _formatDate(DateTime value) => '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

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
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('retry_account_button'),
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isError ? colors.errorContainer : colors.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(
            color:
                isError ? colors.onErrorContainer : colors.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
