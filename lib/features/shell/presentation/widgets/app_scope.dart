import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/core/di/injection.dart';
import 'package:shuttle/features/discovery/presentation/bloc/discovery_cubit.dart';
import 'package:shuttle/features/history/presentation/bloc/history_cubit.dart';
import 'package:shuttle/features/identity/presentation/bloc/identity_cubit.dart';
import 'package:shuttle/features/sharing/presentation/bloc/sharing_bloc.dart';

/// The blocs shared across the signed-in app, provided once around every
/// route that needs them.
///
/// This lives in a `ShellRoute` rather than inside the home page. go_router's
/// nested routes are *not* widget descendants of their parent — only a shell
/// nests widgets — so a page pushed from the tabs sat outside the home
/// page's providers and threw on the first `context.read`. Wrapping the shell
/// puts home and everything reachable from it in one scope.
///
/// Still not singletons: these are factories from the container, created when
/// the shell mounts and disposed with it. The server, the mDNS registration
/// and the log they reflect live in repositories underneath.
class AppScope extends StatelessWidget {
  const AppScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<IdentityCubit>()),
        BlocProvider(
          create: (_) => sl<SharingBloc>()..add(const SharingStarted()),
        ),
        BlocProvider(create: (_) => sl<DiscoveryCubit>()),
        BlocProvider(create: (_) => sl<HistoryCubit>()),
      ],
      child: child,
    );
  }
}
