import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_preferences_service.dart';
import 'firebase_multi_session.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  final activeAccountUid = ref.watch(activeAccountUidProvider);
  final rememberedAccounts = ref.watch(rememberedAccountsProvider);
  final account = rememberedAccounts
      .where((item) => item.uid == activeAccountUid)
      .firstOrNull;
  final appName = account?.firebaseAppName ?? defaultFirebaseSessionAppName;
  return authForSessionAppName(appName);
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final activeAccountUid = ref.watch(activeAccountUidProvider);
  final rememberedAccounts = ref.watch(rememberedAccountsProvider);
  final account = rememberedAccounts
      .where((item) => item.uid == activeAccountUid)
      .firstOrNull;
  final appName = account?.firebaseAppName ?? defaultFirebaseSessionAppName;
  return firestoreForSessionAppName(appName);
});

final firebaseMessagingProvider = Provider<FirebaseMessaging>(
  (ref) => FirebaseMessaging.instance,
);
