import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../theme/app_theme.dart';
import 'app_navigation_menu.dart';

class AppShell extends ConsumerWidget {
  const AppShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (MediaQuery.sizeOf(context).width < 960) return child;

    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 252,
            child: ColoredBox(
              color: AppColors.midnightBlue,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(22, 24, 18, 22),
                      child: Row(
                        children: [
                          _BrandMark(),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'GUPMAX AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final destination
                              in AppNavigationMenu.destinations)
                            _NavigationItem(
                              destination: destination,
                              selected: _isSelected(destination.path),
                              onTap: () => context.go(destination.path),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.violet,
                                foregroundColor: Colors.white,
                                child: Text(_initials(auth.user?.fullName)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  auth.user?.fullName ?? 'Minha conta',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Sair',
                                onPressed:
                                    auth.isSubmitting ? null : auth.logout,
                                color: AppColors.lightGold,
                                icon: const Icon(Icons.logout_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  bool _isSelected(String path) =>
      location == path || location.startsWith('$path/');

  static String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'G';
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.cyanGlow, AppColors.violet],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.lightGold),
        ),
        child: const Icon(Icons.auto_awesome, color: Colors.white),
      );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ({String path, String label, IconData icon}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Material(
          color: selected
              ? AppColors.violet.withValues(alpha: 0.32)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            selected: selected,
            tileColor: Colors.transparent,
            selectedTileColor: Colors.transparent,
            selectedColor: Colors.white,
            textColor: const Color(0xFFDCE7F7),
            iconColor: selected ? AppColors.lightGold : const Color(0xFFAFC2DB),
            leading: Icon(destination.icon),
            title: Text(
              destination.label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: selected
                  ? BorderSide(color: AppColors.gold.withValues(alpha: 0.7))
                  : BorderSide.none,
            ),
            onTap: onTap,
          ),
        ),
      );
}
