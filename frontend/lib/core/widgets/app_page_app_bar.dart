import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_navigation_menu.dart';

class AppPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppPageAppBar({
    required this.title,
    this.actions = const [],
    this.fallbackLocation = '/dashboard',
    this.showNavigationMenu = true,
    super.key,
  });

  final String title;
  final List<Widget> actions;
  final String fallbackLocation;
  final bool showNavigationMenu;

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackLocation);
    }
  }

  @override
  Widget build(BuildContext context) => AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: Row(
          children: [
            TextButton.icon(
              key: const Key('app_back_button'),
              onPressed: () => _back(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          ...actions,
          IconButton(
            key: const Key('app_home_button'),
            tooltip: 'Início',
            onPressed: () => context.go('/dashboard'),
            icon: const Icon(Icons.home_outlined),
          ),
          if (showNavigationMenu) const AppNavigationMenu(),
          const SizedBox(width: 8),
        ],
      );

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
