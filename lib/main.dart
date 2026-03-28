import 'dart:async';
import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/app_lifecycle_sync.dart';
import 'core/services/app_pin_lock_gate.dart';
import 'core/services/app_preferences_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/hybrid_sync_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización de Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Error inicializando Firebase: $e');
  }

  // Llama a esta función para ver el SHA-1 en la consola al iniciar
  await printKeyHash();

  final sharedPreferences = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
    ],
  );

  FlutterError.onError = (details) {
    debugPrint('Flutter Error: ${details.exception}');
  };

  ErrorWidget.builder = (details) {
    return Material(
      color: const Color(0xFFF9F6FA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 64, color: Colors.redAccent),
              const SizedBox(height: 24),
              const Text(
                'Messeya encontró un problema',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Estamos teniendo dificultades para cargar un componente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => main(),
                child: const Text('Reintentar inicio'),
              ),
            ],
          ),
        ),
      ),
    );
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MesseyaApp(),
    ),
  );

  _initializeBackgroundServices(container);
}

Future<void> _initializeBackgroundServices(ProviderContainer container) async {
  try {
    await container.read(fcmServiceProvider).initialize().timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('Error inicializando FCM: $e');
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

    return AppLifecycleSync(
      child: AppPinLockGate(
        child: MaterialApp.router(
          title: 'Messeya',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          routerConfig: router,
        ),
      ),
    );
  }
}

Future<void> printKeyHash() async {
  try {
    const platform = MethodChannel('flutter.native/helper');
    final String? result = await platform.invokeMethod('getHash');
    // BUSCA ESTA LÍNEA EN LA CONSOLA (DEBUG CONSOLE)
    print("---------------------------------------------------------");
    print("TU SHA-1 REAL ES: $result");
    print("---------------------------------------------------------");
  } catch (e) {
    print("No se pudo obtener la firma. Asegúrate de que MainActivity esté configurada.");
  }
}
