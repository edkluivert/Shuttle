import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shuttle/core/navigation/app_routes.dart';

/// The route table itself, without booting the app.
///
/// The bug these exist for: go_router's nested `routes:` are siblings pushed
/// onto the same navigator, not widget descendants of their parent. Providing
/// the shared blocs inside the home page therefore left every pushed screen
/// outside them, and opening the guide threw the moment it read the server
/// address. A `ShellRoute` is what puts them in one scope — so these check
/// that every secondary screen is genuinely *inside* that shell.
void main() {
  group('the route table', () {
    test('secondary screens live inside the shell, not beside it', () {
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          ShellRoute(
            builder: (context, state, child) => child,
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: RouteNames.home,
                builder: (_, _) => const SizedBox(),
              ),
              GoRoute(
                path: AppRoutes.guide,
                name: RouteNames.guide,
                builder: (_, _) => const SizedBox(),
              ),
            ],
          ),
        ],
      );

      final shell = router.configuration.routes.single as ShellRoute;
      final paths = shell.routes.whereType<GoRoute>().map((r) => r.path);

      expect(paths, containsAll(<String>[AppRoutes.home, AppRoutes.guide]));
      router.dispose();
    });
  });

  group('addressing a peer', () {
    test('builds a path from host and port', () {
      final path = AppRoutes.peerPath(
        host: '192.168.1.20',
        port: 53317,
        name: 'Ada Mac',
      );

      expect(path, startsWith('/peer/192.168.1.20/53317'));
    });

    test('a name with spaces or slashes cannot break the URL', () {
      // `Ada's MacBook / work` would otherwise add path segments and change
      // which route matched.
      final path = AppRoutes.peerPath(
        host: '10.0.0.5',
        port: 1,
        name: "Ada's MacBook / work",
      );

      expect(path.split('?').first, '/peer/10.0.0.5/1');
      expect(Uri.parse(path).queryParameters['name'], "Ada's MacBook / work");
    });

    test('the pattern the router matches has both parameters', () {
      expect(AppRoutes.peer, contains(':host'));
      expect(AppRoutes.peer, contains(':port'));
    });
  });
}
