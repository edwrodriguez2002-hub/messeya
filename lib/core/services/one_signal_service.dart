import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../config/one_signal_config.dart';
import '../firebase/firebase_providers.dart';
import '../../routing/app_router.dart';

final oneSignalServiceProvider = Provider<OneSignalService>(
  (ref) => OneSignalService(ref.watch(firebaseAuthProvider)),
);

class OneSignalService {
  OneSignalService(this._auth);

  final FirebaseAuth _auth;
  StreamSubscription<User?>? _authSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || !OneSignalConfig.isConfigured) return;

    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    OneSignal.initialize(OneSignalConfig.appId);

    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      final route = data?['route']?.toString();
      if (route != null && route.isNotEmpty) {
        rootNavigatorKey.currentContext?.go(route);
      }
    });

    await OneSignal.Notifications.requestPermission(false);

    final currentUser = _auth.currentUser;
    if (currentUser != null && !currentUser.isAnonymous) {
      OneSignal.login(currentUser.uid);
    }

    _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null || user.isAnonymous) {
        OneSignal.logout();
        return;
      }
      OneSignal.login(user.uid);
    });

    _initialized = true;
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
  }
}
