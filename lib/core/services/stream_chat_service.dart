import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:stream_chat_flutter_core/stream_chat_flutter_core.dart';

import '../config/stream_config.dart';

final streamChatServiceProvider = Provider<StreamChatService>((ref) {
  final service = StreamChatService();
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

final streamChatClientProvider = Provider<StreamChatClient?>((ref) {
  return ref.watch(streamChatServiceProvider).client;
});

class StreamChatService {
  StreamChatService()
      : _client = StreamConfig.isConfigured
            ? StreamChatClient(
                StreamConfig.apiKey,
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                logLevel: Level.INFO,
              )
            : null;

  final StreamChatClient? _client;
  String? _connectedUserId;
  firebase_auth.User? _lastAuthUser;
  bool _appActive = true;
  Future<void>? _syncAuthFuture;
  String? _syncAuthTargetUserId;

  StreamChatClient? get client => _client;
  bool get isConfigured => _client != null;

  Future<StreamChatClient?> waitForConnectedClient({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final client = _client;
    if (client == null) return null;
    if (client.state.currentUser != null) return client;

    if (_appActive && _lastAuthUser != null) {
      try {
        await syncAuthUser(_lastAuthUser);
      } catch (_) {}
      if (client.state.currentUser != null) return client;
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (client.state.currentUser != null) {
        return client;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    return client.state.currentUser != null ? client : null;
  }

  Future<StreamChatClient> requireConnectedClient({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final client = await waitForConnectedClient(timeout: timeout);
    if (client == null || client.state.currentUser == null) {
      throw StateError(
        'Stream Chat aun no esta conectado. Abre la app un momento y vuelve a intentar.',
      );
    }
    return client;
  }

  Future<void> syncAuthUser(firebase_auth.User? firebaseUser) async {
    _lastAuthUser = firebaseUser;
    final desiredUserId = (_appActive && firebaseUser != null) ? firebaseUser.uid : null;

    final inFlightSync = _syncAuthFuture;
    if (inFlightSync != null) {
      if (_syncAuthTargetUserId == desiredUserId) {
        await inFlightSync;
        return;
      }

      try {
        await inFlightSync;
      } catch (_) {}
    }

    final operation = _performSyncAuthUser(firebaseUser);
    _syncAuthFuture = operation;
    _syncAuthTargetUserId = desiredUserId;

    try {
      await operation;
    } finally {
      if (identical(_syncAuthFuture, operation)) {
        _syncAuthFuture = null;
        _syncAuthTargetUserId = null;
      }
    }
  }

  Future<void> _performSyncAuthUser(firebase_auth.User? firebaseUser) async {
    final client = _client;
    if (client == null) return;

    if (firebaseUser == null) {
      if (_connectedUserId != null) {
        await client.disconnectUser();
        _connectedUserId = null;
      }
      return;
    }

    if (!_appActive) {
      return;
    }

    if (_connectedUserId == firebaseUser.uid && client.state.currentUser != null) {
      return;
    }

    if (_connectedUserId != null) {
      await client.disconnectUser();
      _connectedUserId = null;
    }

    final token = await _resolveToken(firebaseUser, client);
    final user = User(
      id: firebaseUser.uid,
      name: _resolveDisplayName(firebaseUser),
      image: firebaseUser.photoURL,
      extraData: {
        'email': firebaseUser.email ?? '',
      },
    );

    await client.connectUser(user, token);
    _connectedUserId = firebaseUser.uid;

    debugPrint(
      'Stream Chat: usuario conectado ${firebaseUser.uid} '
      '(${StreamConfig.shouldUseDevelopmentToken ? 'dev-token' : 'token-provider'})',
    );
  }

  Future<void> setAppActive(bool isActive) async {
    final client = _client;
    if (client == null) return;
    if (_appActive == isActive) return;
    _appActive = isActive;

    if (!isActive) {
      if (_connectedUserId != null || client.state.currentUser != null) {
        await client.disconnectUser();
        _connectedUserId = null;
        debugPrint('Stream Chat: usuario desconectado por app en segundo plano.');
      }
      return;
    }

    final authUser = _lastAuthUser;
    if (authUser != null) {
      await syncAuthUser(authUser);
    }
  }

  Future<void> dispose() async {
    final client = _client;
    if (client == null) return;
    if (_connectedUserId != null) {
      await client.disconnectUser();
    }
    await client.dispose();
    _connectedUserId = null;
  }

  Future<String> _resolveToken(
    firebase_auth.User firebaseUser,
    StreamChatClient client,
  ) async {
    if (StreamConfig.shouldUseDevelopmentToken) {
      return client.devToken(firebaseUser.uid).rawValue;
    }

    final urls = StreamConfig.tokenProviderUrls;
    if (urls.isEmpty) {
      throw StateError(
        'Stream Chat no esta configurado. Define '
        'MESSEYA_STREAM_TOKEN_PROVIDER_URL'
        ' o MESSEYA_STREAM_TOKEN_PROVIDER_URLS.',
      );
    }

    final firebaseToken = await firebaseUser.getIdToken();
    final errors = <String>[];

    for (final url in urls) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $firebaseToken',
              },
              body: jsonEncode({
                'userId': firebaseUser.uid,
              }),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError(
            'No se pudo obtener el token de Stream (${response.statusCode}).',
          );
        }

        final payload = jsonDecode(response.body);
        final token = payload is Map<String, dynamic>
            ? (payload['token'] as String? ?? '').trim()
            : '';
        if (token.isEmpty) {
          throw StateError('El token provider de Stream respondio sin token.');
        }

        if (!kReleaseMode && url != urls.first) {
          debugPrint('Stream Chat: token provider alcanzado usando $url');
        }

        return token;
      } catch (error) {
        errors.add('$url -> $error');
      }
    }

    throw StateError(
      'No se pudo conectar con el token provider de Stream. '
      'Intentos: ${errors.join(' | ')}',
    );
  }

  String _resolveDisplayName(firebase_auth.User firebaseUser) {
    final displayName = firebaseUser.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;

    final email = firebaseUser.email?.trim() ?? '';
    if (email.isNotEmpty) return email.split('@').first;

    return 'Usuario Messeya';
  }
}
