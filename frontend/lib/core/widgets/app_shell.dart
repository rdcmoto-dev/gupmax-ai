import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../theme/app_theme.dart';
import 'app_navigation_menu.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.location, required this.child, super.key});
  final String location;
  final Widget child;
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _collapsed = false;
  bool _showExpandedContent = true;
  bool _transitioning = false;
  bool _selected(String path) =>
      widget.location == path || widget.location.startsWith('$path/');

  Future<void> _toggleSidebar() async {
    if (_transitioning) return;
    _transitioning = true;
    if (_collapsed) {
      setState(() => _collapsed = false);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (mounted) setState(() => _showExpandedContent = true);
    } else {
      setState(() => _showExpandedContent = false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (mounted) setState(() => _collapsed = true);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    _transitioning = false;
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 960) return widget.child;
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: Row(children: [
        AnimatedContainer(
          key: const Key('app_sidebar'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: _collapsed ? 84 : 252,
          color: AppColors.midnightBlue,
          child: SafeArea(
              child: Column(children: [
            _Header(
              collapsed: !_showExpandedContent,
              onToggle: _toggleSidebar,
            ),
            Expanded(
                child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final destination in AppNavigationMenu.destinations)
                  _NavigationItem(
                    destination: destination,
                    collapsed: !_showExpandedContent,
                    selected: _selected(destination.path),
                    onTap: () => context.go(destination.path),
                  ),
              ],
            )),
            _AccountArea(
              collapsed: !_showExpandedContent,
              name: auth.user?.fullName ?? 'Minha conta',
              initials: _initials(auth.user?.fullName),
              signingOut: auth.isSubmitting,
              onLogout: auth.logout,
            ),
          ])),
        ),
        Expanded(
            child: DecoratedBox(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.background,
              Color(0xFFF7FCFF),
              Color(0xFFDCEEFF)
            ],
          )),
          child: widget.child,
        )),
      ]),
    );
  }

  static String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    final result = parts.map((part) => part[0].toUpperCase()).join();
    return result.isEmpty ? 'G' : result;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.collapsed, required this.onToggle});
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BrandMark(),
            const SizedBox(height: 6),
            IconButton(
              key: const Key('sidebar_toggle'),
              tooltip: 'Expandir navegação',
              color: const Color(0xFFDCE7F7),
              onPressed: onToggle,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 8, 18),
      child: Row(
        children: [
          const _BrandMark(),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'GUPMAX AI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            key: const Key('sidebar_toggle'),
            tooltip: 'Recolher navegação',
            color: const Color(0xFFDCE7F7),
            onPressed: onToggle,
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'GUPMAX AI',
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.cyanGlow, AppColors.violet]),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.lightGold),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
      );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem(
      {required this.destination,
      required this.collapsed,
      required this.selected,
      required this.onTap});
  final ({String path, String label, IconData icon}) destination;
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Tooltip(
          message: collapsed ? destination.label : '',
          child: Semantics(
            button: true,
            selected: selected,
            label: destination.label,
            child: Material(
              color: selected
                  ? AppColors.electricBlue.withValues(alpha: .25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: collapsed ? 18 : 16),
                selected: selected,
                selectedColor: Colors.white,
                textColor: const Color(0xFFDCE7F7),
                iconColor:
                    selected ? AppColors.cyanGlow : const Color(0xFFAFC2DB),
                leading: Icon(destination.icon),
                title: collapsed
                    ? null
                    : Text(destination.label,
                        style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: selected
                        ? BorderSide(
                            color: AppColors.cyanGlow.withValues(alpha: .8))
                        : BorderSide.none),
                onTap: onTap,
              ),
            ),
          ),
        ),
      );
}

class _AccountArea extends StatelessWidget {
  const _AccountArea(
      {required this.collapsed,
      required this.name,
      required this.initials,
      required this.signingOut,
      required this.onLogout});
  final bool collapsed;
  final String name;
  final String initials;
  final bool signingOut;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withValues(alpha: .7))),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                    message: name,
                    child: CircleAvatar(
                        backgroundColor: AppColors.violet,
                        foregroundColor: Colors.white,
                        child: Text(initials))),
                const SizedBox(height: 6),
                IconButton(
                    tooltip: 'Sair',
                    onPressed: signingOut ? null : onLogout,
                    color: AppColors.lightGold,
                    icon: const Icon(Icons.logout_rounded)),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gold.withValues(alpha: .7))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            CircleAvatar(
                backgroundColor: AppColors.violet,
                foregroundColor: Colors.white,
                child: Text(initials)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700))),
            IconButton(
                tooltip: 'Sair',
                onPressed: signingOut ? null : onLogout,
                color: AppColors.lightGold,
                icon: const Icon(Icons.logout_rounded)),
          ]),
        ),
      ),
    );
  }
}
