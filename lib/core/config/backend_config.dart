class BackendConfig {
  const BackendConfig._();

  // El backend legado para notificaciones/chat ya no se usa en la app.
  static const String apiBaseUrl = '';

  static bool get hasApiBaseUrl => false;

  static const String companySubscriptionProductId = String.fromEnvironment(
    'MESSEYA_COMPANY_SUBSCRIPTION_PRODUCT_ID',
    defaultValue: 'company_chat_business',
  );

  static const String androidPackageName = String.fromEnvironment(
    'MESSEYA_ANDROID_PACKAGE_NAME',
    defaultValue: 'com.messeya.chat',
  );

  static Uri buildUri(String path) {
    throw StateError('El backend legado ha sido desactivado en favor de Stream Chat.');
  }
}
