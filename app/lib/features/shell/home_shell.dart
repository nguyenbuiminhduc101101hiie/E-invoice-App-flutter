import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets.dart';
import '../../state/app_state.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.selectedIcon, {this.adminOnly = false});
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool adminOnly;
}

const _destinations = [
  _Destination('/orders', 'Đơn hàng', Icons.receipt_long_outlined, Icons.receipt_long),
  _Destination('/viettel', 'HĐ Viettel', Icons.cloud_outlined, Icons.cloud),
  _Destination('/users', 'Tài khoản', Icons.group_outlined, Icons.group, adminOnly: true),
  _Destination('/settings', 'Cài đặt', Icons.settings_outlined, Icons.settings),
];

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.user));
    final items = _destinations.where((d) => !d.adminOnly || (user?.isAdmin ?? false)).toList();
    final index = items.indexWhere((d) => location.startsWith(d.path)).clamp(0, items.length - 1);
    void go(int i) => context.go(items[i].path);
    final t = Theme.of(context);

    if (isWide(context)) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: go,
            extended: MediaQuery.sizeOf(context).width >= 1280,
            minExtendedWidth: 220,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.receipt_long_rounded, color: t.colorScheme.onPrimary),
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Tooltip(
                    message: '${user?.displayName ?? ''} (${user?.role ?? ''})',
                    child: CircleAvatar(
                      backgroundColor: t.colorScheme.secondaryContainer,
                      child: Text((user?.displayName ?? '?').characters.first.toUpperCase()),
                    ),
                  ),
                ),
              ),
            ),
            destinations: items
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: go,
        destinations: items
            .map((d) => NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label))
            .toList(),
      ),
    );
  }
}
