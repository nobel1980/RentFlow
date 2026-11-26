import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rentflow/features/dashboard/presentation/owner_shell_screen.dart';
import 'package:rentflow/features/tenant_portal/presentation/tenant_shell_screen.dart';

final appRouterProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    initialLocation: '/owner',
    routes: <RouteBase>[
      GoRoute(
        path: '/owner',
        name: 'owner',
        builder: (BuildContext context, GoRouterState state) =>
            const OwnerShellScreen(),
      ),
      GoRoute(
        path: '/tenant',
        name: 'tenant',
        builder: (BuildContext context, GoRouterState state) =>
            const TenantShellScreen(),
      ),
    ],
  );
});
