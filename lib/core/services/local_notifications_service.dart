import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationsService {
  LocalNotificationsService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const AndroidNotificationChannel chatChannel =
      AndroidNotificationChannel(
    'messeya_messages',
    'Mensajes',
    description: 'Notificaciones de mensajes de Messeya',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel callChannel =
      AndroidNotificationChannel(
    'messeya_calls',
    'Llamadas',
    description: 'Notificaciones de llamadas de Messeya',
    importance: Importance.max,
    playSound: true,
  );

  static final FlutterLocalNotificationsPlugin _backgroundPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<String?> initialize({
    required void Function(String payload) onPayloadTap,
  }) async {
    if (_initialized) {
      return _getLaunchPayload();
    }
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        onPayloadTap(payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    await _createAndroidChannels(_plugin);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
    return _getLaunchPayload();
  }

  Future<void> showChatNotification({
    required String title,
    required String body,
    required String payload,
    String? notificationId,
  }) async {
    await _plugin.show(
      _resolveNotificationId(
        explicitId: notificationId,
        fallbackSeed: '$title|$body|$payload',
      ),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          chatChannel.id,
          chatChannel.name,
          channelDescription: chatChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> showIncomingCallNotification({
    required String callerName,
    required bool isVideo,
    required String payload,
    String? notificationId,
  }) async {
    await _plugin.show(
      _resolveNotificationId(
        explicitId: notificationId,
        fallbackSeed: 'call|$callerName|$payload',
      ),
      isVideo ? 'Videollamada entrante' : 'Llamada entrante',
      '$callerName te esta llamando',
      NotificationDetails(
        android: AndroidNotificationDetails(
          callChannel.id,
          callChannel.name,
          channelDescription: callChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ticker: 'Llamada entrante',
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> initializeBackground() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _backgroundPlugin.initialize(initializationSettings);
    await _createAndroidChannels(_backgroundPlugin);
  }

  static Future<void> showBackgroundRemoteNotification({
    required String title,
    required String body,
    required String payload,
    bool isCall = false,
    String? notificationId,
  }) async {
    await _backgroundPlugin.show(
      _resolveNotificationId(
        explicitId: notificationId,
        fallbackSeed: 'bg|$title|$body|$payload',
      ),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          isCall ? callChannel.id : chatChannel.id,
          isCall ? callChannel.name : chatChannel.name,
          channelDescription:
              isCall ? callChannel.description : chatChannel.description,
          importance: isCall ? Importance.max : Importance.high,
          priority: isCall ? Priority.max : Priority.high,
          category: isCall ? AndroidNotificationCategory.call : null,
          fullScreenIntent: isCall,
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> _createAndroidChannels(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(chatChannel);
    await android?.createNotificationChannel(callChannel);
  }

  Future<String?> _getLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final payload = details?.notificationResponse?.payload;
    if (payload == null || payload.isEmpty) return null;
    return payload;
  }

  static int _resolveNotificationId({
    String? explicitId,
    required String fallbackSeed,
  }) {
    final parsed = int.tryParse(explicitId ?? '');
    if (parsed != null) {
      return parsed & 0x7fffffff;
    }
    return _stableId(fallbackSeed);
  }

  static int _stableId(String seed) {
    return seed.hashCode & 0x7fffffff;
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  debugPrint('Notification tapped in background: ${response.payload}');
}
