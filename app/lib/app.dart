import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/orders/order_edit_screen.dart';
import 'features/orders/orders_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/users/users_screen.dart';
import 'features/viettel/viettel_invoices_screen.dart';
import 'state/app_state.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authChanges = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, _) => authChanges.value++);
  ref.onDispose(authChanges.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/orders',
    refreshListenable: authChanges,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final atLogin = state.matchedLocation == '/login';
      if (!auth.isLoggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/orders';
      if (state.matchedLocation.startsWith('/users') && !(auth.user?.isAdmin ?? false)) return '/orders';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/orders/edit',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => OrderEditScreen(
          orderIds: (state.uri.queryParameters['ids'] ?? '').split(',').where((e) => e.isNotEmpty).toList(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/orders', pageBuilder: (_, _) => const NoTransitionPage(child: OrdersScreen())),
          GoRoute(path: '/viettel', pageBuilder: (_, _) => const NoTransitionPage(child: ViettelInvoicesScreen())),
          GoRoute(path: '/users', pageBuilder: (_, _) => const NoTransitionPage(child: UsersScreen())),
          GoRoute(path: '/settings', pageBuilder: (_, _) => const NoTransitionPage(child: SettingsScreen())),
        ],
      ),
    ],
  );
});

class InvoiceApp extends ConsumerWidget {
  const InvoiceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Hóa đơn điện tử',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
