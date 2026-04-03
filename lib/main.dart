import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_chat_flutter_core/stream_chat_flutter_core.dart';

import 'core/config/one_signal_config.dart';
import 'core/firebase/firebase_multi_session.dart';
import 'core/firebase/firebase_providers.dart';
import 'core/services/app_lifecycle_sync.dart';
import 'core/services/app_pin_lock_gate.dart';
import 'core/services/app_preferences_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/hybrid_sync_service.dart';
import 'core/services/one_signal_service.dart';
import 'core/services/stream_chat_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'features/auth/data/auth_repository.dart';
import 'routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Error inicializando Firebase: $e');
  }

  if (!kIsWeb) {
    await printKeyHash();
  }

  final sharedPreferences = await SharedPreferences.getInstance();
  final preferencesService = AppPreferencesService(sharedPreferences);
  await initializeRememberedSessionApps(
    preferencesService.getRememberedAccounts(),
  );

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
    ],
  );

  final streamChatService = container.read(streamChatServiceProvider);
  final initialAuth = container.read(firebaseAuthProvider);

  unawaited(
    streamChatService.syncAuthUser(initialAuth.currentUser).catchError((
      error,
      stackTrace,
    ) {
      debugPrint('Error sincronizando Stream Chat al iniciar: $error');
    }),
  );

  container.listen<AsyncValue<firebase_auth.User?>>(
    authStateChangesProvider,
    (_, next) {
      final user = next.valueOrNull;
      unawaited(
        streamChatService.syncAuthUser(user).catchError((error, stackTrace) {
          debugPrint('Error sincronizando Stream Chat: $error');
        }),
      );
    },
    fireImmediately: true,
  );

  FlutterError.onError = (details) {
    debugPrint('Flutter Error: ${details.exception}');
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MesseyaApp(),
    ),
  );

  if (!kIsWeb) {
    _initializeBackgroundServices(container);
  }
}

Future<void> _initializeBackgroundServices(ProviderContainer container) async {
  try {
    await container.read(oneSignalServiceProvider).initialize().timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('Error inicializando OneSignal: $e');
  }

  if (!OneSignalConfig.isConfigured) {
    try {
      await container.read(fcmServiceProvider).initialize().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Error inicializando FCM: $e');
    }
  }

  try {
    await container.read(hybridSyncServiceProvider).initialize().timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('Error inicializando sincronización: $e');
  }
}

class MesseyaApp extends ConsumerWidget {
  const MesseyaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final streamChatClient = ref.watch(streamChatClientProvider);

    final app = MaterialApp.router(
      title: 'Messeya',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );

    return AppLifecycleSync(
      child: AppPinLockGate(
        child: streamChatClient == null
            ? app
            : StreamChatCore(
                client: streamChatClient,
                child: app,
              ),
      ),
    );
  }
}

Future<void> printKeyHash() async {
  try {
    const platform = MethodChannel('flutter.native/helper');
    final String? result = await platform.invokeMethod('getHash');
    debugPrint("TU SHA-1 REAL ES: $result");
  } catch (e) {
    debugPrint("No se pudo obtener la firma.");
  }
}
