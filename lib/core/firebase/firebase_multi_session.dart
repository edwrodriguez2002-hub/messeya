import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase_options.dart';
import '../../shared/models/remembered_account.dart';

const defaultFirebaseSessionAppName = '__default__';

Future<FirebaseApp> ensureSessionFirebaseApp(String appName) async {
  if (appName.isEmpty || appName == defaultFirebaseSessionAppName) {
    return Firebase.app();
  }

  try {
    return Firebase.app(appName);
  } catch (_) {
    return Firebase.initializeApp(
      name: appName,
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

Future<void> initializeRememberedSessionApps(
  List<RememberedAccount> accounts,
) async {
  for (final account in accounts) {
    final appName = account.firebaseAppName;
    if (appName.isEmpty || appName == defaultFirebaseSessionAppName) {
      continue;
    }
    await ensureSessionFirebaseApp(appName);
  }
}

FirebaseAuth authForSessionAppName(String appName) {
  if (appName.isEmpty || appName == defaultFirebaseSessionAppName) {
    return FirebaseAuth.instance;
  }
  return FirebaseAuth.instanceFor(app: Firebase.app(appName));
}

FirebaseFirestore firestoreForSessionAppName(String appName) {
  if (appName.isEmpty || appName == defaultFirebaseSessionAppName) {
    return FirebaseFirestore.instance;
  }
  return FirebaseFirestore.instanceFor(app: Firebase.app(appName));
}
