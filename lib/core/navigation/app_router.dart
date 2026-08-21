import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shuttle/core/navigation/app_routes.dart';
import 'package:shuttle/core/widgets/window_chrome.dart';
import 'package:shuttle/features/appearance/presentation/pages/appearance_page.dart';
import 'package:shuttle/features/history/presentation/pages/history_page.dart';
import 'package:shuttle/features/shell/presentation/pages/guide_page.dart';
import 'package:shuttle/features/shell/presentation/pages/home_page.dart';
import 'package:shuttle/features/shell/presentation/widgets/app_scope.dart';
import 'package:shuttle/features/transfer/presentation/pages/peer_page.dart';

/// The app's routes.
///
/// go_router rather than raw `Navigator.push` calls: the destinations are
/// declared in one place, the peer screen is addressable by its host and port
/// rather than by whatever object the caller happened to hold, and back
/// behaviour is the router's problem rather than each page's.
abstract final class AppRouter {
  static GoRouter build() => GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      // A shell with no chrome of its own: it exists so every route below it
      // shares one set of providers.
      //
      // This is load-bearing. Nested `routes:` in go_router are *not* widget
      // descendants of their parent — they are siblings pushed onto the same
      // navigator — so providing the blocs inside the home page left every
      // pushed screen outside them, and opening the guide threw a
      // ProviderNotFound the moment it read the server address.
      ShellRoute(
        // The titlebar inset wraps the scope so every route below it — tabs
        // and pushed screens alike — starts clear of the macOS traffic lights.
        builder: (context, state, child) =>
            MacTitlebarInset(child: AppScope(child: child)),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            name: RouteNames.home,
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: AppRoutes.history,
            name: RouteNames.history,
            pageBuilder: (context, state) =>
                _slideUp(state, const HistoryPage()),
          ),
          GoRoute(
            path: AppRoutes.guide,
            name: RouteNames.guide,
            pageBuilder: (context, state) => _slideUp(state, const GuidePage()),
          ),
          GoRoute(
            path: AppRoutes.appearance,
            name: RouteNames.appearance,
            pageBuilder: (context, state) =>
                _slideUp(state, const AppearancePage()),
          ),
          GoRoute(
            path: AppRoutes.peer,
            name: RouteNames.peer,
            builder: (context, state) {
              final host = state.pathParameters['host'] ?? '';
              final port =
                  int.tryParse(state.pathParameters['port'] ?? '') ?? 0;
              return PeerPage(
                // The name is decoration; the address is what identifies the
                // peer, so a link without one still works.
                name: state.uri.queryParameters['name'] ?? host,
                host: host,
                port: port,
              );
            },
          ),
        ],
      ),
    ],
  );

  /// Secondary screens rise from the bottom — they are detours from the tabs,
  /// not steps deeper into them.
  static CustomTransitionPage<void> _slideUp(
    GoRouterState state,
    Widget child,
  ) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondary, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: child,
    );
  }
}
