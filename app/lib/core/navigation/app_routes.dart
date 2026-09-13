abstract final class AppRoutes {
  static const String appShell = '/app';

  static String normalize(String? routeName) {
    // Flutter is the mobile client. Legacy root links and unknown routes also
    // open its five-tab shell; the public landing page is owned by native Web.
    return appShell;
  }
}
