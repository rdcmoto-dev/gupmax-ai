import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final roleLabel = user.role == 'admin' ? 'Administrador' : 'Usuário';
    return Scaffold(
      appBar: AppBar(
        title: const Text('GUPMAX AI'),
        actions: [
          TextButton.icon(
            key: const Key('logout_button'),
            onPressed: auth.isSubmitting ? null : auth.logout,
            icon: const Icon(Icons.logout),
            label: const Text('Sair'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Olá, ${user.fullName}',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text('Sua sessão está conectada ao backend GUPMAX AI.'),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      key: const Key('create_prompt_button'),
                      onPressed: () => context.go('/prompts/new'),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Criar prompt'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('my_prompts_button'),
                      onPressed: () => context.go('/prompts'),
                      icon: const Icon(Icons.history),
                      label: const Text('Meus prompts'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('my_usage_button'),
                      onPressed: () => context.go('/usage'),
                      icon: const Icon(Icons.insights_outlined),
                      label: const Text('Meu uso'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sua conta',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 20),
                        _UserDetail(
                            icon: Icons.person_outline,
                            label: 'Nome',
                            value: user.fullName),
                        _UserDetail(
                            icon: Icons.email_outlined,
                            label: 'E-mail',
                            value: user.email),
                        _UserDetail(
                            icon: Icons.badge_outlined,
                            label: 'Perfil',
                            value: roleLabel),
                        _UserDetail(
                          icon: user.isActive
                              ? Icons.check_circle_outline
                              : Icons.block,
                          label: 'Status',
                          value: user.isActive ? 'Ativo' : 'Inativo',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserDetail extends StatelessWidget {
  const _UserDetail(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                Text(value, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
