import 'package:flutter/foundation.dart';

class StreamConfig {
  const StreamConfig._();

  static const String apiKey = String.fromEnvironment(
    'MESSEYA_STREAM_API_KEY',
    defaultValue: '53xxk3b6a588',
  );

  static const String tokenProviderUrl = String.fromEnvironment(
    'MESSEYA_STREAM_TOKEN_PROVIDER_URL',
    defaultValue: '',
  );

  static const String tokenProviderUrlsRaw = String.fromEnvironment(
    'MESSEYA_STREAM_TOKEN_PROVIDER_URLS',
    defaultValue: '',
  );

  static const bool useDevelopmentToken = bool.fromEnvironment(
    'MESSEYA_STREAM_DEV_TOKEN',
    defaultValue: false,
  );

  static bool get isConfigured => apiKey.trim().isNotEmpty;

  static bool get shouldUseDevelopmentToken {
    if (!isConfigured) return false;
    return useDevelopmentToken;
  }

  static List<String> get tokenProviderUrls {
    final configuredUrls = <String>{
      ...tokenProviderUrlsRaw
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
      if (tokenProviderUrl.trim().isNotEmpty) tokenProviderUrl.trim(),
    };

    if (configuredUrls.isEmpty) {
      return const <String>[];
    }

    if (kReleaseMode) {
      return configuredUrls.toList(growable: false);
    }

    final expanded = <String>{...configuredUrls};
    for (final value in configuredUrls) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.isEmpty) continue;

      if (uri.host == '10.0.2.2') {
        expanded.add(uri.replace(host: '10.0.3.2').toString());
      } else if (uri.host == '10.0.3.2') {
        expanded.add(uri.replace(host: '10.0.2.2').toString());
      } else if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
        expanded.add(uri.replace(host: '10.0.2.2').toString());
        expanded.add(uri.replace(host: '10.0.3.2').toString());
      }
    }

    return expanded.toList(growable: false);
  }
}
