import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation_menu.dart';
import '../../auth/auth_providers.dart';
import '../../projects/project_overview.dart';

const _dashboardProjectsQuery = ProjectOverviewQuery(limit: 4);
final recentProjectsProvider =
    projectOverviewsProvider(_dashboardProjectsQuery);

typedef RecentProjectItem = ProjectOverview;

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final recentProjects = ref.watch(recentProjectsProvider);
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final compact = MediaQuery.sizeOf(context).width < 600;
    final roleLabel = user.role == 'admin' ? 'Administrador' : 'Usuário';
    return Scaffold(
      appBar: AppBar(
        title: const Text('GUPMAX AI'),
        backgroundColor: AppColors.midnightBlue,
        foregroundColor: Colors.white,
        actions: [
          const AppNavigationMenu(),
          if (compact)
            IconButton(
              key: const Key('logout_button'),
              tooltip: 'Sair',
              onPressed: auth.isSubmitting ? null : auth.logout,
              icon: const Icon(Icons.logout),
            )
          else
            TextButton.icon(
              key: const Key('logout_button'),
              onPressed: auth.isSubmitting ? null : auth.logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sair'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.background,
              Color(0xFFF8FCFF),
              Color(0xFFDCEEFF),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WelcomePanel(
                    name: user.fullName,
                    onPrompts: () => context.go('/prompts'),
                    onUsage: () => context.go('/usage'),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(builder: (context, constraints) {
                    final width = constraints.maxWidth < 640
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _GoalCard(
                          key: const Key('create_prompt_button'),
                          width: width,
                          icon: Icons.auto_awesome,
                          colors: const [Color(0xFF16B9E8), Color(0xFF0874C9)],
                          title: 'Criar um prompt',
                          description:
                              'Transforme uma ideia em uma instrução clara.',
                          onTap: () => context.go('/prompts/new'),
                        ),
                        _GoalCard(
                          key: const Key('plan_project_button'),
                          width: width,
                          icon: Icons.account_tree_outlined,
                          colors: const [Color(0xFF44DC68), Color(0xFF0A9B55)],
                          title: 'Planejar um projeto',
                          description: 'Organize uma ideia complexa em etapas.',
                          onTap: () => context.go('/prompts/new?mode=expert'),
                        ),
                        _GoalCard(
                          key: const Key('compare_ai_button'),
                          width: width,
                          icon: Icons.compare_arrows,
                          colors: const [Color(0xFFC94FE5), Color(0xFF7A35C5)],
                          title: 'Comparar entre IAs',
                          description: 'Veja versões para diferentes destinos.',
                          onTap: () => context.go('/prompts/new?compare=true'),
                        ),
                        _GoalCard(
                          key: const Key('my_chains_button'),
                          width: width,
                          icon: Icons.route_outlined,
                          colors: const [Color(0xFFFF9C31), Color(0xFFE85B18)],
                          title: 'Continuar um fluxo',
                          description:
                              'Retome suas etapas e projetos em andamento.',
                          onTap: () => context.go('/chains'),
                        ),
                        _GoalCard(
                          key: const Key('my_templates_button'),
                          width: width,
                          icon: Icons.bookmarks_outlined,
                          colors: const [Color(0xFFFF4F88), Color(0xFFD91F61)],
                          title: 'Usar um template',
                          description:
                              'Comece a partir de um modelo reutilizável.',
                          onTap: () => context.go('/templates'),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 28),
                  _RecentProjectsSection(
                    value: recentProjects,
                    onOpen: (item) => context.go(item.route),
                    onCreate: () => context.go('/prompts/new?mode=expert'),
                    onSeeAll: () => context.go('/projects'),
                    onRetry: () => ref.invalidate(recentProjectsProvider),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Sua biblioteca e conta',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('my_projects_button'),
                        style: _dashboardOutlineStyle,
                        onPressed: () => context.go('/projects'),
                        icon: const Icon(Icons.folder_outlined),
                        label: const Text('Meus projetos'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('credits_and_plans_button'),
                        style: _dashboardOutlineStyle,
                        onPressed: () => context.go('/credits'),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Créditos e planos'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('my_account_button'),
                        style: _dashboardOutlineStyle,
                        onPressed: () => context.go('/account'),
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Minha conta'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('payments_button'),
                        style: _dashboardOutlineStyle,
                        onPressed: () => context.go('/payments'),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Pagamentos'),
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
      ),
    );
  }
}

class _RecentProjectsSection extends StatelessWidget {
  const _RecentProjectsSection({
    required this.value,
    required this.onOpen,
    required this.onCreate,
    required this.onSeeAll,
    required this.onRetry,
  });

  final AsyncValue<List<RecentProjectItem>> value;
  final ValueChanged<RecentProjectItem> onOpen;
  final VoidCallback onCreate;
  final VoidCallback onSeeAll;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Projetos recentes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton.icon(
                key: const Key('see_all_projects'),
                onPressed: onSeeAll,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: const Text('Ver todos os projetos'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          value.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => _RecentProjectsMessage(
              message: 'Não foi possível carregar seus projetos agora.',
              action: 'Tentar novamente',
              onPressed: onRetry,
            ),
            data: (items) => items.isEmpty
                ? _RecentProjectsMessage(
                    message: 'Você ainda não criou nenhum projeto.',
                    action: 'Criar meu primeiro projeto',
                    onPressed: onCreate,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth < 640
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final item in items)
                            _RecentProjectCard(
                              key: Key(
                                  'recent_project_${item.project?.id ?? item.chain!.id}'),
                              item: item,
                              width: width,
                              onPressed: () => onOpen(item),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      );
}

class _RecentProjectsMessage extends StatelessWidget {
  const _RecentProjectsMessage({
    required this.message,
    required this.action,
    required this.onPressed,
  });
  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.raisedSurface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(message),
              FilledButton.icon(
                key: const Key('create_first_project'),
                onPressed: onPressed,
                icon: const Icon(Icons.add),
                label: Text(action),
              ),
            ],
          ),
        ),
      );
}

class _RecentProjectCard extends StatelessWidget {
  const _RecentProjectCard({
    required this.item,
    required this.width,
    required this.onPressed,
    super.key,
  });
  final RecentProjectItem item;
  final double width;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          color: AppColors.raisedSurface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, color: AppColors.cyanGlow),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (item.categoryLabel case final category?)
                        Text(category),
                      if (item.progressLabel case final progress?)
                        Text(progress),
                      Text(item.statusLabel,
                          style: TextStyle(
                            color: item.statusLabel == 'Concluído'
                                ? Colors.green.shade700
                                : AppColors.oceanBlue,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: Key('open_recent_${item.project?.id ?? item.chain!.id}'),
                  onPressed: onPressed,
                  icon: Icon(item.canContinue
                      ? Icons.play_arrow_rounded
                      : Icons.folder_open_outlined),
                  label: Text(item.canContinue ? 'Continuar' : 'Abrir'),
                ),
              ],
            ),
          ),
        ),
      );
}

final _dashboardOutlineStyle = OutlinedButton.styleFrom(
  foregroundColor: AppColors.oceanBlue,
  backgroundColor: AppColors.raisedSurface,
  side: const BorderSide(color: AppColors.gold),
);

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

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({
    required this.name,
    required this.onPrompts,
    required this.onUsage,
  });

  final String name;
  final VoidCallback onPrompts;
  final VoidCallback onUsage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.oceanBlue, AppColors.midnightBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Olá, $name',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O que você quer fazer hoje?',
              style: TextStyle(
                color: AppColors.lightGold,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  key: const Key('my_prompts_button'),
                  onPressed: onPrompts,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('Ver meus prompts'),
                ),
                TextButton.icon(
                  key: const Key('my_usage_button'),
                  onPressed: onUsage,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.lightGold,
                    backgroundColor: AppColors.gold.withValues(alpha: 0.12),
                  ),
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('Ver meu uso'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.width,
    required this.icon,
    required this.colors,
    required this.title,
    required this.description,
    required this.onTap,
    super.key,
  });

  final double width;
  final IconData icon;
  final List<Color> colors;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 112,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.lightGold, AppColors.gold],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66D7B44A),
                blurRadius: 13,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        _AppIcon(icon: icon),
                        const SizedBox(width: 14),
                        Expanded(child: _GoalText(title, description)),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.17),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightGold, width: 1.5),
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      );
}

class _GoalText extends StatelessWidget {
  const _GoalText(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 3),
          Text(description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.25,
                  )),
        ],
      );
}
