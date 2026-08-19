import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppNavigationMenu extends StatelessWidget {
  const AppNavigationMenu({super.key});

  static const destinations = <({String path, String label, IconData icon})>[
    (path: '/dashboard', label: 'Dashboard', icon: Icons.dashboard_outlined),
    (path: '/prompts/new', label: 'Criar prompt', icon: Icons.auto_awesome),
    (path: '/prompts', label: 'Meus prompts', icon: Icons.history),
    (
      path: '/templates',
      label: 'Meus templates',
      icon: Icons.bookmarks_outlined
    ),
    (path: '/usage', label: 'Meu uso', icon: Icons.insights_outlined),
    (
      path: '/credits',
      label: 'Créditos e planos',
      icon: Icons.account_balance_wallet_outlined,
    ),
    (path: '/payments', label: 'Pagamentos', icon: Icons.receipt_long_outlined),
    (
      path: '/account',
      label: 'Minha conta',
      icon: Icons.manage_accounts_outlined
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('app_navigation_menu'),
      tooltip: 'Navegação principal',
      icon: const Icon(Icons.menu),
      onSelected: context.go,
      itemBuilder: (_) => destinations
          .map(
            (destination) => PopupMenuItem<String>(
              value: destination.path,
              child: ListTile(
                leading: Icon(destination.icon),
                title: Text(destination.label),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          )
          .toList(),
    );
  }
}
