class OneSignalConfig {
  const OneSignalConfig._();

  static const String appId = String.fromEnvironment(
    'MESSEYA_ONESIGNAL_APP_ID',
    defaultValue: '9fd1dc1a-2fd4-4b44-a964-ea92778f0473',
  );

  static bool get isConfigured => appId.trim().isNotEmpty;
}
