import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/core/di/injection.dart';
import 'package:shuttle/core/navigation/app_router.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';
import 'package:shuttle/features/appearance/presentation/bloc/appearance_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const ShuttleApp());
}

class ShuttleApp extends StatelessWidget {
  const ShuttleApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Above MaterialApp, because the accent has to rebuild the whole tree.
    return BlocProvider(
      create: (_) => sl<AppearanceCubit>(),
      child: const _App(),
    );
  }
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  /// Built once and held: rebuilding the router on every theme change would
  /// throw away the navigation stack with it.
  final router = AppRouter.build();

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceCubit>().state.appearance;

    return MaterialApp.router(
      title: 'Shuttle',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(appearance.accent),
      darkTheme: AppTheme.dark(appearance.accent),
      themeMode: switch (appearance.mode) {
        ThemeModePreference.system => ThemeMode.system,
        ThemeModePreference.light => ThemeMode.light,
        ThemeModePreference.dark => ThemeMode.dark,
      },
      routerConfig: router,
    );
  }
}
