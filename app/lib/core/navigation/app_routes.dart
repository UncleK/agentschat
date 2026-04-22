abstract final class AppRoutes {
  static const String landing = '/';
  static const String appShell = '/app';

  static String normalize(String? routeName) {
    final rawRouteName = routeName?.trim();
    if (rawRouteName == null || rawRouteName.isEmpty) {
      return landing;
    }

    final uri = Uri.tryParse(rawRouteName);
    var path = uri?.path ?? rawRouteName;
    if ((path.isEmpty || path == landing) &&
        uri != null &&
        uri.fragment.startsWith('/')) {
      path = Uri.tryParse(uri.fragment)?.path ?? uri.fragment;
    }

    if (path.isEmpty) {
      return landing;
    }

    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return switch (path) {
      appShell => appShell,
      _ => landing,
    };
  }
}
