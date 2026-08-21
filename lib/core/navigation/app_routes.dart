/// Every destination in the app, named once.
///
/// Paths and names live together so a typo is a compile error at the call
/// site rather than a blank screen at runtime.
abstract final class AppRoutes {
  static const String home = '/';

  static const String history = '/history';
  static const String guide = '/guide';
  static const String appearance = '/appearance';

  /// Takes the peer's address, so a link identifies which device it means.
  static const String peer = '/peer/:host/:port';

  static String peerPath({
    required String host,
    required int port,
    required String name,
  }) => '/peer/$host/$port?name=${Uri.encodeComponent(name)}';
}

abstract final class RouteNames {
  static const String home = 'home';
  static const String history = 'history';
  static const String guide = 'guide';
  static const String appearance = 'appearance';
  static const String peer = 'peer';
}
