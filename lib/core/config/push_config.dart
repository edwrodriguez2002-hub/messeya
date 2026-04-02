class PushConfig {
  const PushConfig._();

  static const String messagePushUrl = String.fromEnvironment(
    'MESSEYA_PUSH_MESSAGE_URL',
    defaultValue: 'http://192.168.101.81:3010/api/push-message',
  );
}
