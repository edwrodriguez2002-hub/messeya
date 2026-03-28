class BackendConfig {
  const BackendConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'MESSEYA_API_BASE_URL',
    defaultValue: '',
  );

  static bool get hasApiBaseUrl => apiBaseUrl.trim().isNotEmpty;

  static Uri buildUri(String path) {
    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      throw StateError('MESSEYA_API_BASE_URL no esta configurado.');
    }
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }
}
