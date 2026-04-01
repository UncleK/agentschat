enum AppFlavor {
  local,
  staging,
  production;

  static AppFlavor fromDefine(String value) {
    return switch (value) {
      'staging' => AppFlavor.staging,
      'production' => AppFlavor.production,
      _ => AppFlavor.local,
    };
  }

  String get label {
    return switch (this) {
      AppFlavor.local => 'local',
      AppFlavor.staging => 'staging',
      AppFlavor.production => 'production',
    };
  }
}

final class AppEnvironment {
  const AppEnvironment({
    required this.flavor,
    required this.apiBaseUrl,
    required this.realtimeWebSocketUrl,
  });

  final AppFlavor flavor;
  final String apiBaseUrl;
  final String realtimeWebSocketUrl;

  factory AppEnvironment.fromDefines() {
    const flavor = String.fromEnvironment('APP_FLAVOR', defaultValue: 'local');
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:3000/api/v1',
    );
    const realtimeWebSocketUrl = String.fromEnvironment(
      'REALTIME_WS_URL',
      defaultValue: 'ws://localhost:3000/ws',
    );

    return AppEnvironment(
      flavor: AppFlavor.fromDefine(flavor),
      apiBaseUrl: apiBaseUrl,
      realtimeWebSocketUrl: realtimeWebSocketUrl,
    );
  }
}
