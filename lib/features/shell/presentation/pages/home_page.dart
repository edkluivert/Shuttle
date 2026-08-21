import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/core/di/injection.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/widgets/app_ui.dart';
import 'package:shuttle/core/widgets/bounce_tap.dart';
import 'package:shuttle/features/discovery/domain/use_case/discovery_use_case.dart';
import 'package:shuttle/features/discovery/presentation/pages/receive_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shuttle/core/navigation/app_routes.dart';
import 'package:shuttle/features/identity/domain/use_case/identity_use_case.dart';
import 'package:shuttle/features/identity/presentation/bloc/identity_cubit.dart';
import 'package:shuttle/features/identity/presentation/widgets/rename_device_dialog.dart';
import 'package:shuttle/features/sharing/domain/use_case/sharing_use_case.dart';
import 'package:shuttle/features/sharing/presentation/bloc/sharing_bloc.dart';
import 'package:shuttle/features/sharing/presentation/pages/share_page.dart';
import 'package:shuttle/features/usb/presentation/bloc/usb_cubit.dart';
import 'package:shuttle/features/usb/presentation/pages/usb_page.dart';

/// The tabs.
///
/// The blocs it reads come from `AppScope` on the shell route, not from here.
/// Providing them at this page put every pushed screen outside the scope —
/// go_router's nested routes are siblings in the widget tree, not children.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static bool get showUsb => UsbCubit.isSupportedPlatform;

  @override
  Widget build(BuildContext context) => const _HomeView();
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> with WidgetsBindingObserver {
  int _index = 0;

  /// Use cases, not blocs: these are singletons, safe to hold and safe to
  /// call from dispose.
  final DiscoveryUseCase _discovery = sl<DiscoveryUseCase>();
  final SharingUseCase _sharing = sl<SharingUseCase>();
  final IdentityUseCase _identity = sl<IdentityUseCase>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _announce();
  }

  /// Advertise only once the server is up: registering a port nothing is
  /// listening on would put a dead entry on the network.
  Future<void> _announce() async {
    await _sharing.start();
    final port = _sharing.status().port;
    if (port == null) return;

    final identity = _identity.current();
    await _discovery.advertise(
      deviceId: identity.id,
      deviceName: identity.name,
      port: port,
    );
    await _discovery.startSearching();
  }

  /// Coming back to the app is when the peer list is most likely stale.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _discovery.refresh();

    // Going away for good. `dispose` is not guaranteed to run when the process
    // is torn down, and a registration left behind keeps advertising a port
    // nothing will ever answer on — it shows up on every other device as a
    // real, tappable entry that fails the moment you open it.
    if (state == AppLifecycleState.detached) {
      _discovery.stop();
      _sharing.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _discovery.stop();
    _sharing.stop();
    super.dispose();
  }

  Future<void> _rename() async {
    final name = await showRenameDeviceDialog(
      context,
      _identity.current().name,
    );
    if (name == null || !mounted) return;

    await context.read<IdentityCubit>().rename(name);

    // The name is baked into the mDNS registration, so it has to be
    // re-published for anyone to see the new one.
    final port = _sharing.status().port;
    if (port == null) return;
    final identity = _identity.current();
    await _discovery.advertise(
      deviceId: identity.id,
      deviceName: identity.name,
      port: port,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showUsb = HomePage.showUsb;
    final pages = [
      const SharePage(),
      const ReceivePage(),
      if (showUsb) const UsbPage(),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onRename: _rename),
            PillNav(
              index: _index,
              onSelect: (i) => setState(() => _index = i),
              destinations: [
                const NavDestination(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Share',
                ),
                const NavDestination(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Receive',
                ),
                if (showUsb)
                  const NavDestination(icon: Icons.usb_rounded, label: 'USB'),
              ],
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                // Cross-fade with a slight lift, so switching sections reads
                // as a change of view rather than a redraw.
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.015),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_index),
                  child: pages[_index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's own header: identity on the left, live status on the right.
class _Header extends StatelessWidget {
  const _Header({required this.onRename});

  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = context.select((IdentityCubit c) => c.state.identity.name);
    final online = context.select((SharingBloc b) => b.state.isOnline);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space5,
        AppTheme.space5,
        AppTheme.space4,
        AppTheme.space4,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: palette.heroGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.swap_vert_rounded,
              color: palette.onAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: AppTheme.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: context.type.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: onRename,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                Text('Shuttle', style: context.type.bodySmall),
              ],
            ),
          ),
          StatusPill(
            label: online ? 'Online' : 'Starting',
            tone: online ? StatusTone.live : StatusTone.idle,
            pulsing: online,
          ),
          const SizedBox(width: AppTheme.space1),
          _HeaderAction(
            tooltip: 'Appearance',
            icon: Icons.palette_outlined,
            onTap: () => context.pushNamed(RouteNames.appearance),
          ),
          _HeaderAction(
            tooltip: 'History',
            icon: Icons.history_rounded,
            onTap: () => context.pushNamed(RouteNames.history),
          ),
          _HeaderAction(
            tooltip: 'How it works',
            icon: Icons.help_outline_rounded,
            onTap: () => context.pushNamed(RouteNames.guide),
          ),
        ],
      ),
    );
  }
}

/// A header icon that presses in when tapped, like everything else here.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: BounceTap(
        onTap: onTap,
        minScale: 0.86,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space2),
          child: Icon(icon, size: 20, color: context.palette.textMuted),
        ),
      ),
    );
  }
}
