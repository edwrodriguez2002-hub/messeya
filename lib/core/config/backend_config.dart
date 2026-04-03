class BackendConfig {
  const BackendConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'MESSEYA_COMPANY_BILLING_URL',
    defaultValue: 'https://messeya-company-billing.onrender.com',
  );

  static bool get hasApiBaseUrl => apiBaseUrl.trim().isNotEmpty;

  static const String companySubscriptionProductId = String.fromEnvironment(
    'MESSEYA_COMPANY_SUBSCRIPTION_PRODUCT_ID',
    defaultValue: 'company_chat_business',
  );

  static const String androidPackageName = String.fromEnvironment(
    'MESSEYA_ANDROID_PACKAGE_NAME',
    defaultValue: 'com.messeya.chat',
  );

  static const String playStoreUrl = String.fromEnvironment(
    'MESSEYA_PLAY_STORE_URL',
    defaultValue: 'https://play.google.com/store/apps/details?id=com.messeya.chat',
  );

  static Uri buildUri(String path) {
    if (!hasApiBaseUrl) {
      throw StateError(
        'No hay backend configurado para verificar la suscripcion empresarial.',
      );
    }

    final normalizedBase = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }
}
