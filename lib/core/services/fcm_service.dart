import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
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
  debugPrint('Mensaje FCM recibido en background: ${message.messageId}');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  if (message.notification != null) return;

  await LocalNotificationsService.initializeBackground();
  
  final title = message.data['title']?.toString() ?? 'Messeya';
  String body = message.data['body']?.toString() ?? 'Tienes un nuevo mensaje.';
  
  if (body.startsWith('{') && body.contains('cipherText')) {
    body = '🔒 Mensaje cifrado';
  }

  final payload = message.data['route']?.toString() ?? '/home';
  final type = message.data['type']?.toString() ?? 'message';
  final notificationId = message.data['notificationId']?.toString() ?? message.messageId;

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

  bool _initialized = false;
  String? _registeredToken;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _localNotifications.initialize(onPayloadTap: _handleNotificationPayload);
      
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      if (Platform.isAndroid) {
        await Permission.notification.request();
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      FirebaseMessaging.onMessage.listen((message) async {
        await _showRemoteMessageLocally(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final payload = message.data['route']?.toString();
        if (payload != null) _handleNotificationPayload(payload);
      });

      _setupTokenSync();
      _initialized = true;
    } catch (e) {
      debugPrint('FCM Init Error: $e');
    }
  }

  void _setupTokenSync() {
    _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen((user) async {
      if (user == null || user.isAnonymous) {
        await _unregisterCurrentDeviceFromFirestore();
        return;
      }

      final token = await _messaging.getToken();
      if (token != null) {
        await _registerDeviceInFirestore(token);
      }
    });

    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      await _replaceRegisteredDevice(token);
    });
  }

  Future<void> deleteTokenOnLogout() async {
    await _unregisterCurrentDeviceFromFirestore();
    await _messaging.deleteToken();
    _registeredToken = null;
  }

  Future<void> _showRemoteMessageLocally(RemoteMessage message) async {
    final title = message.data['title']?.toString() ?? message.notification?.title ?? 'Messeya';
    String body = message.data['body']?.toString() ?? message.notification?.body ?? 'Nuevo mensaje';
    
    if (body.startsWith('{') && body.contains('cipherText')) {
      body = '🔒 Mensaje cifrado';
    }

    final payload = message.data['route']?.toString() ?? '/home';
    final type = message.data['type']?.toString() ?? 'message';

    if (type == 'call') {
      await _localNotifications.showIncomingCallNotification(
        callerName: title,
        isVideo: (message.data['callType']?.toString() ?? 'audio') == 'video',
        payload: payload,
      );
    } else {
      await _localNotifications.showChatNotification(
        title: title,
        body: body,
        payload: payload,
      );
    }
  }

  void _handleNotificationPayload(String payload) {
    rootNavigatorKey.currentContext?.go(payload);
  }

  Future<void> _replaceRegisteredDevice(String nextToken) async {
    if (_registeredToken == nextToken) return;

    await _unregisterCurrentDeviceFromFirestore();
    await _registerDeviceInFirestore(nextToken);
  }

  Future<void> _registerDeviceInFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      if (_registeredToken != null && _registeredToken != token) {
        await _usersLinkedDevices(user.uid).doc(_deviceDocId(_registeredToken!)).delete();
      }

      await _usersLinkedDevices(user.uid).doc(_deviceDocId(token)).set({
        'token': token,
        'platform': Platform.isAndroid ? 'android' : 'unknown',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _registeredToken = token;
      debugPrint('FCM Push: dispositivo registrado en Firestore.');
    } catch (error) {
      debugPrint('FCM Push: error registrando dispositivo: $error');
    }
  }

  Future<void> _unregisterCurrentDeviceFromFirestore() async {
    final token = _registeredToken;
    final user = _auth.currentUser;
    if (token == null || user == null) return;

    try {
      await _usersLinkedDevices(user.uid).doc(_deviceDocId(token)).delete();
      debugPrint('FCM Push: dispositivo removido de Firestore.');
    } catch (error) {
      debugPrint('FCM Push: error removiendo dispositivo: $error');
    } finally {
      _registeredToken = null;
    }
  }

  CollectionReference<Map<String, dynamic>> _usersLinkedDevices(String userId) {
    return _firestore.collection('users').doc(userId).collection('linked_devices');
  }

  String _deviceDocId(String token) {
    return base64Url.encode(utf8.encode(token)).replaceAll('=', '');
  }
}
