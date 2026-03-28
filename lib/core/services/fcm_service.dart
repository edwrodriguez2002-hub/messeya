import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import '../../routing/app_router.dart';
import '../firebase/firebase_providers.dart';
import 'local_notifications_service.dart';

final localNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>(
  (ref) => FlutterLocalNotificationsPlugin(),
);

final localNotificationsServiceProvider = Provider<LocalNotificationsService>(
  (ref) => LocalNotificationsService(
    ref.watch(localNotificationsPluginProvider),
  ),
);

final fcmServiceProvider = Provider<FcmService>(
  (ref) => FcmService(
    ref.watch(firebaseMessagingProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
    ref.watch(localNotificationsServiceProvider),
  ),
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (message.notification != null) {
    // Android ya muestra las notificaciones remotas con bloque notification
    // cuando la app esta en segundo plano o terminada.
    return;
  }
  await LocalNotificationsService.initializeBackground();
  final title = message.notification?.title ??
      message.data['title']?.toString() ??
      'Messeya';
  final body = message.notification?.body ??
      message.data['body']?.toString() ??
      'Tienes una nueva notificacion.';
  final payload = message.data['route']?.toString() ?? '/home';
  final type = message.data['type']?.toString() ?? 'message';
  final notificationId =
      message.data['notificationId']?.toString() ?? message.messageId;
  await LocalNotificationsService.showBackgroundRemoteNotification(
    title: title,
    body: body,
    payload: payload,
    isCall: type == 'call',
    notificationId: notificationId,
  );
}

class FcmService {
  FcmService(
    this._messaging,
    this._auth,
    this._firestore,
    this._localNotifications,
  );

  final FirebaseMessaging _messaging;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final LocalNotificationsService _localNotifications;

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final launchPayload = await _localNotifications.initialize(
        onPayloadTap: _handleNotificationPayload,
      );
      await _messaging.setAutoInitEnabled(true);
      final permissionSettings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
        (message) async {
          await _showRemoteMessageLocally(message);
        },
      );

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final payload = message.data['route']?.toString();
        if (payload != null && payload.isNotEmpty) {
          _handleNotificationPayload(payload);
        }
      });

      final initialMessage = await _messaging.getInitialMessage();
      final initialPayload = initialMessage?.data['route']?.toString();
      final startupPayload = launchPayload != null && launchPayload.isNotEmpty
          ? launchPayload
          : initialPayload;
      if (startupPayload != null && startupPayload.isNotEmpty) {
        Future<void>.delayed(
          const Duration(milliseconds: 600),
          () => _handleNotificationPayload(startupPayload),
        );
      }

      _authSubscription ??= _auth.authStateChanges().listen((user) async {
        if (user == null || user.isAnonymous) return;
        await _syncTokenForUser(user.uid);
      });

      _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((token) {
        final user = _auth.currentUser;
        if (user == null || user.isAnonymous) return;
        _persistToken(user.uid, token);
      });

      final user = _auth.currentUser;
      if (user != null && !user.isAnonymous) {
        await _syncTokenForUser(user.uid);
      }

      if (permissionSettings.authorizationStatus ==
          AuthorizationStatus.denied) {
        debugPrint('FCM notifications permission denied by user.');
      }

      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('FCM init skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> showChatPreviewNotification({
    required String title,
    required String body,
    required String route,
    String? notificationId,
  }) async {
    await _localNotifications.showChatNotification(
      title: title,
      body: body,
      payload: route,
      notificationId: notificationId,
    );
  }

  Future<void> showIncomingCallSystemNotification({
    required String callerName,
    required bool isVideo,
    String route = '/calls',
    String? notificationId,
  }) async {
    await _localNotifications.showIncomingCallNotification(
      callerName: callerName,
      isVideo: isVideo,
      payload: route,
      notificationId: notificationId,
    );
  }

  Future<void> _showRemoteMessageLocally(RemoteMessage message) async {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'Messeya';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        'Tienes una nueva notificacion.';
    final payload = message.data['route']?.toString() ?? '/home';
    final type = message.data['type']?.toString() ?? 'message';
    final notificationId =
        message.data['notificationId']?.toString() ?? message.messageId;

    if (type == 'call') {
      await _localNotifications.showIncomingCallNotification(
        callerName: title,
        isVideo: (message.data['callType']?.toString() ?? 'audio') == 'video',
        payload: payload,
        notificationId: notificationId,
      );
      return;
    }

    await _localNotifications.showChatNotification(
      title: title,
      body: body,
      payload: payload,
      notificationId: notificationId,
    );
  }

  void _handleNotificationPayload(String payload) {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    context.go(payload);
  }

  Future<void> _syncTokenForUser(String uid) async {
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _persistToken(uid, token);
  }

  Future<void> _persistToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set({
      'notificationTokens': FieldValue.arrayUnion([token]),
      'notificationTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
